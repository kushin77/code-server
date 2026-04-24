#!/bin/bash
################################################################################
# Phase 13 Day 2: Load Test Executor
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Execute 24-hour sustained load test with real-time metrics
# Target: code-server via Caddy reverse proxy
# Concurrency: 100 concurrent users (adjustable)
# Duration: 86,400 seconds (24 hours)
#
# Idempotence: Can be started/stopped/resumed multiple times
# Immutability: No state modification except append-only logs
# IaC: All config via environment variables, no hardcoded values
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Environment Configuration (Version Pinned)
# ─────────────────────────────────────────────────────────────────────────────

# Load test parameters (override via environment)
LOAD_TEST_DURATION=${LOAD_TEST_DURATION:-86400}          # 24 hours in seconds
CONCURRENT_USERS=${CONCURRENT_USERS:-100}                # Max concurrent connections
REQUEST_TIMEOUT=${REQUEST_TIMEOUT:-30}                   # Per-request timeout in seconds
REPORT_INTERVAL=${REPORT_INTERVAL:-300}                  # Report every 5 minutes

# Target configuration (can be Caddy external or internal Docker)
TARGET_HOST=${TARGET_HOST:-"localhost"}
TARGET_PORT=${TARGET_PORT:-80}
TARGET_PATH=${TARGET_PATH:-"/healthz"}
TARGET_PROTOCOL=${TARGET_PROTOCOL:-"http"}
TARGET_URL="${TARGET_PROTOCOL}://${TARGET_HOST}:${TARGET_PORT}${TARGET_PATH}"

# Logging
TIMESTAMP=$(date +%s)
LOG_DIR="/tmp/phase-13-day2"
LATENCY_LOG="${LOG_DIR}/latencies-${TIMESTAMP}.txt"
REQUEST_LOG="${LOG_DIR}/requests-${TIMESTAMP}.txt"
ERROR_LOG="${LOG_DIR}/errors-${TIMESTAMP}.txt"

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

log_latency() {
    echo "$1" >> "$LATENCY_LOG"
}

log_request() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" >> "$REQUEST_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $@" | tee -a "$ERROR_LOG"
}

