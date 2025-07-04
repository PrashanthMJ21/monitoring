#!/bin/bash

# -------- SETTINGS --------
WATCH_FILE="./alerts/alert-details.yml"
DEPLOY_SCRIPT="./alerts/generate-and-push-alerts.sh"
ENV_FILE="./alerts/.env"
# --------------------------

echo "👀 Watching for changes in $WATCH_FILE ..."
echo "🔁 Press Ctrl+C to stop."

# Ensure the script and file exist
if [ ! -f "$WATCH_FILE" ]; then
  echo "❌ Alert details file not found: $WATCH_FILE"
  exit 1
fi

if [ ! -f "$DEPLOY_SCRIPT" ]; then
  echo "❌ Deployment script not found: $DEPLOY_SCRIPT"
  exit 1
fi

# Ensure env variables are loaded
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Start watching using inotifywait
while inotifywait -e modify "$WATCH_FILE"; do
  echo "📦 Detected change in alert-details.yml. Re-deploying alerts..."
  GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" "$DEPLOY_SCRIPT"
  echo "✅ Alerts reloaded."
done
