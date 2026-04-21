#!/usr/bin/env bash
# @file        scripts/ops/deploy-p0-1163-secret.sh
# @module      ops/security
# @description Deploy IDE_SESSION_LB_SECRET to production hosts (P0 #1163)
#
# This script provisions the load balancer session secret to both primary and
# replica hosts, replacing the hardcoded fallback 'secret734' with proper
# secret management via environment variables.
#
# Usage:
#   bash scripts/ops/deploy-p0-1163-secret.sh              # Deploy to both hosts
#   bash scripts/ops/deploy-p0-1163-secret.sh --primary    # Deploy to primary only
#   bash scripts/ops/deploy-p0-1163-secret.sh --replica    # Deploy to replica only
#   bash scripts/ops/deploy-p0-1163-secret.sh --dry-run    # Show what would deploy

set -euo pipefail
trap 'log_fatal "Script failed at line $LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
SSH_USER="${DEPLOY_USER:-akushnir}"
DEPLOY_PATH="/home/${SSH_USER}/code-server-enterprise"

# Secret configuration
SECRET_NAME="IDE_SESSION_LB_SECRET"
SECRET_LENGTH=32
SECRET_CHARSET="A-Za-z0-9_-"

# Deployment targets
DEPLOY_PRIMARY=false
DEPLOY_REPLICA=false
DRY_RUN=false

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

generate_secret() {
    local length=${1:-32}
    log_info "Generating ${length}-char secret..."
    openssl rand -base64 "$length" | tr -d '\n=' | head -c "$length"
}

deploy_to_host() {
    local host=$1
    local secret=$2
    
    log_info "Deploying to $host..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute on $host:"
        log_info "  1. Backup .env: cp .env .env.bak"
        log_info "  2. Add secret: echo 'IDE_SESSION_LB_SECRET=$secret' >> .env"
        log_info "  3. Verify: grep -q '$SECRET_NAME=' .env && echo 'OK'"
        log_info "  4. Restart: docker compose up -d"
        return 0
    fi
    
    local commands=$(cat <<EOF
set -euo pipefail
cd $DEPLOY_PATH || exit 1

# Backup existing .env
if [[ -f .env ]]; then
    cp .env .env.\$(date +%Y%m%d-%H%M%S).bak
    log_info "Backed up .env"
fi

# Remove existing IDE_SESSION_LB_SECRET if present
grep -v "^${SECRET_NAME}=" .env > .env.tmp 2>/dev/null || true
mv .env.tmp .env

# Add new secret
echo "${SECRET_NAME}=${secret}" >> .env
log_info "Added ${SECRET_NAME} to .env"

# Verify
if grep -q "^${SECRET_NAME}=" .env; then
    echo "✓ Secret deployed successfully"
else
    echo "✗ Failed to deploy secret"
    exit 1
fi

# Restart services
docker compose up -d
log_info "Restarted docker compose"

# Final verification
if grep -q "${SECRET_NAME}" ~/code-server-enterprise/Caddyfile; then
    echo "✓ Caddyfile using environment variable (no hardcoded secret734)"
else
    echo "⚠ Warning: Caddyfile might not reference ${SECRET_NAME}"
fi
EOF
)
    
    # Execute on remote host
    if ssh -o ConnectTimeout=10 "${SSH_USER}@${host}" bash <<'REMOTE_SCRIPT' "$commands" "$SECRET_NAME"
        eval "$1"
REMOTE_SCRIPT
    then
        log_info "✓ Deployment to $host successful"
        return 0
    else
        log_error "✗ Deployment to $host failed"
        return 1
    fi
}

verify_deployment() {
    local host=$1
    
    log_info "Verifying deployment on $host..."
    
    if ssh -o ConnectTimeout=10 "${SSH_USER}@${host}" bash <<'VERIFY_SCRIPT'
        set -euo pipefail
        cd ~/code-server-enterprise
        
        # Check .env
        if ! grep -q "^IDE_SESSION_LB_SECRET=" .env; then
            echo "✗ IDE_SESSION_LB_SECRET not found in .env"
            exit 1
        fi
        
        # Check no hardcoded secret734 in Caddyfile
        if grep -q "secret734" Caddyfile; then
            echo "✗ Found hardcoded 'secret734' in Caddyfile"
            exit 1
        fi
        
        # Check services running
        if ! docker compose ps | grep -q "code-server.*Up"; then
            echo "✗ Services not running"
            exit 1
        fi
        
        echo "✓ Verification passed"
VERIFY_SCRIPT
    then
        log_info "✓ Verification on $host successful"
        return 0
    else
        log_error "✗ Verification on $host failed"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --primary)  DEPLOY_PRIMARY=true; shift ;;
            --replica)  DEPLOY_REPLICA=true; shift ;;
            --dry-run)  DRY_RUN=true; shift ;;
            *)          log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    # Default to both hosts if none specified
    if [[ "$DEPLOY_PRIMARY" == "false" && "$DEPLOY_REPLICA" == "false" ]]; then
        DEPLOY_PRIMARY=true
        DEPLOY_REPLICA=true
    fi
    
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "P0 #1163: Deploying IDE_SESSION_LB_SECRET"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Generate secret once (use same on both hosts)
    SECRET=$(generate_secret "$SECRET_LENGTH")
    log_info "Generated secret: ${SECRET:0:8}... (${#SECRET} chars)"
    
    # Deploy to primary
    if [[ "$DEPLOY_PRIMARY" == "true" ]]; then
        log_info ""
        log_info "Deploying to PRIMARY ($PRIMARY_HOST)..."
        if ! deploy_to_host "$PRIMARY_HOST" "$SECRET"; then
            log_error "Primary deployment failed"
            exit 1
        fi
    fi
    
    # Deploy to replica
    if [[ "$DEPLOY_REPLICA" == "true" ]]; then
        log_info ""
        log_info "Deploying to REPLICA ($REPLICA_HOST)..."
        if ! deploy_to_host "$REPLICA_HOST" "$SECRET"; then
            log_error "Replica deployment failed"
            exit 1
        fi
    fi
    
    # Verify both hosts
    log_info ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "VERIFICATION"
    log_info "═══════════════════════════════════════════════════════════════"
    
    local verify_failed=0
    
    if [[ "$DEPLOY_PRIMARY" == "true" ]]; then
        if ! verify_deployment "$PRIMARY_HOST"; then
            verify_failed=1
        fi
    fi
    
    if [[ "$DEPLOY_REPLICA" == "true" ]]; then
        if ! verify_deployment "$REPLICA_HOST"; then
            verify_failed=1
        fi
    fi
    
    if [[ $verify_failed -eq 0 ]]; then
        log_info ""
        log_info "✓ ALL DEPLOYMENTS SUCCESSFUL"
        log_info "P0 #1163 is now RESOLVED"
        return 0
    else
        log_error "Some deployments failed verification"
        exit 1
    fi
}

main "$@"
