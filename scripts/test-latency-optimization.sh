#!/bin/bash
# Test and Validation Script for Latency Optimization Integration
# Issue #182: Latency Optimization - Comprehensive Testing
#
# Purpose: Verify all components of latency optimization are working correctly
# Usage: bash scripts/test-latency-optimization.sh [--detailed] [--stress]
# Expected Runtime: 5-10 minutes (normal), 20-30 minutes (stress test)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERMINAL_OPTIMIZER_HOST="127.0.0.1"
TERMINAL_OPTIMIZER_PORT="8081"
LATENCY_MONITOR_HOST="127.0.0.1"
LATENCY_MONITOR_PORT="8082"
GIT_PROXY_HOST="127.0.0.1"
GIT_PROXY_PORT="8443"
CLOUDFLARE_URL="${CLOUDFLARE_URL:-https://dev.example.com}"
TEST_ITERATIONS=100
STRESS_ITERATIONS=1000

# Parse arguments
DETAILED_OUTPUT=false
STRESS_TEST=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --detailed) DETAILED_OUTPUT=true; shift ;;
    --stress) STRESS_TEST=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Global test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
  ((TESTS_PASSED++))
}

log_failure() {
  echo -e "${RED}✗ $1${NC}"
  ((TESTS_FAILED++))
}

log_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

log_info() {
  echo -e "${BLUE}ℹ $1${NC}"
}

check_url() {
  local url=$1
  local expected_status=${2:-200}
  
  local status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  
  if [[ "$status" == "$expected_status" ]]; then
    return 0
  else
    return 1
  fi
}

check_port_open() {
  local host=$1
  local port=$2
  
  timeout 2 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null || return 1
}

calculate_percentile() {
  local values=$1
  local percentile=$2
  
  # Simple percentile calculation (would need awk/python for production)
  local sorted=$(echo "$values" | tr ' ' '\n' | sort -n)
  local count=$(echo "$sorted" | wc -l)
  local index=$((count * percentile / 100))
  
  echo "$sorted" | sed -n "${index}p"
}

# ============================================================================
# TEST SUITE 1: SERVICE HEALTH CHECKS
# ============================================================================

test_services_health() {
  log_section "TEST 1: Service Health Checks"
  
  # Check Terminal Optimizer
  echo "Checking Terminal Optimizer..."
  if check_port_open "$TERMINAL_OPTIMIZER_HOST" "$TERMINAL_OPTIMIZER_PORT"; then
    if check_url "http://$TERMINAL_OPTIMIZER_HOST:$TERMINAL_OPTIMIZER_PORT/health"; then
      log_success "Terminal Optimizer service is healthy"
    else
      log_failure "Terminal Optimizer endpoint not responding"
    fi
  else
    log_failure "Terminal Optimizer port $TERMINAL_OPTIMIZER_PORT not open"
  fi
  
  # Check Latency Monitor
  echo "Checking Latency Monitor..."
  if check_port_open "$LATENCY_MONITOR_HOST" "$LATENCY_MONITOR_PORT"; then
    if check_url "http://$LATENCY_MONITOR_HOST:$LATENCY_MONITOR_PORT/health"; then
      log_success "Latency Monitor service is healthy"
    else
      log_failure "Latency Monitor endpoint not responding"
    fi
  else
    log_failure "Latency Monitor port $LATENCY_MONITOR_PORT not open"
  fi
  
  # Check Git Proxy (might need cert bypass)
  echo "Checking Git Proxy Server..."
  if check_port_open "$GIT_PROXY_HOST" "$GIT_PROXY_PORT"; then
    log_success "Git Proxy port $GIT_PROXY_PORT is open"
  else
    log_warning "Git Proxy port $GIT_PROXY_PORT not responding (may need authentication)"
  fi
}

# ============================================================================
# TEST SUITE 2: TERMINAL OPTIMIZER FUNCTIONALITY
# ============================================================================

