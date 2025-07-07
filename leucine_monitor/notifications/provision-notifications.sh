#!/bin/bash

# 🔐 Inject before running: GRAFANA_URL and API_KEY

TEMPLATE_FILE="./notifications/notification-templates.yml"
CONTACT_FILE="./notifications/contact-points.yml"

echo "📤 Creating notification templates (UI editable)..."
yq e -o=json "$TEMPLATE_FILE" | jq -c '.templates[]' | while read -r template; do
  curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/notification-templates" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$template"
done

echo "📤 Creating contact points (UI editable)..."
yq e -o=json "$CONTACT_FILE" | jq -c '.contactPoints[]' | while read -r cp; do
  curl -s -X POST "$GRAFANA_URL/api/v1/provisioning/contact-points" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Disable-Provenance: true" \
    -d "$cp"
done

echo "✅ Contact point and templates provisioned successfully."
