#!/bin/bash
# cleanup_daemon.sh — Auto-destroys expired sandbox environments
# Runs every 60 seconds checking TTL of all active environments
# Usage: ./cleanup_daemon.sh &

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
ENVS_DIR="$BASE_DIR/envs"
LOG_FILE="$BASE_DIR/logs/cleanup.log"

# Create logs directory if it doesn't exist
mkdir -p "$BASE_DIR/logs"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" | tee -a "$LOG_FILE"
}

log "🚀 Cleanup daemon started (PID: $$)"

while true; do
    # Check each environment state file
    for STATE_FILE in "$ENVS_DIR"/*.json; do
        # Skip if no files found
        [ -f "$STATE_FILE" ] || continue

        # Read environment details
        ENV_ID=$(jq -r '.id' "$STATE_FILE")
        ENV_NAME=$(jq -r '.name' "$STATE_FILE")
        EXPIRES_AT=$(jq -r '.expires_at' "$STATE_FILE")
        STATUS=$(jq -r '.status' "$STATE_FILE")

        # Skip already destroyed envs
        [ "$STATUS" = "destroyed" ] && continue

        # Check if expired
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        EXPIRES_EPOCH=$(date -d "$EXPIRES_AT" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date -u +%s)

        if [ "$NOW_EPOCH" -gt "$EXPIRES_EPOCH" ]; then
            log "⏰ Environment $ENV_NAME ($ENV_ID) has expired — destroying..."
            bash "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG_FILE" 2>&1
            log "✅ Environment $ENV_NAME ($ENV_ID) destroyed by cleanup daemon"
        fi
    done

    # Sleep 60 seconds before next check
    sleep 60
done
