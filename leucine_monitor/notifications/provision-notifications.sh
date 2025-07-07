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

  response=$(curl -s -X POST "$GRAFANA_URL/api/alerting/notification-template" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$json_payload")

  echo "📨 [$name] => $response"
done

echo "📤 Creating contact points (UI editable)..."
yq e -o=json "$CONTACT_FILE" | jq -c '.contactPoints[]' | while read -r cp; do
  response=$(curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/contact-points" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$cp")
  echo "📨 [Contact Point] => $response"
done

echo "✅ Contact point and templates provisioned successfully."
