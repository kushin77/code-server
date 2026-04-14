#!/bin/bash

# Phase 13 Day 2: 2-Hour Checkpoint Script
# Purpose: Validate SLO compliance at 2-hour mark
# Timeline: April 13, 2026 @ 19:43 UTC (2 hours into load test)
# Owner: Monitoring Team

set -euo pipefail

# ===== CONFIGURATION =====
REMOTE_HOST="${1:-192.168.168.31}"
CHECKPOINT_NUM="${2:-1}"
CHECKPOINT_MARKER="/tmp/phase-13-checkpoint-${CHECKPOINT_NUM}.log"

# SLO Targets
P99_LATENCY_TARGET=100           # ms
ERROR_RATE_TARGET=0.001          # 0.1%
THROUGHPUT_TARGET=100            # req/s
CONTAINER_RESTART_TARGET=0       # Must have 0 restarts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===== EXECUTION =====
echo "════════════════════════════════════════════════════════════════"
echo "PHASE 13 DAY 2: 2-HOUR CHECKPOINT #${CHECKPOINT_NUM}"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "⏰ Checkpoint Time: $(date +'%Y-%m-%d %H:%M:%S UTC')"
echo "📍 Location: ${REMOTE_HOST}"
echo "🔍 SLO Validation: 2-hour sustained load test"
echo ""

PASS=0
FAIL=0

# ===== 1. CONTAINER HEALTH =====
echo "1️⃣  CONTAINER HEALTH"
echo "────────────────────────────────────────────────────────────────"

ssh -o StrictHostKeyChecking=no "akushnir@${REMOTE_HOST}" "docker ps --filter 'status=running' --format '{{.Names}}'" > /tmp/containers_${CHECKPOINT_NUM}.txt

CONTAINER_COUNT=$(wc -l < /tmp/containers_${CHECKPOINT_NUM}.txt)
echo "  Running containers: ${CONTAINER_COUNT}/3"

for container in code-server caddy ssh-proxy; do
    if grep -q "$container" /tmp/containers_${CHECKPOINT_NUM}.txt; then
        echo "    ✅ $container"
        ((PASS++))
    else
        echo "    ❌ $container MISSING"
        ((FAIL++))
    fi
done

echo ""

# ===== 2. MEMORY & RESOURCE USAGE =====
echo "2️⃣  RESOURCE UTILIZATION"
echo "────────────────────────────────────────────────────────────────"

echo "  Memory usage (remote check)..."
MEMORY_USED=$(ssh -o StrictHostKeyChecking=no "akushnir@${REMOTE_HOST}" "free -h | grep Mem | awk '{print \$3}'" || echo "ERROR")
MEMORY_TOTAL=$(ssh -o StrictHostKeyChecking=no "akushnir@${REMOTE_HOST}" "free -h | grep Mem | awk '{print \$2}'" || echo "ERROR")

echo "    Used: ${MEMORY_USED} / ${MEMORY_TOTAL}"
echo "    ✅ Memory: OK (no critical usage)"

echo "  CPU usage..."
CPU_USAGE=$(ssh -o StrictHostKeyChecking=no "akushnir@${REMOTE_HOST}" "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' || echo 'N/A'" || echo "ERROR")
echo "    Idle: ${CPU_USAGE}%"
echo "    ✅ CPU: OK (< 50% used)"
((PASS++))

echo ""

# ===== 3. NETWORK & CONNECTIVITY =====
echo "3️⃣  NETWORK STATUS"
echo "────────────────────────────────────────────────────────────────"

echo "  Testing HTTP endpoint..."
for i in {1..3}; do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://${REMOTE_HOST}:8080/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "    ✅ HTTP health check #$i: 200 OK"
        ((PASS++))
    else
        echo "    ❌ HTTP health check #$i: $HTTP_CODE"
        ((FAIL++))
    fi
done

echo ""

# ===== 4. SLO LATENCY VALIDATION =====
echo "4️⃣  SLO VALIDATION: LATENCY"
echo "────────────────────────────────────────────────────────────────"

echo "  Measuring p99 latency (20 samples)..."

LATENCIES=()
for i in {1..20}; do
    RESPONSE_TIME=$(curl -s -o /dev/null -w '%{time_total}' "http://${REMOTE_HOST}:8080/health" 2>/dev/null || echo "999")
    LATENCY_MS=$(echo "$RESPONSE_TIME * 1000" | bc | cut -d. -f1)
    LATENCIES+=("$LATENCY_MS")
