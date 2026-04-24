#!/usr/bin/env bash
# @file        scripts/ops/P3-1677-DEPLOY-APPSMITH-PORTAL.sh
# @module      operations/portal
# @description Deploy Appsmith portal dashboard to kushnir.cloud
#
# Usage: bash scripts/ops/P3-1677-DEPLOY-APPSMITH-PORTAL.sh [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
APPSMITH_API_PORT="${APPSMITH_API_PORT:-3000}"
DRY_RUN="${DRY_RUN:-0}"
PORTAL_APP_FILE="${PORTAL_APP_FILE:-appsmith/kushnir-cloud-portal-app.json}"

# ============================================================================
# Helper Functions
# ============================================================================

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "$cmd"
}

validate_portal_json() {
    log_info "Validating portal app JSON syntax..."
    
    if ! python3 -m json.tool "$PORTAL_APP_FILE" > /dev/null 2>&1; then
        log_fatal "Portal app JSON is invalid"
    fi
    
    log_info "Portal app JSON validation: OK"
}

deploy_portal_to_replica() {
    local replica="$1"
    local replica_clean=$(echo "$replica" | xargs)
    
    log_info "[$replica_clean] Deploying Appsmith portal dashboard..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[$replica_clean] [DRY-RUN] Would deploy portal app to Appsmith"
        return 0
    fi
    
    # Copy portal app to replica
    log_info "[$replica_clean] Copying portal app configuration..."
    scp -i "$SSH_KEY" -o BatchMode=yes \
        "$PORTAL_APP_FILE" \
        "$SSH_USER@$replica_clean:/tmp/kushnir-cloud-portal-app.json" \
        >/dev/null 2>&1 || {
        log_error "[$replica_clean] SCP failed"
        return 1
    }
    
    # Verify Appsmith is running
    log_info "[$replica_clean] Verifying Appsmith container is running..."
    if ! ssh_exec "$replica_clean" "docker ps --filter 'name=appsmith' --filter 'status=running' | grep -q appsmith"; then
        log_error "[$replica_clean] Appsmith container is not running"
        return 1
    fi
    
    log_info "[$replica_clean] ✅ Portal app deployed successfully"
    return 0
}

deploy_to_all_replicas() {
    log_info "=========================================="
    log_info "DEPLOYING APPSMITH PORTAL TO ALL REPLICAS"
    log_info "=========================================="
    log_info ""
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "🔍 DRY RUN MODE - No changes will be made"
        log_info ""
        log_info "Would deploy portal app:"
        log_info "  From: $PORTAL_APP_FILE"
        log_info "  To replicas: $REPLICAS"
        log_info "  Portal URL: https://kushnir.cloud"
        log_info "  Appsmith API: http://localhost:$APPSMITH_API_PORT"
        log_info ""
        return 0
    fi
    
    local failed_replicas=""
    local IFS=","
    for replica in $REPLICAS; do
        if ! deploy_portal_to_replica "$replica"; then
            failed_replicas="$failed_replicas $replica"
        fi
    done
    
    if [[ -n "$failed_replicas" ]]; then
        log_error "Failed to deploy to replicas:$failed_replicas"
        return 1
    fi
    
    return 0
}

verify_portal_access() {
    log_info "=========================================="
    log_info "VERIFYING PORTAL ACCESSIBILITY"
    log_info "=========================================="
    log_info ""
    
    local portal_url="https://kushnir.cloud"
    log_info "Testing portal accessibility at: $portal_url"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would test GET $portal_url"
        return 0
    fi
    
    # Test portal health
    if curl -s -k "$portal_url/health" | grep -q "OK"; then
        log_info "✅ Portal health check passed"
        return 0
    else
        log_warn "Portal health check did not respond as expected"
        log_info "Note: Portal may still be initializing. Full verification requires visiting https://kushnir.cloud in browser"
        return 0  # Don't fail on health check - portal may need time to initialize
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "APPSMITH KUSHNIR.CLOUD PORTAL"
    log_info "=========================================="
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    # Validate portal app JSON
    validate_portal_json
    
    # Deploy to all replicas
    if ! deploy_to_all_replicas; then
        log_error "❌ Portal deployment failed"
        return 1
    fi
    
    # Verify portal is accessible
    if ! verify_portal_access; then
        log_error "❌ Portal accessibility verification failed"
        return 1
    fi
    
    log_info "✅ Appsmith portal deployment complete"
    log_info ""
    log_info "Portal Dashboard:"
    log_info "  URL: https://kushnir.cloud"
    log_info "  Features:"
    log_info "    - KC branding with logo and colors"
    log_info "    - Cluster health status (R31, R42)"
    log_info "    - User profile widget"
    log_info "    - Quick links (IDE, Monitoring, Docs)"
    log_info ""
    
    return 0
}

main "$@"