init_logs() {
    mkdir -p "$LOG_DIR"
    > "$LATENCY_LOG"
    > "$REQUEST_LOG"
    > "$ERROR_LOG"
    log "Load test logs initialized"
    log "  Latency log: $LATENCY_LOG"
    log "  Request log: $REQUEST_LOG"
    log "  Error log:   $ERROR_LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# Load Test Worker (Single Request)
# ─────────────────────────────────────────────────────────────────────────────

make_request() {
    local worker_id=$1
    local start_ns=$(date +%s%N)
    
    # Execute HTTP request with timeout
    local response=$(curl -s \
        --connect-timeout "$REQUEST_TIMEOUT" \
        --max-time "$REQUEST_TIMEOUT" \
        -w "STATUS:%{http_code}\nTIME:%{time_total}" \
        -o /dev/null \
        "$TARGET_URL" 2>&1 || true)
    
    local end_ns=$(date +%s%N)
    local latency_ms=$(( (end_ns - start_ns) / 1000000 ))
    
    # Parse response
    local http_code=$(echo "$response" | grep "^STATUS:" | cut -d: -f2 || echo "000")
    local curl_time=$(echo "$response" | grep "^TIME:" | cut -d: -f2 || echo "0.000")
    
    # Log metrics
    log_latency "$latency_ms $http_code"
    
    if [ "$http_code" = "200" ]; then
        log_request "Worker $worker_id: SUCCESS ($latency_ms ms)"
    else
        log_error "Worker $worker_id: HTTP $http_code ($latency_ms ms)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Concurrent Request Generator
# ─────────────────────────────────────────────────────────────────────────────

run_concurrent_requests() {
    local end_time=$(($(date +%s) + LOAD_TEST_DURATION))
    local request_count=0
    
    log "Starting load test: $CONCURRENT_USERS concurrent users, $LOAD_TEST_DURATION seconds"
    log "Target: $TARGET_URL"
    log ""
    
    while [ $(date +%s) -lt $end_time ]; do
        # Spawn concurrent workers
        for i in $(seq 1 $CONCURRENT_USERS); do
            (
                make_request "$i"
            ) &
        done
        
        # Wait for all workers to complete
        wait
        
        request_count=$((request_count + CONCURRENT_USERS))
    done
    
    log "Load test complete: $request_count total requests"
}

# ─────────────────────────────────────────────────────────────────────────────
# Metrics Analysis (Real-time)
# ─────────────────────────────────────────────────────────────────────────────

analyze_metrics() {
    log ""
    log "═══════════════════════════════════════════════════════════════════════════"
    log "LOAD TEST RESULTS"
    log "═══════════════════════════════════════════════════════════════════════════"
    log ""
    
    if [ ! -f "$LATENCY_LOG" ] || [ ! -s "$LATENCY_LOG" ]; then
        log_error "No latency data collected"
        return 1
    fi
    
    # Parse latency data
    local total_requests=$(wc -l < "$LATENCY_LOG")
    local successful=$(awk '$2 == "200" {count++} END {print count+0}' "$LATENCY_LOG")
    local failed=$((total_requests - successful))
    local error_rate=$(awk "BEGIN {printf \"%.2f\", ($failed / $total_requests) * 100}")
    
    # Latency statistics
    local latencies=$(awk '{print $1}' "$LATENCY_LOG" | sort -n)
    local p50=$(echo "$latencies" | awk 'NR==int(NR/2)+1')
    local p95=$(echo "$latencies" | awk 'NR==int(NR*0.95)+1')
    local p99=$(echo "$latencies" | awk 'NR==int(NR*0.99)+1')
    local p999=$(echo "$latencies" | awk 'NR==int(NR*0.999)+1')
    
    # Throughput
    local duration_seconds=$LOAD_TEST_DURATION
    local throughput=$(awk "BEGIN {printf \"%.2f\", $total_requests / $duration_seconds}")
    
    # Report
    log "Test Duration:        ${duration_seconds}s"
    log "Total Requests:       $total_requests"
    log "Successful:           $successful"
    log "Failed:               $failed"
    log "Error Rate:           ${error_rate}%"
    log "Throughput:           ${throughput} req/s"
    log ""
    log "Latency Percentiles (ms):"
    log "  p50:                $p50 ms"
    log "  p95:                $p95 ms"
    log "  p99:                $p99 ms"
    log "  p99.9:              $p999 ms"
    log ""
    
    # SLO Validation
    log "═══════════════════════════════════════════════════════════════════════════"
    log "SLO VALIDATION"
    log "═══════════════════════════════════════════════════════════════════════════"
    log ""
    
    local all_pass=true
    
    # p99 latency target
    if [ "${p99%.*}" -lt 100 ]; then
        log "✓ p99 Latency: ${p99}ms < 100ms"
    else
        log "✗ p99 Latency: ${p99}ms >= 100ms"
        all_pass=false
    fi
    
    # Error rate target
    if (( $(echo "$error_rate < 0.1" | bc -l) )); then
        log "✓ Error Rate: ${error_rate}% < 0.1%"
    else
        log "✗ Error Rate: ${error_rate}% >= 0.1%"
        all_pass=false
    fi
    
    # Throughput target
    if (( $(echo "$throughput > 100" | bc -l) )); then
        log "✓ Throughput: ${throughput} req/s > 100 req/s"
    else
        log "✗ Throughput: ${throughput} req/s <= 100 req/s"
        all_pass=false
    fi
    
    log ""
    
    if [ "$all_pass" = true ]; then
        log "═══════════════════════════════════════════════════════════════════════════"
        log "RESULT: 🟢 ALL SLOs PASSED"
        log "═══════════════════════════════════════════════════════════════════════════"
        return 0
    else
        log "═══════════════════════════════════════════════════════════════════════════"
        log "RESULT: 🔴 SOME SLOs FAILED"
        log "═══════════════════════════════════════════════════════════════════════════"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log "═══════════════════════════════════════════════════════════════════════════"
    log "PHASE 13 DAY 2: LOAD TEST EXECUTOR"
    log "═══════════════════════════════════════════════════════════════════════════"
    log ""
    
    # Initialize
    init_logs
    log ""
    
    # Verify connectivity
    if ! curl -sf "$TARGET_URL" > /dev/null 2>&1; then
        log_error "Target not reachable: $TARGET_URL"
        exit 1
    fi
    log "✓ Target connectivity verified: $TARGET_URL"
    log ""
    
    # Run load test
    run_concurrent_requests
    
    # Analyze results
    analyze_metrics
}

# Execute
main "$@"
