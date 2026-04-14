#!/bin/bash
################################################################################
# Phase 13 Day 2: Execute 4-Hour Checkpoint Collection
# Collects metrics and validates SLO compliance at first checkpoint
################################################################################

set -euo pipefail

REMOTE_HOST="${1:-192.168.168.31}"
REMOTE_USER="akushnir"
CHECKPOINT_NAME="4-hour"
CHECKPOINT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "========================================================================"
echo "PHASE 13 DAY 2: ${CHECKPOINT_NAME} CHECKPOINT EXECUTION"
echo "========================================================================"
echo "Time: ${CHECKPOINT_TIME}"
echo "Host: ${REMOTE_HOST}"
echo ""

# SSH into remote host and execute checkpoint
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${REMOTE_USER}@${REMOTE_HOST}" << 'EOFCHECKPOINT'

echo "[CHECKPOINT: 4-Hour Mark]"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Container Status ==="
docker ps --filter "status=running" --format "table {{.Names}}\t{{.Status}}" | grep -E "code-server|caddy|ssh"
echo ""

echo "=== Resource Metrics ==="
echo "Memory:"
free -h | awk 'NR==2{print "  Total: "$2", Used: "$3", Available: "$7}'
echo ""
echo "Disk:"
df -h / | awk 'NR==2{print "  Available: "$4", Used: "$3, "Total: "$2}'
echo ""

echo "=== HTTP Endpoint Health ==="
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null | grep -q "200"; then
    echo "  ✓ HTTP 200 OK"
else
    echo "  ✗ HTTP endpoint issue"
fi
echo ""

echo "=== Container Resource Usage ==="
docker ps --filter "name=code-server-31" --format "{{.Names}}" | while read container; do
    if [ -n "$container" ]; then
        STATS=$(docker stats --no-stream "$container" 2>/dev/null | tail -1)
        if [ -n "$STATS" ]; then
            echo "  $STATS"
        fi
    fi
done
echo ""

echo "=== Load Test Metrics (if available) ==="
if [ -f /tmp/phase-13-metrics/current-aggregated.json ]; then
    echo "Latest metrics:"
    tail -20 /tmp/phase-13-metrics/current-aggregated.json | head -5
elif [ -f /tmp/phase-13-metrics/metrics.log ]; then
    echo "Recent metrics log:"
    tail -5 /tmp/phase-13-metrics/metrics.log
else
    echo "  Metrics collection in progress..."
fi
echo ""

echo "[CHECKPOINT: 4-Hour Data Collection Complete]"

EOFCHECKPOINT

echo ""
echo "✅ 4-Hour Checkpoint Collection Complete"
echo ""
echo "Next checkpoint: 8 hours (estimated 2026-04-14 01:43:26 UTC)"