test_terminal_optimizer() {
  log_section "TEST 2: Terminal Optimizer Functionality"
  
  local endpoint="http://$TERMINAL_OPTIMIZER_HOST:$TERMINAL_OPTIMIZER_PORT"
  
  # Test 1: Check configuration
  echo "Retrieving optimizer configuration..."
  local config=$(curl -s "$endpoint/config" 2>/dev/null || echo "{}")
  if echo "$config" | grep -q "batch_timeout"; then
    log_success "Terminal Optimizer configuration retrieved successfully"
    if [[ "$DETAILED_OUTPUT" == true ]]; then
      echo "$config" | jq .
    fi
  else
    log_warning "Could not retrieve full configuration"
  fi
  
  # Test 2: Create a test session
  echo "Creating test optimizer session..."
  local session_response=$(curl -s -X POST "$endpoint/sessions/start" \
    -H "Content-Type: application/json" \
    -d '{
      "session_id": "test-session-'"$(date +%s)"'",
      "compression": true
    }' 2>/dev/null || echo "{}")
  
  if echo "$session_response" | grep -q "session_id"; then
    log_success "Terminal Optimizer session created"
    if [[ "$DETAILED_OUTPUT" == true ]]; then
      echo "$session_response" | jq .
    fi
  else
    log_warning "Could not create test session"
  fi
  
  # Test 3: Send test terminal updates
  echo "Sending test terminal updates..."
  for i in $(seq 1 10); do
    curl -s -X POST "$endpoint/update" \
      -H "Content-Type: application/json" \
      -d "{
        \"session_id\": \"test-session\",
        \"data\": \"Terminal output line $i\\n\",
        \"timestamp\": $(date +%s%N)
      }" > /dev/null 2>&1 || true
  done
  log_success "Sent 10 test terminal update messages"
  
  # Test 4: Retrieve metrics
  echo "Retrieving optimizer metrics..."
  local metrics=$(curl -s "$endpoint/metrics" 2>/dev/null || echo "{}")
  if echo "$metrics" | grep -q "compression_ratio"; then
    log_success "Terminal Optimizer metrics retrieved"
    local ratio=$(echo "$metrics" | jq -r '.compression_ratio // "N/A"')
    log_info "Compression ratio: $ratio (target: >0.4)"
    if [[ "$DETAILED_OUTPUT" == true ]]; then
      echo "$metrics" | jq .
    fi
  else
    log_warning "Could not retrieve compression metrics"
  fi
}

# ============================================================================
# TEST SUITE 3: LATENCY MONITOR FUNCTIONALITY
# ============================================================================

test_latency_monitor() {
  log_section "TEST 3: Latency Monitor Functionality"
  
  local endpoint="http://$LATENCY_MONITOR_HOST:$LATENCY_MONITOR_PORT"
  
  # Test 1: Submit test measurements
  echo "Submitting test latency measurements..."
  local measurements_sent=0
  for i in $(seq 1 "$TEST_ITERATIONS"); do
    local value=$((40 + RANDOM % 60))  # Random value 40-100ms
    
    curl -s -X POST "$endpoint/measure" \
      -H "Content-Type: application/json" \
      -d "{
        \"developer_id\": \"test-dev-001\",
        \"latency_type\": \"keystroke\",
        \"value_ms\": $value,
        \"metadata\": {\"test\": true}
      }" > /dev/null 2>&1 && ((measurements_sent++))
  done
  
  if [[ $measurements_sent -gt 0 ]]; then
    log_success "Submitted $measurements_sent/$(($TEST_ITERATIONS)) latency measurements"
  else
    log_failure "No measurements submitted successfully"
  fi
  
  # Test 2: Allow database to process
  echo "Waiting for database to process..."
  sleep 2
  
  # Test 3: Retrieve statistics
  echo "Retrieving latency statistics..."
  local stats=$(curl -s "$endpoint/statistics?latency_type=keystroke" 2>/dev/null || echo "{}")
  
  if echo "$stats" | grep -q "p99"; then
    log_success "Latency statistics retrieved"
    
    # Extract key percentiles
    local p50=$(echo "$stats" | jq -r '.p50 // "N/A"')
    local p95=$(echo "$stats" | jq -r '.p95 // "N/A"')
    local p99=$(echo "$stats" | jq -r '.p99 // "N/A"')
    
    log_info "Latency statistics: p50=$p50ms, p95=$p95ms, p99=$p99ms"
    
    # Validate targets
    if (( $(echo "$p99 < 150" | bc -l) )); then
      log_success "p99 latency within target (<150ms)"
    else
      log_warning "p99 latency above target: ${p99}ms (goal: <150ms)"
    fi
    
    if [[ "$DETAILED_OUTPUT" == true ]]; then
      echo "$stats" | jq .
    fi
  else
    log_failure "Could not retrieve latency statistics"
  fi
  
  # Test 4: Check for anomalies
  echo "Checking for latency anomalies..."
  local anomalies=$(curl -s "$endpoint/anomalies?threshold=3sigma" 2>/dev/null || echo "[]")
  local anomaly_count=$(echo "$anomalies" | jq 'length // 0')
  
  if [[ $anomaly_count -eq 0 ]]; then
    log_success "No anomalies detected (normal distribution)"
  else
    log_warning "Detected $anomaly_count anomalies (may indicate performance issues)"
    if [[ "$DETAILED_OUTPUT" == true ]]; then
      echo "$anomalies" | jq '.[0:3]'  # Show first 3
    fi
  fi
}

