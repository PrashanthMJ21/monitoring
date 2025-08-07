#!/bin/bash

###############################################################################
# 🚀 GRAFANA MONITORING BOOTSTRAP SCRIPT
#
# This script automates the end-to-end provisioning of a complete Grafana
# monitoring stack using Docker Compose. It includes:
#   - Installing dependencies (Docker, jq, yq, etc.)
#   - Cloning the monitoring GitHub repository
#   - Setting up volume directories and permissions
#   - Starting Grafana, Prometheus, Loki, Tempo, and Promtail containers
#   - Creating a Grafana service account and generating a bearer API token
#   - Dynamically fetching the Prometheus datasource UID
#   - Saving credentials and configuration to `alerts/.env`
#   - Pushing contact points, alert rules, and dashboards via API
#   - Launching a watcher to auto-sync future changes
###############################################################################

# ----------- SETTINGS -------------
REPO_URL="https://github.com/PrashanthMJ21/monitoring.git"
REPO_DIR="monitoring"
GRAFANA_URL="prod-monitoring.leucinetech.com"
GRAFANA_USER="admin"
GRAFANA_PASS="fhbv@4JUbkgmb"
SERVICE_ACCOUNT_NAME="provisioning-sa"
TOKEN_NAME="provisioning-token"
PROMETHEUS_DS_NAME="Prometheus"
ENV_FILE="./alerts/.env"
# ----------------------------------

set -e

echo "📦 Installing base packages..."
sudo apt update -y
sudo apt install -y git curl docker.io docker-compose inotify-tools

sudo systemctl start docker
sudo systemctl enable docker

echo "📦 Installing jq v1.7 manually..."
sudo wget -q -O /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64
sudo chmod +x /usr/local/bin/jq
echo "✅ jq version: $(jq --version)"

echo "📦 Installing yq..."
sudo wget -q -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
echo "✅ yq version: $(yq --version)"

# 📁 Clone repo if not present
if [ ! -d "$REPO_DIR" ]; then
  git clone "$REPO_URL"
fi
cd "$REPO_DIR/leucine_monitor"

# ✅ Verify docker-compose file exists
if [ ! -f "docker-compose.yml" ]; then
  echo "❌ docker-compose.yml not found in $(pwd)"
  exit 1
fi

# 📁 Create ./data-volumes folder structure
echo "📁 Preparing ./data-volumes folders..."
for dir in grafana prometheus loki promtail tempo; do
  mkdir -p ./data-volumes/$dir
done
mkdir -p ./data-volumes/grafana/plugins
mkdir -p ./data-volumes/prometheus/rules
mkdir -p ./data-volumes/loki/{rules,chunks,compactor,tsdb-shipper-cache,tsdb-shipper-active/uploader}
mkdir -p ./data-volumes/tempo

# 🔧 Run init-perms container to fix ownership
echo "🔧 Running init-perms container to fix volume ownership..."
sudo docker-compose run --rm init-perms

# 📁 Ensure alerts/.env directory exists
mkdir -p ./alerts

# 🐳 Start services
echo "🐳 Starting Docker containers..."
sudo docker-compose up -d

# ⏳ Wait for Grafana to become available
echo "⏳ Waiting for Grafana to come online..."
until curl -s -u $GRAFANA_USER:$GRAFANA_PASS "$GRAFANA_URL/api/health" | grep -q 'database'; do
  sleep 3
done

# 🆔 Create service account & token
echo "🆔 Creating service account: $SERVICE_ACCOUNT_NAME"
SA_RESPONSE=$(curl -s -u $GRAFANA_USER:$GRAFANA_PASS -X POST "$GRAFANA_URL/api/serviceaccounts" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$SERVICE_ACCOUNT_NAME\", \"role\": \"Admin\"}")
SA_ID=$(echo "$SA_RESPONSE" | jq -r '.id')

if [ "$SA_ID" == "null" ] || [ -z "$SA_ID" ]; then
  echo "❌ Failed to create service account."
  exit 1
fi

echo "🔐 Generating API token..."
TOKEN_RESPONSE=$(curl -s -u $GRAFANA_USER:$GRAFANA_PASS -X POST "$GRAFANA_URL/api/serviceaccounts/$SA_ID/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$TOKEN_NAME\", \"secondsToLive\": 0}")
RAW_KEY=$(echo "$TOKEN_RESPONSE" | jq -r '.key')

if [ -z "$RAW_KEY" ] || [ "$RAW_KEY" == "null" ]; then
  echo "❌ Failed to generate API key."
  exit 1
fi

API_KEY="Bearer $RAW_KEY"
echo "✅ Token created and stored"

# 🔎 Fetch Prometheus UID
echo "🔎 Fetching datasource UID..."
PROMETHEUS_UID=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/datasources" \
  | jq -r '.[] | select(.type=="prometheus") | .uid')

echo "✅ Prometheus UID: $PROMETHEUS_UID"

# �� Save credentials and UID
echo "GRAFANA_URL=\"$GRAFANA_URL\"" > "$ENV_FILE"
echo "API_KEY=\"$API_KEY\"" >> "$ENV_FILE"
echo "PROMETHEUS_UID=\"$PROMETHEUS_UID\"" >> "$ENV_FILE"
echo "🔒 Saved credentials to $ENV_FILE"

# ✅ Make scripts executable
chmod +x ./alerts/generate-and-push-alerts.sh
chmod +x ./notifications/provision-notifications.sh
chmod +x ./dashboards/push-dashboard.sh

# 📬 Contact points
echo "📬 Provisioning contact points..."
GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" ./notifications/provision-notifications.sh

# 🚨 Alerts
echo "🚨 Pushing alert rules..."
source "$ENV_FILE"
if [ -z "$PROMETHEUS_UID" ]; then
  echo "❌ PROMETHEUS_UID is not set. Exiting..."
  exit 1
fi
GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" PROMETHEUS_UID="$PROMETHEUS_UID" ./alerts/generate-and-push-alerts.sh

# 📊 Dashboards
echo "📊 Pushing dashboards..."
GRAFANA_URL="$GRAFANA_URL" API_KEY="$API_KEY" ./dashboards/push-dashboard.sh

# 👀 Watcher
chmod +x ./watch-changes.sh
echo "👀 Starting watcher..."
nohup ./watch-changes.sh > ./alerts/watcher.log 2>&1 &

echo "✅ Bootstrap complete."

