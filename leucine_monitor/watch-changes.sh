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

SLEEP_INTERVAL=10
# --------------------------

echo "👀 Polling for file changes every $SLEEP_INTERVAL seconds..."
echo "🔁 Press Ctrl+C to stop."

# Load env
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Initialize checksums
get_hash() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

prev_alert_hash=$(get_hash "$ALERT_FILE")
prev_template_hash=$(get_hash "$NOTIF_TEMPLATE_FILE")
prev_contact_hash=$(get_hash "$CONTACT_FILE")
prev_datasource_hash=$(get_hash "$DATASOURCE_FILE")

while true; do
  sleep "$SLEEP_INTERVAL"

  curr_alert_hash=$(get_hash "$ALERT_FILE")
  curr_template_hash=$(get_hash "$NOTIF_TEMPLATE_FILE")
  curr_contact_hash=$(get_hash "$CONTACT_FILE")
  curr_datasource_hash=$(get_hash "$DATASOURCE_FILE")

  if [ "$curr_alert_hash" != "$prev_alert_hash" ]; then
    echo "🚨 Detected change in alert-details.yml — Re-deploying alerts..."
    GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" "$ALERT_SCRIPT"
    echo "✅ Alerts updated."
    prev_alert_hash="$curr_alert_hash"
  fi

  if [ "$curr_template_hash" != "$prev_template_hash" ] || [ "$curr_contact_hash" != "$prev_contact_hash" ]; then
    echo "📬 Detected change in notification files — Re-deploying..."
    GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT"
    echo "✅ Notifications updated."
    prev_template_hash="$curr_template_hash"
    prev_contact_hash="$curr_contact_hash"
  fi

  if [ "$curr_datasource_hash" != "$prev_datasource_hash" ]; then
    echo "📡 Detected datasource.yml change — Restarting Grafana..."
    docker-compose restart grafana
    echo "✅ Grafana restarted."
    prev_datasource_hash="$curr_datasource_hash"
  fi
done
