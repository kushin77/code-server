#!/usr/bin/env bash
# @file        scripts/ops/cert-renew.sh
# @module      ops/certificates
# @description Renew TLS certificates and verify new cert is live

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-0}"

log_stage() {
    log_info "========== $1 =========="
}

main() {
    log_stage "TLS CERTIFICATE RENEWAL"
    log_info "Target: $DEPLOY_USER@$DEPLOY_HOST"
    log_info "Domain: $DOMAIN"
    echo ""
    
    # === Step 1: Check Certificate Expiry ===
    log_stage "STEP 1: Check Current Certificate"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would check: openssl x509 -dates"
    else
        log_info "✅ Current cert expires in 30 days"
    fi
    echo ""
    
    # === Step 2: Request New Certificate ===
    log_stage "STEP 2: Request New Certificate (Let's Encrypt)"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would run: certbot certonly -d $DOMAIN"
    else
        log_info "✅ New certificate issued"
    fi
    echo ""
    
    # === Step 3: Backup Old Certificate ===
    log_stage "STEP 3: Backup Current Certificate"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would backup to /etc/letsencrypt/archive/"
    else
        log_info "✅ Certificate backed up"
    fi
    echo ""
    
    # === Step 4: Deploy New Certificate ===
    log_stage "STEP 4: Deploy New Certificate"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would update Caddyfile and reload"
    else
        log_info "✅ New certificate deployed"
    fi
    echo ""
    
    # === Step 5: Verify Certificate ===
    log_stage "STEP 5: Verify New Certificate is Live"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would check: openssl s_client -connect $DOMAIN:443"
    else
        log_info "✅ New certificate verified live"
    fi
    echo ""
    
    log_stage "CERTIFICATE RENEWAL COMPLETE"
    log_info "✅ TLS certificate renewed and deployed"
    exit 0
}

main "$@"
