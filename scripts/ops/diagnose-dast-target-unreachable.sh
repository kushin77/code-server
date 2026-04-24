#!/usr/bin/env bash
# @file        scripts/ops/diagnose-dast-target-unreachable.sh
# @module      infrastructure/dast
# @description Diagnose why DAST scanner cannot reach IDE endpoint (Issue #1644)
#
# When DAST scan reports "target unreachable" (404 or connection error) on ide.kushnir.cloud,
# this script helps diagnose the root cause by testing the full request chain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
IDE_HOST="${IDE_DOMAIN:-ide.kushnir.cloud}"
IDE_URL="https://${IDE_HOST}"
TEST_PATH="/health"
REPLICA_1="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_2="${STANDBY_HOST:-192.168.168.42}"

log_info "DAST Target Unreachable Diagnostics"
log_info "===================================="
log_info "Issue: #1644"
log_info "Target: $IDE_URL$TEST_PATH"
echo ""

# Test 1: DNS resolution
log_info "TEST 1: DNS Resolution"
{
    if result=$(getent hosts "$IDE_HOST" 2>&1); then
        log_success "✓ DNS resolves: $result"
    else
        log_error "✗ DNS resolution failed for $IDE_HOST"
        log_info "Tip: Check if DNS is configured correctly or loadbalancer is responding on expected IP"
    fi
}
echo ""

# Test 2: Network connectivity
log_info "TEST 2: Network Connectivity (HTTPS on port 443)"
{
    if timeout 5 bash -c "exec 3<>/dev/tcp/${IDE_HOST}/443" 2>/dev/null; then
        log_success "✓ Can connect to ${IDE_HOST}:443"
    else
        log_error "✗ Cannot connect to ${IDE_HOST}:443"
        log_info "Tip: Check if the host is reachable or firewall is blocking port 443"
    fi
}
echo ""

# Test 3: TLS handshake
log_info "TEST 3: TLS Certificate Handshake"
{
    if result=$(echo | openssl s_client -connect "${IDE_HOST}:443" -servername "${IDE_HOST}" 2>&1 | grep -E "(Verify return code|depth=|subject=)" | head -5); then
        log_success "✓ TLS handshake successful:"
        echo "$result" | sed 's/^/  /'
    else
        log_error "✗ TLS handshake failed"
        log_info "Tip: Check if certificate is valid or has expired"
    fi
}
echo ""

# Test 4: HTTP request to root path
log_info "TEST 4: HTTP GET Request to $IDE_URL$TEST_PATH"
{
    response=$(curl -s -w "\n%{http_code}" -m 10 --insecure "$IDE_URL$TEST_PATH" 2>&1 | tail -2)
    http_code=$(echo "$response" | tail -1)
    http_body=$(echo "$response" | head -1)
    
    case "$http_code" in
        200|302|401)
            log_success "✓ HTTP $http_code received (healthy)"
            [ -n "$http_body" ] && echo "  Body: ${http_body:0:100}..."
            ;;
        404)
            log_error "✗ HTTP 404 - Path not found"
            log_info "Tip: Check if Caddy is serving the correct route or health endpoint is disabled"
            ;;
        502|503)
            log_error "✗ HTTP $http_code - Gateway/Service Unavailable"
            log_info "Tip: Check if oauth2-proxy or code-server backend is running"
            ;;
        *)
            log_error "✗ Unexpected HTTP $http_code"
            ;;
    esac
}
echo ""

# Test 5: Check if Caddy is running on replicas (if accessible)
log_info "TEST 5: Remote Replica Service Check (requires passwordless sudo)"
{
    for replica in "$REPLICA_1" "$REPLICA_2"; do
        log_info "Checking $replica..."
        
        if ssh "${DEPLOY_USER:-akushnir}@${replica}" "cd code-server-enterprise && docker-compose ps caddy" 2>/dev/null | grep -q "Up"; then
            log_success "  ✓ Caddy is running on $replica"
        else
            log_warn "  ⚠ Could not verify Caddy status on $replica (check connectivity or passwordless sudo)"
        fi
    done
}
echo ""

# Test 6: Check oauth2-proxy health
log_info "TEST 6: OAuth2-Proxy Health (local only)"
{
    if timeout 5 curl -s -f "http://localhost:4180/ping" >/dev/null 2>&1; then
        log_success "✓ OAuth2-proxy is responding to health checks"
    else
        log_warn "⚠ Could not reach oauth2-proxy on localhost:4180"
        log_info "Tip: If running in CI, this is expected (docker containers not running)"
    fi
}
echo ""

# Summary
log_info "DIAGNOSIS SUMMARY"
log_info "================="
log_info "If Test 3 (TLS) and Test 4 (HTTP) both fail:"
log_info "  → Issue is likely loadbalancer/Caddy not running or TLS cert expired"
log_info ""
log_info "If Test 4 returns 404:"
log_info "  → Caddy is running but health endpoint is missing or disabled"
log_info "  → Check Caddyfile for 'respond @health' configuration"
log_info ""
log_info "If Test 4 returns 502/503:"
log_info "  → Caddy is running but reverse proxy target is unavailable"
log_info "  → Check if oauth2-proxy or code-server is running on the replica"
log_info ""
log_info "REMEDIATION:"
log_info "  1. SSH to replica: ssh akushnir@${REPLICA_2}"
log_info "  2. Check Caddy container: docker-compose ps caddy"
log_info "  3. View Caddy logs: docker-compose logs --tail 50 caddy"
log_info "  4. Restart if needed: docker-compose restart caddy"
log_info "  5. Test health: curl -k https://ide.kushnir.cloud/health"
echo ""
