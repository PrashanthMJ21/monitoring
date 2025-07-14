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
LOG_FILE="$ROOT_DIR/alerts/watcher.log"
# --------------------------

echo "👀 Watching for changes..." >> "$LOG_FILE"
echo "🔁 Press Ctrl+C to stop." >> "$LOG_FILE"

# Load env
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE" >> "$LOG_FILE"
  exit 1
fi

# Watch loop
inotifywait -mq -e close_write --format '%w%f' \
  "$ALERT_FILE" \
  "$NOTIF_TEMPLATE_FILE" \
  "$CONTACT_FILE" \
  "$DATASOURCE_FILE" | while read changed_file; do

  echo "📦 Change detected in: $changed_file" >> "$LOG_FILE"

  case "$changed_file" in
    *alert-details.yml)
      echo "🚨 Re-deploying alerts..." >> "$LOG_FILE"
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" "$ALERT_SCRIPT" >> "$LOG_FILE" 2>&1
      echo "✅ Alerts updated." >> "$LOG_FILE"
      ;;

    *notification-templates.yml|*contact-points.yml)
      echo "📬 Re-deploying contact points and templates..." >> "$LOG_FILE"
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT" >> "$LOG_FILE" 2>&1
      echo "✅ Notifications updated." >> "$LOG_FILE"
      ;;

    *datasources.yml)
      echo "📡 Restarting Grafana due to datasource config change..." >> "$LOG_FILE"
      docker-compose restart grafana >> "$LOG_FILE" 2>&1
      echo "✅ Grafana restarted." >> "$LOG_FILE"
      ;;
  esac
done
