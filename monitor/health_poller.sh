#!/bin/bash
# health_poller.sh — Monitors health of all active sandbox environments
# Polls /health endpoint every 30 seconds
# Usage: ./health_poller.sh &

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$BASE_DIR/envs"
LOGS_DIR="$BASE_DIR/logs"

# Track consecutive failures per env
declare -A FAIL_COUNT

log_health() {
    local ENV_ID=$1
    local STATUS=$2
    local LATENCY=$3
    local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$TIMESTAMP | $STATUS | ${LATENCY}ms" >> "$LOGS_DIR/$ENV_ID/health.log"
}

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] 🚀 Health poller started (PID: $$)"

while true; do
    for STATE_FILE in "$ENVS_DIR"/*.json; do
        [ -f "$STATE_FILE" ] || continue

        ENV_ID=$(jq -r '.id' "$STATE_FILE")
        PORT=$(jq -r '.port' "$STATE_FILE")
        STATUS=$(jq -r '.status' "$STATE_FILE")

        # Skip degraded or non-running envs
        [ "$STATUS" = "destroyed" ] && continue

        # Create log dir if missing
        mkdir -p "$LOGS_DIR/$ENV_ID"

        # Poll /health endpoint
        START=$(date +%s%3N)
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 \
            "http://localhost:$PORT/health" 2>/dev/null)
        END=$(date +%s%3N)
        LATENCY=$((END - START))

        if [ "$HTTP_STATUS" = "200" ]; then
            # Reset failure count on success
            FAIL_COUNT[$ENV_ID]=0
            log_health "$ENV_ID" "200" "$LATENCY"
        else
            # Increment failure count
            FAIL_COUNT[$ENV_ID]=$((${FAIL_COUNT[$ENV_ID]:-0} + 1))
            log_health "$ENV_ID" "${HTTP_STATUS:-000}" "$LATENCY"

            echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ⚠️  $ENV_ID health check failed (${FAIL_COUNT[$ENV_ID]}/3)"

            # Mark as degraded after 3 consecutive failures
            if [ "${FAIL_COUNT[$ENV_ID]}" -ge 3 ]; then
                echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] 🔴 $ENV_ID is DEGRADED after 3 failures!"

                # Update status in state file atomically
                TEMP=$(mktemp)
                jq '.status = "degraded"' "$STATE_FILE" > "$TEMP"
                mv "$TEMP" "$STATE_FILE"
            fi
        fi
    done

    sleep 30
done