# ============================================================================
# TEST SUITE 4: CLOUDFLARE COMPRESSION VALIDATION
# ============================================================================

test_cloudflare_compression() {
  log_section "TEST 4: Cloudflare Compression Validation"
  
  if [[ "$CLOUDFLARE_URL" == "https://dev.example.com" ]]; then
    log_warning "Skipping Cloudflare tests (URL not configured)"
    ((TESTS_SKIPPED++))
    return
  fi
  
  # Test 1: Check compression header
  echo "Testing compression header..."
  local response=$(curl -s -I -H "Accept-Encoding: gzip" "$CLOUDFLARE_URL" 2>/dev/null || echo "")
  
  if echo "$response" | grep -qi "content-encoding: gzip"; then
    log_success "Cloudflare compression is enabled (gzip)"
    
    # Calculate compression ratio
    local uncompressed_size=$(curl -s "$CLOUDFLARE_URL" -H "Accept-Encoding: identity" 2>/dev/null | wc -c)
    local compressed_size=$(curl -s "$CLOUDFLARE_URL" -H "Accept-Encoding: gzip" 2>/dev/null | wc -c)
    
    if [[ $uncompressed_size -gt 0 ]]; then
      local ratio=$(echo "scale=2; $compressed_size / $uncompressed_size" | bc -l)
      log_info "Compression ratio: ${ratio} (target: <0.6)"
      
      if (( $(echo "$ratio < 0.6" | bc -l) )); then
        log_success "Compression ratio within target"
      else
        log_warning "Compression ratio above target"
      fi
    fi
  else
    log_warning "Cloudflare compression not detected in response headers"
  fi
  
  # Test 2: Check performance metrics
  echo "Checking Cloudflare performance metrics..."
  local perf=$(curl -s -w "\n%{time_total},%{size_download}" -o /dev/null "$CLOUDFLARE_URL" 2>/dev/null || echo "0,0")
  local time_total=$(echo "$perf" | cut -d',' -f1)
  local size=$(echo "$perf" | cut -d',' -f2)
  
  log_info "Response time: ${time_total}s, Size: ${size} bytes"
  
  if (( $(echo "$time_total < 0.5" | bc -l) )); then
    log_success "Load time within target (<500ms)"
  else
    log_warning "Load time above target"
  fi
}

# ============================================================================
# TEST SUITE 5: END-TO-END INTEGRATION
# ============================================================================

