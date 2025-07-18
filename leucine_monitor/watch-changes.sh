#!/bin/bash

# -------- SETTINGS --------
ROOT_DIR="$(realpath "$(dirname "$0")")"
ENV_FILE="$ROOT_DIR/alerts/.env"
ALERTS_DIR="$ROOT_DIR/alerts/alert-details"
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

# -------- INIT HASHES --------
# Notification and datasource hashes (single files)
get_hash() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

prev_template_hash=$(get_hash "$NOTIF_TEMPLATE_FILE")
prev_contact_hash=$(get_hash "$CONTACT_FILE")
prev_datasource_hash=$(get_hash "$DATASOURCE_FILE")

# Alert hashes (per file)
declare -A file_hash_map
for file in "$ALERTS_DIR"/*.yml; do
  [ -f "$file" ] || continue
  file_hash_map["$file"]="$(get_hash "$file")"
done
# -----------------------------

# -------- WATCH LOOP --------
while true; do
  sleep "$SLEEP_INTERVAL"

  # 🔁 Check alert files one by one
  for file in "$ALERTS_DIR"/*.yml; do
    [ -f "$file" ] || continue
    curr_hash=$(get_hash "$file")
    prev_hash="${file_hash_map[$file]}"

    if [ "$curr_hash" != "$prev_hash" ]; then
      echo "🚨 Change detected in: $(basename "$file")"
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" YAML_FILE="$file" "$ALERT_SCRIPT"
      echo "✅ Synced alerts from: $(basename "$file")"
      file_hash_map["$file"]=$curr_hash
    fi
  done

  # 🔁 Check notification templates and contact points
  curr_template_hash=$(get_hash "$NOTIF_TEMPLATE_FILE")
  curr_contact_hash=$(get_hash "$CONTACT_FILE")

  if [ "$curr_template_hash" != "$prev_template_hash" ] || [ "$curr_contact_hash" != "$prev_contact_hash" ]; then
    echo "📬 Detected change in notification files — Re-deploying..."
    GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT"
    echo "✅ Notifications updated."
    prev_template_hash="$curr_template_hash"
    prev_contact_hash="$curr_contact_hash"
  fi

  # 🔁 Check datasource config
  curr_datasource_hash=$(get_hash "$DATASOURCE_FILE")
  if [ "$curr_datasource_hash" != "$prev_datasource_hash" ]; then
    echo "📡 Detected datasource.yml change — Restarting Grafana..."
    docker-compose restart grafana
    echo "✅ Grafana restarted."
    prev_datasource_hash="$curr_datasource_hash"
  fi
done
