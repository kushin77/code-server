#!/usr/bin/env bash
# @file        scripts/ops/diagnose-dast-404-error.sh
# @module      operations/security
# @description Diagnose DAST target 404 errors on ide.kushnir.cloud (P1 #1644)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || exit 1

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
REPO_PATH="/home/${EXEC_USER}/code-server-enterprise"
TARGET_URL="https://ide.kushnir.cloud/health"

# Check if Caddy is running
check_caddy_status() {
    local host="$1"
    
    log_info "Checking Caddy status on $host..."
    
    local caddy_status
    caddy_status=$(ssh "${host}" "docker ps --filter name=caddy --format '{{.Status}}' 2>/dev/null | head -1 || echo 'NOT_FOUND'" || echo "ERROR")
    
    log_info "Caddy status: $caddy_status"
    
    if [[ "$caddy_status" != "Up"* ]]; then
        log_error "✗ Caddy is not running or not healthy"
        return 1
    fi
    
    log_success "✓ Caddy is running"
    return 0
}

# Check Caddy logs for errors
check_caddy_logs() {
    local host="$1"
    
    log_info "Checking Caddy logs for recent errors..."
    
    local logs
    logs=$(ssh "${host}" "docker logs --tail 20 caddy 2>/dev/null || echo 'NO_LOGS'" || echo "ERROR")
    
    if [ "$logs" = "NO_LOGS" ] || [ "$logs" = "ERROR" ]; then
        log_warn "Could not retrieve Caddy logs"
        return 0
    fi
    
    log_info "Recent Caddy logs:"
    echo "$logs" | grep -i "error\|404\|ide.kushnir.cloud" || log_info "(no errors found in recent logs)"
}

# Check if oauth2-proxy is running
check_oauth2_proxy_status() {
    local host="$1"
    
    log_info "Checking oauth2-proxy status on $host..."
    
    local proxy_status
    proxy_status=$(ssh "${host}" "docker ps --filter name=oauth2-proxy --format '{{.Status}}' 2>/dev/null | head -1 || echo 'NOT_FOUND'" || echo "ERROR")
    
    log_info "oauth2-proxy status: $proxy_status"
    
    if [[ "$proxy_status" != "Up"* ]]; then
        log_error "✗ oauth2-proxy is not running or not healthy"
        return 1
    fi
    
    log_success "✓ oauth2-proxy is running"
    return 0
}

# Check oauth2-proxy health endpoint
check_oauth2_proxy_health() {
    local host="$1"
    
    log_info "Checking oauth2-proxy health endpoint (localhost:4180/ping)..."
    
    local health_status
    health_status=$(ssh "${host}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:4180/ping 2>/dev/null || echo 'ERROR'" || echo "ERROR")
    
    log_info "oauth2-proxy health response code: $health_status"
    
    if [ "$health_status" = "200" ]; then
        log_success "✓ oauth2-proxy is responding to health checks"
        return 0
    else
        log_error "✗ oauth2-proxy health check failed (code: $health_status)"
        return 1
    fi
}

# Check if code-server is running
check_code_server_status() {
    local host="$1"
    
    log_info "Checking code-server status on $host..."
    
    local server_status
    server_status=$(ssh "${host}" "docker ps --filter name=code-server --format '{{.Status}}' 2>/dev/null | head -1 || echo 'NOT_FOUND'" || echo "ERROR")
    
    log_info "code-server status: $server_status"
    
    if [[ "$server_status" != "Up"* ]]; then
        log_error "✗ code-server is not running or not healthy"
        return 1
    fi
    
    log_success "✓ code-server is running"
    return 0
}

# Check code-server internal endpoint
check_code_server_endpoint() {
    local host="$1"
    
    log_info "Checking code-server internal endpoint (localhost:8080/healthz)..."
    
    local endpoint_status
    endpoint_status=$(ssh "${host}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/healthz 2>/dev/null || echo 'ERROR'" || echo "ERROR")
    
    log_info "code-server endpoint response code: $endpoint_status"
    
    if [ "$endpoint_status" = "200" ]; then
        log_success "✓ code-server is responding on internal endpoint"
        return 0
    else
        log_error "✗ code-server internal endpoint failed (code: $endpoint_status)"
        return 1
    fi
}

# Test external DAST access (simulating DAST scanner)
test_dast_access() {
    local url="$1"
    
    log_info "Testing DAST access to $url (simulating DAST scanner)..."
    log_warn "Note: This will fail if DNS/certs not resolvable from this machine"
    
    local response
    response=$(curl -s -o /dev/null -w '%{http_code}' --insecure "$url" 2>/dev/null || echo "ERROR")
    
    log_info "External DAST response code: $response"
    
    if [ "$response" = "200" ] || [ "$response" = "302" ] || [ "$response" = "401" ]; then
        log_success "✓ Target is reachable (code: $response)"
        return 0
    elif [ "$response" = "404" ]; then
        log_error "✗ Target returned 404 Not Found"
        return 1
    else
        log_warn "Unexpected response code: $response (may be DNS/cert issue from this machine)"
        return 0
    fi
}

# Check docker-compose configuration
check_compose_config() {
    local host="$1"
    
    log_info "Checking docker-compose service configuration on $host..."
    
    local compose_config
    compose_config=$(ssh "${host}" "cd $REPO_PATH && docker-compose config 2>/dev/null | grep -A10 'oauth2-proxy:\|code-server:' | head -20 || echo 'ERROR'" || echo "ERROR")
    
    if [ "$compose_config" != "ERROR" ]; then
        log_info "Relevant services in docker-compose:"
        echo "$compose_config" | sed 's/^/  /'
    else
        log_warn "Could not retrieve docker-compose config"
    fi
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "DAST Target 404 Error Diagnostics (P1 #1644)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Target URL: $TARGET_URL"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected"
    log_info ""
    
    # Run all diagnostics
    log_info "DIAGNOSTIC CHECKS"
    log_info "=================="
    log_info ""
    
    check_caddy_status "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_caddy_logs "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_oauth2_proxy_status "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_oauth2_proxy_health "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_code_server_status "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_code_server_endpoint "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""
    
    check_compose_config "${EXEC_USER}@${PRIMARY_HOST}" || true
    log_info ""

    test_dast_access "$TARGET_URL" || true
    log_info ""
    
    log_success "========================================================================"
    log_success "Diagnostics complete!"
    log_success "========================================================================"
    log_info ""
    log_info "Summary:"
    log_info "  1. Caddy must be running and routing traffic"
    log_info "  2. oauth2-proxy must be responding on port 4180"
    log_info "  3. code-server must be responding on localhost:8080"
    log_info "  4. DAST scanner should probe /health, not the auth-gated root path"
    log_info ""
    log_info "If oauth2-proxy or code-server are down:"
    log_info "  ssh ${EXEC_USER}@${PRIMARY_HOST}"
    log_info "  cd $REPO_PATH"
    log_info "  docker-compose up -d oauth2-proxy code-server"
}

main "$@"
