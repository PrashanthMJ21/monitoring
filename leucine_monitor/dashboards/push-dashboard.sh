#!/bin/bash

# ✅ Load environment variables
source ./alerts/.env

echo "📊 Pushing dashboards..."

# Loop through all JSON files in ./dashboards
for file in ./dashboards/*.json; do
  echo "📄 Pushing dashboard: $file"

  # ✅ Check if already wrapped (i.e., top-level "dashboard" key exists)
  if jq 'has("dashboard")' "$file" | grep -q true; then
    payload=$(cat "$file")
    echo "📦 Already Wrapped: $(basename "$file")"
  else
    # ✅ Safely wrap unwrapped dashboards
    if jq empty "$file" > /dev/null 2>&1; then
      payload=$(jq -n --slurpfile dash "$file" \
        '{dashboard: $dash[0], overwrite: true, folderUid: ""}')
      echo "📦 Wrapped: $(basename "$file")"
    else
      echo "❌ Invalid JSON: $(basename "$file")"
      continue
    fi
  fi

  # 🚀 Push to Grafana
  response=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "➡️ Response for $(basename "$file"): $response"
done

echo "✅ All dashboards pushed successfully."
