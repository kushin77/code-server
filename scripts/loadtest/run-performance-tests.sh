#!/usr/bin/env bash
# @file        scripts/loadtest/run-performance-tests.sh
# @module      performance/testing
# @description Execute k6 load tests and collect metrics for production readiness validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
BASE_URL="${TEST_BASE_URL:-http://localhost:8080}"
K6_RESULTS_DIR="${PROJECT_ROOT}/artifacts/performance"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)

# Test configurations
BASELINE_VUS="${BASELINE_VUS:-100}"
BASELINE_DURATION="${BASELINE_DURATION:-10m}"
SPIKE_VUS="${SPIKE_VUS:-1000}"
SPIKE_DURATION="${SPIKE_DURATION:-5m}"
SUSTAINED_VUS="${SUSTAINED_VUS:-500}"
SUSTAINED_DURATION="${SUSTAINED_DURATION:-30m}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

mkdir -p "$K6_RESULTS_DIR"

log_info() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} WARNING: $*"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ERROR: $*"
}

run_test() {
  local test_name=$1
  local script=$2
  local vus=$3
  local scale_profile=$4
  local output_file="${K6_RESULTS_DIR}/${test_name}-${TIMESTAMP}.json"
  
  log_info "Starting $test_name test..."
  log_info "  Base URL: $BASE_URL"
  log_info "  Virtual Users: $vus"
  log_info "  Scale Profile: $scale_profile"
  
  # Run k6 test with JSON output
  if k6 run \
    --vus "$vus" \
    --out "json=$output_file" \
    -e BASE_URL="$BASE_URL" \
    -e SCALE_PROFILE="$scale_profile" \
    "$script" 2>&1 | tee "${K6_RESULTS_DIR}/${test_name}-${TIMESTAMP}.log"; then
    log_info "✓ $test_name test completed successfully"
    echo "$output_file"
  else
    log_error "$test_name test failed"
    return 1
  fi
}

collect_prometheus_metrics() {
  local metric_name=$1
  local query=$2
  local output_file="${K6_RESULTS_DIR}/prometheus-${metric_name}-${TIMESTAMP}.json"
  
  log_info "Collecting prometheus metric: $metric_name"
  
  if curl -s "${PROMETHEUS_URL}/api/v1/query?query=${query}" > "$output_file"; then
    log_info "✓ Metrics collected: $output_file"
  else
    log_warn "Failed to collect prometheus metrics"
  fi
}

validate_results() {
  local results_file=$1
  local test_name=$2
  
  log_info "Validating results for $test_name..."
  
  # Extract key metrics from k6 JSON output
  if [ -f "$results_file" ]; then
    # Parse and display key metrics
    local error_rate=$(jq '.metrics.http_req_failed.values.rate // 0' "$results_file" 2>/dev/null || echo "unknown")
    local p99_latency=$(jq '.metrics.http_req_duration.values.p99 // "unknown"' "$results_file" 2>/dev/null || echo "unknown")
    local p95_latency=$(jq '.metrics.http_req_duration.values.p95 // "unknown"' "$results_file" 2>/dev/null || echo "unknown")
    
    log_info "Results for $test_name:"
    log_info "  Error Rate: $error_rate"
    log_info "  p95 Latency: ${p95_latency}ms"
    log_info "  p99 Latency: ${p99_latency}ms"
  else
    log_warn "Results file not found: $results_file"
  fi
}

main() {
  log_info "Performance Testing Framework - Starting"
  log_info "========================================="
  
  # Check if k6 is installed
  if ! command -v k6 &> /dev/null; then
    log_error "k6 not found. Install it with: npm install -g k6"
    exit 1
  fi
  
  # Check if test scripts exist
  if [ ! -f "$SCRIPT_DIR/k6-baseline.js" ]; then
    log_error "k6-baseline.js not found at $SCRIPT_DIR/k6-baseline.js"
    exit 1
  fi
  
  # Run tests based on arguments
  case "${1:-all}" in
    baseline)
      run_test "baseline" "$SCRIPT_DIR/k6-baseline.js" "$BASELINE_VUS" "100x"
      ;;
    spike)
      run_test "spike" "$SCRIPT_DIR/k6-spike.js" "$SPIKE_VUS" "1000x"
      ;;
    sustained)
      run_test "sustained" "$SCRIPT_DIR/k6-sustained.js" "$SUSTAINED_VUS" "500x"
      ;;
    all|*)
      log_info "Running all performance tests..."
      baseline_results=$(run_test "baseline" "$SCRIPT_DIR/k6-baseline.js" "$BASELINE_VUS" "100x") || true
      spike_results=$(run_test "spike" "$SCRIPT_DIR/k6-spike.js" "$SPIKE_VUS" "1000x") || true
      sustained_results=$(run_test "sustained" "$SCRIPT_DIR/k6-sustained.js" "$SUSTAINED_VUS" "500x") || true
      
      # Validate each test
      [ -n "$baseline_results" ] && validate_results "$baseline_results" "Baseline"
      [ -n "$spike_results" ] && validate_results "$spike_results" "Spike"
      [ -n "$sustained_results" ] && validate_results "$sustained_results" "Sustained"
      ;;
  esac
  
  # Collect prometheus metrics
  log_info "Collecting system metrics from Prometheus..."
  collect_prometheus_metrics "cpu" "node_cpu_seconds_total"
  collect_prometheus_metrics "memory" "node_memory_MemAvailable_bytes"
  collect_prometheus_metrics "requests" "rate(http_requests_total[1m])"
  
  log_info "========================================="
  log_info "Performance testing completed"
  log_info "Results saved to: $K6_RESULTS_DIR"
}

main "$@"
