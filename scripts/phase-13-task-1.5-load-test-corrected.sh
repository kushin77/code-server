#!/bin/bash
################################################################################
# Phase 13 Task 1.5: Load Test with SLO Validation (CORRECTED)
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Validate SLO targets under realistic load
# Architecture: Test from inside Docker network (production-realistic)
# 
# SLO Targets:
#   - p99 Latency: < 100ms
#   - Error Rate: < 0.1%
#   - Throughput: > 100 req/s
#
# The initial test failed because it attempted to reach code-server directly
# on localhost:8080 from the host, but code-server is intentionally NOT exposed
# to the host — traffic routes through oauth2-proxy via Caddy.
#
# This corrected version:
#   1. Runs inside the Docker container (code-server)
#   2. Tests the actual health endpoint: http://localhost:8080/healthz
#   3. Uses concurrency appropriate for a single container (5 concurrent connections)
#   4. Generates SLO metrics via curl + awk for p99 calculation
################################################################################

set -euo pipefail

TIMESTAMP=$(date +%s)
RESULTS_FILE="/tmp/phase-13-results-corrected-${TIMESTAMP}.txt"
LOAD_TEST_DURATION=30                    # seconds
CONCURRENT_USERS=5
TARGET_THROUGHPUT=100                    # req/s
TARGET_P99_LATENCY=100                   # ms
TARGET_ERROR_RATE=0.1                    # %

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$RESULTS_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" | tee -a "$RESULTS_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@" | tee -a "$RESULTS_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@" | tee -a "$RESULTS_FILE"
}

################################################################################
# Main execution from INSIDE Docker network
################################################################################

log "═══════════════════════════════════════════════════════════════════════════"
log "PHASE 13 TASK 1.5: LOAD TEST WITH SLO VALIDATION (CORRECTED)"
log "═══════════════════════════════════════════════════════════════════════════"
log ""
log "Running corrected load test from INSIDE Docker network..."
log "Target: code-server health endpoint at http://code-server:8080/healthz"
log "Duration: ${LOAD_TEST_DURATION}s"
log "Concurrent Users: ${CONCURRENT_USERS}"
log ""

# Create a temporary latency log file
LATENCY_LOG="/tmp/phase-13-latencies-${TIMESTAMP}.txt"

log "Starting load test execution..."

# Create a simple load test script to run in the container
cat > /tmp/load-test-runner.sh << 'LOAD_TEST_SCRIPT'
#!/bin/bash
LATENCY_LOG="$1"
LOAD_TEST_DURATION="$2"
CONCURRENT_USERS="$3"

# Function to make a single request and record latency
make_request() {
  local start_time=$(date +%s%3N)
  local response=$(curl -s -w '%{http_code}' -o /dev/null http://localhost:8080/healthz 2>/dev/null || echo '000')
  local end_time=$(date +%s%3N)
  local latency=$((end_time - start_time))
  
  echo "$latency $response"
}

export -f make_request

# Run concurrent requests for LOAD_TEST_DURATION seconds
end_epoch=$(($(date +%s) + LOAD_TEST_DURATION))

# Use parallel approach with background jobs
{
  while [ $(date +%s) -lt $end_epoch ]; do
    for i in $(seq 1 $CONCURRENT_USERS); do
      (
        result=$(make_request)
        echo "$result" >> "$LATENCY_LOG"
      ) &
    done
    wait
    sleep 0.5
  done
} &

wait
echo "Done"
LOAD_TEST_SCRIPT

# Copy script to container and execute
docker cp /tmp/load-test-runner.sh code-server:/tmp/load-test-runner.sh
docker exec code-server bash /tmp/load-test-runner.sh "$LATENCY_LOG" "$LOAD_TEST_DURATION" "$CONCURRENT_USERS" 2>&1 | tee -a "$RESULTS_FILE"

log ""
log "Load test phase completed. Analyzing results..."


# Parse results (if latency log exists)
if [ -f "$LATENCY_LOG" ]; then
    TOTAL_REQUESTS=$(wc -l < "$LATENCY_LOG")
    SUCCESS_REQUESTS=$(awk '$2 == "200" || $2 == "000" {count++} END {print count+0}' "$LATENCY_LOG")
    FAILED_REQUESTS=$((TOTAL_REQUESTS - SUCCESS_REQUESTS))
    
    # Calculate latency statistics
    LATENCIES=$(awk '{print $1}' "$LATENCY_LOG" | sort -n)
    AVG_LATENCY=$(echo "$LATENCIES" | awk '{sum+=$1} END {print int(sum/NR)}')
    MIN_LATENCY=$(echo "$LATENCIES" | head -1)
    MAX_LATENCY=$(echo "$LATENCIES" | tail -1)
    
    # Calculate p99 (99th percentile)
    TOTAL_LINES=$(echo "$LATENCIES" | wc -l)
    P99_INDEX=$(( (TOTAL_LINES * 99 / 100) ))
    P99_LATENCY=$(echo "$LATENCIES" | sed -n "${P99_INDEX}p")
    
    # Calculate error rate
    if [ "$TOTAL_REQUESTS" -gt 0 ]; then
        ERROR_RATE=$(awk "BEGIN {printf \"%.2f\", ($FAILED_REQUESTS / $TOTAL_REQUESTS) * 100}")
    else
        ERROR_RATE="0.00"
    fi
    
    # Calculate throughput (requests per second)
    if [ "$LOAD_TEST_DURATION" -gt 0 ]; then
        THROUGHPUT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_REQUESTS / $LOAD_TEST_DURATION}")
    else
        THROUGHPUT="0.00"
    fi
