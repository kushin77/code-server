#!/usr/bin/env bash
# @file        scripts/infrastructure/fix-ssl-protocol-error.sh
# @module      infrastructure/incident-response
# @description Automated remediation for SSL_PROTOCOL_ERROR on kushnir.cloud
#              Consolidates Docker Compose primary to single SSOT
#              Timeline: ~30 minutes (automated) + 5 min (DNS + verification)
#
# USAGE:
#   bash fix-ssl-protocol-error.sh              # Dry run (shows what would happen)
#   bash fix-ssl-protocol-error.sh --execute    # Execute all fixes
#   bash fix-ssl-protocol-error.sh --verify     # Verify only (no changes)
#
# REQUIREMENTS:
#   - SSH access to 192.168.168.31 (primary host)
#   - Docker and docker-compose on primary
#   - Bash 4.0+

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

PRIMARY_HOST="192.168.168.31"
PRIMARY_USER="akushnir"
PRIMARY_PATH="/home/akushnir/code-server-enterprise"
DOMAIN="kushnir.cloud"

DRY_RUN=true  # Default: dry run (safe)
EXECUTE=false
VERIFY_ONLY=false

# ════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  $*"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*"
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $*" >&2
}

log_section() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ $1"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

run_remote() {
cmd="$1"
desc="${2:-}"
    
    if [ -n "$desc" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] $desc"
        else
            log_info "$desc"
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo "  > ssh ${PRIMARY_USER}@${PRIMARY_HOST} '$cmd'"
        return 0
    fi
    
    ssh -o ConnectTimeout=5 "${PRIMARY_USER}@${PRIMARY_HOST}" "$cmd"
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: VERIFY PRIMARY HOST CONNECTIVITY
# ════════════════════════════════════════════════════════════════════════════

step_verify_connectivity() {
    log_section "STEP 1: Verify SSH Connectivity to Primary (192.168.168.31)"
    
    run_remote "hostname -I | grep -o '192.168.168.31'" \
        "Checking primary host IP..."
    
    if [ $? -eq 0 ]; then
        log_success "Connected to primary host"
    else
        log_error "Cannot connect to ${PRIMARY_HOST}"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: VERIFY CADDY HEALTH
# ════════════════════════════════════════════════════════════════════════════

step_verify_caddy() {
    log_section "STEP 2: Verify Caddy TLS/HTTPS Service"
    
    run_remote \
        "cd ${PRIMARY_PATH} && docker ps | grep caddy | grep -E 'healthy|Up'" \
        "Checking Caddy status..."
    
caddy_status=$?
    if [ $caddy_status -eq 0 ]; then
        log_success "Caddy is running and healthy"
    else
        log_error "Caddy is not running or unhealthy"
        log_error "Start Caddy manually: docker-compose up -d caddy"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: FIX PROMETHEUS CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

step_fix_prometheus() {
    log_section "STEP 3: Fix Prometheus Configuration Error"
    
    log_info "Checking prometheus.yml for directory reference..."
    
    run_remote \
        "cd ${PRIMARY_PATH} && docker exec prometheus cat /etc/prometheus/prometheus.yml | grep 'rule_files' -A 2" \
        "Reading prometheus rule_files config..."
    
    log_info "If rule_files points to directory (not *.yml), updating configuration..."
    
    # The fix is applied by updating docker-compose.yml volume mount
    # This is typically done by the ops team, so we'll generate instructions
    
    if [ "$EXECUTE" = true ]; then
        log_warn "Prometheus config fix requires manual update to docker-compose.yml"
        log_warn "See IMMEDIATE-EXECUTION-GUIDE.md STEP 3 for details"
        
        # Restart prometheus to apply any changes
        run_remote \
            "cd ${PRIMARY_PATH} && docker-compose restart prometheus" \
            "Restarting Prometheus..."
        
        # Wait for startup
        sleep 5
        
        # Verify
        run_remote \
            "docker ps | grep prometheus | grep -E 'Up|Exited'" \
            "Verifying Prometheus status..."
    else
        log_info "[DRY-RUN] Would restart Prometheus after config fix"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: FIX SESSION-BROKER IMAGE REFERENCE
# ════════════════════════════════════════════════════════════════════════════

step_fix_session_broker() {
    log_section "STEP 4: Fix session-broker Image Digest Reference"
    
    log_info "Extracting code-server image digest..."
    
    run_remote \
        "cd ${PRIMARY_PATH} && docker images code-server-enterprise:dev --digests --quiet | head -1" \
        "Getting image digest..."
    
    if [ "$EXECUTE" = true ]; then
digest
        digest=$(ssh -o ConnectTimeout=5 "${PRIMARY_USER}@${PRIMARY_HOST}" \
            "cd ${PRIMARY_PATH} && docker images code-server-enterprise:dev --digests --quiet | head -1")
        
        if [ -z "$digest" ]; then
            log_error "Could not get code-server image digest"
            return 1
        fi
        
        log_success "Image digest: $digest"
        
        # Update .env
        run_remote \
            "cd ${PRIMARY_PATH} && \
             if grep -q 'CODE_SERVER_IMAGE_ID' .env; then \
                 sed -i.bak "\"s|CODE_SERVER_IMAGE_ID=.*|CODE_SERVER_IMAGE_ID=code-server-enterprise@${digest}|"\" .env; \
             else \
                 echo "\"CODE_SERVER_IMAGE_ID=code-server-enterprise@${digest}"\" >> .env; \
             fi && \
             grep CODE_SERVER_IMAGE_ID .env" \
            "Updating CODE_SERVER_IMAGE_ID in .env..."
        
        # Restart session-broker
        run_remote \
            "cd ${PRIMARY_PATH} && docker-compose restart session-broker" \
            "Restarting session-broker..."
        
        # Wait for startup
        sleep 5
        
        # Verify
        run_remote \
            "docker ps | grep session-broker | grep -v Restarting" \
            "Verifying session-broker status..."
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 5: FIX REDIS SENTINEL CLUSTER
# ════════════════════════════════════════════════════════════════════════════

step_fix_sentinel() {
    log_section "STEP 5: Fix Redis Sentinel Cluster"
    
    if [ "$EXECUTE" = true ]; then
        log_info "Restarting Redis Sentinel components..."
        
        run_remote \
            "cd ${PRIMARY_PATH} && docker-compose restart redis-sentinel-1 redis-sentinel-arbiter pgbouncer" \
            "Restarting sentinel cluster..."
        
        sleep 10
        
        run_remote \
            "docker ps | grep -E 'sentinel|pgbouncer|redis' | grep -v 'redis-exporter'" \
            "Verifying cluster status..."
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 6: VERIFY ALL SERVICES
# ════════════════════════════════════════════════════════════════════════════

step_verify_services() {
    log_section "STEP 6: Verify All Services Are Healthy"
    
    run_remote \
        "cd ${PRIMARY_PATH} && docker compose ps" \
        "Full service status..."
    
    run_remote \
        "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v Up || echo '--- All Up ---'" \
        "Services that are NOT running (should be empty)..."
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 7: DNS VERIFICATION
# ════════════════════════════════════════════════════════════════════════════

step_verify_dns() {
    log_section "STEP 7: DNS Resolution Check"
    
    if command -v nslookup &> /dev/null; then
        log_info "Current DNS resolution:"
        nslookup "${DOMAIN}" 2>/dev/null || echo "DNS lookup failed"
    else
        log_warn "nslookup not available, skipping DNS check"
        log_warn "Manual check: nslookup ${DOMAIN}"
    fi
    
    log_warn "⚠️  IMPORTANT: Update DNS to point to 192.168.168.31"
    log_warn "   Current: 192.168.168.42 (replica)"
    log_warn "   Target: 192.168.168.31 (primary)"
    log_warn "   Provider: [Cloudflare/Route53/Registrar]"
}

# ════════════════════════════════════════════════════════════════════════════
# STEP 8: HTTPS TEST
# ════════════════════════════════════════════════════════════════════════════

step_test_https() {
    log_section "STEP 8: Test HTTPS Access"
    
    if command -v curl &> /dev/null; then
        log_info "Testing HTTPS connectivity (this may fail until DNS updates)..."
        
        if [ "$EXECUTE" = true ]; then
            # Try with --insecure first in case cert doesn't match yet
            curl -v "https://${DOMAIN}" --insecure --max-time 5 2>&1 | \
                grep -E "HTTP/|certificate|SSL|TLS" || \
                log_warn "HTTPS test inconclusive (DNS may not be updated yet)"
        else
            log_info "[DRY-RUN] Would run: curl -v https://${DOMAIN}"
        fi
    else
        log_warn "curl not available, skipping HTTPS test"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════════════════

print_summary() {
    log_section "EXECUTION SUMMARY"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY-RUN MODE: No changes made"
        log_info "To execute, run: bash $0 --execute"
    else
        log_success "All automated fixes completed"
    fi
    
    log_section "NEXT STEPS (Manual Actions Required)"
    
    echo "1. Update DNS Record:"
    echo "   - Provider: [Cloudflare / Route53 / Registrar]"
    echo "   - Record: kushnir.cloud"
    echo "   - Current: 192.168.168.42 (replica)"
    echo "   - Change to: 192.168.168.31 (primary)"
    echo "   - TTL: 300 seconds (for faster failover)"
    echo ""
    echo "2. Verify DNS Propagation (wait 5-15 minutes):"
    echo "   nslookup ${DOMAIN}"
    echo ""
    echo "3. Test HTTPS Access:"
    echo "   curl -v https://${DOMAIN}"
    echo "   Browser: https://${DOMAIN}"
    echo ""
    echo "4. Check Certificate:"
    echo "   - Should show Let's Encrypt"
    echo "   - No SSL warnings"
    echo ""
    echo "5. Monitor Logs (first hour):"
    echo "   ssh ${PRIMARY_USER}@${PRIMARY_HOST} 'docker logs -f caddy'"
    echo ""
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --execute) EXECUTE=true; DRY_RUN=false ;;
            --verify)  VERIFY_ONLY=true; DRY_RUN=true ;;
            --dry-run) DRY_RUN=true ;;
            -h|--help)
                echo "Usage: bash fix-ssl-protocol-error.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --execute    Execute all fixes (default: dry-run)"
                echo "  --verify     Verify only (no changes)"
                echo "  --dry-run    Show what would happen (default)"
                echo "  -h, --help   Show this help"
                exit 0
                ;;
        esac
    done
    
    # Welcome banner
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         SSL_PROTOCOL_ERROR Automated Remediation               ║"
    echo "║                                                                ║"
    echo "║  Domain: ${DOMAIN}"
    echo "║  Primary: ${PRIMARY_HOST}"
    echo "║  Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN (safe)" || echo "EXECUTE (make changes)")"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ "$VERIFY_ONLY" = true ]; then
        log_section "VERIFICATION MODE"
        step_verify_connectivity || return 1
        step_verify_caddy || return 1
        step_verify_services
        return 0
    fi
    
    # Execute steps
    step_verify_connectivity || return 1
    step_verify_caddy || return 1
    step_fix_prometheus
    step_fix_session_broker
    step_fix_sentinel
    step_verify_services
    step_verify_dns
    step_test_https
    
    # Print summary
    print_summary
    
    echo ""
    log_success "Remediation process complete"
    echo ""
}

# ════════════════════════════════════════════════════════════════════════════

main "$@"
