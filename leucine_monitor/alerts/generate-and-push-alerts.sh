#!/bin/bash

# ----------- CONFIGURABLE VARIABLES -------------
YAML_FILE="./alerts/alerts-details.yml"
TEMPLATE_FILE="./alerts/alert.template.json"
GRAFANA_URL="http://localhost:3000"
API_KEY="Bearer YOUR_GRAFANA_API_KEY"  # 🔐 Replace with your actual API key
# -----------------------------------------------

# Count number of alerts
alerts=$(yq e '.alerts | length' "$YAML_FILE")

for i in $(seq 0 $((alerts - 1))); do
  # Extract individual alert object
  alert_json=$(yq e ".alerts[$i]" "$YAML_FILE" | yq -o=json)

  # Inject values into template
  payload=$(jq -n --argjson alert "$alert_json" \
    --slurpfile template "$TEMPLATE_FILE" \
    '$template[0] |
     .title = $alert.title |
     .folderUID = ($alert.folder | gsub(" "; "-") | ascii_downcase) |
     .group = $alert.group |
     .condition = $alert.condition |
     .noDataState = $alert.no_data_state |
     .execErrState = $alert.exec_err_state |
     .for = $alert.pending |
     .keepState = $alert.keep_firing_for |
     .data[0].datasourceUid = $alert.datasource_uid |
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

  # Push to Grafana
  echo "📤 Pushing alert: $(echo "$alert_json" | jq -r '.name')"
  curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/alert-rules" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload"
done

echo "✅ All alerts pushed dynamically."

