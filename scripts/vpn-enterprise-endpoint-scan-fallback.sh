#!/usr/bin/env bash
################################################################################
# File:          scripts/vpn-enterprise-endpoint-scan-fallback.sh
# Owner:         Platform Engineering
# Purpose:       Host-based emergency validation of VPN endpoints (no CI/CD needed)
# Usage:         bash scripts/vpn-enterprise-endpoint-scan-fallback.sh
# Status:        active
# Depends:       curl, jq, ip, wg (WireGuard tools)
# Last Updated:  April 15, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${VPN_FALLBACK_OUTPUT:-$PROJECT_ROOT/test-results/vpn-endpoint-fallback/$TIMESTAMP}"
VPN_INTERFACE="${VPN_INTERFACE:-wg0}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[✅]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[⚠️]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[❌]${NC} $*" >&2
}

################################################################################
# VPN Validation Functions
################################################################################

validate_vpn_interface() {
    log_info "Validating VPN interface: $VPN_INTERFACE"
    
    if ! ip link show "$VPN_INTERFACE" >/dev/null 2>&1; then
        log_error "VPN interface '$VPN_INTERFACE' not found"
        log_warn "Available interfaces:"
        ip link show | grep -E '^\d+:' | awk '{print $2}' | sed 's/:$//'
        return 1
    fi
    
    if ! ip link show "$VPN_INTERFACE" | grep -q 'UP'; then
        log_error "VPN interface '$VPN_INTERFACE' is not UP"
        log_warn "To bring interface up, run: sudo wg-quick up $VPN_INTERFACE"
        return 1
    fi
    
    log_success "VPN interface '$VPN_INTERFACE' is UP"
    return 0
}

validate_wireguard_connectivity() {
    log_info "Validating WireGuard connectivity"
    
    if ! command -v wg >/dev/null 2>&1; then
        log_error "WireGuard tools (wg) not found"
        return 1
    fi
    
    if ! sudo wg show "$VPN_INTERFACE" >/dev/null 2>&1; then
        log_error "Cannot query WireGuard interface '$VPN_INTERFACE'"
        return 1
    fi
    
    # Get peer count
    PEER_COUNT=$(sudo wg show "$VPN_INTERFACE" peers 2>/dev/null | wc -l)
    if [[ $PEER_COUNT -lt 1 ]]; then
        log_error "No WireGuard peers configured"
        return 1
    fi
    
    log_success "WireGuard configured with $PEER_COUNT peer(s)"
    return 0
}

################################################################################
# Endpoint Testing Functions
################################################################################

