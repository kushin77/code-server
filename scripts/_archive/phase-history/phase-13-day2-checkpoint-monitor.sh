#!/bin/bash
################################################################################
# Phase 13 Day 2: Automated Checkpoint Monitoring System
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Monitor and report on 24-hour load test at key intervals
# Checkpoints: 2h, 6h, 12h, 23h55m, 24h
# Idempotence: Safe to run multiple times, checks state before action
# IaC: All config via environment variables
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

TARGET_HOST=${TARGET_HOST:-"192.168.168.31"}
TARGET_USER=${TARGET_USER:-"akushnir"}
DEPLOYMENT_DIR=${DEPLOYMENT_DIR:-"/tmp/code-server-phase13"}
PHASE_13_START_TIME=${PHASE_13_START_TIME:-"2026-04-13T17:42:00Z"}
CHECKPOINT_LOG="/tmp/phase-13-checkpoints.log"

# Checkpoint intervals (in seconds from start)
declare -a CHECKPOINTS=(
    "7200"    # 2 hours
    "21600"   # 6 hours
    "43200"   # 12 hours
    "86100"   # 23h 55m
    "86400"   # 24 hours
)

declare -a CHECKPOINT_NAMES=(
    "2-HOUR"
    "6-HOUR"
    "12-HOUR"
    "23h55m-COOLDOWN"
    "24-HOUR-COMPLETION"
)

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_checkpoint() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $@" | tee -a "$CHECKPOINT_LOG"
}

get_elapsed_seconds() {
    local start_epoch=$(date -d "$PHASE_13_START_TIME" +%s)
    local current_epoch=$(date +%s)
    echo $((current_epoch - start_epoch))
}

get_remaining_seconds() {
    local start_epoch=$(date -d "$PHASE_13_START_TIME" +%s)
    local current_epoch=$(date +%s)
    local elapsed=$((current_epoch - start_epoch))
    echo $((86400 - elapsed))
}

# ─────────────────────────────────────────────────────────────────────────────
# Checkpoint Assessment Functions
# ─────────────────────────────────────────────────────────────────────────────

check_infrastructure_health() {
    log_checkpoint "  Infrastructure Health Check:"

    ssh -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_HOST}" bash << 'CHECK_SCRIPT'
echo "    Docker Containers:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | tail -3 | while read line; do
    echo "      $line"
done
echo "    Memory Utilization:"
free -h | awk 'NR==2 {print "      Total: " $2 ", Used: " $3 " (" int($3/$2*100) "%)"}'
echo "    Load Generators:"
pgrep -f 'bash.*while' | wc -l | awk '{print "      Active: " $1 " processes"}'
CHECK_SCRIPT
}

check_slo_metrics() {
    log_checkpoint "  SLO Metrics:"

    ssh -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_HOST}" bash << 'SLO_SCRIPT'
# Get latest metrics checkpoint
LATEST_METRICS=$(ls -t /tmp/phase-13-metrics/metrics-*.log 2>/dev/null | head -1)
if [ -n "$LATEST_METRICS" ]; then
    echo "    Latest metrics from: $(basename $LATEST_METRICS)"
    tail -3 "$LATEST_METRICS" | grep -E "Response Time|Load Generator" | while read line; do
        echo "      $line"
    done
else
    echo "    No metrics collected yet"
fi

# Test endpoint health
RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null http://localhost/ 2>/dev/null | tail -c 3)
echo "    Current endpoint: HTTP $RESPONSE"
SLO_SCRIPT
}

execute_checkpoint() {
    local checkpoint_num=$1
    local checkpoint_name=$2
    local checkpoint_secs=$3

    log_checkpoint ""
    log_checkpoint "─────────────────────────────────────────────────────────────"
    log_checkpoint "CHECKPOINT $checkpoint_num: $checkpoint_name"
    log_checkpoint "─────────────────────────────────────────────────────────────"
    log_checkpoint "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    log_checkpoint "Expected At: $checkpoint_secs seconds into Phase 13"

    # Check infrastructure
    check_infrastructure_health

    # Check SLO metrics
    check_slo_metrics

    # Decision points
    case $checkpoint_secs in
        86100)
            log_checkpoint "  [DECISION] Ready to execute cool-down phase"
            log_checkpoint "  [ACTION] Cool-down phase will begin in 5 minutes"
            ;;
        86400)
            log_checkpoint "  [DECISION] Phase 13 Day 2 complete, initiate go/no-go decision"
            log_checkpoint "  [ACTION] Collecting final metrics for decision..."
            ;;
    esac

    log_checkpoint ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Checkpoint Loop
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_checkpoint "═══════════════════════════════════════════════════════════════"
    log_checkpoint "PHASE 13 DAY 2: AUTOMATED CHECKPOINT MONITORING SYSTEM"
    log_checkpoint "═══════════════════════════════════════════════════════════════"
    log_checkpoint "Start Time: $PHASE_13_START_TIME"
    log_checkpoint "Current Time: $(date '+%Y-%m-%d %H:%M:%S')"

    local elapsed=$(get_elapsed_seconds)
    local remaining=$(get_remaining_seconds)

    log_checkpoint "Elapsed: ${elapsed}s | Remaining: ${remaining}s"
    log_checkpoint "Checkpoint Log: $CHECKPOINT_LOG"
    log_checkpoint ""

    # Infinite loop checking for checkpoint times
    while true; do
        local current_elapsed=$(get_elapsed_seconds)

        # Check if Phase 13 is complete
        if [ "$current_elapsed" -ge 86400 ]; then
            log_checkpoint "✓ Phase 13 Day 2 Complete (${current_elapsed}s elapsed)"
            break
        fi

        # Check each checkpoint
        for i in "${!CHECKPOINTS[@]}"; do
            local checkpoint_secs=${CHECKPOINTS[$i]}
            local checkpoint_name=${CHECKPOINT_NAMES[$i]}

            # If we've reached this checkpoint (within 60 second window)
            if [ "$current_elapsed" -ge "$checkpoint_secs" ] && [ "$current_elapsed" -lt "$((checkpoint_secs + 60))" ]; then
                # Check if we've already logged this checkpoint
                if ! grep -q "CHECKPOINT.*$checkpoint_name" "$CHECKPOINT_LOG" 2>/dev/null; then
                    execute_checkpoint "$((i+1))" "$checkpoint_name" "$checkpoint_secs"
                fi
            fi
        done

        # Sleep 30 seconds before next check
        sleep 30
    done

    log_checkpoint "═══════════════════════════════════════════════════════════════"
    log_checkpoint "Phase 13 Day 2 Checkpoint Monitoring Complete"
    log_checkpoint "═══════════════════════════════════════════════════════════════"
}

# Execute
main "$@"
