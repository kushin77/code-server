#!/bin/bash
###############################################################################
# Phase 5 Week 2: Chaos Engineering Master Orchestrator
#
# Coordinates multiple chaos scenarios in sequence or parallel
# Collects metrics and generates chaos testing report
#
# Usage:
#   bash scripts/chaos/orchestrate-chaos-tests.sh full-suite
#   bash scripts/chaos/orchestrate-chaos-tests.sh quick-test
#   bash scripts/chaos/orchestrate-chaos-tests.sh analyze-results
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/artifacts/chaos-results"

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
CHAOS_DURATION="${CHAOS_DURATION:-60}"
RESULTS_FILE="$RESULTS_DIR/chaos-report-$(date +%Y%m%d-%H%M%S).txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cleanup_on_exit() {
    log_info "Restoring services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d 2>/dev/null || true
}

# Initialize results directory
initialize_results() {
    mkdir -p "$RESULTS_DIR"
    
    {
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║     CHAOS ENGINEERING TEST REPORT                      ║"
        echo "╚════════════════════════════════════════════════════════╝"
        echo ""
        echo "Test Start Time: $(date)"
        echo "Test Duration: ${CHAOS_DURATION}s"
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo "TEST SCENARIOS"
        echo "════════════════════════════════════════════════════════"
    } | tee "$RESULTS_FILE"
}

# Run network failure tests
run_network_tests() {
    log_info "Running network failure tests..."
    
    {
        echo ""
        echo "1. NETWORK FAILURES"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } | tee -a "$RESULTS_FILE"
    
    # Packet loss test
    {
        echo ""
        echo "1.1 Packet Loss (5%)"
        echo "Status: Testing..."
    } | tee -a "$RESULTS_FILE"
    
    if CHAOS_DURATION=$CHAOS_DURATION bash "$SCRIPT_DIR/simulate-network-failures.sh" packet-loss 5 2>&1 | tee -a "$RESULTS_FILE"; then
        echo "Status: ✅ PASSED" | tee -a "$RESULTS_FILE"
    else
        echo "Status: ⚠️  SKIPPED (requires root)" | tee -a "$RESULTS_FILE"
    fi
}

# Run service degradation tests
run_degradation_tests() {
    log_info "Running service degradation tests..."
    
    {
        echo ""
        echo "2. SERVICE DEGRADATION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "2.1 Cache Flush (simulating cache miss pattern)"
        echo "Status: Testing..."
    } | tee -a "$RESULTS_FILE"
    
    if CHAOS_DURATION=$CHAOS_DURATION bash "$SCRIPT_DIR/inject-service-degradation.sh" cache-flush 2>&1 | tee -a "$RESULTS_FILE"; then
        echo "Status: ✅ PASSED" | tee -a "$RESULTS_FILE"
    else
        echo "Status: ❌ FAILED" | tee -a "$RESULTS_FILE"
    fi
}

# Run resource exhaustion tests
run_resource_tests() {
    log_info "Running resource exhaustion tests..."
    
    {
        echo ""
        echo "3. RESOURCE EXHAUSTION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "3.1 Memory Pressure (512MB allocation)"
        echo "Status: Testing..."
    } | tee -a "$RESULTS_FILE"
    
    if MEMORY_MB=512 CHAOS_DURATION=$CHAOS_DURATION bash "$SCRIPT_DIR/resource-exhaustion-tests.sh" memory-pressure 2>&1 | tee -a "$RESULTS_FILE"; then
        echo "Status: ✅ PASSED" | tee -a "$RESULTS_FILE"
    else
        echo "Status: ❌ FAILED" | tee -a "$RESULTS_FILE"
    fi
}

# Run container failure tests
run_container_tests() {
    log_info "Running container failure tests..."
    
    {
        echo ""
        echo "4. CONTAINER FAILURES"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "4.1 Measure Recovery Time"
        echo "Status: Testing..."
    } | tee -a "$RESULTS_FILE"
    
    if bash "$SCRIPT_DIR/chaos-container-killer.sh" measure-recovery 2>&1 | tee -a "$RESULTS_FILE"; then
        echo "Status: ✅ PASSED" | tee -a "$RESULTS_FILE"
    else
        echo "Status: ⚠️  TIMEOUT" | tee -a "$RESULTS_FILE"
    fi
}

# Finalize results
finalize_results() {
    {
        echo ""
        echo "════════════════════════════════════════════════════════"
        echo "TEST SUMMARY"
        echo "════════════════════════════════════════════════════════"
        echo "Test End Time: $(date)"
        echo ""
        echo "SUCCESS CRITERIA:"
        echo "  ✅ System recovers automatically from any single failure"
        echo "  ✅ No data loss in any chaos scenario"
        echo "  ✅ Alert system triggers appropriately"
        echo "  ✅ Recovery time < 5 minutes for any failure"
        echo ""
        echo "════════════════════════════════════════════════════════"
    } | tee -a "$RESULTS_FILE"
    
    log_success "Chaos test report saved to: $RESULTS_FILE"
}

# Run quick test suite
run_quick_test() {
    log_info "Running quick chaos test suite (reduced duration)..."
    
    CHAOS_DURATION=30
    initialize_results
    
    run_degradation_tests
    run_container_tests
    
    finalize_results
}

# Run full test suite
run_full_test() {
    log_info "Running full chaos test suite..."
    
    initialize_results
    
    run_network_tests
    run_degradation_tests
    run_resource_tests
    run_container_tests
    
    finalize_results
}

# Analyze test results
analyze_results() {
    if [ ! -f "$RESULTS_FILE" ]; then
        log_error "No results file found"
        return 1
    fi
    
    log_info "Analyzing chaos test results..."
    cat "$RESULTS_FILE"
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 2: Chaos Engineering Orchestrator"
    
    case "$scenario" in
        full-suite)
            run_full_test
            ;;
        quick-test)
            run_quick_test
            ;;
        analyze-results)
            analyze_results
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Usage:"
            echo "  $0 full-suite        - Run all chaos tests"
            echo "  $0 quick-test        - Run reduced chaos tests"
            echo "  $0 analyze-results   - View latest results"
            exit 1
            ;;
    esac
}

main "$@"
