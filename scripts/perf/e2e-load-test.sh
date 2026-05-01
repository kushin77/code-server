#!/bin/bash

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# E2E and Load Test Runner
# Issue #1537 Week 3: E2E + Load Testing
# 
# This script orchestrates E2E and load testing against real Docker Compose stack
#
# Usage:
#   ./scripts/perf/e2e-load-test.sh [command]
#
# Commands:
#   setup      - Start Docker Compose stack for testing
#   e2e        - Run E2E tests
#   load       - Run all load tests
#   oauth-load - Run OAuth load test (100 users)
#   user-load  - Run user load test (200 users)
#   team-load  - Run team load test (150 users)
#   gateway-load - Run gateway load test (300 users)
#   cleanup    - Stop Docker Compose stack
#   all        - Run full suite (setup, e2e, load, cleanup)
#

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_ROOT="$PROJECT_ROOT/apps/auth-server"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_URL="http://localhost:3100"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
K6_TIMEOUT="5m"
E2E_TIMEOUT="30s"
COMPOSE_CMD=()

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose (prefer plugin, fall back to standalone binary)
    if docker compose version &> /dev/null; then
        COMPOSE_CMD=(docker compose)
        log_info "Using Docker Compose plugin"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD=(docker-compose)
        log_info "Using docker-compose binary"
    else
        log_error "Neither 'docker compose' nor 'docker-compose' is available"
        exit 1
    fi
    
    # Check K6 (for load tests)
    if [ "$1" != "e2e" ] && ! command -v k6 &> /dev/null; then
        log_warning "K6 is not installed - install with: brew install k6 (macOS) or visit https://k6.io/docs/getting-started/installation/"
    fi
    
    # Check pytest (for E2E tests)
    if [ "$1" != "load" ] && ! command -v pytest &> /dev/null; then
        log_warning "pytest is not installed in environment"
    fi
    
    log_success "Prerequisites check complete"
}

wait_for_service() {
    local service_url=$1
    local timeout=$2
    local elapsed=0
    
    log_info "Waiting for service at $service_url..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -sf "$service_url/health" > /dev/null 2>&1; then
            log_success "Service is ready"
            return 0
        fi
        
        echo -n "."
        sleep 1
        elapsed+=1
    done
    
    log_error "Service did not become ready within ${timeout}s"
    return 1
}

setup_stack() {
    log_info "Starting Docker Compose stack for testing..."
    
    cd "$PROJECT_ROOT"
    
    # Start services
    "${COMPOSE_CMD[@]}" up -d --build
    
    # Wait for API to be ready
    if ! wait_for_service "$API_URL" 60; then
        log_error "Failed to start services"
        return 1
    fi
    
    log_success "Docker Compose stack is ready"
}

run_e2e_tests() {
    log_info "Running E2E tests..."
    
    cd "$APP_ROOT"
    
    if ! command -v pytest &> /dev/null; then
        log_warning "pytest not found, skipping E2E tests"
        return 0
    fi
    
    pytest tests/e2e/ \
        -v \
        --tb=short \
        -m e2e \
        --timeout=30 \
        --junit-xml=test-results-e2e.xml \
        --html=test-results-e2e.html \
        --self-contained-html
    
    if [ $? -eq 0 ]; then
        log_success "E2E tests passed"
    else
        log_error "E2E tests failed"
        return 1
    fi
}

run_oauth_load_test() {
    log_info "Running OAuth load test (100 concurrent users)..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/oauth-load-test.js \
        --vus 100 \
        --duration "$K6_TIMEOUT" \
        --out json=test-results-oauth-load.json
    
    if [ $? -eq 0 ]; then
        log_success "OAuth load test passed"
    else
        log_warning "OAuth load test encountered issues"
    fi
}

run_user_load_test() {
    log_info "Running user load test (200 concurrent users)..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/user-load-test.js \
        --vus 200 \
        --duration "$K6_TIMEOUT" \
        --out json=test-results-user-load.json
    
    if [ $? -eq 0 ]; then
        log_success "User load test passed"
    else
        log_warning "User load test encountered issues"
    fi
}

run_team_load_test() {
    log_info "Running team load test (150 concurrent users)..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/team-load-test.js \
        --vus 150 \
        --duration "$K6_TIMEOUT" \
        --out json=test-results-team-load.json
    
    if [ $? -eq 0 ]; then
        log_success "Team load test passed"
    else
        log_warning "Team load test encountered issues"
    fi
}

run_gateway_load_test() {
    log_info "Running gateway load test (300 concurrent users)..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/gateway-load-test.js \
        --vus 300 \
        --duration "$K6_TIMEOUT" \
        --out json=test-results-gateway-load.json
    
    if [ $? -eq 0 ]; then
        log_success "Gateway load test passed"
    else
        log_warning "Gateway load test encountered issues"
    fi
}

run_stress_test() {
    log_info "Running stress test (500+ concurrent users)..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/stress-test.js \
        --vus 500 \
        --duration 10m \
        --out json=test-results-stress.json
    
    if [ $? -eq 0 ]; then
        log_success "Stress test passed"
    else
        log_warning "Stress test encountered issues (expected under extreme load)"
    fi
}

