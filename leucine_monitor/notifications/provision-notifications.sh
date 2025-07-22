#!/bin/bash

# 🔐 Load environment variables
source ./alerts/.env

TEMPLATE_FILE="./notifications/notification-templates.yml"
CONTACT_FILE="./notifications/contact-points.yml"

echo "📤 Creating notification templates (UI editable)..."
yq e -o=json "$TEMPLATE_FILE" | jq -c '.templates[]' | while read -r tpl; do
  name=$(echo "$tpl" | jq -r '.name')
  template=$(echo "$tpl" | jq -r '.template')

  json_payload=$(jq -n \
    --arg name "$name" \
    --arg template "$template" \
    '{name: $name, template: $template}')

  curl -s -X PUT "$GRAFANA_URL/api/v1/provisioning/templates/$name" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$json_payload" > /dev/null

  echo "📨 [$name] => Template Updated"
done

echo "📤 Creating contact points (UI editable)..."
yq e -o=json "$CONTACT_FILE" | jq -c '.contactPoints[]' | while read -r cp; do
  name=$(echo "$cp" | jq -r '.name')

  existing=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/v1/provisioning/contact-points" |
    jq -r --arg name "$name" '.[] | select(.name == $name)')

  if [ -n "$existing" ]; then
    uid=$(echo "$existing" | jq -r '.uid')
    method="PUT"
    url="$GRAFANA_URL/api/v1/provisioning/contact-points/$uid"
  else
    method="POST"
    url="$GRAFANA_URL/api/v1/provisioning/contact-points"
  fi

  curl -s -X "$method" "$url" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$cp" > /dev/null

  echo "📨 [$name] => $method"
done

echo "📤 Updating notification policy (default and child policies)..."
curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/policies" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/yaml" \
  --data-binary @./notifications/alerty-policy.yml > /dev/null

echo "✅ Contact points, templates, and notification policy provisioned successfully."
