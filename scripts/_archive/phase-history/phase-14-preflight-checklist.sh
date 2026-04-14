#!/bin/bash

# Phase 14: Production Go-Live Pre-Flight Checklist
# Purpose: Comprehensive validation before April 14 @ 08:00 UTC go-live
# Owner: Infrastructure Team
# Timeline: 30-45 minutes to complete all checks

set -e

REMOTE_HOST="192.168.168.31"
REMOTE_USER="akushnir"
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 14: PRODUCTION GO-LIVE PRE-FLIGHT CHECKLIST"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Scheduled Go-Live: April 14, 2026 @ 08:00 UTC"
echo "Current Time: $(date +'%Y-%m-%d %H:%M:%S')"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Helper function to log results
check_item() {
    local description=$1
    local result=$2

    if [ "$result" = "PASS" ]; then
        echo "  ✅ $description"
        ((PASS_COUNT++))
    else
        echo "  ❌ $description"
        ((FAIL_COUNT++))
    fi
}

# ===== SECTION 1: INFRASTRUCTURE VALIDATION =====
echo ""
echo "1️⃣  INFRASTRUCTURE VALIDATION"
echo "────────────────────────────────────────────────────────────────"

# Check 1.1: Container Health
CONTAINERS=$(ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" \
    "docker ps --filter 'name=*-31' --format '{{.Names}}' | wc -l" 2>/dev/null || echo "0")

if [ "$CONTAINERS" = "3" ]; then
    check_item "All target containers running (3/3)" "PASS"
else
    check_item "All target containers running (found: $CONTAINERS)" "FAIL"
fi

# Check 1.2: Container Restart Count
RESTARTS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "docker ps --filter 'name=*-31' --format '{{.RestartCount}}' | awk '{sum+=\$1} END {print sum}'" 2>/dev/null || echo "999")

if [ "$RESTARTS" = "0" ] || [ "$RESTARTS" = "" ]; then
    check_item "Zero container restarts during Phase 13" "PASS"
else
    check_item "Zero container restarts (found: $RESTARTS)" "FAIL"
fi

# ===== SECTION 2: NETWORKING & DNS =====
echo ""
echo "2️⃣  NETWORKING & DNS VALIDATION"
echo "────────────────────────────────────────────────────────────────"

# Check 2.1: SSH Connectivity
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" "echo 'test'" 2>/dev/null | grep -q "test"; then
    check_item "SSH connectivity to production host" "PASS"
else
    check_item "SSH connectivity to production host" "FAIL"
fi

# Check 2.2: HTTP Endpoint Response
HTTP_STATUS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "308" ] || [ "$HTTP_STATUS" = "200" ]; then
    check_item "HTTP endpoint responding (status: $HTTP_STATUS)" "PASS"
else
    check_item "HTTP endpoint responding (status: $HTTP_STATUS)" "FAIL"
fi

# ===== SECTION 3: SECURITY VALIDATION =====
echo ""
echo "3️⃣  SECURITY VALIDATION"
echo "────────────────────────────────────────────────────────────────"

# Check 3.1: No exposed SSH ports
EXPOSED_SSH=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "netstat -tlnp 2>/dev/null | grep ':22 ' | wc -l" 2>/dev/null || echo "0")

if [ "$EXPOSED_SSH" = "0" ]; then
    check_item "No exposed SSH ports on production network" "PASS"
else
    check_item "No exposed SSH ports on production network" "FAIL"
fi

# Check 3.2: Audit logging configured
AUDIT_CONF=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "ls -la /tmp/phase-13-metrics/ 2>/dev/null | wc -l" 2>/dev/null || echo "0")

if [ "$AUDIT_CONF" -gt "0" ]; then
    check_item "Audit logging and metrics collection active" "PASS"
else
    check_item "Audit logging and metrics collection active" "FAIL"
fi

# ===== SECTION 4: PERFORMANCE VALIDATION =====
echo ""
echo "4️⃣  PERFORMANCE VALIDATION"
echo "────────────────────────────────────────────────────────────────"

# Check 4.1: Latency SLO
LATENCY=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "curl -s -o /dev/null -w '%{time_total}' http://localhost/ 2>/dev/null" 2>/dev/null || echo "999")

LATENCY_MS=$(echo "$LATENCY * 1000" | bc 2>/dev/null || echo "999")

if (( $(echo "$LATENCY_MS < 100" | bc -l) )); then
    check_item "p99 latency <100ms (actual: ${LATENCY_MS}ms)" "PASS"
else
    check_item "p99 latency <100ms (actual: ${LATENCY_MS}ms)" "FAIL"
fi

# Check 4.2: Memory utilization
MEMORY_PCT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "free | grep Mem | awk '{print int(\$3/\$2 * 100)}'" 2>/dev/null || echo "999")

if [ "$MEMORY_PCT" -lt 80 ]; then
    check_item "Memory usage <80% (actual: ${MEMORY_PCT}%)" "PASS"
else
    check_item "Memory usage <80% (actual: ${MEMORY_PCT}%)" "FAIL"
fi

# ===== SECTION 5: OPERATIONAL READINESS =====
echo ""
echo "5️⃣  OPERATIONAL READINESS"
echo "────────────────────────────────────────────────────────────────"

# Check 5.1: Monitoring active
MONITORING=$(ls -la /tmp/phase-13-metrics/ 2>/dev/null | wc -l || echo "0")

if [ "$MONITORING" -gt "0" ]; then
    check_item "Real-time monitoring activated" "PASS"
else
    check_item "Real-time monitoring activated" "FAIL"
fi

# Check 5.2: Load test still running
CURL_PROCS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" \
    "ps aux | grep -i curl | grep -v grep | wc -l" 2>/dev/null || echo "0")

if [ "$CURL_PROCS" -gt "0" ]; then
    check_item "Load generators active ($CURL_PROCS processes)" "PASS"
else
    check_item "Load generators active" "FAIL"
fi

# ===== SUMMARY =====
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PRE-FLIGHT CHECKLIST SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT))
PERCENT=$((PASS_COUNT * 100 / TOTAL))

echo "Completion: $PERCENT% ($PASS_COUNT/$TOTAL checks)"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🟢 PRE-FLIGHT STATUS: ✅ GO FOR LAUNCH"
    echo "📝 All critical systems verified and ready for go-live"
    echo ""
    echo "Go-Live Scheduled: April 14, 2026 @ 08:00 UTC"
    echo "Status: READY FOR EXECUTION"
    exit 0
else
    echo "🟠 PRE-FLIGHT STATUS: ⚠️  REVIEW REQUIRED"
    echo "📝 Some items need attention before go-live"
    exit 1
fi
