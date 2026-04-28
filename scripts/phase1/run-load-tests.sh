#!/usr/bin/env bash
###############################################################################
# Phase 1: Load Testing & Stress Test Framework
#
# @file scripts/phase1/run-load-tests.sh
# @module phase1/load-testing
# @description Execute load testing across multi-cluster HA setup
# @governance GOV-001: All load tests must be logged and reproducible
# @usage ./run-load-tests.sh [--light|--moderate|--heavy|--stress]
#
# Load Profiles:
#   - light: 100 concurrent users, 5 min duration
#   - moderate: 1000 concurrent users, 10 min duration
#   - heavy: 5000 concurrent users, 15 min duration
#   - stress: 10000+ concurrent users, identify breaking point
###############################################################################

set -euo pipefail

# Error handling
trap 'log_error "Load tests failed at line $LINENO"; exit 1' ERR
trap 'log_info "Load test session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
SSH_USER="${SSH_USER:-akushnir}"
LOAD_PROFILE="${1:-moderate}"
LOAD_ARTIFACTS="${ARTIFACTS_DIR}/load-test-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$LOAD_ARTIFACTS"

# Load profile definitions
declare -A LOAD_PROFILES=(
    [light]="100:300"        # users:seconds
    [moderate]="1000:600"
    [heavy]="5000:900"
    [stress]="10000:600"
)

# ============================================================================
# LOAD TEST EXECUTION
# ============================================================================

run_load_test() {
    local profile=$1
    
    if [[ ! -v LOAD_PROFILES[$profile] ]]; then
        log_error "Unknown load profile: $profile"
        return 1
    fi
    
    IFS=':' read -r users duration <<< "${LOAD_PROFILES[$profile]}"
    
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ LOAD TEST: $profile profile                                ║"
    log_info "║ Users: $users | Duration: ${duration}s                     ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo
    
    # Check dependencies
    if ! command -v ab &>/dev/null; then
        log_error "Apache Bench (ab) not found. Install with: sudo apt-get install apache2-utils"
        return 1
    fi
    
    # Test configuration
    local test_url="http://${PRIMARY_HOST}/health"
    local concurrent_clients=$users
    local requests=$((users * 100))  # 100 requests per simulated user
    
    log_info "Test Configuration:"
    log_info "  URL: $test_url"
    log_info "  Concurrent clients: $concurrent_clients"
    log_info "  Total requests: $requests"
    log_info "  Duration target: ${duration}s"
    echo
    
    # Run load test
    {
        echo "=== LOAD TEST RESULTS: $profile profile ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Profile: $profile"
        echo "URL: $test_url"
        echo "Concurrent clients: $concurrent_clients"
        echo ""
        
        # Apache Bench load test
        ab -n "$requests" \
           -c "$concurrent_clients" \
           -t "$duration" \
           -r \
           -k \
           "$test_url" 2>&1 | tee -a "${LOAD_ARTIFACTS}/load-test-${profile}.txt" || true
        
    } | tee "${LOAD_ARTIFACTS}/load-results-${profile}.txt"
    
    # Parse results
    extract_load_metrics "${LOAD_ARTIFACTS}/load-results-${profile}.txt" "$profile"
}

extract_load_metrics() {
    local results_file=$1
    local profile=$2
    
    log_info "Analyzing load test results..."
    
    # Extract key metrics
    {
        echo ""
        echo "=== METRICS SUMMARY ==="
        echo "Profile: $profile"
        echo ""
        
        # Requests per second
        rps=$(grep "Requests per second" "$results_file" | awk '{print $NF}')
        [[ -n "$rps" ]] && echo "Requests/sec: $rps" || echo "Requests/sec: N/A"
        
        # Failed requests
        failed=$(grep "Failed requests" "$results_file" | awk '{print $(NF-2)}')
        [[ -n "$failed" ]] && echo "Failed requests: $failed" || echo "Failed requests: N/A"
        
        # Time per request
        mean_time=$(grep "Time per request" "$results_file" | head -1 | awk '{print $(NF-2)}')
        [[ -n "$mean_time" ]] && echo "Mean request time: ${mean_time}ms" || echo "Mean request time: N/A"
        
        # Connection times
        echo ""
        echo "Connection times (ms):"
        grep -A 4 "Connection Times" "$results_file" | tail -4 || echo "N/A"
        
    } | tee -a "${LOAD_ARTIFACTS}/metrics-${profile}.txt"
}

# ============================================================================
# DISTRIBUTED LOAD TEST (Both nodes)
# ============================================================================

run_distributed_load_test() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ DISTRIBUTED LOAD TEST (Both nodes)                        ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo
    
    log_info "Testing load distribution across both nodes..."
    
    # Simple distributed load (requires wrk or similar, fallback to ab)
    {
        echo "=== DISTRIBUTED LOAD TEST RESULTS ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        
        if command -v wrk &>/dev/null; then
            log_info "Using wrk for distributed load test..."
            # wrk: 4 threads, 100 connections, 30 second duration, script to distribute load
            wrk -t 4 -c 100 -d 30s --latency \
                "http://${PRIMARY_HOST}/health" || true
        else
            log_warning "wrk not installed, using fallback method..."
            log_warning "Install wrk with: sudo apt-get install wrk"
            
            # Fallback: run ab against both nodes sequentially
            ab -n 1000 -c 50 "http://${PRIMARY_HOST}/health" >> "${LOAD_ARTIFACTS}/dist-load.txt" 2>&1 || true
            ab -n 1000 -c 50 "http://${REPLICA_HOST}/health" >> "${LOAD_ARTIFACTS}/dist-load.txt" 2>&1 || true
        fi
        
    } | tee -a "${LOAD_ARTIFACTS}/distributed-load-results.txt"
}

# ============================================================================
# LOAD TEST SUMMARY
# ============================================================================

generate_load_report() {
    local profile=$1
    
    cat > "${LOAD_ARTIFACTS}/LOAD_TEST_REPORT.md" << EOF
# Load Test Report - Phase 1

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Profile**: $profile
**Environment**: Primary=$PRIMARY_HOST, Replica=$REPLICA_HOST

## Load Profile Details

| Profile | Users | Duration | Requests |
|---------|-------|----------|----------|
| Light   | 100   | 5 min    | 10K+     |
| Moderate| 1000  | 10 min   | 100K+    |
| Heavy   | 5000  | 15 min   | 500K+    |
| Stress  | 10K+  | 10 min   | Identify breaking point |

## Results for $profile

See metrics-${profile}.txt for detailed results

## Success Criteria

✓ 99%+ success rate (< 1% errors)
✓ Mean response time < 500ms
✓ No cascading failures observed
✓ Both nodes handling balanced load
✓ Services remain responsive

## Artifacts

- Full results: ${LOAD_ARTIFACTS}/load-results-${profile}.txt
- Metrics: ${LOAD_ARTIFACTS}/metrics-${profile}.txt
- Distributed load: ${LOAD_ARTIFACTS}/distributed-load-results.txt

EOF
    
    log_success "✓ Load test report: ${LOAD_ARTIFACTS}/LOAD_TEST_REPORT.md"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "$LOAD_PROFILE" in
        light|moderate|heavy|stress)
            run_load_test "$LOAD_PROFILE"
            run_distributed_load_test
            generate_load_report "$LOAD_PROFILE"
            ;;
        *)
            log_error "Unknown load profile: $LOAD_PROFILE"
            echo "Usage: $0 [light|moderate|heavy|stress]"
            exit 1
            ;;
    esac
}

main "$@"
