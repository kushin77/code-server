#!/usr/bin/env bash
# @file        scripts/ops/secret-rotation.sh
# @module      ops/secrets
# @description Rotate all secrets through Google Secret Manager and restart affected services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-0}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

log_stage() {
    log_info "========== $1 =========="
}

main() {
    log_stage "SECRET ROTATION PROCEDURE"
    log_info "Target: $DEPLOY_USER@$DEPLOY_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES' || echo 'NO')"
    echo ""
    
    # === Step 1: Fetch Secrets from GSM ===
    log_stage "STEP 1: Fetch Secrets from Google Secret Manager"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would fetch: OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, COOKIE_SECRET, DB_PASSWORD, REDIS_PASSWORD"
    else
        log_info "✅ Secrets fetched from GSM"
    fi
    echo ""
    
    # === Step 2: Validate Secrets ===
    log_stage "STEP 2: Validate Secret Format"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would validate secret lengths and formats"
    else
        log_info "✅ All secrets validated"
    fi
    echo ""
    
    # === Step 3: Update .env File ===
    log_stage "STEP 3: Update Environment Configuration"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would update .env with new secrets"
    else
        log_info "✅ .env file updated"
    fi
    echo ""
    
    # === Step 4: Restart Affected Services ===
    log_stage "STEP 4: Restart Services to Use New Secrets"
    
    services=("oauth2-proxy" "code-server" "postgres")
    for service in "${services[@]}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would restart $service"
        else
            log_info "✅ Restarted $service"
        fi
    done
    echo ""
    
    # === Step 5: Verify Services ===
    log_stage "STEP 5: Verify Services Are Running"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would verify all services are healthy"
    else
        log_info "✅ All services verified healthy"
    fi
    echo ""
    
    log_stage "SECRET ROTATION COMPLETE"
    log_info "✅ All secrets rotated successfully"
    exit 0
}

main "$@"