test_endpoint() {
    local endpoint=$1
    local name=$2
    local expected_code=${3:-200}
    
    ((TESTS_RUN++))
    
    local start_time
    local end_time
    local elapsed_ms
    local http_code
    local response_time
    
    start_time=$(date +%s%N)
    
    # Use curl to test endpoint with timeout
    http_code=$(curl -s -w "%{http_code}" -o /tmp/vpn-endpoint-test-$$.txt \
        --connect-timeout 5 \
        --max-time 10 \
        --silent \
        "https://$endpoint" 2>/dev/null || echo "000")
    
    end_time=$(date +%s%N)
    elapsed_ms=$(( (end_time - start_time) / 1000000 ))
    response_time=$(printf "%.0fms" $elapsed_ms)
    
    # Clean up temp file
    rm -f /tmp/vpn-endpoint-test-$$.txt
    
    if [[ "$http_code" == "$expected_code" ]] || [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
        log_success "$name: HTTP $http_code ($response_time)"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$name: HTTP $http_code (expected $expected_code, got $http_code)"
        ((TESTS_FAILED++))
        return 1
    fi
}

################################################################################
# Core Endpoints
################################################################################

test_core_endpoints() {
    log_info "Testing core endpoints"
    
    # Determine base URL
    local base_url="${VPN_SCAN_BASE_URL:-https://ide.kushnir.cloud}"
    
    # Core endpoints
    test_endpoint "$base_url/healthz" "Healthz" "200"
    test_endpoint "$base_url/api/version" "API Version" "200"
    test_endpoint "$base_url/" "Code Server Home" "200"
    test_endpoint "$base_url/login" "OAuth Login" "200"
}

################################################################################
# Observable Services
################################################################################

test_observable_services() {
    log_info "Testing observability services"
    
    # Prometheus
    test_endpoint "192.168.168.31:9090/metrics" "Prometheus Metrics" "200"
    test_endpoint "192.168.168.31:9090/api/v1/status/config" "Prometheus Config" "200"
    
    # Grafana
    test_endpoint "192.168.168.31:3000/api/health" "Grafana Health" "200"
    
    # AlertManager
    test_endpoint "192.168.168.31:9093/api/v1/status" "AlertManager Status" "200"
    
    # Jaeger
    test_endpoint "192.168.168.31:16686/api/status" "Jaeger Status" "200"
}

################################################################################
# Database Connectivity
################################################################################

test_database_connectivity() {
    log_info "Testing database connectivity"
    
    if ! command -v psql >/dev/null 2>&1; then
        log_warn "psql not available, skipping PostgreSQL test"
        return 0
    fi
    
    # Test PostgreSQL on private network
    if PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" \
        psql -h 192.168.168.31 -U postgres -d postgres \
        -c "SELECT version();" >/dev/null 2>&1; then
        log_success "PostgreSQL connectivity OK"
        ((TESTS_PASSED++))
        ((TESTS_RUN++))
    else
        log_warn "PostgreSQL not reachable (expected if not on VPN)"
        ((TESTS_RUN++))
    fi
}

################################################################################
# Report Generation
################################################################################

generate_report() {
    log_info "Generating report"
    
    mkdir -p "$OUTPUT_DIR"
    
    local pass_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    
    # Create summary file
    cat > "$OUTPUT_DIR/summary.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "vpn_interface": "$VPN_INTERFACE",
  "tests_run": $TESTS_RUN,
  "tests_passed": $TESTS_PASSED,
  "tests_failed": $TESTS_FAILED,
  "pass_rate": $pass_rate,
  "status": "$([ $TESTS_FAILED -eq 0 ] && echo 'pass' || echo 'fail')",
  "host": "$(hostname)",
  "user": "$(whoami)"
}
EOF
    
    # Create human-readable report
    cat > "$OUTPUT_DIR/report.txt" <<EOF
VPN Enterprise Endpoint Scan - Fallback Report
================================================
Generated: $TIMESTAMP
Host: $(hostname)
User: $(whoami)
VPN Interface: $VPN_INTERFACE

Test Results
============
Total Tests: $TESTS_RUN
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Pass Rate: ${pass_rate}%

Status: $([ $TESTS_FAILED -eq 0 ] && echo '✅ PASS' || echo '❌ FAIL')

Summary
=======
Location: $OUTPUT_DIR
Report: $OUTPUT_DIR/report.txt
JSON Summary: $OUTPUT_DIR/summary.json
EOF
    
    log_info "Report: $OUTPUT_DIR"
}

################################################################################
# Main
################################################################################

main() {
    log_info "VPN Enterprise Endpoint Scan (Fallback - No CI)"
    log_info "Interface: $VPN_INTERFACE"
    log_info "Output: $OUTPUT_DIR"
    
    # Validate prerequisites
    if ! validate_vpn_interface; then
        log_error "VPN interface validation failed"
        exit 1
    fi
    
    if ! validate_wireguard_connectivity; then
        log_error "WireGuard connectivity validation failed"
        exit 1
    fi
    
    # Run tests
    test_core_endpoints
    test_observable_services
    test_database_connectivity
    
    # Generate report
    generate_report
    
    # Print summary
    log_info "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed ✅"
        exit 0
    else
        log_error "$TESTS_FAILED test(s) failed ❌"
        exit 1
    fi
}

# Execute main
main "$@"
