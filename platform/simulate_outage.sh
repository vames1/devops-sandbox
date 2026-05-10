#!/bin/bash
# simulate_outage.sh — Injects chaos into a sandbox environment
# Usage: ./simulate_outage.sh --env <env_id> --mode <crash|pause|network|recover>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$BASE_DIR/envs"

# ── Parse arguments ────────────────────────────────────────────────────────────
ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --env) ENV_ID="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) echo "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_ID" ] || [ -z "$MODE" ]; then
    echo "❌ Usage: $0 --env <env_id> --mode <crash|pause|network|recover>"
    exit 1
fi

# ── Safety guard — never run against platform containers ──────────────────────
CONTAINER_NAME="sandbox-app-$ENV_ID"

# Check this isn't a platform container
if [[ "$CONTAINER_NAME" == "sandbox-nginx" ]] || \
   [[ "$CONTAINER_NAME" == "sandbox-daemon" ]] || \
   [[ "$CONTAINER_NAME" == "sandbox-api" ]]; then
    echo "❌ SAFETY GUARD: Cannot simulate outage on platform containers!"
    exit 1
fi

# ── Check environment exists ───────────────────────────────────────────────────
STATE_FILE="$ENVS_DIR/$ENV_ID.json"
if [ ! -f "$STATE_FILE" ]; then
    echo "❌ Environment $ENV_ID not found"
    exit 1
fi

ENV_NAME=$(jq -r '.name' "$STATE_FILE")
NETWORK=$(jq -r '.network' "$STATE_FILE")

echo "⚡ Simulating outage: $MODE on $ENV_NAME ($ENV_ID)"

case "$MODE" in
    crash)
        echo "💥 Crashing container $CONTAINER_NAME..."
        docker kill "$CONTAINER_NAME" 2>/dev/null || echo "Container may already be stopped"
        echo "✅ Container crashed — health monitor should detect within 90s"
        ;;

    pause)
        echo "⏸️  Pausing container $CONTAINER_NAME..."
        docker pause "$CONTAINER_NAME"
        echo "✅ Container paused — use --mode recover to unpause"
        ;;

    network)
        echo "🌐 Disconnecting container from network..."
        docker network disconnect "$NETWORK" "$CONTAINER_NAME"
        echo "✅ Network disconnected — use --mode recover to reconnect"
        ;;

    recover)
        echo "🔄 Recovering environment $ENV_NAME..."

        # Try to unpause if paused
        docker unpause "$CONTAINER_NAME" 2>/dev/null && echo "  ✅ Container unpaused" || true

        # Try to reconnect network if disconnected
        docker network connect "$NETWORK" "$CONTAINER_NAME" 2>/dev/null && echo "  ✅ Network reconnected" || true

        # Try to restart if crashed
        if ! docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
            docker start "$CONTAINER_NAME" 2>/dev/null && echo "  ✅ Container restarted" || true
        fi

        # Reset status to running in state file
        TEMP=$(mktemp)
        jq '.status = "running"' "$STATE_FILE" > "$TEMP"
        mv "$TEMP" "$STATE_FILE"

        echo "✅ Environment $ENV_NAME recovered!"
        ;;

    *)
        echo "❌ Unknown mode: $MODE"
        echo "   Valid modes: crash, pause, network, recover"
        exit 1
        ;;
esac
