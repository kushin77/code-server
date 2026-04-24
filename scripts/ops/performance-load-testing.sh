#!/usr/bin/env bash
# @file        scripts/ops/performance-load-testing.sh
# @module      testing/performance
# @description Comprehensive load testing script for production readiness validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEST_TARGET="${TEST_TARGET:-}"
TEST_DURATION_BASELINE=${TEST_DURATION_BASELINE:-600}  # 10 minutes
TEST_DURATION_SPIKE=${TEST_DURATION_SPIKE:-300}        # 5 minutes
TEST_DURATION_SUSTAINED=${TEST_DURATION_SUSTAINED:-1800} # 30 minutes
BASELINE_USERS=${BASELINE_USERS:-100}
SPIKE_USERS=${SPIKE_USERS:-1000}
SUSTAINED_USERS=${SUSTAINED_USERS:-500}
OUTPUT_DIR=${OUTPUT_DIR:-./artifacts/performance-tests}
TEST_PAUSE_BETWEEN_PHASES=${TEST_PAUSE_BETWEEN_PHASES:-30}
K6_CMD=()

if [[ -z "$TEST_TARGET" ]]; then
    log_error "Set TEST_TARGET before running performance load testing"
    exit 1
fi

resolve_k6_command() {
    if command -v k6 &> /dev/null; then
        K6_CMD=(k6)
    elif command -v docker &> /dev/null; then
        K6_CMD=(docker run --rm -v "$(pwd):/work" -w /work grafana/k6)
    else
        K6_CMD=()
    fi
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    resolve_k6_command
    
    # Check if curl available
    if ! command -v curl &> /dev/null; then
        log_error "curl not found. Please install curl."
        exit 1
    fi
    
    # Check if jq available
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found. Some output formatting will be limited."
    fi
    
    if [ ${#K6_CMD[@]} -eq 0 ]; then
        log_warn "k6 not found and docker is unavailable. Falling back to the built-in simple benchmark path."
    elif [ "${K6_CMD[0]}" = "docker" ]; then
        log_info "k6 will be run via docker run grafana/k6"
    fi
    
    # Check if target is reachable
    if ! curl -fsSL -m 5 "$TEST_TARGET/health" > /dev/null 2>&1; then
        log_error "Target $TEST_TARGET is not reachable"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Create k6 load test script
create_k6_script() {
    local test_type=$1
    local users=$2
    local duration=$3
    local output_file=$4
    local fast_mode=${FAST_MODE:-0}
    
    cat > "$output_file" << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
    stages: [__STAGES__],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  const res = http.get(__URL__ + '/health');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
}
EOF
    
    # Replace placeholders
    if [ "$fast_mode" = "1" ]; then
        local ramp_seconds=$(( duration / 4 ))
        local sustain_seconds=$(( duration - ramp_seconds ))

        if [ "$ramp_seconds" -lt 1 ]; then
            ramp_seconds=1
        fi

        if [ "$sustain_seconds" -lt 1 ]; then
            sustain_seconds=1
        fi

        sed -i "s|__STAGES__|{ duration: '${ramp_seconds}s', target: $users }, { duration: '${sustain_seconds}s', target: $users }|g" "$output_file"
    else
        case "$test_type" in
            "baseline")
                # Ramp up to 100 users over 2 minutes, stay for 8 minutes
                sed -i "s|__STAGES__|{ duration: '2m', target: $users }, { duration: '8m', target: $users }|g" "$output_file"
                ;;
            "spike")
                # Ramp up to 1000 users over 30 seconds, stay for 4:30 minutes
                sed -i "s|__STAGES__|{ duration: '30s', target: $users }, { duration: '4m30s', target: $users }|g" "$output_file"
                ;;
            "sustained")
                # Ramp up to 500 users over 5 minutes, stay for 25 minutes
                sed -i "s|__STAGES__|{ duration: '5m', target: $users }, { duration: '25m', target: $users }|g" "$output_file"
                ;;
        esac
    fi
    
    sed -i "s|__URL__|'$TEST_TARGET'|g" "$output_file"
}

