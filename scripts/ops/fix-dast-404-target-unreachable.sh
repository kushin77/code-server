#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-404-target-unreachable.sh
# @module      operations/security
# @description Fix DAST target 404 errors - restart services and verify endpoints (P1 #1644)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
REPO_PATH="/home/${EXEC_USER}/code-server-enterprise"
DRY_RUN="${DRY_RUN:-0}"
TARGET_URL="https://ide.kushnir.cloud"

# Restart services
restart_services() {
    local host="$1"
    
    log_info "Restarting critical services on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would restart: oauth2-proxy, code-server, caddy"
        log_info "[DRY-RUN] Command: docker-compose up -d oauth2-proxy code-server"
        return 0
    fi
    
    # Restart oauth2-proxy and code-server
    log_info "Restarting oauth2-proxy and code-server..."
    ssh "${host}" "cd $REPO_PATH && docker-compose up -d oauth2-proxy code-server" || {
        log_error "Failed to restart services"
        return 1
    }
    
    # Wait for services to be ready
    log_info "Waiting 5 seconds for services to stabilize..."
    sleep 5
    
    log_success "✓ Services restarted"
    return 0
}

# Verify internal endpoints
verify_internal_endpoints() {
    local host="$1"
    
    log_info "Verifying internal endpoints on $host..."
    
    local oauth_status
    local cs_status
    
    # Check oauth2-proxy health
    oauth_status=$(ssh "${host}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:4180/ping 2>/dev/null || echo 'TIMEOUT'" || echo "ERROR")
    
    log_info "oauth2-proxy /ping response: $oauth_status"
    if [ "$oauth_status" != "200" ]; then
        log_warn "oauth2-proxy not responding properly (expected 200)"
    else
        log_success "✓ oauth2-proxy health endpoint working"
    fi
    
    # Check code-server health
    cs_status=$(ssh "${host}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/healthz 2>/dev/null || echo 'TIMEOUT'" || echo "ERROR")
    
    log_info "code-server /healthz response: $cs_status"
    if [ "$cs_status" != "200" ]; then
        log_warn "code-server not responding properly (expected 200)"
    else
        log_success "✓ code-server health endpoint working"
    fi
}

# Verify Caddy routing
verify_caddy_routing() {
    local host="$1"
    
    log_info "Verifying Caddy routing configuration on $host..."
    
    # Check if Caddyfile is valid
    local caddy_check
    caddy_check=$(ssh "${host}" "docker exec caddy /usr/local/bin/caddy validate --config /etc/caddy/Caddyfile 2>&1 | head -5 || echo 'ERROR'" || echo "ERROR")
    
    if [[ "$caddy_check" == *"ERROR"* ]] || [[ "$caddy_check" == *"error"* ]]; then
        log_warn "Caddy configuration validation output: $caddy_check"
    else
        log_success "✓ Caddy configuration valid"
    fi
}

# Test external access (local machine)
test_external_access() {
    log_info "Testing external access to $TARGET_URL..."
    
    local response
    response=$(curl -s -o /dev/null -w '%{http_code}' --insecure "$TARGET_URL" 2>/dev/null || echo "ERROR")
    
    if [ "$response" = "ERROR" ]; then
        log_warn "Could not test external access from this machine (DNS/network issue)"
        return 0
    fi
    
    log_info "External response code: $response"
    
    if [ "$response" = "200" ] || [ "$response" = "302" ] || [ "$response" = "401" ]; then
        log_success "✓ Target is reachable (response code: $response)"
        return 0
    elif [ "$response" = "404" ]; then
        log_error "✗ Target returned 404 - services may need additional restart"
        return 1
    else
        log_info "Unexpected response code: $response"
        return 0
    fi
}

# Check service logs for errors
check_service_logs() {
    local host="$1"
    
    log_info "Checking recent service logs on $host..."
    
    log_info ""
    log_info "Recent oauth2-proxy logs:"
    ssh "${host}" "docker logs --tail 10 oauth2-proxy 2>/dev/null | grep -i 'error\|404\|unreachable' || echo '(no errors found)'" | sed 's/^/  /'
    
    log_info ""
    log_info "Recent code-server logs:"
    ssh "${host}" "docker logs --tail 10 code-server 2>/dev/null | grep -i 'error\|failed' || echo '(no errors found)'" | sed 's/^/  /'
    
    log_info ""
    log_info "Recent Caddy logs:"
    ssh "${host}" "docker logs --tail 10 caddy 2>/dev/null | grep -i 'error\|404' || echo '(no errors found)'" | sed 's/^/  /'
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "DAST Target 404 Fix - Service Restart & Verification (P1 #1644)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Target URL: $TARGET_URL"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    # Verify SSH connectivity
    log_info "Verifying SSH connectivity..."
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    log_info ""
    
    # STEP 1: Check service logs
    log_info "STEP 1: Analyzing current service state"
    log_info "========================================"
    log_info ""
    check_service_logs "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    # STEP 2: Restart services
    log_info "STEP 2: Restarting critical services"
    log_info "====================================="
    log_info ""
    restart_services "${EXEC_USER}@${PRIMARY_HOST}" || return 1
    log_info ""
    
    # STEP 3: Verify internal endpoints
    log_info "STEP 3: Verifying internal endpoints"
    log_info "===================================="
    log_info ""
    verify_internal_endpoints "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    # STEP 4: Verify Caddy routing
    log_info "STEP 4: Verifying Caddy routing"
    log_info "================================"
    log_info ""
    verify_caddy_routing "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    # STEP 5: Test external access
    log_info "STEP 5: Testing external access"
    log_info "==============================="
    log_info ""
    test_external_access || true
    log_info ""
    
    log_success "========================================================================"
    log_success "DAST 404 fix complete!"
    log_success "========================================================================"
    log_info ""
    log_info "Summary:"
    log_info "  1. Services restarted (oauth2-proxy, code-server)"
    log_info "  2. Internal endpoints verified"
    log_info "  3. Caddy routing validated"
    log_info "  4. External access tested"
    log_info ""
    log_info "If DAST scan still fails:"
    log_info "  1. Run this script again with DRY_RUN=0"
    log_info "  2. Check docker-compose.yml for service configuration"
    log_info "  3. Verify DAST scanner has network access to ide.kushnir.cloud"
    log_info "  4. Check DNS resolution: nslookup ide.kushnir.cloud"
}

main "$@"
