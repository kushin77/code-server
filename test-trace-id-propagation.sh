#!/bin/bash
# test-trace-id-propagation.sh
#
# Integration test suite for trace ID propagation across service layers
# Verifies that trace IDs are correctly generated, propagated, and logged
#
# Usage: bash test-trace-id-propagation.sh [target_url]
# Example: bash test-trace-id-propagation.sh http://code-server.local

set -e

TARGET_URL="${1:-http://code-server.local}"
TRACE_ID_FORMAT="[0-9a-f]{32}"  # UUID format: 32 hex characters
SPAN_ID_FORMAT="[0-9a-f]{16}"   # 16 hex characters

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ===== TEST UTILITIES =====

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

assert_header_exists() {
    local response="$1"
    local header_name="$2"
    local test_name="$3"
    
    ((TOTAL_TESTS++))
    
    if echo "$response" | grep -qi "^$header_name:"; then
        log_pass "$test_name: Header '$header_name' exists"
    else
        log_fail "$test_name: Header '$header_name' missing"
    fi
}

assert_header_format() {
    local response="$1"
    local header_name="$2"
    local expected_pattern="$3"
    local test_name="$4"
    
    ((TOTAL_TESTS++))
    
    local header_value=$(echo "$response" | grep -i "^$header_name:" | cut -d' ' -f2- | tr -d '\r')
    
    if [[ $header_value =~ $expected_pattern ]]; then
        log_pass "$test_name: Header '$header_name' format valid: $header_value"
    else
        log_fail "$test_name: Header '$header_name' format invalid. Expected pattern: $expected_pattern, Got: $header_value"
    fi
}

# ===== TEST 1: TRACE ID GENERATION =====

echo ""
echo "================================================"
echo "TEST SUITE: Trace ID Propagation"
echo "Target: $TARGET_URL"
echo "================================================"
echo ""

log_test "TEST 1: Caddy generates trace ID for request without one"

RESPONSE=$(curl -s -i "$TARGET_URL/health" 2>&1)

# Check if x-trace-id header is present in response
if echo "$response" | grep -qi "x-trace-id"; then
    ((TOTAL_TESTS++))
    TRACE_ID=$(echo "$RESPONSE" | grep -i "^x-trace-id:" | cut -d' ' -f2 | tr -d '\r')
    
    if [[ $TRACE_ID =~ $TRACE_ID_FORMAT ]]; then
        log_pass "TEST 1: Caddy generated valid trace ID: $TRACE_ID"
    else
        log_fail "TEST 1: Trace ID format invalid: $TRACE_ID"
    fi
else
    ((TOTAL_TESTS++))
    log_fail "TEST 1: x-trace-id header missing from response"
fi

# ===== TEST 2: TRACE ID PROPAGATION =====

echo ""
log_test "TEST 2: Trace ID propagates through oauth2-proxy"

TRACE_ID="4bf92f3577b34da6a3ce929d0e0e4736"
RESPONSE=$(curl -s -i -H "X-Trace-Id: $TRACE_ID" "$TARGET_URL/oauth2/auth" 2>&1)

assert_header_exists "$RESPONSE" "x-trace-id" "TEST 2.1: oauth2-proxy preserves x-trace-id"

# Check if trace ID is in response headers
if echo "$RESPONSE" | grep -qi "x-trace-id.*$TRACE_ID"; then
    ((TOTAL_TESTS++))
    log_pass "TEST 2.2: oauth2-proxy returns same trace ID: $TRACE_ID"
else
    ((TOTAL_TESTS++))
    log_fail "TEST 2.2: oauth2-proxy did not return same trace ID"
fi

# ===== TEST 3: W3C TRACEPARENT HEADER =====

echo ""
log_test "TEST 3: W3C Trace Context (traceparent header) support"

TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
RESPONSE=$(curl -s -i -H "Traceparent: $TRACEPARENT" "$TARGET_URL/health" 2>&1)

assert_header_exists "$RESPONSE" "traceparent" "TEST 3.1: traceparent header preserved"

