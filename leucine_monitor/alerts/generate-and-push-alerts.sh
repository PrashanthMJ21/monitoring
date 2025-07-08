#!/bin/bash

# ----------- CONFIGURABLE VARIABLES -------------
YAML_FILE="./alerts/alert-details.yml"
TEMPLATE_FILE="./alerts/alert-template.json"
GRAFANA_URL="${GRAFANA_URL}"
API_KEY="${API_KEY}"
PROMETHEUS_DS_NAME="Prometheus"
# -----------------------------------------------

# Step 1: Get Prometheus UID dynamically
PROMETHEUS_UID=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/datasources" | \
  jq -r --arg name "$PROMETHEUS_DS_NAME" '.[] | select(.name == $name) | .uid')

if [ -z "$PROMETHEUS_UID" ] || [ "$PROMETHEUS_UID" == "null" ]; then
  echo "❌ Prometheus UID not found. Exiting..."
  exit 1
else
  echo "✅ Found Prometheus UID: $PROMETHEUS_UID"
fi

# Step 2: Loop through alerts and push
alerts=$(yq e '.alerts | length' "$YAML_FILE")

for i in $(seq 0 $((alerts - 1))); do
  alert_json=$(yq e ".alerts[$i]" "$YAML_FILE" | yq -o=json)
  folder=$(echo "$alert_json" | jq -r '.folder')

  # ✅ Step 2.1: Resolve or create folder UID
  existing_folder_uid=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/folders" | \
    jq -r --arg title "$folder" '.[] | select(.title == $title) | .uid')

  if [ -n "$existing_folder_uid" ]; then
    folder_uid="$existing_folder_uid"
  else
    folder_uid=$(echo "$folder" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    echo "📁 Creating folder '$folder'..."
    curl -s -X POST "$GRAFANA_URL/api/folders" \
      -H "Authorization: $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"title\": \"$folder\", \"uid\": \"$folder_uid\"}" > /dev/null
  fi

  annotations=$(echo "$alert_json" | jq '.annotations // {}')
  labels=$(echo "$alert_json" | jq '.labels // {}')

  # ✅ Step 2.2: Build dynamic payload
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
    | (if $alert.group then .ruleGroup = $alert.group else del(.ruleGroup) end)
    | .condition = $alert.condition
    | .noDataState = $alert.no_data_state
    | .execErrState = $alert.exec_err_state
    | .for = $alert.pending
    | (if $alert.keep_firing_for then .keepState = $alert.keep_firing_for else . end)
    | .data[0].datasourceUid = $prometheus_uid
    | .data[0].model.expr = $alert.expr
    | .data[1].model.conditions[0].evaluator.params[0] = $alert.threshold
    | .data[1].model.conditions[0].unloadEvaluator.params[0] = $alert.recovery_threshold
    | .data[1].model.conditions[0].query.params[0] = "A"
    | .annotations = $annotations
    | .labels = $labels
    | if $alert.contact_point then .notification_settings.receiver = $alert.contact_point else del(.notification_settings) end
  ')

  title=$(echo "$alert_json" | jq -r '.title')

  # ✅ Check for existing alert rule by title
  existing_uid=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/v1/provisioning/alert-rules" | \
    jq -r --arg title "$title" '.[] | select(.title == $title) | .uid')

  if [ -n "$existing_uid" ]; then
    method="PUT"
    url="$GRAFANA_URL/api/v1/provisioning/alert-rules/$existing_uid"
  else
    method="POST"
    url="$GRAFANA_URL/api/v1/provisioning/alert-rules"
  fi

  echo "📤 Pushing alert: $title via $method"
  response=$(curl -s -w "\n%{http_code}" -o "./alerts/response_body_$i.txt" \
    -X "$method" "$url" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$payload")

  echo "📥 Response: $(tail -n1 <<< "$response")"
done

echo "✅ All alerts pushed dynamically."
