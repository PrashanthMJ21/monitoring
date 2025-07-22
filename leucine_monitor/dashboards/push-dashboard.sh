#!/bin/bash

# 👇 Load env from correct relative path
source ./alerts/.env

# Array of dashboards to push
dashboards=("multi-server-dashboard.json" "synthetic-monitoring.json")

for file in "${dashboards[@]}"; do
  full_path="./dashboards/$file"
  echo "📄 Pushing dashboard: $full_path"

  # Check if the file is already wrapped
  if jq -e 'has("dashboard")' "$full_path" > /dev/null; then
    payload=$(cat "$full_path")
    echo "📦 Already wrapped: $file"
  else
    payload=$(jq -n --argjson dash "$(cat "$full_path")" \
      '{dashboard: $dash, folderId: 0, overwrite: true}')
    echo "📦 Wrapped: $file"
  fi

  # Push via API
  response=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "➡️ Response for $file: $response"
done

echo "📊 All dashboards pushed!"
