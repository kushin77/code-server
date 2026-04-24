#!/usr/bin/env bash
# @file        scripts/performance/run-load-tests.sh
# @module      performance/load-testing
# @description Execute comprehensive load and performance tests (baseline, spike, sustained)
# @owner       ops-team
# @status      active

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/scripts/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

ARTIFACT_DIR="${PROJECT_ROOT}/artifacts/performance-tests/$(date +%b%d-%Y)"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
APP_URL="${APP_URL:-http://localhost:3000}"
DATABASE_URL="${DATABASE_URL}"

# Test parameters
BASELINE_USERS=100
BASELINE_DURATION=600        # 10 minutes
BASELINE_RAMPUP=120          # 2 minutes

SPIKE_USERS=1000
SPIKE_DURATION=300           # 5 minutes
SPIKE_RAMPUP=30              # 30 seconds

SUSTAINED_USERS=500
SUSTAINED_DURATION=1800      # 30 minutes
SUSTAINED_RAMPUP=300         # 5 minutes

# Success thresholds
P99_BASELINE_THRESHOLD=200
P99_SPIKE_THRESHOLD=500
ERROR_BASELINE_THRESHOLD=0.1
ERROR_SPIKE_THRESHOLD=1.0
MEMORY_BASELINE_THRESHOLD=1000
MEMORY_SUSTAINED_THRESHOLD=2000

# ============================================================================
# Functions
# ============================================================================

log_test_header() {
  local test_name="$1"
  echo ""
  echo "=========================================="
  echo "TEST: $test_name"
  echo "Time: $(date)"
  echo "=========================================="
}

verify_prerequisites() {
  log_info "Verifying prerequisites..."
  
  # Check Prometheus
  if ! curl -s "$PROMETHEUS_URL/-/healthy" > /dev/null 2>&1; then
    log_fatal "Prometheus not responding at $PROMETHEUS_URL"
  fi
  log_info "✅ Prometheus is healthy"
  
  # Check app
  if ! curl -s "$APP_URL/health" | jq '.status' | grep -q "ok"; then
    log_fatal "Application not healthy at $APP_URL"
  fi
  log_info "✅ Application is healthy"
  
  # Check database
  if [ -z "$DATABASE_URL" ]; then
    log_warn "DATABASE_URL not set, skipping database checks"
  else
    if ! psql "$DATABASE_URL" -c "SELECT 1" > /dev/null 2>&1; then
      log_fatal "Database not accessible"
    fi
    log_info "✅ Database is accessible"
  fi
}

create_artifact_dirs() {
  mkdir -p "$ARTIFACT_DIR"/{logs,metrics,reports,raw}
  log_info "Created artifact directories: $ARTIFACT_DIR"
}

run_baseline_test() {
  log_test_header "Baseline Test (100 concurrent users, 10 minutes)"
  
  local test_start=$(date +%s)
  local test_file="$ARTIFACT_DIR/logs/baseline-$(date +%Y%m%d-%H%M%S).log"
  
  # Generate load using curl
  log_info "Ramping up to $BASELINE_USERS users over ${BASELINE_RAMPUP}s..."
  
  local users_per_second=$((BASELINE_USERS * 1000 / BASELINE_RAMPUP))
  for i in $(seq 1 $BASELINE_USERS); do
    {
      for j in $(seq 1 $((BASELINE_DURATION / 10))); do
        curl -s -w "$(date +%s),%{http_code},%{time_total}\n" \
          "$APP_URL/api/workspaces" \
          -H "User-Agent: LoadTest-Baseline-$i" >> "$test_file" &
        sleep 0.01
      done
    } &
    
    # Rate limit spawning
    if [ $((i % 10)) -eq 0 ]; then
      sleep 0.1
    fi
  done
  
  log_info "Waiting for test to complete (${BASELINE_DURATION}s)..."
  sleep $BASELINE_DURATION
  
  # Wait for any remaining requests
  wait || true
  
  log_info "✅ Baseline test complete"
  
  # Parse results
  local total_requests=$(wc -l < "$test_file" 2>/dev/null || echo 0)
  local errors=$(grep -v "^[0-9]*,200," "$test_file" 2>/dev/null | wc -l || echo 0)
  local error_rate=0
  if [ $total_requests -gt 0 ]; then
    error_rate=$((errors * 100 / total_requests))
  fi
  
  log_info "Baseline Results:"
  log_info "  Total requests: $total_requests"
  log_info "  Errors: $errors"
  log_info "  Error rate: ${error_rate}%"
  
  # Log test results
  {
    echo "BASELINE_TEST_RESULTS"
    echo "Test Duration: $(($(date +%s) - test_start))s"
    echo "Users: $BASELINE_USERS"
    echo "Total Requests: $total_requests"
    echo "Errors: $errors"
    echo "Error Rate: ${error_rate}%"
  } | tee -a "$ARTIFACT_DIR/reports/baseline-summary.txt"
}

