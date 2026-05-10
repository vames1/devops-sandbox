#!/bin/bash
# destroy_env.sh — Destroys a sandbox environment completely
# Usage: ./destroy_env.sh <env_id>

set -e

# ── Arguments ─────────────────────────────────────────────────────────────────
ENV_ID="${1}"
if [ -z "$ENV_ID" ]; then
    echo "❌ Usage: $0 <env_id>"
    exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$BASE_DIR/envs"
LOGS_DIR="$BASE_DIR/logs"
NGINX_CONF_DIR="$BASE_DIR/nginx/conf.d"
STATE_FILE="$ENVS_DIR/$ENV_ID.json"

# ── Check state file exists ────────────────────────────────────────────────────
if [ ! -f "$STATE_FILE" ]; then
    echo "❌ Environment $ENV_ID not found"
    exit 1
fi

# ── Read state file ────────────────────────────────────────────────────────────
CONTAINER=$(jq -r '.container' "$STATE_FILE")
NETWORK=$(jq -r '.network' "$STATE_FILE")
LOG_PID=$(jq -r '.log_pid' "$STATE_FILE")
ENV_NAME=$(jq -r '.name' "$STATE_FILE")

echo "🗑️  Destroying environment: $ENV_NAME ($ENV_ID)"

# ── Kill log shipping process ──────────────────────────────────────────────────
echo "📝 Stopping log shipping (PID: $LOG_PID)..."
if [ -n "$LOG_PID" ] && [ "$LOG_PID" != "null" ]; then
    kill "$LOG_PID" 2>/dev/null || true
fi
# Also kill from PID file if exists
PID_FILE="$LOGS_DIR/$ENV_ID/log_ship.pid"
if [ -f "$PID_FILE" ]; then
    kill "$(cat $PID_FILE)" 2>/dev/null || true
    rm -f "$PID_FILE"
fi

# ── Stop and remove containers ─────────────────────────────────────────────────
echo "📦 Removing containers..."
docker ps -q --filter "label=sandbox.env=$ENV_ID" | xargs -r docker stop 2>/dev/null || true
docker ps -aq --filter "label=sandbox.env=$ENV_ID" | xargs -r docker rm 2>/dev/null || true

# ── Remove Docker network ──────────────────────────────────────────────────────
echo "🌐 Removing Docker network: $NETWORK..."
docker network rm "$NETWORK" 2>/dev/null || true

# ── Archive logs ───────────────────────────────────────────────────────────────
echo "📁 Archiving logs..."
if [ -d "$LOGS_DIR/$ENV_ID" ]; then
    mkdir -p "$LOGS_DIR/archived"
    cp -r "$LOGS_DIR/$ENV_ID" "$LOGS_DIR/archived/$ENV_ID"
    rm -rf "$LOGS_DIR/$ENV_ID"
fi

# ── Remove Nginx config and reload ────────────────────────────────────────────
echo "🔧 Removing Nginx route..."
rm -f "$NGINX_CONF_DIR/$ENV_ID.conf"
docker exec sandbox-nginx nginx -s reload 2>/dev/null || true

# ── Delete state file ──────────────────────────────────────────────────────────
echo "💾 Deleting state file..."
rm -f "$STATE_FILE"

echo ""
echo "✅ Environment $ENV_NAME ($ENV_ID) destroyed successfully!"
echo "   Logs archived to: logs/archived/$ENV_ID/"
