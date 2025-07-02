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
  folder_uid=$(echo "$folder" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

  echo "📁 Creating folder '$folder'..."
  curl -s -X POST "$GRAFANA_URL/api/folders" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"title\": \"$folder\", \"uid\": \"$folder_uid\"}" > /dev/null

  payload=$(jq -n --argjson alert "$alert_json" \
    --slurpfile template "$TEMPLATE_FILE" \
    --arg prometheus_uid "$PROMETHEUS_UID" \
    --arg folder_uid "$folder_uid" \
    '$template[0] |
     .folderUID = $folder_uid |
     .title = $alert.title |
     .group = $alert.group |
     .condition = $alert.condition |
     .noDataState = $alert.no_data_state |
     .execErrState = $alert.exec_err_state |
     .for = $alert.pending |
     .keepState = $alert.keep_firing_for |
     .data[0].datasourceUid = $prometheus_uid |
     .data[0].model.expr = $alert.expr |
     .data[1].model.conditions[0].evaluator.params[0] = $alert.threshold |
     .data[1].model.conditions[0].unloadEvaluator.params[0] = $alert.recovery_threshold |
     .annotations.server = $alert.server |
     .annotations.summary = $alert.summary |
     .annotations.threshold = ($alert.threshold | tostring) |
     .annotations.url = $alert.url |
     .annotations.title = $alert.title |
     .labels = $alert.labels |
     .notification_settings.receiver = $alert.contact_point')

  echo "$payload" > "./alerts/payload_debug_$i.json"

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
