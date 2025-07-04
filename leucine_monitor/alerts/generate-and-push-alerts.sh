#!/bin/bash

# ----------- CONFIGURABLE VARIABLES -------------
YAML_FILE="./alerts/alert-details.yml"
TEMPLATE_FILE="./alerts/alert-template.json"
ENV_FILE="./alerts/.env"
PROMETHEUS_DS_NAME="Prometheus"
# -----------------------------------------------

# Load environment variables
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# Validate required ENV vars
if [[ -z "$GRAFANA_URL" || -z "$API_KEY" ]]; then
  echo "❌ GRAFANA_URL or API_KEY is not set. Export them or check $ENV_FILE"
  exit 1
fi

# Step 1: Get Prometheus UID
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

# Step 2: Loop through alerts
alerts=$(yq e '.alerts | length' "$YAML_FILE")

for i in $(seq 0 $((alerts - 1))); do
  alert_json=$(yq e ".alerts[$i]" "$YAML_FILE" | yq -o=json)
  folder=$(echo "$alert_json" | jq -r '.folder')

  # Folder check or create
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

  annotations=$(echo "$alert_json" | jq '.annotations // {}')
  labels=$(echo "$alert_json" | jq '.labels // {}')

  # Build dynamic payload
payload=$(jq -n \
  --argjson alert "$alert_json" \
  --argjson annotations "$annotations" \
  --argjson labels "$labels" \
  --slurpfile template "$TEMPLATE_FILE" \
  --arg prometheus_uid "$PROMETHEUS_UID" \
  --arg folder_uid "$folder_uid" '
  $template[0]
  | .folderUID = $folder_uid
  | .title = ($alert.title // $alert.name)
  | .group = $alert.group
  | .ruleGroup = $alert.group
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

  # POST to Grafana
  response=$(curl -s -w "\n%{http_code}" -o "./alerts/response_body_$i.txt" \
    -X POST "$GRAFANA_URL/api/v1/rules" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  http_status=$(tail -n1 <<< "$response")

  echo "📤 Pushing alert: $(echo "$alert_json" | jq -r '.name')"
  echo "📥 HTTP Status: $http_status"
  cat "./alerts/response_body_$i.txt"
  echo
done

echo "✅ All alerts pushed dynamically"
