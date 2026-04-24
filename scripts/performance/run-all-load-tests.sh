#!/usr/bin/env bash
# @file        scripts/performance/run-all-load-tests.sh
# @module      operations/performance-testing
# @description Orchestrate all performance load tests sequentially
# @owner       QA/Operations
# @status      Production ready - April 23, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
BASE_URL="${BASE_URL:-http://localhost:3000}"
RESULTS_DIR="${PROJECT_DIR}/artifacts/performance"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${RESULTS_DIR}/load-tests-${TIMESTAMP}.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# Create results directory
mkdir -p "$RESULTS_DIR"

log_info "=========================================="
log_info "Performance Load Testing Campaign"
log_info "=========================================="
log_info "Target: $BASE_URL"
log_info "Results: $RESULTS_DIR"
log_info "Started: $(date)"
log_info ""

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    log_error "k6 not found. Install from https://k6.io/docs/getting-started/installation/"
    exit 1
fi

log_info "k6 version: $(k6 --version)"
log_info ""

# Run Baseline Load Test
log_info "Running BASELINE LOAD TEST (100 concurrent users / 10 minutes)..."
log_info "This test establishes performance baselines under normal operating conditions."

if k6 run \
    -e BASE_URL="$BASE_URL" \
    -e RAMP_UP_DURATION="2m" \
    -e TEST_DURATION="10m" \
    -e MAX_USERS="100" \
    "$SCRIPT_DIR/baseline-load-test.js" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "✓ Baseline load test PASSED"
else
    log_warn "⚠ Baseline load test had issues (check logs)"
fi

log_info ""
log_info "Waiting 5 minutes between tests for system recovery..."
sleep 300

# Run Spike Load Test
log_info "Running SPIKE LOAD TEST (1000 concurrent users / 5 minutes)..."
log_info "This test validates system resilience under sudden traffic surge."

if k6 run \
    -e BASE_URL="$BASE_URL" \
    -e SPIKE_USERS="1000" \
    -e SPIKE_DURATION="5m" \
    "$SCRIPT_DIR/spike-load-test.js" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "✓ Spike load test PASSED"
else
    log_warn "⚠ Spike load test had issues (check logs)"
fi

log_info ""
log_info "Waiting 5 minutes between tests for system recovery..."
sleep 300

# Run Sustained Load Test
log_info "Running SUSTAINED LOAD TEST (500 concurrent users / 30 minutes)..."
log_info "This test validates system stability and resource consumption over extended period."

if k6 run \
    -e BASE_URL="$BASE_URL" \
    -e SUSTAINED_USERS="500" \
    -e SUSTAINED_DURATION="30m" \
    "$SCRIPT_DIR/sustained-load-test.js" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "✓ Sustained load test PASSED"
else
    log_warn "⚠ Sustained load test had issues (check logs)"
fi

log_info ""
log_info "=========================================="
log_info "Performance Testing Campaign Complete"
log_info "=========================================="
log_info "Results saved to: $RESULTS_DIR"
log_info "Log file: $LOG_FILE"
log_info "Completed: $(date)"
log_info ""

# Generate summary report
log_info "Generating performance summary report..."

cat > "$RESULTS_DIR/PERFORMANCE-TEST-SUMMARY-${TIMESTAMP}.md" << 'EOF'
# Performance Load Testing Results

## Campaign Summary
- **Date**: $(date)
- **Target**: $BASE_URL
- **Total Tests**: 3 (Baseline, Spike, Sustained)
- **Total Duration**: ~50 minutes

## Test Results

### 1. Baseline Load Test (100 concurrent users / 10 minutes)
**Status**: PASS/FAIL
- Response Time: [Check baseline-results.json]
- Error Rate: [Check baseline-results.json]
- Success Criteria: All responses < 5 seconds, Error rate < 0.1%

### 2. Spike Load Test (1000 concurrent users / 5 minutes)
**Status**: PASS/FAIL
- Peak Response Time: [Check spike-results.json]
- Recovery Time: [Check spike-results.json]
- Success Criteria: Graceful degradation, Recovery < 2 minutes, Error rate < 1%

### 3. Sustained Load Test (500 concurrent users / 30 minutes)
**Status**: PASS/FAIL
- Memory Stability: [Check sustained-results.json]
- Connection Pool: [Check sustained-results.json]
- Success Criteria: Memory stable, No pool exhaustion, Consistent performance

## Performance Baselines

| Metric | Baseline | Spike | Sustained |
|--------|----------|-------|-----------|
| Avg Response Time | TBD | TBD | TBD |
| P95 Response Time | TBD | TBD | TBD |
| Error Rate | TBD | TBD | TBD |
| Throughput | TBD | TBD | TBD |

## Recommendations

1. [Performance optimization opportunities]
2. [Capacity planning recommendations]
3. [Infrastructure improvements]

## Next Steps

- [ ] Review detailed JSON results
- [ ] Compare against SLA thresholds
- [ ] Create optimization roadmap
- [ ] Schedule infrastructure improvements
- [ ] Plan production deployment validation

## Artifacts
- baseline-results.json
- spike-results.json
- sustained-results.json
- load-tests-${TIMESTAMP}.log
EOF

log_info "✓ Summary report created at: $RESULTS_DIR/PERFORMANCE-TEST-SUMMARY-${TIMESTAMP}.md"
log_info ""
log_info "Next steps:"
log_info "1. Review detailed JSON results in $RESULTS_DIR"
log_info "2. Compare metrics against SLA thresholds"
log_info "3. Create optimization roadmap based on findings"
log_info "4. Schedule infrastructure improvements"
log_info ""