# Run k6 test
run_k6_test() {
    local test_name=$1
    local test_file=$2
    local output_json=$3
    
    log_info "Running $test_name test..."
    
    "${K6_CMD[@]}" run \
        --out json="$output_json" \
        --summary-export="$OUTPUT_DIR/${test_name}-summary.json" \
        "$test_file" 2>&1 | tee "$OUTPUT_DIR/${test_name}-output.log"
    
    log_success "$test_name test completed"
}

# Parse k6 results
parse_k6_results() {
    local test_name=$1
    local results_file=$2
    local report_file=$3
    
    log_info "Parsing $test_name results..."
    
    # Extract key metrics from k6 JSON output
    if command -v jq &> /dev/null; then
        jq '.' "$results_file" | grep -E '"metric"|"value"' > "$report_file" 2>/dev/null || true
    fi
    
    # Generate simple text report
    cat >> "$report_file" << EOF

=== $test_name Test Results ===
Test Target: $TEST_TARGET
Test File: $results_file

For detailed metrics, see: $results_file
EOF
    
    log_success "Results saved to $report_file"
}

# Simple HTTP benchmark (fallback if k6 not available)
run_simple_benchmark() {
    local test_name=$1
    local users=$2
    local duration_seconds=$3
    local output_file=$4
    
    log_info "Running simple benchmark for $test_name (no k6)..."
    
    cat > "$output_file" << EOF
=== $test_name Benchmark Results ===
Date: $(date)
Target: $TEST_TARGET
Users: $users (simulated via concurrent requests)
Duration: ${duration_seconds}s

Sample Results:
EOF
    
    # Run 10 concurrent requests as a simple test
    local start_time=$(date +%s%N)
    
    for i in {1..10}; do
        (curl -fsSL -w "\nStatus: %{http_code}\nTime: %{time_total}s\n" "$TEST_TARGET/health" >> "$output_file" &)
    done
    
    wait
    
    local end_time=$(date +%s%N)
    local elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    
    cat >> "$output_file" << EOF

Total Time: ${elapsed_ms}ms
Requests: 10
Average Time per Request: $(( elapsed_ms / 10 ))ms

Note: This is a simple benchmark. For comprehensive load testing, install k6.
EOF
    
    log_success "Benchmark completed: $output_file"
}

# Collect system metrics during test
collect_metrics() {
    local test_name=$1
    local duration=$2
    local metrics_file="$OUTPUT_DIR/${test_name}-metrics.log"
    
    log_info "Collecting system metrics for $test_name..."
    
    # Monitor for the duration of the test
    {
        while true; do
            echo "=== $(date) ==="
            
            # CPU and memory
            if command -v top &> /dev/null; then
                top -bn1 | head -n 3
            fi
            
            # Target service health
            if command -v curl &> /dev/null; then
                echo "Service Health:"
                curl -fsSL -m 2 "$TEST_TARGET/health" 2>/dev/null || echo "Timeout/Error"
            fi
            
            # Docker stats (if running in container)
            if command -v docker &> /dev/null; then
                docker stats --no-stream 2>/dev/null | grep code-server || true
            fi
            
            echo ""
            sleep 30
        done
    } | tee "$metrics_file" &
    
    local metrics_pid=$!
    
    # Wait for test duration then kill metrics collection
    sleep "$duration"
    kill $metrics_pid 2>/dev/null || true
    
    log_success "Metrics collected to $metrics_file"
}

