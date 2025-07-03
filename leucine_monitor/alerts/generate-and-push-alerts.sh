#!/bin/bash

# ----------- CONFIGURABLE VARIABLES -------------
YAML_FILE="./alerts/alert-details.yml"
TEMPLATE_FILE="./alerts/alert-template.json"
GRAFANA_URL="${GRAFANA_URL}"
API_KEY="${API_KEY}"
PROMETHEUS_DS_NAME="Prometheus"
# -----------------------------------------------

# Step 1: Validate required environment variables
if [[ -z "$GRAFANA_URL" || -z "$API_KEY" ]]; then
  echo "❌ GRAFANA_URL or API_KEY is not set. Export them and rerun."
  exit 1
fi

# Step 2: Get Prometheus UID with retry
echo "🔎 Checking Prometheus UID..."
for attempt in {1..10}; do
  PROMETHEUS_UID=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/datasources" | \
    jq -r --arg name "$PROMETHEUS_DS_NAME" '.[] | select(.name == $name) | .uid')

  if [[ -n "$PROMETHEUS_UID" && "$PROMETHEUS_UID" != "null" ]]; then
    echo "✅ Found Prometheus UID: $PROMETHEUS_UID"
    break
  fi

  echo "⏳ Waiting for Prometheus UID... attempt $attempt"
  sleep 2
done

if [[ -z "$PROMETHEUS_UID" || "$PROMETHEUS_UID" == "null" ]]; then
  echo "❌ Prometheus UID not found. Exiting..."
  exit 1
fi

# Step 3: Loop through alerts
alerts=$(yq e '.alerts | length' "$YAML_FILE")

for i in $(seq 0 $((alerts - 1))); do
  alert_json=$(yq e ".alerts[$i]" "$YAML_FILE" | yq -o=json)
  folder=$(echo "$alert_json" | jq -r '.folder')

  # Step 3.1: Resolve or create folder
  existing_folder_uid=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/folders" | \
    jq -r --arg title "$folder" '.[] | select(.title == $title) | .uid')

  if [[ -n "$existing_folder_uid" ]]; then
    folder_uid="$existing_folder_uid"
  else
    folder_uid=$(echo "$folder" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    echo "📁 Creating folder '$folder'..."
    curl -s -X POST "$GRAFANA_URL/api/folders" \
      -H "Authorization: $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"title\": \"$folder\", \"uid\": \"$folder_uid\"}" > /dev/null
  fi

  # Step 3.2: Prepare annotations and labels
  annotations=$(echo "$alert_json" | jq '.annotations // {}')
  labels=$(echo "$alert_json" | jq '.labels // {}')

  # Step 3.3: Generate payload from template
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
    | (if $alert.group then .group = $alert.group else del(.group) end)
    | .condition = $alert.condition
    | .noDataState = $alert.no_data_state
    | .execErrState = $alert.exec_err_state
    | .for = $alert.pending
    | (if $alert.keep_firing_for then .keepState = $alert.keep_firing_for else del(.keepState) end)
    | .data[0].datasourceUid = $prometheus_uid
    | .data[0].model.expr = $alert.expr
    | .data[1].model.conditions[0].evaluator.params[0] = $alert.threshold
    | .data[1].model.conditions[0].unloadEvaluator.params[0] = $alert.recovery_threshold
    | .data[1].model.conditions[0].query.params[0] = "A"
    | .annotations = $annotations
    | .labels = $labels
    | if $alert.contact_point then .notification_settings.receiver = $alert.contact_point else del(.notification_settings) end
  ')

  echo "$payload" > "./alerts/payload_debug_$i.json"

  # Step 3.4: POST to Grafana
  response=$(curl -s -w "\n%{http_code}" -o "./alerts/response_body_$i.txt" \
    -X POST "$GRAFANA_URL/api/v1/provisioning/alert-rules" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  http_status=$(tail -n1 <<< "$response")

  echo "📤 Pushing alert: $(echo "$alert_json" | jq -r '.name')"
  echo "📥 HTTP Status: $http_status"
  echo "📥 Response Body:"
  cat "./alerts/response_body_$i.txt"
  echo
done

echo "✅ All alerts pushed dynamically."
