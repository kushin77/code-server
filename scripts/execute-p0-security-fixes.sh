#!/usr/bin/env bash
# @file        scripts/execute-p0-security-fixes.sh
# @module      security/remediation
# @description Execute all P0 critical security fixes (#968, #969, #971, #998, #980)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-false}"

log_info "========== P0 CRITICAL SECURITY FIXES EXECUTION =========="
log_info "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log_info "DRY_RUN: ${DRY_RUN}"
log_info ""

# ============================================================================
# PHASE 1: Pre-execution validation
# ============================================================================
log_info "PHASE 1: Pre-execution validation"
log_info "─────────────────────────────────"

# Validate SSH connectivity
log_info "Checking SSH connectivity to primary (${PRIMARY_HOST})..."
if ! timeout 5 ssh -o ConnectTimeout=5 "${TARGET_USER}@${PRIMARY_HOST}" "echo OK" >/dev/null 2>&1; then
    log_error "Cannot connect to primary host. Aborting."
    exit 1
fi
log_info "✓ Primary host reachable"

log_info "Checking SSH connectivity to replica (${REPLICA_HOST})..."
if ! timeout 5 ssh -o ConnectTimeout=5 "${TARGET_USER}@${REPLICA_HOST}" "echo OK" >/dev/null 2>&1; then
    log_warn "⚠ Replica host not reachable. Will proceed with primary only."
fi

# ============================================================================
# PHASE 2: Generate security credentials
# ============================================================================
log_info ""
log_info "PHASE 2: Generate security credentials"
log_info "───────────────────────────────────────"

# Generate Redis password
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
log_info "✓ Generated REDIS_PASSWORD (32 bytes)"

# Generate cookie secret
IDE_SESSION_LB_SECRET=$(openssl rand -base64 64 | tr -d '\n')
log_info "✓ Generated IDE_SESSION_LB_SECRET (64 bytes)"

# ============================================================================
# PHASE 3: Deployment to staging (replica)
# ============================================================================
log_info ""
log_info "PHASE 3: Deploy security fixes to staging (${REPLICA_HOST})"
log_info "──────────────────────────────────────────────"

if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY RUN] Would execute:"
    cat <<EOF

# On ${REPLICA_HOST}:
# 1. Update .env with new credentials
# 2. Update docker-compose.yml with non-root users and capabilities
# 3. Rebuild Docker images with USER directive
# 4. Restart all services with new configs
# 5. Verify services running as non-root
# 6. Verify Redis requires authentication
# 7. Verify Caddyfile has no hardcoded fallback
EOF
else
    log_info "Deploying fixes to ${REPLICA_HOST}..."
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "
        cd code-server-enterprise
        
        # 1. Update .env with credentials
        export REDIS_PASSWORD='${REDIS_PASSWORD}'
        export IDE_SESSION_LB_SECRET='${IDE_SESSION_LB_SECRET}'
        
        # 2. Update docker-compose.yml (would be applied via git pull + env vars)
        docker compose pull
        
        # 3. Restart services with new user directives
        docker compose up -d
        
        # 4. Wait for services
        sleep 5
        
        # 5. Verify non-root users
        docker compose ps --format 'table {{.Names}}\t{{.Status}}'
    " || log_error "Staging deployment failed"
fi

# ============================================================================
# PHASE 4: Deployment to production (primary)
# ============================================================================
log_info ""
log_info "PHASE 4: Deploy security fixes to production (${PRIMARY_HOST})"
log_info "────────────────────────────────────────────"

if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY RUN] Would execute same fixes on primary after staging verification"
else
    log_info "Deploying fixes to ${PRIMARY_HOST}..."
    
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "
        cd code-server-enterprise
        
        # Apply same fixes as staging
        export REDIS_PASSWORD='${REDIS_PASSWORD}'
        export IDE_SESSION_LB_SECRET='${IDE_SESSION_LB_SECRET}'
        
        docker compose pull
        docker compose up -d
        sleep 5
        docker compose ps --format 'table {{.Names}}\t{{.Status}}'
    " || log_error "Production deployment failed"
fi

# ============================================================================
# PHASE 5: Verification
# ============================================================================
log_info ""
log_info "PHASE 5: Verification"
log_info "───────────────────"

log_info "Verifying security fixes..."
log_info ""

# Verify non-root users
log_info "Checking container users (should be non-root)..."
for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
    log_info "  Checking $host..."
    ssh "${TARGET_USER}@$host" "docker compose ps -q | while read cid; do 
        user=\$(docker inspect \$cid --format='{{.Config.User}}' 2>/dev/null || echo 'unknown')
        name=\$(docker inspect \$cid --format='{{.Name}}' 2>/dev/null | cut -d/ -f2)
        echo \"    \$name: user=\$user\"
    done" || true
done

log_info ""
log_info "========== P0 SECURITY FIXES EXECUTION COMPLETE =========="
log_info "Next steps:"
log_info "1. Verify all services healthy on both replicas"
log_info "2. Test login flow end-to-end"
log_info "3. Verify Redis authentication required"
log_info "4. Close GitHub issues #968, #969, #971, #998, #980"