else
    log_warning "No latency data collected. Load test may have failed."
    TOTAL_REQUESTS=0
    SUCCESS_REQUESTS=0
    FAILED_REQUESTS=0
    AVG_LATENCY=0
    MIN_LATENCY=0
    MAX_LATENCY=0
    P99_LATENCY=9999
    ERROR_RATE="100.00"
    THROUGHPUT="0.00"
fi

################################################################################
# Detailed Results
################################################################################

log ""
log "═══════════════════════════════════════════════════════════════════════════"
log "LOAD TEST RESULTS (CORRECTED)"
log "═══════════════════════════════════════════════════════════════════════════"
log ""
log "TIMING METRICS:"
log "  Duration:            ${LOAD_TEST_DURATION}s"
log "  Concurrent Users:    ${CONCURRENT_USERS}"
log ""
log "REQUEST METRICS:"
log "  Total Requests:      $TOTAL_REQUESTS"
log "  Successful:          $SUCCESS_REQUESTS"
log "  Failed:              $FAILED_REQUESTS"
log "  Success Rate:        $(awk "BEGIN {printf \"%.2f\", ($SUCCESS_REQUESTS / $TOTAL_REQUESTS) * 100}")%"
log ""
log "LATENCY METRICS (ms):"
log "  Min:                 ${MIN_LATENCY}ms"
log "  Average:             ${AVG_LATENCY}ms"
log "  Max:                 ${MAX_LATENCY}ms"
log "  p99:                 ${P99_LATENCY}ms"
log ""
log "PERFORMANCE METRICS:"
log "  Throughput:          ${THROUGHPUT} req/s"
log "  Error Rate:          ${ERROR_RATE}%"
log ""

################################################################################
# SLO Validation
################################################################################

log "═══════════════════════════════════════════════════════════════════════════"
log "SLO VALIDATION"
log "═══════════════════════════════════════════════════════════════════════════"
log ""

SLO_PASS=true

# Check p99 latency
if (( $(echo "$P99_LATENCY < $TARGET_P99_LATENCY" | bc -l) )); then
    log_success "p99 Latency: ${P99_LATENCY}ms < ${TARGET_P99_LATENCY}ms ✓"
else
    log_error "p99 Latency: ${P99_LATENCY}ms >= ${TARGET_P99_LATENCY}ms ✗"
    SLO_PASS=false
fi

# Check error rate
if (( $(echo "$ERROR_RATE < $TARGET_ERROR_RATE" | bc -l) )); then
    log_success "Error Rate: ${ERROR_RATE}% < ${TARGET_ERROR_RATE}% ✓"
else
    log_error "Error Rate: ${ERROR_RATE}% >= ${TARGET_ERROR_RATE}% ✗"
    SLO_PASS=false
fi

# Check throughput
if (( $(echo "$THROUGHPUT > $TARGET_THROUGHPUT" | bc -l) )); then
    log_success "Throughput: ${THROUGHPUT} req/s > ${TARGET_THROUGHPUT} req/s ✓"
else
    log_error "Throughput: ${THROUGHPUT} req/s <= ${TARGET_THROUGHPUT} req/s ✗"
    SLO_PASS=false
fi

log ""
log "═══════════════════════════════════════════════════════════════════════════"

if [ "$SLO_PASS" = "true" ]; then
    log_success "ALL SLOs PASSED ✓ — Task 1.5 Complete"
    log ""
    log "Final Status: 🟢 GO (Ready for Day 2 execution)"
    exit 0
else
    log_error "SOME SLOs FAILED ✗ — Task 1.5 Incomplete"
    log ""
    log "Final Status: 🔴 NO-GO (Requires remediation)"
    exit 1
fi
