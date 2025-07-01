#!/bin/bash

set -e  # Exit on any error

echo "📦 Installing dependencies..."
sudo apt update -y
sudo apt install -y git curl docker.io jq yq

echo "🚀 Cloning your repo..."
git clone https://github.com/PrashanthMJ21/monitoring.git
cd monitoring/leucine_monitor

echo "🐳 Starting Docker Compose stack..."
docker-compose up -d

echo "⏳ Waiting for Grafana to initialize..."
sleep 20  # Wait to ensure Grafana is fully up

echo "🔐 Generating Grafana API key..."
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
KEY_NAME="provisioning-key"

API_KEY=$(curl -s -X POST "$GRAFANA_URL/api/auth/keys" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$KEY_NAME\", \"role\": \"Admin\", \"secondsToLive\": 0}" | jq -r '.key')

if [[ "$API_KEY" == "null" || -z "$API_KEY" ]]; then
  echo "❌ Failed to create Grafana API key. Exiting."
  exit 1
fi

echo "✅ API Key generated."

echo "📤 Pushing alerts to Grafana..."
export API_KEY="Bearer $API_KEY"
chmod +x alerts/generate-and-push-alerts.sh
./alerts/generate-and-push-alerts.sh

echo "🎉 Setup complete! Visit Grafana at: http://<your-server-ip>:3000 or https://grafana.leucinetech.com"

