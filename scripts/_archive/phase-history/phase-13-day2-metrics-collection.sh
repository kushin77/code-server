#!/bin/bash
################################################################################
# Phase 13 Day 2: Metrics Collection & Analysis Script
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Collect performance metrics every 5 minutes during 24-hour load test
# Interval: Every 300 seconds
# Metrics: Response times, throughput, errors, resource utilization
################################################################################

set -euo pipefail

# Configuration
COLLECTION_INTERVAL=${COLLECTION_INTERVAL:-300}  # 5 minutes
METRICS_DIR="/tmp/phase-13-metrics"
TIMESTAMP=$(date +%s)
METRICS_LOG="${METRICS_DIR}/metrics-${TIMESTAMP}.log"

# Create metrics directory
mkdir -p "$METRICS_DIR"

# Initialize logs
> "$METRICS_LOG"

log_metric() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $@" | tee -a "$METRICS_LOG"
}

log_metric "=== PHASE 13 DAY 2: METRICS COLLECTION STARTED ==="
log_metric "Start Time: $(date)"
log_metric "Collection Interval: ${COLLECTION_INTERVAL}s"
log_metric "Metrics Log: $METRICS_LOG"
log_metric ""

# Infinite monitoring loop
CHECKPOINT=0
while true; do
    CHECKPOINT=$((CHECKPOINT + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    log_metric "────────────────────────────────────────────────────────────────"
    log_metric "Checkpoint #$CHECKPOINT - $TIMESTAMP"
    log_metric "────────────────────────────────────────────────────────────────"

    # Collect system metrics
    log_metric "System Resources:"
    free -m | awk 'NR==2 {printf "[%s] Memory: %d MB used / %d MB total (%.1f%%)\n", FILENAME, $3, $2, ($3/$2)*100}' FILENAME="$TIMESTAMP" | tee -a "$METRICS_LOG"

    # Docker container stats
    log_metric "Container Status:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | tail -3 | while read line; do
        echo "[${TIMESTAMP}] $line" | tee -a "$METRICS_LOG"
    done

    # Load test process count
    load_procs=$(pgrep -c 'bash.*while.*curl' 2>/dev/null || echo 0)
    log_metric "Load Generators Active: $load_procs processes"

    # Network connectivity test
    response_time=$(timeout 5 curl -s -w "%{time_total}" -o /dev/null http://localhost/ 2>/dev/null || echo "TIMEOUT")
    log_metric "Code-Server Response Time: ${response_time}s"

    # Uptime
    log_metric "Container Uptime:"
    docker ps --format 'table {{.Names}}\t{{.RunningFor}}' 2>/dev/null | tail -3 | while read line; do
        echo "[${TIMESTAMP}] $line" | tee -a "$METRICS_LOG"
    done

    log_metric ""

    # Sleep until next collection
    sleep "$COLLECTION_INTERVAL"
done