run_deployment_verification() {
    log_info "Running deployment verification tests..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/deployment-verification.js \
        --vus 5 \
        --duration 5m \
        --out json=test-results-deployment-verification.json
    
    if [ $? -eq 0 ]; then
        log_success "Deployment verification passed"
    else
        log_error "Deployment verification failed"
        return 1
    fi
}

run_performance_benchmark() {
    log_info "Running performance benchmarking..."
    
    if ! command -v k6 &> /dev/null; then
        log_error "K6 is not installed"
        return 1
    fi
    
    cd "$APP_ROOT"
    
    k6 run tests/load/performance-benchmark.js \
        --vus 50 \
        --duration 5m \
        --out json=test-results-performance-benchmark.json
    
    if [ $? -eq 0 ]; then
        log_success "Performance benchmarking completed"
    else
        log_warning "Performance benchmarking encountered issues"
    fi
}

run_all_load_tests() {
    log_info "Running all load tests..."
    
    run_oauth_load_test
    run_user_load_test
    run_team_load_test
    run_gateway_load_test
    
    log_success "All load tests completed"
}

cleanup_stack() {
    log_info "Cleaning up Docker Compose stack..."
    
    cd "$PROJECT_ROOT"
    
    "${COMPOSE_CMD[@]}" down -v
    
    log_success "Docker Compose stack stopped"
}

generate_report() {
    log_info "Generating test report..."
    
    cd "$APP_ROOT"
    
    echo "## E2E & Load Test Report" > TEST_REPORT.md
    echo "" >> TEST_REPORT.md
    echo "Generated: $(date)" >> TEST_REPORT.md
    echo "" >> TEST_REPORT.md
    
    if [ -f "test-results-e2e.html" ]; then
        echo "### E2E Tests" >> TEST_REPORT.md
        echo "See test-results-e2e.html" >> TEST_REPORT.md
        echo "" >> TEST_REPORT.md
    fi
    
    if [ -f "test-results-oauth-load.json" ]; then
        echo "### OAuth Load Test Results" >> TEST_REPORT.md
        echo "\`\`\`" >> TEST_REPORT.md
        k6 stats test-results-oauth-load.json 2>/dev/null || echo "See test-results-oauth-load.json" >> TEST_REPORT.md
        echo "\`\`\`" >> TEST_REPORT.md
        echo "" >> TEST_REPORT.md
    fi
    
    log_success "Report generated: TEST_REPORT.md"
}

# Main
main() {
    local command="${1:-all}"
    
    case "$command" in
        setup)
            check_prerequisites "setup"
            setup_stack
            ;;
        e2e)
            check_prerequisites "e2e"
            run_e2e_tests
            ;;
        load)
            check_prerequisites "load"
            run_all_load_tests
            ;;
        oauth-load)
            check_prerequisites "load"
            run_oauth_load_test
            ;;
        user-load)
            check_prerequisites "load"
            run_user_load_test
            ;;
        team-load)
            check_prerequisites "load"
            run_team_load_test
            ;;
        gateway-load)
            check_prerequisites "load"
            run_gateway_load_test
            ;;
        stress)
            check_prerequisites "load"
            run_stress_test
            ;;
        deployment-verify)
            check_prerequisites "load"
            run_deployment_verification
            ;;
        benchmark)
            check_prerequisites "load"
            run_performance_benchmark
            ;;
        chaos)
            log_info "Running chaos engineering tests..."
            if [ -f scripts/ops/chaos-test.sh ]; then
                chmod +x scripts/ops/chaos-test.sh
                ./scripts/ops/chaos-test.sh all || true
            else
                log_warning "Chaos test script not found"
            fi
            ;;
        security)
            log_info "Running security scanning..."
            if [ -f scripts/security/security-scan.sh ]; then
                chmod +x scripts/security/security-scan.sh
                ./scripts/security/security-scan.sh comprehensive || true
            else
                log_warning "Security scan script not found"
            fi
            ;;
        dr-drills)
            log_info "Running disaster recovery drills..."
            if [ -f scripts/ops/disaster-recovery-drills.sh ]; then
                chmod +x scripts/ops/disaster-recovery-drills.sh
                ./scripts/ops/disaster-recovery-drills.sh all || true
            else
                log_warning "DR drills script not found"
            fi
            ;;
        cleanup)
            cleanup_stack
            ;;
        all)
            check_prerequisites "all"
            setup_stack
            run_e2e_tests
            run_all_load_tests
            run_stress_test
            run_deployment_verification
            run_performance_benchmark
            generate_report
            cleanup_stack
            ;;
        *)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup              - Start Docker Compose stack for testing"
            echo "  e2e                - Run E2E tests"
            echo "  load               - Run all load tests"
            echo "  oauth-load         - Run OAuth load test (100 users)"
            echo "  user-load          - Run user load test (200 users)"
            echo "  team-load          - Run team load test (150 users)"
            echo "  gateway-load       - Run gateway load test (300 users)"
            echo "  stress             - Run stress test (500+ users)"
            echo "  deployment-verify  - Run deployment verification tests"
            echo "  benchmark          - Run performance benchmarking"
            echo "  cleanup            - Stop Docker Compose stack"
            echo "  all                - Run full suite"
            exit 1
            ;;
    esac
}

main "$@"
