#!/bin/bash

# ----------- CONFIGURABLE VARIABLES -------------
TEMPLATE_FILE="./alerts/alert-template.json"
ALERTS_DIR="./alerts/alert-details"
GRAFANA_URL="${GRAFANA_URL}"
API_KEY="${API_KEY}"
PROMETHEUS_UID="${PROMETHEUS_UID}"
# -----------------------------------------------

if [ -z "$PROMETHEUS_UID" ] || [ "$PROMETHEUS_UID" == "null" ]; then
  echo "❌ PROMETHEUS_UID is not set. Exiting..."
  exit 1
else
  echo "✅ Using Prometheus UID: $PROMETHEUS_UID"
fi

# 🧠 Step 1: Collect all declared UIDs from all YAMLs
declared_uids=""
for YAML_FILE in "$ALERTS_DIR"/*.yml; do
  declared_uids+=$(yq e '.alerts[].uid // ""' "$YAML_FILE" | grep -v '^$' | sort)
  declared_uids+=$'\n'
done

# 🧠 Step 2: Get all existing alert UIDs from Grafana
existing_alerts=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/v1/provisioning/alert-rules")
existing_uids=$(echo "$existing_alerts" | jq -r '.[].uid' | sort)

# 🧹 Step 3: Delete alerts not in YAMLs
for uid in $existing_uids; do
  if ! grep -Fxq "$uid" <<< "$declared_uids"; then
    echo "🗑️ Deleting orphaned alert UID: $uid"
    curl -s -X DELETE "$GRAFANA_URL/api/v1/provisioning/alert-rules/$uid" \
      -H "Authorization: $API_KEY" > /dev/null
  fi
done

# 🚀 Step 4: Loop over each YAML and push alerts
for YAML_FILE in "$ALERTS_DIR"/*.yml; do
  echo "📁 Processing $YAML_FILE"

  alerts_count=$(yq e '.alerts | length' "$YAML_FILE")

  for i in $(seq 0 $((alerts_count - 1))); do
    alert_json=$(yq e ".alerts[$i]" "$YAML_FILE" | yq -o=json)
    folder=$(echo "$alert_json" | jq -r '.folder')
    title=$(echo "$alert_json" | jq -r '.title')
    uid=$(echo "$alert_json" | jq -r '.uid // empty')

    # Create/get folder UID
    folder_uid=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/folders" |
      jq -r --arg title "$folder" '.[] | select(.title == $title) | .uid')
    if [ -z "$folder_uid" ]; then
      folder_uid=$(echo "$folder" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
      curl -s -X POST "$GRAFANA_URL/api/folders" \
        -H "Authorization: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"$folder\", \"uid\": \"$folder_uid\"}" > /dev/null
    fi

    annotations=$(echo "$alert_json" | jq '.annotations // {}')
    labels=$(echo "$alert_json" | jq '.labels // {}')

    # Build payload
    payload=$(jq -n \
      --argjson alert "$alert_json" \
      --argjson annotations "$annotations" \
      --argjson labels "$labels" \
      --slurpfile template "$TEMPLATE_FILE" \
      --arg prometheus_uid "$PROMETHEUS_UID" \
      --arg folder_uid "$folder_uid" '
      $template[0]
      | .folderUID = $folder_uid
      | .title = $alert.title
      | (if $alert.group != null and $alert.group != "" then .ruleGroup = $alert.group else del(.ruleGroup) end)
      | (if $alert.condition != null then .condition = $alert.condition else del(.condition) end)
      | (if $alert.no_data_state != null then .noDataState = $alert.no_data_state else del(.noDataState) end)
      | (if $alert.exec_err_state != null then .execErrState = $alert.exec_err_state else del(.execErrState) end)
      | (if $alert.pending != null then .for = $alert.pending else del(.for) end)
      | (if $alert.keep_firing_for != null then .keepState = $alert.keep_firing_for else del(.keepState) end)
      | .data[0].datasourceUid = $prometheus_uid
      | (if $alert.expr != null then .data[0].model.expr = $alert.expr else del(.data[0].model.expr) end)
      | (if $alert.threshold != null then .data[1].model.conditions[0].evaluator.params[0] = $alert.threshold else del(.data[1].model.conditions[0].evaluator.params[0]) end)
      | (if $alert.recovery_threshold != null then .data[1].model.conditions[0].unloadEvaluator.params[0] = $alert.recovery_threshold else del(.data[1].model.conditions[0].unloadEvaluator.params[0]) end)
      | (if .data[1]?.model?.conditions?[0]?.query?.params != null then .data[1].model.conditions[0].query.params[0] = "A" else . end)
      | .annotations = $annotations
      | .labels = $labels
      | (if $alert.contact_point != null then .notification_settings.receiver = $alert.contact_point else del(.notification_settings) end)
      | (if $alert.uid != null then .uid = $alert.uid else del(.uid) end)
    ')

    # Detect existing UID in Grafana
    existing_uid=$(echo "$existing_alerts" | jq -r --arg title "$title" '.[] | select(.title == $title) | .uid')

    if [ -n "$existing_uid" ]; then
      method="PUT"
      url="$GRAFANA_URL/api/v1/provisioning/alert-rules/$existing_uid"
    else
      method="POST"
      url="$GRAFANA_URL/api/v1/provisioning/alert-rules"
    fi

    echo "📤 Pushing alert: $title via $method"
    response=$(curl -s -w "\n%{http_code}" -o "./alerts/response_body_${uid:-$i}.txt" \
      -X "$method" "$url" \
      -H "Authorization: $API_KEY" \
      -H "Content-Type: application/json" \
      -H "X-Disable-Provenance: true" \
      -d "$payload")

    echo "📥 Response for $title: $(tail -n1 <<< "$response")"
  done
done

echo "✅ All alerts synced with Grafana."
