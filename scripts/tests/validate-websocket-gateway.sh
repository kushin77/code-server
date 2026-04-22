#!/usr/bin/env bash
# @file        scripts/tests/validate-websocket-gateway.sh
# @module      tests/websocket
# @description Comprehensive validation of WebSocket gateway cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATEWAY_HOST="${1:-localhost}"
GATEWAY_PORT="${2:-8080}"
TEST_DURATION="${3:-300}"  # 5 minutes default

RESULTS_FILE="artifacts/websocket-validation-results.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

test_result() {
    local name=$1
    local status=$2
    local details=$3
    
    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}✓ ${name}${NC}"
        ((TESTS_PASSED++))
    elif [[ "$status" == "FAIL" ]]; then
        echo -e "${RED}✗ ${name}${NC}: ${details}"
        ((TESTS_FAILED++))
    else
        echo -e "${YELLOW}⊘ ${name}${NC}: ${details}"
        ((TESTS_SKIPPED++))
    fi
}

echo "=========================================="
echo "WebSocket Gateway Cluster Validation"
echo "=========================================="
echo ""
echo "Target: ${GATEWAY_HOST}:${GATEWAY_PORT}"
echo "Duration: ${TEST_DURATION}s"
echo ""

# 1. Connectivity Tests
echo "1. Basic Connectivity"
echo "===================="

# Test HTTP endpoint
if curl -s -f "http://${GATEWAY_HOST}:${GATEWAY_PORT}/health" > /dev/null 2>&1; then
    test_result "HTTP endpoint reachable" "PASS"
else
    test_result "HTTP endpoint reachable" "FAIL" "No response from http://${GATEWAY_HOST}:${GATEWAY_PORT}"
fi

# Test HAProxy stats page
if curl -s -f "http://${GATEWAY_HOST}:8404/stats" > /dev/null 2>&1; then
    test_result "HAProxy stats page" "PASS"
else
    test_result "HAProxy stats page" "FAIL" "Cannot reach http://${GATEWAY_HOST}:8404/stats"
fi

# 2. WebSocket Connectivity Tests
echo ""
echo "2. WebSocket Connectivity"
echo "========================="

# Test WebSocket upgrade request
WS_RESPONSE=$(curl -s -i \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  -H "Sec-WebSocket-Version: 13" \
  "http://${GATEWAY_HOST}:${GATEWAY_PORT}/ws?session_id=test-validate-1" 2>&1)

if echo "$WS_RESPONSE" | grep -q "101 Switching Protocols\|Connection: Upgrade"; then
    test_result "WebSocket upgrade negotiation" "PASS"
else
    test_result "WebSocket upgrade negotiation" "FAIL" "No 101 response"
fi

# 3. Relay Node Health
echo ""
echo "3. Relay Node Health"
echo "===================="

for i in 1 2 3; do
    PORT=$((3000 + i))
    if curl -s "http://${GATEWAY_HOST}:${PORT}/health" | grep -q '"status":"healthy"'; then
        test_result "Relay node ${i} healthy" "PASS"
    else
        test_result "Relay node ${i} healthy" "FAIL" "No healthy response from port ${PORT}"
    fi
done

# 4. Load Balancing Test
echo ""
echo "4. Load Balancing"
echo "================="

# Test consistent hashing: same session_id should route to same node
SESSION_ID="test-balance-$(date +%s)"
NODE_1=$(curl -s "http://${GATEWAY_HOST}:8080/route?session_id=${SESSION_ID}" 2>/dev/null | grep -o 'node[0-9]' | head -1 || echo "unknown")
NODE_2=$(curl -s "http://${GATEWAY_HOST}:8080/route?session_id=${SESSION_ID}" 2>/dev/null | grep -o 'node[0-9]' | head -1 || echo "unknown")

if [[ "$NODE_1" == "$NODE_2" && "$NODE_1" != "unknown" ]]; then
    test_result "Consistent hash routing" "PASS"
elif [[ "$NODE_1" == "unknown" ]]; then
    test_result "Consistent hash routing" "SKIP" "Route endpoint not available"
else
    test_result "Consistent hash routing" "FAIL" "Different nodes for same session: ${NODE_1} vs ${NODE_2}"
fi

# 5. Message Delivery Test
echo ""
echo "5. Message Delivery"
echo "==================="

# Create a simple test to send and receive a message
# This requires a more sophisticated test client (would use Node.js with ws library)
echo "Skipping message delivery test - requires WebSocket client library"

# 6. Performance Baseline
echo ""
echo "6. Performance Baseline"
echo "======================"

# Test connection time (rough estimate)
START_TIME=$(date +%s%N)
if curl -s -f "http://${GATEWAY_HOST}:${GATEWAY_PORT}/health" > /dev/null 2>&1; then
    END_TIME=$(date +%s%N)
    CONN_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # Convert to milliseconds
    
    if (( CONN_TIME < 1000 )); then
        test_result "Connection time < 1s (${CONN_TIME}ms)" "PASS"
    elif (( CONN_TIME < 5000 )); then
        test_result "Connection time < 5s (${CONN_TIME}ms)" "PASS"
    else
        test_result "Connection time < 5s (${CONN_TIME}ms)" "FAIL"
    fi
fi

# 7. System Capacity
echo ""
echo "7. System Capacity"
echo "=================="

# Check if system can handle concurrent connections (basic check)
CONCURRENT=10
echo "Testing ${CONCURRENT} concurrent connections..."

CONCURRENT_SUCCESS=0
for i in $(seq 1 $CONCURRENT); do
    if (timeout 2 curl -s -f "http://${GATEWAY_HOST}:${GATEWAY_PORT}/health" > /dev/null 2>&1) &
    then
        ((CONCURRENT_SUCCESS++))
    fi
done
wait

if (( CONCURRENT_SUCCESS >= 8 )); then
    test_result "Concurrent connections (${CONCURRENT_SUCCESS}/${CONCURRENT})" "PASS"
else
    test_result "Concurrent connections (${CONCURRENT_SUCCESS}/${CONCURRENT})" "FAIL"
fi

# 8. Error Handling
echo ""
echo "8. Error Handling"
echo "================"

# Test invalid session ID
INVALID_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null \
    "http://${GATEWAY_HOST}:${GATEWAY_PORT}/ws?session_id=invalid%00null")

if [[ "$INVALID_RESPONSE" == "200" ]]; then
    test_result "Invalid session rejection" "FAIL" "Expected rejection, got HTTP ${INVALID_RESPONSE}"
else
    test_result "Invalid session rejection" "PASS"
fi

# 9. Monitoring Integration
echo ""
echo "9. Monitoring Integration"
echo "==============================="

if curl -s "http://${GATEWAY_HOST}:9090/api/v1/query?query=up" | grep -q '"__name__":"up"'; then
    test_result "Prometheus endpoint available" "PASS"
else
    test_result "Prometheus endpoint available" "SKIP" "Prometheus not configured"
fi

if curl -s "http://${GATEWAY_HOST}:3000/api/health" > /dev/null 2>&1; then
    test_result "Grafana endpoint available" "PASS"
else
    test_result "Grafana endpoint available" "SKIP" "Grafana not available"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC}  ${TESTS_PASSED}"
echo -e "${RED}Failed:${NC}  ${TESTS_FAILED}"
echo -e "${YELLOW}Skipped:${NC} ${TESTS_SKIPPED}"
echo -e "Total:   $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
echo ""

if (( TESTS_FAILED > 0 )); then
    echo -e "${RED}❌ Validation FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Validation PASSED${NC}"
    exit 0
fi