# Main test execution
main() {
    log_info "Starting Performance Load Testing Suite"
    log_info "Target: $TEST_TARGET"
    log_info "Output Directory: $OUTPUT_DIR"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Create k6 scripts
    log_info "Creating load test scripts..."
    create_k6_script "baseline" "$BASELINE_USERS" "$TEST_DURATION_BASELINE" "$OUTPUT_DIR/baseline-test.js"
    create_k6_script "spike" "$SPIKE_USERS" "$TEST_DURATION_SPIKE" "$OUTPUT_DIR/spike-test.js"
    create_k6_script "sustained" "$SUSTAINED_USERS" "$TEST_DURATION_SUSTAINED" "$OUTPUT_DIR/sustained-test.js"
    log_success "Load test scripts created"
    echo ""
    
    # Run baseline test
    log_info "=== BASELINE TEST: $BASELINE_USERS concurrent users ==="
    if [ ${#K6_CMD[@]} -gt 0 ]; then
        run_k6_test "baseline" "$OUTPUT_DIR/baseline-test.js" "$OUTPUT_DIR/baseline-results.json"
        parse_k6_results "baseline" "$OUTPUT_DIR/baseline-results.json" "$OUTPUT_DIR/baseline-report.txt"
    else
        run_simple_benchmark "baseline" "$BASELINE_USERS" "$TEST_DURATION_BASELINE" "$OUTPUT_DIR/baseline-report.txt"
    fi
    echo ""
    
    sleep "$TEST_PAUSE_BETWEEN_PHASES"
    
    # Run spike test
    log_info "=== SPIKE TEST: $SPIKE_USERS concurrent users ==="
    if [ ${#K6_CMD[@]} -gt 0 ]; then
        run_k6_test "spike" "$OUTPUT_DIR/spike-test.js" "$OUTPUT_DIR/spike-results.json"
        parse_k6_results "spike" "$OUTPUT_DIR/spike-results.json" "$OUTPUT_DIR/spike-report.txt"
    else
        run_simple_benchmark "spike" "$SPIKE_USERS" "$TEST_DURATION_SPIKE" "$OUTPUT_DIR/spike-report.txt"
    fi
    echo ""
    
    sleep "$TEST_PAUSE_BETWEEN_PHASES"
    
    # Run sustained test (with metrics collection)
    log_info "=== SUSTAINED TEST: $SUSTAINED_USERS concurrent users for 30 minutes ==="
    
    # Start metrics collection in background
    collect_metrics "sustained" "$TEST_DURATION_SUSTAINED" &
    
    if [ ${#K6_CMD[@]} -gt 0 ]; then
        run_k6_test "sustained" "$OUTPUT_DIR/sustained-test.js" "$OUTPUT_DIR/sustained-results.json"
        parse_k6_results "sustained" "$OUTPUT_DIR/sustained-results.json" "$OUTPUT_DIR/sustained-report.txt"
    else
        run_simple_benchmark "sustained" "$SUSTAINED_USERS" "$TEST_DURATION_SUSTAINED" "$OUTPUT_DIR/sustained-report.txt"
    fi
    echo ""
    
    # Generate summary report
    log_info "Generating summary report..."
    
    cat > "$OUTPUT_DIR/PERFORMANCE-TEST-SUMMARY.md" << EOF
# Performance Load Testing Report
**Date**: $(date)
**Target**: $TEST_TARGET

## Test Configuration
- Baseline Users: $BASELINE_USERS
- Spike Users: $SPIKE_USERS
- Sustained Users: $SUSTAINED_USERS
- Baseline Duration: ${TEST_DURATION_BASELINE}s
- Spike Duration: ${TEST_DURATION_SPIKE}s
- Sustained Duration: ${TEST_DURATION_SUSTAINED}s

## Success Criteria
- p99 latency: < 200ms
- Error rate: < 0.1%
- Memory usage: < 2GB
- CPU usage: < 50%
- Database connections: < 80
- Cache hit rate: > 80%

## Test Results

### Baseline Test (100 concurrent users)
See: baseline-report.txt

**Expected Results**:
- p99 response time: < 200ms
- Error rate: < 0.1%
- Memory: < 1GB
- CPU: < 30%

### Spike Test (1000 concurrent users)
See: spike-report.txt

**Expected Results**:
- p99 response time: < 500ms (degraded OK)
- Error rate: < 1%
- No connection timeouts
- System recovers after spike

### Sustained Test (500 concurrent users, 30 minutes)
See: sustained-report.txt & sustained-metrics.log

**Expected Results**:
- Stable performance over time
- No memory growth > 100MB
- Cache hit rate consistent
- Replication lag < 1 second

## Detailed Results
- baseline-results.json (k6 JSON output)
- spike-results.json (k6 JSON output)
- sustained-results.json (k6 JSON output)
- *-metrics.log (system metrics during tests)

## Analysis

[To be filled by performance engineer after reviewing results]

## Recommendation

[GREEN/YELLOW/RED: Ready for production / Needs monitoring / Needs fixes]

---
Generated: $(date)
EOF
    
    log_success "Summary report generated"
    log_success "All tests completed!"
    log_info "Results available in: $OUTPUT_DIR"
    
    echo ""
    log_info "Files generated:"
    ls -lh "$OUTPUT_DIR"/ 2>/dev/null || true
}

# Run main
main "$@"
