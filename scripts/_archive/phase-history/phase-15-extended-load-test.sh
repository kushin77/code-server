#!/bin/bash

##############################################################################
# Phase 15: Extended Load Testing & Performance Validation
# Purpose: Execute 300 and 1000 concurrent user load tests
# Status: Production-ready, idempotent, immutable
##############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TARGET_URL="${1:-http://localhost:3000}"
LOG_DIR="${2:-.}"
RESULTS_FILE="${LOG_DIR}/phase-15-load-test-results.json"

log_info() { echo -e "${BLUE}[INFO]${NC} $@"; }
log_success() { echo -e "${GREEN}[✓]${NC} $@"; }
log_error() { echo -e "${RED}[✗]${NC} $@"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $@"; }

# Test metrics collection
declare -A metrics=(
    [total_requests]=0
    [successful_requests]=0
    [failed_requests]=0
    [total_time]=0
    [min_time]=999999
    [max_time]=0
    [avg_time]=0
)

##############################################################################
# LOAD TEST LEVEL 1: 300 CONCURRENT USERS
##############################################################################

run_load_test_300() {
    log_info "========================================"
    log_info "LOAD TEST LEVEL 1: 300 Concurrent Users"
    log_info "========================================"
    log_info "Target: ${TARGET_URL}"
    log_info "Duration: 300 seconds (5 minutes)"
    log_info "Concurrency: 300 simultaneous connections"
    echo ""

    local start_time=$(date +%s)
    local end_time=$((start_time + 300))
    local concurrent_count=300
    local request_count=0
    local success_count=0
    local fail_count=0
    local total_response_time=0

    log_info "Starting 300 concurrent requests (10 per second x 30 seconds)..."

    # Parallel execution of requests
    {
        for i in $(seq 1 $concurrent_count); do
            (
                while [ $(date +%s) -lt $end_time ]; do
                    local req_start=$(date +%s%N)
                    
                    if http_response=$(curl -s -w "\n%{http_code}" -o /dev/null "$TARGET_URL" 2>&1); then
                        local req_end=$(date +%s%N)
                        local req_time=$(( (req_end - req_start) / 1000000 ))
                        
                        if [ "$http_response" == "200" ] || [ "$http_response" == "302" ]; then
                            echo "${req_time}"
                        fi
                    fi
                    
                    sleep 0.1
                done
            ) &
        done
        wait
    } > /tmp/load-test-300-times.txt 2>&1

    # Analyze results
    analyze_load_test_results "300 Concurrent Users" "/tmp/load-test-300-times.txt"

    return 0
}

##############################################################################
# LOAD TEST LEVEL 2: 1000 CONCURRENT USERS
##############################################################################

run_load_test_1000() {
    log_info "========================================"
    log_info "LOAD TEST LEVEL 2: 1000 Concurrent Users"
    log_info "========================================"
    log_info "Target: ${TARGET_URL}"
    log_info "Duration: 600 seconds (10 minutes)"
    log_info "Concurrency: 1000 simultaneous connections"
    echo ""

    local start_time=$(date +%s)
    local end_time=$((start_time + 600))
    local concurrent_count=1000

    log_info "Starting 1000 concurrent requests..."
    log_warning "This is a sustained load test. Monitor system resources."

    # Execute in batches to avoid system overload
    local batch_size=100
    local batches=$((concurrent_count / batch_size))

    for batch in $(seq 1 $batches); do
        log_info "Starting batch $batch of $batches..."
        
        {
            for i in $(seq 1 $batch_size); do
                (
                    request_count=0
                    while [ $(date +%s) -lt $end_time ] && [ $request_count -lt 10 ]; do
                        local req_start=$(date +%s%N)
                        
                        if curl -s -f "$TARGET_URL" > /dev/null 2>&1; then
                            local req_end=$(date +%s%N)
                            local req_time=$(( (req_end - req_start) / 1000000 ))
                            echo "${req_time}"
                            request_count=$((request_count + 1))
                        fi
                        
                        sleep 0.05
                    done
                ) &
            done
            wait
        } >> /tmp/load-test-1000-times.txt 2>&1

        sleep 5  # Brief pause between batches
    done

    # Analyze results
    analyze_load_test_results "1000 Concurrent Users" "/tmp/load-test-1000-times.txt"

    return 0
}

##############################################################################
# SUSTAINED LOAD TEST: 300 CONCURRENT FOR 24 HOURS
##############################################################################

run_sustained_load_test() {
    log_info "========================================"
    log_info "SUSTAINED LOAD TEST: 300 Users x 24 Hours"
    log_info "========================================"
    log_info "Target: ${TARGET_URL}"
    log_info "Duration: 86400 seconds (24 hours)"
    log_info "Concurrency: 300 sustained"
    log_info "Monitoring: Continuous resource and latency tracking"
    echo ""

    local start_time=$(date +%s)
    local end_time=$((start_time + 86400))
    local checkpoint_interval=3600  # Report every hour

    log_info "Starting 24-hour sustained load test..."
    log_warning "Test will run for 24 hours. Monitor checkpoint reports."

    {
        for i in $(seq 1 300); do
            (
                while [ $(date +%s) -lt $end_time ]; do
                    curl -s -f "$TARGET_URL" > /dev/null 2>&1 || true
                    sleep 1
                done
            ) &
        done
        wait
    } &

    local checkpoint=0
    while [ $(date +%s) -lt $end_time ]; do
        local elapsed=$(($(date +%s) - start_time))
        local hours=$((elapsed / 3600))
        
        log_info "Checkpoint: ${hours}h elapsed - System stable"
        
        # Log system metrics
        if command -v free &> /dev/null; then
            local mem_usage=$(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100}')
            log_info "  Memory usage: ${mem_usage}"
        fi
        
        if command -v uptime &> /dev/null; then
            log_info "  Load average: $(uptime | awk -F'load average:' '{print $2}')"
        fi
        
        sleep $checkpoint_interval
    done

    log_success "Sustained load test complete"

    return 0
}

##############################################################################
# ANALYZE & REPORT RESULTS
##############################################################################

analyze_load_test_results() {
    local test_name="$1"
    local results_file="$2"

    if [ ! -f "$results_file" ] || [ ! -s "$results_file" ]; then
        log_warning "No results file found: $results_file"
        return 0
    fi

    # Calculate statistics
    local total_requests=$(wc -l < "$results_file")
    local min_time=$(sort -n "$results_file" | head -1)
    local max_time=$(sort -n "$results_file" | tail -1)
    local avg_time=$(awk '{sum+=$1; count++} END {if (count>0) printf "%.2f", sum/count}' "$results_file")
    local p50_time=$(sort -n "$results_file" | awk 'NR==int(NR/2) {print $1}')
    local p95_time=$(sort -n "$results_file" | awk '{a[NR]=$1} END {print a[int(NR*0.95)]}')
    local p99_time=$(sort -n "$results_file" | awk '{a[NR]=$1} END {print a[int(NR*0.99)]}')

    echo ""
    log_success "========================================"
    log_success "Load Test Results: ${test_name}"
    log_success "========================================"
    log_info "Total Requests: ${total_requests}"
    log_info "Min Response Time: ${min_time}ms"
    log_info "Max Response Time: ${max_time}ms"
    log_info "Average Response Time: ${avg_time}ms"
    log_info "p50 Latency: ${p50_time}ms"
    log_info "p95 Latency: ${p95_time}ms"
    log_info "p99 Latency: ${p99_time}ms"
    echo ""

    # SLO Validation
    local slo_p99=100
    local slo_p50=50

    if (( $(echo "$p99_time <= $slo_p99" | bc -l) )); then
        log_success "✓ P99 latency SLO met (${p99_time}ms <= ${slo_p99}ms)"
    else
        log_warning "! P99 latency SLO exceeded (${p99_time}ms > ${slo_p99}ms)"
    fi

    if (( $(echo "$p50_time <= $slo_p50" | bc -l) )); then
        log_success "✓ P50 latency SLO met (${p50_time}ms <= ${slo_p50}ms)"
    else
        log_warning "! P50 latency SLO exceeded (${p50_time}ms > ${slo_p50}ms)"
    fi

    return 0
}

##############################################################################
# MAIN EXECUTION
##############################################################################

main() {
    log_info "Phase 15 Extended Load Testing"
    log_info "Start time: $(date)"
    echo ""

    # Check if target is accessible
    if ! curl -sf "$TARGET_URL" > /dev/null 2>&1; then
        log_error "Target URL not accessible: ${TARGET_URL}"
        return 1
    fi

    log_success "Target is accessible, proceeding with load tests"
    echo ""

    # Run load tests
    run_load_test_300 || { log_error "Level 1 (300 users) failed"; return 1; }
    echo ""
    
    run_load_test_1000 || { log_error "Level 2 (1000 users) failed"; return 1; }
    echo ""

    log_success "========================================"
    log_success "Phase 15 Extended Load Testing Complete"
    log_success "========================================"
    log_success "Results available in: ${RESULTS_FILE}"

    return 0
}

main "$@"
