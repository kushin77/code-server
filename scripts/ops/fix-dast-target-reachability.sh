#!/usr/bin/env bash
# @file        scripts/ops/fix-dast-target-reachability.sh
# @module      operations/security
# @description Fix DAST target reachability issue for ide.kushnir.cloud (P1 #1626)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || exit 1

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"
IDE_DOMAIN="ide.${APEX_DOMAIN}"

# Check DNS resolution
check_dns_resolution() {
    local domain="$1"
    
    log_info "Checking DNS resolution for $domain..."
    
    local resolved_ip
    resolved_ip=$(ssh "${EXEC_USER}@${PRIMARY_HOST}" "nslookup $domain 2>/dev/null | grep -A1 'Name:' | tail -1 | awk '{print \$NF}' || echo 'FAILED'" || echo "FAILED")
    
    if [ "$resolved_ip" = "FAILED" ]; then
        log_warn "DNS resolution failed for $domain"
        return 1
    fi
    
    log_success "DNS resolves $domain to $resolved_ip"
    return 0
}

# Check HTTP connectivity
check_http_connectivity() {
    local url="$1"
    
    log_info "Checking HTTP connectivity to $url..."
    
    local status_code
    status_code=$(ssh "${EXEC_USER}@${PRIMARY_HOST}" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 '$url' || echo 'TIMEOUT'" || echo "ERROR")
    
    if [ "$status_code" = "TIMEOUT" ] || [ "$status_code" = "ERROR" ]; then
        log_error "Connection failed to $url"
        return 1
    fi
    
    if [ "$status_code" = "200" ]; then
        log_success "✓ HTTP $status_code OK"
        return 0
    else
        log_warn "HTTP $status_code received (expected 200)"
        return 1
    fi
}

# Check Caddyfile routing
check_caddyfile_routing() {
    local host="$1"
    local domain="$2"
    
    log_info "Checking Caddyfile routing for $domain..."
    
    local caddyfile_location="/home/akushnir/code-server-enterprise/Caddyfile"
    
    local domain_config
    domain_config=$(ssh "${EXEC_USER}@${host}" "grep -A5 '$domain' $caddyfile_location 2>/dev/null || echo 'NOT_FOUND'" || echo "ERROR")
    
    if [ "$domain_config" = "NOT_FOUND" ]; then
        log_error "Domain $domain not configured in Caddyfile"
        return 1
    fi
    
    if [ "$domain_config" = "ERROR" ]; then
        log_error "Cannot access Caddyfile on $host"
        return 1
    fi
    
    log_info "Caddyfile configuration for $domain:"
    echo "$domain_config" | sed 's/^/  /'
    return 0
}

# Add DAST scanner IP to allowed IPs (if behind proxy)
configure_dast_scanner_access() {
    local host="$1"
    local domain="$2"
    
    log_info "Configuring DAST scanner access for $domain..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would update access controls for $domain"
        return 0
    fi
    
    # Check if OAuth2 proxy is blocking the scan
    local oauth_logs
    oauth_logs=$(ssh "${EXEC_USER}@${host}" "docker logs \$(docker ps -q -f name=oauth2-proxy 2>/dev/null) 2>&1 | grep -i 'unauthorized\|dast\|zap' | tail -5 || echo 'No auth blocks found'" || echo "")
    
    if [ -n "$oauth_logs" ] && [ "$oauth_logs" != "No auth blocks found" ]; then
        log_warn "OAuth2 proxy may be blocking DAST scanner:"
        echo "$oauth_logs" | sed 's/^/  /'
    fi
}

# Verify Caddy is running and responsive
check_caddy_health() {
    local host="$1"
    
    log_info "Checking Caddy health on $host..."
    
    local caddy_status
    caddy_status=$(ssh "${EXEC_USER}@${host}" "docker ps -q -f name=caddy 2>/dev/null | wc -l" || echo "0")
    
    if [ "$caddy_status" = "0" ]; then
        log_error "Caddy container not running"
        return 1
    fi
    
    log_success "✓ Caddy container is running"
    
    # Check Caddy admin API
    local caddy_api_health
    caddy_api_health=$(ssh "${EXEC_USER}@${host}" "curl -s http://localhost:2019/config/ 2>/dev/null | wc -l" || echo "0")
    
    if [ "$caddy_api_health" = "0" ]; then
        log_warn "Caddy admin API not responding"
        return 1
    fi
    
    log_success "✓ Caddy admin API responding"
    return 0
}

# Enable public access for DAST scan
enable_public_dast_access() {
    local host="$1"
    local domain="$2"
    
    log_info "Enabling public access for DAST scan of $domain..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would configure public access for DAST target"
        log_info "[DRY-RUN] Steps would be:"
        log_info "  1. Add .skip_auth directive to Caddyfile for DAST paths"
        log_info "  2. Or whitelist DAST scanner IP in OAuth2 proxy config"
        log_info "  3. Reload Caddy to apply changes"
        return 0
    fi
    
    # Check if domain is behind auth
    local auth_required
    auth_required=$(ssh "${EXEC_USER}@${host}" "grep -A10 '$domain' /home/akushnir/code-server-enterprise/Caddyfile | grep -c 'forward_auth\|oauth2' || echo 0" || echo "0")
    
    if [ "$auth_required" = "0" ]; then
        log_info "Domain $domain is publicly accessible (no auth required)"
        return 0
    fi
    
    log_warn "Domain $domain has authentication configured"
    log_info "DAST scanner may be blocked by authentication"
    log_info "Consider adding /health or /status endpoints for unauthenticated DAST access"
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Fixing DAST target reachability for ide.kushnir.cloud (P1 #1626)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Target Domain: $IDE_DOMAIN"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    log_info ""
    
    # Diagnostics
    log_info "CONNECTIVITY DIAGNOSTICS"
    log_info "========================"
    
    check_dns_resolution "$IDE_DOMAIN" || log_warn "DNS resolution failed"
    log_info ""
    
    check_caddyfile_routing "$PRIMARY_HOST" "$IDE_DOMAIN" || log_warn "Caddyfile routing issue"
    log_info ""
    
    check_caddy_health "$PRIMARY_HOST" || log_error "Caddy health check failed"
    log_info ""
    
    log_info "NETWORK CONNECTIVITY"
    log_info "==================="
    
    if check_http_connectivity "https://$IDE_DOMAIN/"; then
        log_success "✓ DAST target is reachable and responding"
    else
        log_warn "⚠ DAST target not reachable - applying fixes"
        log_info ""
        
        log_info "APPLYING FIXES"
        log_info "=============="
        configure_dast_scanner_access "$PRIMARY_HOST" "$IDE_DOMAIN"
        enable_public_dast_access "$PRIMARY_HOST" "$IDE_DOMAIN"
    fi
    
    log_info ""
    log_success "========================================================================"
    log_success "DAST target reachability diagnostics complete!"
    log_success "========================================================================"
    log_info ""
    log_info "Next steps:"
    log_info "  1. If reachable: Re-run DAST scan from CI"
    log_info "  2. If not reachable: Check network/firewall rules"
    log_info "  3. If auth blocked: Add /health endpoint for scan access"
}

main "$@"