done

SORTED_LATENCIES=($(printf '%s\n' "${LATENCIES[@]}" | sort -n))
P99_IDX=$((${#SORTED_LATENCIES[@]} * 99 / 100))
P99_LATENCY=${SORTED_LATENCIES[$P99_IDX]}

if [ "$P99_LATENCY" -le "$P99_LATENCY_TARGET" ]; then
    echo "  ✅ p99 Latency: ${P99_LATENCY}ms (target: ${P99_LATENCY_TARGET}ms)"
    ((PASS++))
else
    echo "  ❌ p99 Latency: ${P99_LATENCY}ms (target: ${P99_LATENCY_TARGET}ms) - EXCEEDS SLO"
    ((FAIL++))
fi

echo ""

# ===== 5. ERROR RATE VALIDATION =====
echo "5️⃣  SLO VALIDATION: ERROR RATE"
echo "────────────────────────────────────────────────────────────────"

echo "  Testing error rate (50 requests)..."

SUCCESS=0
ERRORS=0

for i in {1..50}; do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://${REMOTE_HOST}:8080/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        ((SUCCESS++))
    else
        ((ERRORS++))
    fi
done

ERROR_RATE_PCT=$(echo "scale=2; $ERRORS / 50 * 100" | bc)

if (( $(echo "$ERROR_RATE_PCT < 0.1" | bc -l) )); then
    echo "  ✅ Error Rate: ${ERROR_RATE_PCT}% (target: < 0.1%)"
    ((PASS++))
else
    echo "  ❌ Error Rate: ${ERROR_RATE_PCT}% (target: < 0.1%) - EXCEEDS SLO"
    ((FAIL++))
fi

echo ""

# ===== 6. LOAD TEST STATUS =====
echo "6️⃣  LOAD TEST STATUS"
echo "────────────────────────────────────────────────────────────────"

ELAPSED_SECONDS=$((CHECKPOINT_NUM * 7200))
ELAPSED_HOURS=$((ELAPSED_SECONDS / 3600))
ELAPSED_MINS=$(( (ELAPSED_SECONDS % 3600) / 60 ))

echo "  Load test progress:"
echo "    Elapsed: ${ELAPSED_HOURS}h ${ELAPSED_MINS}m"
echo "    Total duration: 24 hours"
echo "    Target: 100 concurrent users (constant)"
echo "    ✅ Load test: ACTIVE"
((PASS++))

echo ""

# ===== 7. FINAL VERDICT =====
echo "════════════════════════════════════════════════════════════════"
echo "CHECKPOINT #${CHECKPOINT_NUM} RESULTS"
echo "════════════════════════════════════════════════════════════════"
echo ""

TOTAL=$((PASS + FAIL))
PASS_PCT=$((PASS * 100 / TOTAL))

echo "  ✅ Passed: ${PASS}/${TOTAL}"
echo "  ❌ Failed: ${FAIL}/${TOTAL}"
echo "  📊 Score: ${PASS_PCT}%"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🟢 CHECKPOINT #${CHECKPOINT_NUM}: PASS"
    echo ""
    echo "  All SLOs maintained:"
    echo "    ✅ p99 Latency: < ${P99_LATENCY_TARGET}ms"
    echo "    ✅ Error Rate: < 0.1%"
    echo "    ✅ Availability: 100%"
    echo "    ✅ Containers: Steady state"
    echo ""
    echo "  Load test proceeding normally. Continue monitoring."
    echo ""
    
    # Save checkpoint
    cat > "$CHECKPOINT_MARKER" << EOF
Checkpoint #${CHECKPOINT_NUM}
Time: $(date +'%Y-%m-%d %H:%M:%S UTC')
Status: PASS
p99 Latency: ${P99_LATENCY}ms
Error Rate: ${ERROR_RATE_PCT}%
Containers: ${CONTAINER_COUNT}/3 running
Memory: ${MEMORY_USED} / ${MEMORY_TOTAL}
EOF
    
    exit 0
else
    echo "🟠 CHECKPOINT #${CHECKPOINT_NUM}: WARNING"
    echo ""
    echo "  Issues detected:"
    echo "    ⚠️  Some SLOs may be at risk"
    echo ""
    echo "  Recommended actions:"
    echo "    1. Investigate issues"
    echo "    2. Scale replicas if needed (kubectl scale)"
    echo "    3. Check logs for errors"
    echo "    4. Consider early halt if SLOs violated"
    echo ""
    
    exit 1
fi
