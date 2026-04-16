#!/bin/bash
# scripts/health/health-recover.sh
# Part of Phase 7d-003: Health Checks & Automatic Failover

set -e

SERVICE=$1
RESTART_COUNT_FILE="/tmp/${SERVICE}_restart_count"
MAX_RESTARTS=3
COOLDOWN=60 # Seconds between restart attempts

if [[ -z "$SERVICE" ]]; then
    echo "Usage: $0 [service_name]"
    exit 1
fi

# Detect if we should attempt recovery
count=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "0")

# 1. Check if service is actually down
if ! docker ps --filter "name=$SERVICE" --format '{{.Status}}' | grep -q "Up"; then
    echo "[RECOVERY] $SERVICE is down (current restarts: $count)"
    
    if [[ $count -lt $MAX_RESTARTS ]]; then
        echo "[RECOVERY] Restarting $SERVICE (attempt $((count + 1))/$MAX_RESTARTS)..."
        docker-compose restart "$SERVICE"
        
        # Update counter
        echo $((count + 1)) > "$RESTART_COUNT_FILE"
        
        # Check success after a brief wait
        sleep 5
        if docker ps --filter "name=$SERVICE" --format '{{.Status}}' | grep -q "Up"; then
            echo "[SUCCESS] $SERVICE recovered successfully."
        else
            echo "[FAIL] $SERVICE failed to recover."
        fi
    else
        echo "[CRITICAL] $SERVICE max restart attempts exceeded ($count). Manual intervention required."
        # Could integrate with Slack/PagerDuty here
        exit 1
    fi
else
    # Service is healthy, reset counter
    if [[ $count -gt 0 ]]; then
        echo "[INFO] $SERVICE is healthy, resetting restart counter."
        echo "0" > "$RESTART_COUNT_FILE"
    fi
fi

exit 0
