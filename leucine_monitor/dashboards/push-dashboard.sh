#!/bin/bash

# 👇 Load env from correct relative path
source ./alerts/.env

# 👇 Make sure these point to correct paths
DASHBOARD_FILES=(
  "./dashboards/multi-server-dashboard.json"
  "./dashboards/synthetic-monitoring.json"
)

for DASHBOARD_FILE in "${DASHBOARD_FILES[@]}"; do
  echo "📄 Pushing dashboard: $DASHBOARD_FILE"

  dashboard_json=$(cat "$DASHBOARD_FILE")

  payload=$(jq -n \
    --argjson dashboard "$dashboard_json" \
    --arg folderId "0" \
    --argjson overwrite true \
    '{dashboard: $dashboard, folderId: ($folderId|tonumber), overwrite: $overwrite}')

  response=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "➡️ Response for $(basename "$DASHBOARD_FILE"): $response"
done

echo "📊 All dashboards pushed!"
