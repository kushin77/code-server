#!/bin/bash
###############################################################################
# Phase 5 Performance Testing Orchestrator
# Manages Docker Compose stack and runs Locust load tests
# 
# Usage:
#   bash scripts/perf/run-performance-test.sh [scenario] [action]
#   bash scripts/perf/run-performance-test.sh medium run
#   bash scripts/perf/run-performance-test.sh heavy analyze
#   bash scripts/perf/run-performance-test.sh light setup
#
# Scenarios: light, medium, heavy, spike, sustained
# Actions: setup, run, analyze, cleanup, all
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; cleanup_on_exit || true' EXIT

cleanup_on_exit() {
    if [ "${CLEANUP_ON_EXIT:-false}" = "true" ]; then
        log_info "Cleaning up resources on exit..."
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
SCENARIO="${1:-medium}"
ACTION="${2:-all}"
API_URL="${API_URL:-http://localhost:3100}"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
LOCUST_SCRIPT="$SCRIPT_DIR/locust-loadtest.py"
RESULTS_DIR="$PROJECT_ROOT/artifacts/performance-results"
LOG_FILE="$RESULTS_DIR/test-$(date +%Y%m%d-%H%M%S).log"

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

# Create results directory
mkdir -p "$RESULTS_DIR"

# Validate scenario
validate_scenario() {
    if [[ ! "$SCENARIO" =~ ^(light|medium|heavy|spike|sustained)$ ]]; then
        log_error "Invalid scenario: $SCENARIO"
        log_error "Valid scenarios: light, medium, heavy, spike, sustained"
        exit 1
    fi
}

# Setup Docker Compose environment
setup_environment() {
    log_info "Setting up Docker Compose environment..."
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose not found. Please install Docker Compose."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found. Please install Python 3."
        exit 1
    fi
    
    log_info "Starting Docker Compose stack..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Waiting for services to be ready..."
    sleep 15
    
    # Check if API is responding
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$API_URL/health" > /dev/null 2>&1; then
            log_success "API is ready at $API_URL"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_warning "API not ready yet ($attempt/$max_attempts), retrying in 2 seconds..."
        sleep 2
    done
    
    log_error "API did not become ready within timeout"
    return 1
}

# Run performance test
run_test() {
    log_info "Running performance test: $SCENARIO"
    
    if [ ! -f "$LOCUST_SCRIPT" ]; then
        log_error "Locust script not found: $LOCUST_SCRIPT"
        exit 1
    fi
    
    # Check if locust is installed
    if ! python3 -m locust --version > /dev/null 2>&1; then
        log_warning "Locust not installed. Installing locust..."
        pip3 install locust 2>&1 | tee -a "$LOG_FILE"
    fi
    
    local results_csv="$RESULTS_DIR/results-${SCENARIO}-$(date +%Y%m%d-%H%M%S)"
    
    log_info "Results will be saved to: $results_csv"
    
    API_URL="$API_URL" SCENARIO="$SCENARIO" python3 -m locust \
        -f "$LOCUST_SCRIPT" \
        --headless \
        --csv="$results_csv" \
        --users 1 \
        --spawn-rate 1 \
        --run-time 60s \
        2>&1 | tee -a "$LOG_FILE"
    
    log_success "Performance test completed"
    log_info "Results saved to: $results_csv"
    
    # Collect container metrics
    log_info "Collecting container metrics..."
    docker stats --no-stream > "$RESULTS_DIR/container-stats-$(date +%Y%m%d-%H%M%S).txt" 2>&1 || true
}

# Analyze results
analyze_results() {
    log_info "Analyzing performance test results..."
    
    local latest_result=$(find "$RESULTS_DIR" -name "results-${SCENARIO}-*.csv" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_result" ]; then
        log_warning "No results found for scenario: $SCENARIO"
        return 0
    fi
    
    log_info "Analyzing: $latest_result"
    
    # Basic analysis
    log_info "Performance Summary:"
    if command -v python3 &> /dev/null; then
        python3 << EOF
import csv
import statistics

with open('$latest_result', 'r') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    
    if not rows:
        print("  No data in results file")
        exit(0)
    
    # Parse response times
    response_times = []
    for row in rows:
        try:
            avg_time = float(row.get('Average Response Time', 0))
            if avg_time > 0:
                response_times.append(avg_time)
        except (ValueError, KeyError):
            pass
    
    if response_times:
        print(f"  Average Response Time: {statistics.mean(response_times):.0f}ms")
        print(f"  Min Response Time: {min(response_times):.0f}ms")
        print(f"  Max Response Time: {max(response_times):.0f}ms")
        print(f"  Median Response Time: {statistics.median(response_times):.0f}ms")
        
        if len(response_times) > 1:
            print(f"  Std Dev: {statistics.stdev(response_times):.0f}ms")
EOF
    fi
}

# Cleanup environment
cleanup_environment() {
    log_info "Cleaning up Docker Compose environment..."
    
    if docker-compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        docker-compose -f "$DOCKER_COMPOSE_FILE" down 2>&1 | tee -a "$LOG_FILE"
        log_success "Docker Compose stack stopped"
    fi
}

# Main execution
main() {
    log_info "Phase 5 Performance Testing Orchestrator"
    log_info "=========================================="
    
    validate_scenario
    
    case "$ACTION" in
        setup)
            setup_environment
            ;;
        run)
            run_test
            ;;
        analyze)
            analyze_results
            ;;
        cleanup)
            cleanup_environment
            ;;
        all)
            setup_environment && run_test && analyze_results && cleanup_environment
            ;;
        *)
            log_error "Invalid action: $ACTION"
            log_error "Valid actions: setup, run, analyze, cleanup, all"
            exit 1
            ;;
    esac
    
    log_info "Test log saved to: $LOG_FILE"
    log_success "Performance test orchestration complete"
}

main "$@"
