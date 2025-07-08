#!/bin/bash

# -------- SETTINGS --------
ROOT_DIR="$(realpath "$(dirname "$0")")"
ENV_FILE="$ROOT_DIR/alerts/.env"
ALERT_FILE="$ROOT_DIR/alerts/alert-details.yml"
NOTIF_TEMPLATE_FILE="$ROOT_DIR/notifications/notification-templates.yml"
CONTACT_FILE="$ROOT_DIR/notifications/contact-points.yml"
DATASOURCE_FILE="$ROOT_DIR/provisioning/datasources/datasources.yml"

ALERT_SCRIPT="$ROOT_DIR/alerts/generate-and-push-alerts.sh"
NOTIF_SCRIPT="$ROOT_DIR/notifications/provision-notifications.sh"
# --------------------------

echo "👀 Watching for changes..."
echo "🔁 Press Ctrl+C to stop."

# Load environment
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Start watcher
inotifywait -mq -e modify --format '%w%f' \
  "$ALERT_FILE" \
  "$NOTIF_TEMPLATE_FILE" \
  "$CONTACT_FILE" \
  "$DATASOURCE_FILE" | while read changed_file; do

  echo "📦 Detected change: $changed_file"

  case "$changed_file" in
    *alert-details.yml)
      echo "🚨 Re-deploying alerts..."
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" "$ALERT_SCRIPT"
      echo "✅ Alerts updated."
      ;;

    *notification-templates.yml|*contact-points.yml)
      echo "📬 Re-deploying contacts and templates..."
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT"
      echo "✅ Notifications updated."
      ;;

    *datasources.yml)
      echo "📡 Restarting Grafana to apply datasource changes..."
      docker-compose restart grafana
      echo "✅ Grafana restarted."
      ;;
  esac
done
