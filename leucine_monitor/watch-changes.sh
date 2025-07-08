#!/bin/bash

# -------- SETTINGS --------
REPO_DIR="$HOME/monitoring/leucine_monitor"

ENV_FILE="$REPO_DIR/alerts/.env"
ALERT_FILE="$REPO_DIR/alerts/alert-details.yml"
NOTIF_TEMPLATE_FILE="$REPO_DIR/notifications/notification-templates.yml"
CONTACT_FILE="$REPO_DIR/notifications/contact-points.yml"
DATASOURCE_FILE="$REPO_DIR/provisioning/datasources/datasources.yml"

ALERT_SCRIPT="$REPO_DIR/alerts/generate-and-push-alerts.sh"
NOTIF_SCRIPT="$REPO_DIR/notifications/provision-notifications.sh"
# --------------------------

echo "👀 Watching for changes..."
echo "🔁 Press Ctrl+C to stop."

# Check dependencies
if ! command -v inotifywait >/dev/null; then
  echo "❌ 'inotifywait' not found. Please install inotify-tools."
  exit 1
fi

# Ensure .env is sourced
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❌ Env file not found: $ENV_FILE"
  exit 1
fi

# Validate scripts
for script in "$ALERT_SCRIPT" "$NOTIF_SCRIPT"; do
  if [ ! -f "$script" ]; then
    echo "❌ Required script missing: $script"
    exit 1
  fi
done

# Start watcher
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
      echo "📬 Re-deploying contact points and templates..."
      GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" "$NOTIF_SCRIPT"
      echo "✅ Notifications updated."
      ;;

    *datasources.yml)
      echo "📡 Datasource config changed. Restarting Grafana..."
      cd "$REPO_DIR"
      docker-compose restart grafana
      echo "✅ Grafana restarted."
      ;;
    *)
      echo "⚠️ No action for: $changed_file"
      ;;
  esac
done
