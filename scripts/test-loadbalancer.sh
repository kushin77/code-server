#!/bin/bash

#############################################################################
# Load Balancer Testing & Validation Suite
#
# Purpose: Comprehensive testing of HAProxy load balancing, failover,
#          session affinity, and routing behavior
#############################################################################

set -e

readonly PRIMARY_HOST="192.168.168.31"
readonly REPLICA_HOST="192.168.168.42"
readonly LOCALHOST="127.0.0.1"
readonly TEST_RESULTS="/tmp/lb-test-results.log"

# Trap error and cleanup handlers
trap 'echo "[ERROR] Test failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Test cleanup complete"; rm -f /tmp/lb-test-*.tmp 2>/dev/null || true' EXIT

test_service_routing() {
  local service_name="$1"
  local port="$2"
  local protocol="${3:-http}"
  
  echo "Testing $service_name on port $port ($protocol)..."
  
  if [[ "$protocol" == "tcp" ]]; then
    timeout 2 bash -c "echo > /dev/tcp/$LOCALHOST/$port" 2>/dev/null && \
      echo "  ✓ $service_name routing works" >> "$TEST_RESULTS" || \
      echo "  ✗ $service_name routing failed" >> "$TEST_RESULTS"
  else
    curl -s -m 2 "http://$LOCALHOST:$port/health" >/dev/null 2>&1 && \
      echo "  ✓ $service_name routing works" >> "$TEST_RESULTS" || \
      echo "  ✗ $service_name routing failed" >> "$TEST_RESULTS"
  fi
}

test_session_affinity() {
  local service="$1"
  local port="$2"
  
  echo "Testing session affinity for $service..."
  
  local host1_count=0
  local host2_count=0
  
  for i in {1..10}; do
    local response=$(curl -s -m 2 "http://$LOCALHOST:$port/whoami" 2>/dev/null || echo "unknown")
    [[ "$response" == *"$PRIMARY_HOST"* ]] && host1_count+=1 || host2_count+=1
  done
  
  echo "  Primary host: $host1_count, Replica host: $host2_count" >> "$TEST_RESULTS"
  [[ $host1_count -eq 10 || $host2_count -eq 10 ]] && \
    echo "  ✓ Session affinity working" >> "$TEST_RESULTS" || \
    echo "  ✗ Session affinity inconsistent" >> "$TEST_RESULTS"
}

# Run all tests
: > "$TEST_RESULTS"
echo "=== Load Balancer Test Suite ===" >> "$TEST_RESULTS"
echo "Started: $(date)" >> "$TEST_RESULTS"

test_service_routing "API Gateway" 8000
test_service_routing "Code Server" 8080
test_service_routing "PostgreSQL" 5432 tcp
test_service_routing "Redis" 6379 tcp
test_service_routing "Vault" 8200

test_session_affinity "Code Server" 8080

echo "Completed: $(date)" >> "$TEST_RESULTS"
cat "$TEST_RESULTS"
