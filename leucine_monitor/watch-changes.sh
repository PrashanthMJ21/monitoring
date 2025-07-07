#!/bin/bash

# -------- SETTINGS --------
ENV_FILE="./alerts/.env"
ALERT_FILE="./alerts/alert-details.yml"
NOTIF_TEMPLATE_FILE="./notifications/notification-templates.yml"
CONTACT_FILE="./notifications/contact-points.yml"
DATASOURCE_FILE="./provisioning/datasources/datasources.yml"

ALERT_SCRIPT="./alerts/generate-and-push-alerts.sh"
NOTIF_SCRIPT="./notifications/provision-notifications.sh"
# --------------------------

echo "👀 Watching for changes..."
echo "🔁 Press Ctrl+C to stop."

# Ensure ENV file
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Validate scripts
for file in "$ALERT_SCRIPT" "$NOTIF_SCRIPT"; do
  if [ ! -f "$file" ]; then
    echo "❌ Required script missing: $file"
    exit 1
  fi
done

# Use inotifywait in background mode
inotifywait -mq -e modify --format '%w%f' \
  "$ALERT_FILE" \
  "$NOTIF_TEMPLATE_FILE" \
  "$CONTACT_FILE" \
  "$DATASOURCE_FILE" |
while read changed_file; do
  echo "📦 Change detected in: $changed_file"

  case "$changed_file" in
    *alert-details.yml)
      echo "🚨 Re-deploying alerts..."
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" "$ALERT_SCRIPT"
      echo "✅ Alerts updated."
      ;;

    *notification-templates.yml|*contact-points.yml)
      echo "📬 Re-deploying contact points and notification templates..."
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT"
      echo "✅ Notifications updated."
      ;;

    *datasources.yml)
      echo "📡 Datasource config changed. Restarting Grafana container..."
      docker-compose restart grafana
      echo "✅ Grafana restarted."
      ;;
  esac
done