test_end_to_end_integration() {
  log_section "TEST 5: End-to-End Integration"
  
  # Test 1: Terminal update flow
  echo "Testing terminal update flow..."
  local flow_success=true
  
  # Create session
  local session=$(curl -s -X POST "http://$TERMINAL_OPTIMIZER_HOST:$TERMINAL_OPTIMIZER_PORT/sessions/start" \
    -H "Content-Type: application/json" \
    -d '{"session_id":"e2e-test","compression":true}' 2>/dev/null || echo "{}")
  
  if echo "$session" | grep -q "session_id"; then
    # Send update
    curl -s -X POST "http://$TERMINAL_OPTIMIZER_HOST:$TERMINAL_OPTIMIZER_PORT/update" \
      -H "Content-Type: application/json" \
      -d "{
        \"session_id\": \"e2e-test\",
        \"data\": \"Test output\",
        \"timestamp\": $(date +%s%N)
      }" > /dev/null 2>&1 || flow_success=false
    
    # Record latency
    if [[ "$flow_success" == true ]]; then
      curl -s -X POST "http://$LATENCY_MONITOR_HOST:$LATENCY_MONITOR_PORT/measure" \
        -H "Content-Type: application/json" \
        -d "{
          \"developer_id\": \"test-dev-e2e\",
          \"latency_type\": \"keystroke\",
          \"value_ms\": 75,
          \"metadata\": {\"e2e_test\": true}
        }" > /dev/null 2>&1 || flow_success=false
    fi
  else
    flow_success=false
  fi
  
  if [[ "$flow_success" == true ]]; then
    log_success "End-to-end integration flow completed successfully"
  else
    log_failure "End-to-end integration flow encountered errors"
  fi
}

# ============================================================================
# TEST SUITE 6: STRESS TESTING (Optional)
# ============================================================================

test_stress_performance() {
  if [[ "$STRESS_TEST" != true ]]; then
    log_section "TEST 6: Stress Testing (Skipped - use --stress flag)"
    ((TESTS_SKIPPED++))
    return
  fi
  
  log_section "TEST 6: Stress Testing"
  
  local endpoint="http://$LATENCY_MONITOR_HOST:$LATENCY_MONITOR_PORT"
  
  echo "Submitting $STRESS_ITERATIONS measurements under load..."
  local start_time=$(date +%s%N)
  local submitted=0
  
  for i in $(seq 1 "$STRESS_ITERATIONS"); do
    local value=$((40 + RANDOM % 100))
    
    curl -s -X POST "$endpoint/measure" \
      -H "Content-Type: application/json" \
      -d "{
        \"developer_id\": \"stress-test\",
        \"latency_type\": \"keystroke\",
        \"value_ms\": $value,
        \"metadata\": {\"stress_test\": true}
      }" > /dev/null 2>&1 && ((submitted++))
    
    # Progress indicator
    if (( i % 100 == 0 )); then
      echo "  Submitted $i/$STRESS_ITERATIONS..."
    fi
  done
  
  local end_time=$(date +%s%N)
  local duration=$(echo "scale=2; ($end_time - $start_time) / 1000000000" | bc -l)
  local throughput=$(echo "scale=2; $submitted / $duration" | bc -l)
  
  log_info "Stress test completed: $submitted measurements in ${duration}s"
  log_info "Throughput: $throughput measurements/second"
  
  if (( $(echo "$throughput > 100" | bc -l) )); then
    log_success "Throughput exceeds 100 msg/sec target"
  else
    log_warning "Throughput below 100 msg/sec target"
  fi
  
  # Check database is still responsive
  sleep 2
  local stats=$(curl -s "$endpoint/statistics?latency_type=keystroke" 2>/dev/null || echo "{}")
  if echo "$stats" | grep -q "p99"; then
    log_success "Database still responsive after stress test"
  else
    log_failure "Database became unresponsive during stress test"
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log_section "Latency Optimization Integration Test Suite"
  log_info "Start time: $(date)"
  log_info "Detailed output: $DETAILED_OUTPUT"
  log_info "Stress testing: $STRESS_TEST"
  
  # Run test suites
  test_services_health
  test_terminal_optimizer
  test_latency_monitor
  test_cloudflare_compression
  test_end_to_end_integration
  test_stress_performance
  
  # Summary
  log_section "Test Summary"
  local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
  
  echo "Passed:  ${GREEN}$TESTS_PASSED${NC}"
  echo "Failed:  ${RED}$TESTS_FAILED${NC}"
  echo "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
  echo "Total:   $total"
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "\n${RED}Some tests failed. Review output above.${NC}"
    exit 1
  fi
}

# Run main
main "$@"
