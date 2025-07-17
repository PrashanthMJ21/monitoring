#!/bin/bash

# 👇 Load env from correct relative path
source ./alerts/.env

# Array of dashboards to push
dashboards=("multi-server-dashboard.json" "synthetic-monitoring.json")

for file in "${dashboards[@]}"; do
  echo "📄 Pushing dashboard: ./dashboards/$file"

  # Read and wrap the dashboard JSON as expected by Grafana
  dashboard_json=$(jq '.' "./dashboards/$file")

  payload=$(jq -n \
    --argjson dashboard "$dashboard_json" \
    '{dashboard: $dashboard, folderId: 0, overwrite: true}')

  # Push via API
  response=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "➡️ Response for $file: $response"
done

echo "📊 All dashboards pushed!"