# Verify format: 00-<trace_id>-<span_id>-<flags>
assert_header_format "$RESPONSE" "traceparent" "^00-[0-9a-f]{32}-[0-9a-f]{16}-[01]{2}$" "TEST 3.2: traceparent format valid"

# ===== TEST 4: TRACE ID PERSISTENCE ACROSS REQUESTS =====

echo ""
log_test "TEST 4: Trace ID persists across multiple requests in same session"

TRACE_ID="abc123def456789012345678901234ab"
REQUEST_COUNT=3

echo "Sending $REQUEST_COUNT requests with same trace ID..."

for i in $(seq 1 $REQUEST_COUNT); do
    RESPONSE=$(curl -s -i -H "X-Trace-Id: $TRACE_ID" "$TARGET_URL/health" 2>&1)
    
    RETURNED_TRACE_ID=$(echo "$RESPONSE" | grep -i "^x-trace-id:" | cut -d' ' -f2 | tr -d '\r')
    
    ((TOTAL_TESTS++))
    if [ "$RETURNED_TRACE_ID" == "$TRACE_ID" ]; then
        log_pass "TEST 4.$i: Request $i returned same trace ID: $TRACE_ID"
    else
        log_fail "TEST 4.$i: Request $i returned different trace ID. Expected: $TRACE_ID, Got: $RETURNED_TRACE_ID"
    fi
done

# ===== TEST 5: TRACE ID LOGGING =====

echo ""
log_test "TEST 5: Trace ID included in access logs"

TRACE_ID="test$(date +%s)0123456789abcdef"
RESPONSE=$(curl -s -i -H "X-Trace-Id: $TRACE_ID" "$TARGET_URL/health" 2>&1)

# Note: This test requires access to Caddy logs
# In a real scenario, we'd parse /var/log/caddy/access.log

echo "Checking for trace ID in logs (requires log file access)..."

if [ -f "/var/log/caddy/access.log" ]; then
    ((TOTAL_TESTS++))
    if grep -q "$TRACE_ID" /var/log/caddy/access.log; then
        log_pass "TEST 5: Trace ID found in Caddy access logs"
    else
        log_fail "TEST 5: Trace ID not found in Caddy access logs"
    fi
else
    ((TOTAL_TESTS++))
    log_fail "TEST 5: Access log file not found at /var/log/caddy/access.log"
fi

# ===== TEST 6: ERROR RESPONSE INCLUDES TRACE ID =====

echo ""
log_test "TEST 6: Error responses include trace ID"

TRACE_ID="error_test_$(date +%s)_abc1234567890"
RESPONSE=$(curl -s -i -H "X-Trace-Id: $TRACE_ID" "$TARGET_URL/nonexistent" 2>&1)

# Should get a 404 with trace ID in response
if echo "$RESPONSE" | grep -qi "404"; then
    ((TOTAL_TESTS++))
    if echo "$RESPONSE" | grep -qi "$TRACE_ID"; then
        log_pass "TEST 6: 404 error response includes trace ID"
    else
        log_fail "TEST 6: 404 error response missing trace ID"
    fi
else
    ((TOTAL_TESTS++))
    log_fail "TEST 6: Did not receive expected 404 response"
fi

# ===== TEST 7: TRACE ID HEADER CASE INSENSITIVITY =====

echo ""
log_test "TEST 7: Trace ID headers are case-insensitive"

TRACE_ID="case_test_$(date +%s)_abc1234567890"

# Try different case variations
HEADERS=(
    "x-trace-id"
    "X-Trace-Id"
    "X-TRACE-ID"
    "x-trace-ID"
)

for header in "${HEADERS[@]}"; do
    RESPONSE=$(curl -s -i -H "$header: $TRACE_ID" "$TARGET_URL/health" 2>&1)
    
    ((TOTAL_TESTS++))
    if echo "$RESPONSE" | grep -qi "x-trace-id.*$TRACE_ID"; then
        log_pass "TEST 7: Header '$header' correctly processed"
    else
        log_fail "TEST 7: Header '$header' not processed correctly"
    fi
done

# ===== TEST SUMMARY =====

echo ""
echo "================================================"
echo "TEST SUMMARY"
echo "================================================"
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
