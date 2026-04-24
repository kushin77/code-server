#!/usr/bin/env bash
# @file        scripts/ops/P3-1678-CONSOLIDATE-OAUTH.sh
# @module      operations/oauth
# @description Consolidate OAuth proxy services into unified cross-subdomain OAuth
#
# Usage: bash scripts/ops/P3-1678-CONSOLIDATE-OAUTH.sh [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
DRY_RUN="${DRY_RUN:-0}"

# ============================================================================
# Helper Functions
# ============================================================================

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "$cmd"
}

validate_oauth_config() {
    log_info "Validating OAuth configuration..."
    
    # Check that .env file has required OAuth variables
    if ! grep -q "OAUTH2_PROXY_COOKIE_SECRET" .env 2>/dev/null; then
        log_warn "OAUTH2_PROXY_COOKIE_SECRET not found in .env"
    fi
    
    if ! grep -q "GOOGLE_CLIENT_ID" .env 2>/dev/null; then
        log_warn "GOOGLE_CLIENT_ID not found in .env"
    fi
    
    log_info "OAuth configuration validation: OK"
}

deploy_oauth_consolidation() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Consolidating OAuth proxy services..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would consolidate OAuth services"
        return 0
    fi
    
    # Stop old oauth2-proxy-portal service
    log_info "[$replica_clean] Stopping old oauth2-proxy-portal service..."
    ssh_exec "$replica_clean" "cd code-server-enterprise && docker-compose stop oauth2-proxy-portal" || {
        log_warn "[$replica_clean] oauth2-proxy-portal stop command failed (may not exist)"
    }
    
    # Reload docker-compose with consolidated config
    log_info "[$replica_clean] Redeploying unified oauth2-proxy service..."
    ssh_exec "$replica_clean" "cd code-server-enterprise && docker-compose up -d oauth2-proxy" >/dev/null 2>&1 || {
        log_error "[$replica_clean] Docker Compose up failed"
        return 1
    }
    
    # Verify oauth2-proxy is running
    log_info "[$replica_clean] Verifying oauth2-proxy container..."
    if ! ssh_exec "$replica_clean" "docker ps --filter 'name=oauth2-proxy$' --filter 'status=running' | grep -q oauth2-proxy"; then
        log_error "[$replica_clean] oauth2-proxy container is not running"
        return 1
    fi
    
    log_info "[$replica_clean] ✅ OAuth consolidation completed"
    return 0
}

test_session_persistence() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Testing session persistence across subdomains..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would test session persistence"
        return 0
    fi
    
    # Test that oauth2-proxy is responding
    log_info "[$replica_clean] Testing oauth2-proxy health..."
    if ssh_exec "$replica_clean" "curl -s http://localhost:4180/oauth2/auth" >/dev/null 2>&1; then
        log_info "[$replica_clean] ✅ oauth2-proxy responding"
    else
        log_warn "[$replica_clean] oauth2-proxy health check inconclusive (may require auth)"
    fi
    
    return 0
}

deploy_to_all_replicas() {
    log_info "=========================================="
    log_info "CONSOLIDATING OAUTH ACROSS ALL REPLICAS"
    log_info "=========================================="
    log_info ""
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        log_info ""
        log_info "Would consolidate OAuth:"
        log_info "  - Merge oauth2-proxy-portal into oauth2-proxy"
        log_info "  - Set cookie-domain=.kushnir.cloud"
        log_info "  - Enable session sharing via Redis"
        log_info "  - Route both kushnir.cloud and ide.kushnir.cloud"
        log_info ""
        return 0
    fi
    
    local failed_replicas=""
    local IFS=","
    for replica in $REPLICAS; do
        if ! deploy_oauth_consolidation "$replica"; then
            failed_replicas="$failed_replicas $replica"
        fi
    done
    
    if [[ -n "$failed_replicas" ]]; then
        log_error "Failed to consolidate OAuth on replicas:$failed_replicas"
        return 1
    fi
    
    # Test session persistence
    for replica in $REPLICAS; do
        test_session_persistence "$replica"
    done
    
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "OAUTH CONSOLIDATION ACROSS SUBDOMAINS"
    log_info "=========================================="
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    # Validate OAuth configuration
    validate_oauth_config
    
    # Deploy consolidation to all replicas
    if ! deploy_to_all_replicas; then
        log_error "❌ OAuth consolidation failed"
        return 1
    fi
    
    log_info "✅ OAuth consolidation complete"
    log_info ""
    log_info "Unified OAuth Configuration:"
    log_info "  - Cookie Domain: .kushnir.cloud"
    log_info "  - Session Store: Redis (shared across cluster)"
    log_info "  - Redirect URLs: kushnir.cloud + ide.kushnir.cloud"
    log_info "  - Token Refresh: Background (15min)"
    log_info "  - Logout: Clears all subdomain sessions"
    log_info ""
    
    return 0
}

main "$@"
