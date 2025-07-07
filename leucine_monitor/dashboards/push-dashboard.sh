#!/bin/bash

# Load environment vars (go up one directory)
source ../alerts/.env

DASHBOARD_FILE="./multi-server-dashboard.json"

# Read dashboard JSON and wrap it for API
dashboard_json=$(cat "$DASHBOARD_FILE")

payload=$(jq -n \
  --argjson dashboard "$dashboard_json" \
  --arg folderId "0" \
  --argjson overwrite true \
  '{dashboard: $dashboard, folderId: ($folderId|tonumber), overwrite: $overwrite}')

# Push via API
response=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
  -H "Authorization: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload")

echo "📊 Dashboard response:"
echo "$response"
