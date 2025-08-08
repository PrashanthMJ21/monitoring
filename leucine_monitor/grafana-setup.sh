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
GRAFANA_URL="https://prod-monitoring.leucinetech.com"
GRAFANA_USER="admin"
GRAFANA_PASS="fhbv@4JUbkgmb"
SERVICE_ACCOUNT_NAME="provisioning-sa"
TOKEN_NAME="provisioning-token"
PROMETHEUS_DS_NAME="Prometheus"
ENV_FILE="./alerts/.env"
# ----------------------------------

set -e

echo "🔍 Checking if Docker, Compose v2, and containerd are installed..."

HAS_DOCKER=$(command -v docker >/dev/null 2>&1 && echo true || echo false)
HAS_COMPOSE_V2=$(docker compose version >/dev/null 2>&1 && echo true || echo false)
HAS_CONTAINERD=$(command -v containerd >/dev/null 2>&1 && echo true || echo false)
HAS_COMPOSE_V1=$(command -v docker-compose >/dev/null 2>&1 && echo true || echo false)

if [[ "$HAS_DOCKER" == "true" && "$HAS_COMPOSE_V2" == "true" && "$HAS_CONTAINERD" == "true" ]]; then
  echo "✅ Docker, Docker Compose v2, and containerd are already installed. Skipping installation."
else
  echo "📦 Installing Docker and Compose v2 using official Docker repository..."

  sudo apt remove -y docker docker-engine docker.io containerd runc || true

  sudo apt update -y
  sudo apt install -y ca-certificates curl gnupg lsb-release

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  sudo systemctl enable docker
  sudo systemctl start docker

  echo "✅ Docker version: $(docker --version)"
  echo "✅ Docker Compose version: $(docker compose version)"
fi

if [[ "$HAS_COMPOSE_V1" == "true" ]]; then
  echo "⚠️ Removing old docker-compose v1 binary..."
  sudo rm -f /usr/local/bin/docker-compose
fi

echo "📦 Installing essential packages: git, curl, inotify-tools..."
sudo apt install -y git curl inotify-tools

echo "📦 Installing jq v1.7 manually..."
sudo wget -q -O /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64
sudo chmod +x /usr/local/bin/jq
echo "✅ jq version: $(jq --version)"

echo "📦 Installing yq..."
sudo wget -q -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
echo "✅ yq version: $(yq --version)"

if [ ! -d "$REPO_DIR/leucine_monitor" ] || [ ! -f "$REPO_DIR/leucine_monitor/docker-compose.yml" ]; then
  echo "⚠️ Repo missing or incomplete. Cleaning up and re-cloning..."
  sudo rm -rf "$REPO_DIR"
  git clone "$REPO_URL"
else
  echo "✅ Repo already exists and looks complete."
fi

cd "$REPO_DIR/leucine_monitor"

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
sudo docker compose run --rm init-perms

# 🔐 Fix Grafana volume permissions before startup
echo "🔐 Fixing Grafana DB volume permissions..."
sudo chown -R 472:472 ./data-volumes/grafana
sudo chmod -R u+rwX ./data-volumes/grafana

# 📁 Ensure alerts/.env directory exists
mkdir -p ./alerts

# 🐳 Start services
echo "🐳 Starting Docker containers..."
sudo docker compose up -d

# ⏳ Wait for Grafana to become available (with timeout)
echo "⏳ Waiting for Grafana to become online..."
for i in {1..30}; do
  if curl -s -u $GRAFANA_USER:$GRAFANA_PASS "$GRAFANA_URL/api/health" | grep -q 'database'; then
    echo "✅ Grafana is online."
    break
  fi
  sleep 3
  if [ "$i" -eq 30 ]; then
    echo "❌ Timeout: Grafana did not come online."
    exit 1
  fi
done
# Change ownership to Grafana user inside container (472)
sudo chown -R 472:472 ./data-volumes/grafana

# Ensure writable permissions
sudo chmod -R u+rwX ./data-volumes/grafana

# 🆔 Create service account & token
echo "🆔 Creating service account: $SERVICE_ACCOUNT_NAME"
SA_RESPONSE=$(curl -s -u $GRAFANA_USER:$GRAFANA_PASS -X POST "$GRAFANA_URL/api/serviceaccounts" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$SERVICE_ACCOUNT_NAME\", \"role\": \"Admin\"}")
SA_ID=$(echo "$SA_RESPONSE" | jq -r '.id')

if [ "$SA_ID" == "null" ] || [ -z "$SA_ID" ]; then
  echo "❌ Failed to create service account. Raw response:"
  echo "$SA_RESPONSE"
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
echo "🔎 Fetching Prometheus datasource UID..."
PROMETHEUS_UID=$(curl -s -H "Authorization: $API_KEY" "$GRAFANA_URL/api/datasources" \
  | jq -r '.[] | select(.type=="prometheus") | .uid')

echo "✅ Prometheus UID: $PROMETHEUS_UID"

# 💾 Save credentials and UID
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
