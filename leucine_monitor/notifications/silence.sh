#!/bin/bash
set -euo pipefail

# --- Config / env ---
ENV_FILE="$HOME/monitoring/leucine_monitor/alerts/.env"
[[ -f "$ENV_FILE" ]] || { echo "❌ .env not found at $ENV_FILE"; exit 1; }
set -o allexport; source "$ENV_FILE"; set +o allexport

[[ -n "${GRAFANA_URL:-}" ]] || { echo "❌ GRAFANA_URL empty in .env"; exit 1; }

# --- Auth header: prefer SA token, else API key ---
if [[ -n "${SERVICE_ACCOUNT_TOKEN:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer ${SERVICE_ACCOUNT_TOKEN}"
elif [[ -n "${API_KEY:-}" ]]; then
  if [[ "$API_KEY" == Bearer* ]]; then AUTH_HEADER="Authorization: ${API_KEY}"
  else AUTH_HEADER="Authorization: Bearer ${API_KEY}"; fi
else
  echo "❌ No SERVICE_ACCOUNT_TOKEN or API_KEY in .env"; exit 1
fi

# --- AM v2 endpoints ---
AM_BASE="${GRAFANA_URL%/}/api/alertmanager/grafana/api/v2"
STATUS_URL="$AM_BASE/status"
SILENCES_URL="$AM_BASE/silences"

# --- Probe auth ---
probe_code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$STATUS_URL")
[[ "$probe_code" == "200" ]] || { echo "❌ Auth probe failed ($probe_code)"; exit 1; }

# ====== Time windows (TOMORROW in Asia/Kolkata) ======
WINDOW_TZ="Asia/Kolkata"
DAYS_AHEAD="${1:-1}"     # default = 1 (tomorrow), override: ./silence.sh 2

# Local windows (IST)
WIN1_START="00:00"; WIN1_END="00:20"
WIN2_START="03:00"; WIN2_END="03:20"

# Return local epoch seconds for a given YYYY-MM-DD and HH:MM in WINDOW_TZ
local_epoch() { TZ="$WINDOW_TZ" date -d "$1 $2" +%s; }
# Convert epoch to RFC3339 Z
to_rfc3339z() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ"; }

# Compute target local date = today + DAYS_AHEAD
target_local_date=$(TZ="$WINDOW_TZ" date -d "+${DAYS_AHEAD} day" +%Y-%m-%d)

s1_local=$(local_epoch "$target_local_date" "$WIN1_START")
e1_local=$(local_epoch "$target_local_date" "$WIN1_END")
s2_local=$(local_epoch "$target_local_date" "$WIN2_START")
e2_local=$(local_epoch "$target_local_date" "$WIN2_END")

START1_UTC=$(to_rfc3339z "$s1_local")
END1_UTC=$(to_rfc3339z "$e1_local")
START2_UTC=$(to_rfc3339z "$s2_local")
END2_UTC=$(to_rfc3339z "$e2_local")

echo "🕒 WINDOW_TZ=$WINDOW_TZ  DAYS_AHEAD=$DAYS_AHEAD (target local date: $target_local_date)"
echo "   00:00–00:20 local → $START1_UTC → $END1_UTC (UTC)"
echo "   03:00–03:20 local → $START2_UTC → $END2_UTC (UTC)"

# ====== Payload + POST ======
FOLDERS=("CPU-Usage" "Memory-Usage" "Disk-Usage" "Blackbox")

post_silence () {
  local folder="$1" start="$2" end="$3"
  echo "🔕 Creating silence for grafana_folder=${folder} | ${start} → ${end}"

  payload=$(jq -n --arg folder "$folder" --arg start "$start" --arg end "$end" \
    '{ matchers:[{name:"grafana_folder",value:$folder,isRegex:false}],
       startsAt:$start, endsAt:$end,
       createdBy:"grafana-auto-silencer",
       comment:"Auto silence for grafana_folder=\($folder)"}')

  resp=$(curl -s -w "\n%{http_code}" -X POST "$SILENCES_URL" \
          -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$payload")
  body=$(echo "$resp" | sed '$d'); code=$(echo "$resp" | tail -n1)

  if [[ "$code" =~ ^20[0-2]$ ]]; then
    id=$(echo "$body" | jq -r '.id? // .silenceID? // empty')
    [[ -n "$id" ]] && echo "✅ Created silence id: $id" || echo "✅ Silence created"
  else
    echo "❌ Failed ($code): $(echo "$body" | jq -r '.message? // .error? // .status? // . | tostring')"
  fi


for f in "${FOLDERS[@]}"; do
  post_silence "$f" "$START1_UTC" "$END1_UTC"
  post_silence "$f" "$START2_UTC" "$END2_UTC"
done