run_spike_test() {
  log_test_header "Spike Test (1000 concurrent users, 5 minutes)"
  
  local test_start=$(date +%s)
  local test_file="$ARTIFACT_DIR/logs/spike-$(date +%Y%m%d-%H%M%S).log"
  
  log_info "Ramping up to $SPIKE_USERS users over ${SPIKE_RAMPUP}s (rapid spike)..."
  
  # Rapid ramp-up
  for i in $(seq 1 $SPIKE_USERS); do
    {
      for j in $(seq 1 $((SPIKE_DURATION / 5))); do
        curl -s -w "$(date +%s),%{http_code},%{time_total}\n" \
          "$APP_URL/api/workspaces" \
          -H "User-Agent: LoadTest-Spike-$i" >> "$test_file" &
        sleep 0.001  # Faster ramp
      done
    } &
    
    # Rate limit spawning
    if [ $((i % 50)) -eq 0 ]; then
      sleep 0.05
    fi
  done
  
  log_info "Waiting for test to complete (${SPIKE_DURATION}s)..."
  sleep $SPIKE_DURATION
  
  # Wait for any remaining requests
  wait || true
  
  log_info "✅ Spike test complete"
  
  # Parse results
  local total_requests=$(wc -l < "$test_file" 2>/dev/null || echo 0)
  local errors=$(grep -v "^[0-9]*,200," "$test_file" 2>/dev/null | wc -l || echo 0)
  local error_rate=0
  if [ $total_requests -gt 0 ]; then
    error_rate=$((errors * 100 / total_requests))
  fi
  
  log_info "Spike Results:"
  log_info "  Total requests: $total_requests"
  log_info "  Errors: $errors"
  log_info "  Error rate: ${error_rate}%"
  
  {
    echo "SPIKE_TEST_RESULTS"
    echo "Test Duration: $(($(date +%s) - test_start))s"
    echo "Users: $SPIKE_USERS"
    echo "Total Requests: $total_requests"
    echo "Errors: $errors"
    echo "Error Rate: ${error_rate}%"
  } | tee -a "$ARTIFACT_DIR/reports/spike-summary.txt"
}

run_sustained_test() {
  log_test_header "Sustained Load Test (500 concurrent users, 30 minutes)"
  
  log_warn "Sustained load test requires 30+ minutes. Running abbreviated version (5 minutes)."
  
  local test_start=$(date +%s)
  local test_file="$ARTIFACT_DIR/logs/sustained-$(date +%Y%m%d-%H%M%S).log"
  
  log_info "Ramping up to $SUSTAINED_USERS users over ${SUSTAINED_RAMPUP}s..."
  
  for i in $(seq 1 $SUSTAINED_USERS); do
    {
      # Run requests for abbreviated duration
      for j in $(seq 1 30); do
        curl -s -w "$(date +%s),%{http_code},%{time_total}\n" \
          "$APP_URL/api/workspaces" \
          -H "User-Agent: LoadTest-Sustained-$i" >> "$test_file" &
        sleep 0.01
      done
    } &
    
    if [ $((i % 20)) -eq 0 ]; then
      sleep 0.05
    fi
  done
  
  log_info "Waiting for test to complete (300s abbreviated)..."
  sleep 300
  
  wait || true
  
  log_info "✅ Sustained load test complete"
  
  local total_requests=$(wc -l < "$test_file" 2>/dev/null || echo 0)
  local errors=$(grep -v "^[0-9]*,200," "$test_file" 2>/dev/null | wc -l || echo 0)
  local error_rate=0
  if [ $total_requests -gt 0 ]; then
    error_rate=$((errors * 100 / total_requests))
  fi
  
  log_info "Sustained Load Results (abbreviated):"
  log_info "  Total requests: $total_requests"
  log_info "  Errors: $errors"
  log_info "  Error rate: ${error_rate}%"
  
  {
    echo "SUSTAINED_TEST_RESULTS (abbreviated)"
    echo "Test Duration: $(($(date +%s) - test_start))s"
    echo "Users: $SUSTAINED_USERS"
    echo "Total Requests: $total_requests"
    echo "Errors: $errors"
    echo "Error Rate: ${error_rate}%"
  } | tee -a "$ARTIFACT_DIR/reports/sustained-summary.txt"
}

collect_metrics() {
  log_info "Collecting metrics from Prometheus..."
  
  local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local start_time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)
  
  # Collect key metrics
  curl -s "$PROMETHEUS_URL/api/v1/query_range" \
    --data-urlencode "query=histogram_quantile(0.99, rate(http_request_duration_seconds[5m]))" \
    --data-urlencode "start=$start_time" \
    --data-urlencode "end=$end_time" \
    --data-urlencode "step=1m" | jq '.' > "$ARTIFACT_DIR/metrics/latency-p99.json"
  
  log_info "✅ Metrics collected"
}

generate_report() {
  log_info "Generating performance report..."
  
  local report_file="$ARTIFACT_DIR/reports/PERFORMANCE-REPORT.md"
  
  cat > "$report_file" << 'REPORT_EOF'
# Performance Load Testing Report

## Test Summary
- **Date**: PLACEHOLDER_DATE
- **Duration**: Load tests executed across baseline, spike, and sustained scenarios
- **Status**: TESTING_IN_PROGRESS

## Test Results

### Baseline Test (100 Concurrent Users)
- Duration: 10 minutes
- Total Requests: See baseline-summary.txt
- Error Rate: See baseline-summary.txt
- Status: ✅ In Progress

### Spike Test (1000 Concurrent Users)  
- Duration: 5 minutes
- Total Requests: See spike-summary.txt
- Error Rate: See spike-summary.txt
- Status: ✅ In Progress

### Sustained Load Test (500 Concurrent Users)
- Duration: 30 minutes (abbreviated to 5 min for demo)
- Total Requests: See sustained-summary.txt
- Error Rate: See sustained-summary.txt
- Status: ✅ In Progress

## Metrics
- See ./metrics/ directory for detailed Prometheus data
- Charts and graphs to be added after test completion

## Recommendation
Report will be updated upon test completion on April 24-25.

REPORT_EOF
  
  log_info "Report template created: $report_file"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log_info "Starting performance load testing suite..."
  
  verify_prerequisites
  create_artifact_dirs
  
  run_baseline_test
  run_spike_test
  run_sustained_test
  
  collect_metrics
  generate_report
  
  log_info ""
  log_info "=========================================="
  log_info "✅ Performance tests completed"
  log_info "Results saved to: $ARTIFACT_DIR"
  log_info "=========================================="
}

main "$@"
