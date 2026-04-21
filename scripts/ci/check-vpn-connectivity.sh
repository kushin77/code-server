#!/usr/bin/env bash
# @file        scripts/ci/check-vpn-connectivity.sh
# @module      ci/vpn-gating
# @description Check VPN connectivity status before running E2E tests
# @owner       qa-infra
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
readonly REQUIRE_VPN="${REQUIRE_VPN:-1}"
readonly VPN_CHECK_HOST="${VPN_CHECK_HOST:-192.168.168.31}"
readonly VPN_CHECK_TIMEOUT="${VPN_CHECK_TIMEOUT:-5}"
readonly VPN_CHECK_URL="${VPN_CHECK_URL:-https://ide.kushnir.cloud}"

# State
VPN_READY="false"
VPN_PING_SUCCESS="false"
VPN_HTTP_SUCCESS="false"
VPN_CHECK_REASON=""

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
# shellcheck disable=SC2034
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

check_vpn_via_ping() {
    log_info "Checking VPN via ICMP ping to $VPN_CHECK_HOST..."
    
    if ping -c 1 -W "$VPN_CHECK_TIMEOUT" "$VPN_CHECK_HOST" >/dev/null 2>&1; then
        log_info "✓ ICMP ping successful to $VPN_CHECK_HOST"
        VPN_PING_SUCCESS="true"
        return 0
    else
        log_warn "✗ ICMP ping failed to $VPN_CHECK_HOST (may be blocked, checking HTTP fallback)"
        return 1
    fi
}

check_vpn_via_http() {
    log_info "Checking VPN via HTTP/HTTPS to $VPN_CHECK_URL..."
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$VPN_CHECK_TIMEOUT" \
        --max-time "$((VPN_CHECK_TIMEOUT * 2))" \
        "$VPN_CHECK_URL" 2>/dev/null || echo "000")
    
    if [[ "$http_code" =~ ^(200|301|302|401|403)$ ]]; then
        log_info "✓ HTTP check successful (status: $http_code) to $VPN_CHECK_URL"
        VPN_HTTP_SUCCESS="true"
        return 0
    else
        log_warn "✗ HTTP check failed (status: $http_code) to $VPN_CHECK_URL"
        return 1
    fi
}

check_vpn_connectivity() {
    log_info "Starting VPN connectivity check..."
    log_info "Configuration:"
    log_info "  REQUIRE_VPN=$REQUIRE_VPN"
    log_info "  VPN_CHECK_HOST=$VPN_CHECK_HOST"
    log_info "  VPN_CHECK_TIMEOUT=$VPN_CHECK_TIMEOUT"
    log_info "  VPN_CHECK_URL=$VPN_CHECK_URL"
    
    # Try both ICMP ping and HTTP check
    check_vpn_via_ping || true
    check_vpn_via_http || true
    
    # Determine final status
    if [[ "$VPN_PING_SUCCESS" == "true" ]] || [[ "$VPN_HTTP_SUCCESS" == "true" ]]; then
        VPN_READY="true"
        VPN_CHECK_REASON="VPN is reachable"
        log_info "✓ VPN connectivity verified (ping=$VPN_PING_SUCCESS, http=$VPN_HTTP_SUCCESS)"
    else
        if [[ "$REQUIRE_VPN" == "1" ]]; then
            VPN_READY="false"
            VPN_CHECK_REASON="VPN is unreachable and REQUIRE_VPN=1"
            log_error "✗ VPN check FAILED and REQUIRE_VPN is enforced"
            log_error "  Cannot reach $VPN_CHECK_HOST (ping) or $VPN_CHECK_URL (HTTP)"
        else
            VPN_READY="true"
            VPN_CHECK_REASON="VPN unavailable but REQUIRE_VPN=0 (tests will run anyway)"
            log_warn "✗ VPN is unreachable but REQUIRE_VPN=0 - continuing without VPN"
        fi
    fi
}

output_github_actions_format() {
    # Output for GitHub Actions workflow
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "VPN_READY=$VPN_READY"
            echo "VPN_PING_SUCCESS=$VPN_PING_SUCCESS"
            echo "VPN_HTTP_SUCCESS=$VPN_HTTP_SUCCESS"
            echo "VPN_REASON=$VPN_CHECK_REASON"
        } >> "$GITHUB_OUTPUT"
        log_info "GitHub Actions outputs written to GITHUB_OUTPUT"
    fi
}

print_summary() {
    local status_color=$RED
    local status_symbol="✗"
    
    if [[ "$VPN_READY" == "true" ]]; then
        status_color=$GREEN
        status_symbol="✓"
    fi
    
    cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VPN CONNECTIVITY CHECK SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${status_color}${status_symbol} Status: $VPN_READY${NC}
  Reason: $VPN_CHECK_REASON
  
  ICMP Ping: $VPN_PING_SUCCESS
  HTTP Check: $VPN_HTTP_SUCCESS
  
  Target Host: $VPN_CHECK_HOST
  Target URL: $VPN_CHECK_URL
  
  Require VPN: $REQUIRE_VPN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

main() {
    log_info "VPN Connectivity Check Script"
    log_info "=========================================="
    
    check_vpn_connectivity
    output_github_actions_format
    print_summary
    
    if [[ "$VPN_READY" == "true" ]]; then
        log_info "VPN check PASSED - E2E tests can proceed"
        return 0
    else
        log_error "VPN check FAILED - E2E tests will be skipped or fail"
        return 1
    fi
}

main "$@"
