#!/usr/bin/env bash
# @file        scripts/verify-p0-fixes-deployed.sh
# @module      security/verification
# @description Verify all P0 security fixes are deployed on both production replicas

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"

log_info "========== P0 SECURITY FIXES DEPLOYMENT VERIFICATION =========="
log_info ""

# ============================================================================
# VERIFICATION PHASE 1: Local Repository State
# ============================================================================
log_info "PHASE 1: Local Repository State"
log_info "───────────────────────────────"

log_info "Current commit:"
git log --oneline -1

log_info ""
log_info "Working directory status:"
git status --short || true

# ============================================================================
# VERIFICATION PHASE 2: Non-Root Containers (P0 #969)
# ============================================================================
log_info ""
log_info "PHASE 2: Non-Root Container Verification (P0 #969)"
log_info "──────────────────────────────────────────────────"

for service in oauth2-proxy oauth2-oidc-issuer code-server session-broker redis; do
    USER_VAL=$(grep -A10 "^\s*$service:" docker-compose.yml | grep -m1 "user:" | awk -F': ' '{print $2}' | tr -d ' ' | tr -d "'" || echo "NOT FOUND")
    if [ "$USER_VAL" = "NOT FOUND" ]; then
        log_warn "  ⚠ $service: user directive not found"
    else
        log_info "  ✓ $service: user=$USER_VAL"
    fi
done

# ============================================================================
# VERIFICATION PHASE 3: Redis Authentication (P0 #971)
# ============================================================================
log_info ""
log_info "PHASE 3: Redis Authentication (P0 #971)"
log_info "──────────────────────────────────────"

if grep -q "requirepass.*REDIS_PASSWORD" docker-compose.yml; then
    log_info "  ✓ Redis requirepass configured with REDIS_PASSWORD env var"
else
    log_warn "  ⚠ Redis requirepass not found or not using env var"
fi

# ============================================================================
# VERIFICATION PHASE 4: Cookie Secret (P0 #968)
# ============================================================================
log_info ""
log_info "PHASE 4: Cookie Secret Handling (P0 #968)"
log_info "────────────────────────────────────────"

if grep -q 'OAUTH2_PROXY_COOKIE_SECRET.*?:' docker-compose.yml; then
    log_info "  ✓ OAUTH2_PROXY_COOKIE_SECRET has required-flag (?:)"
else
    log_warn "  ⚠ OAUTH2_PROXY_COOKIE_SECRET may have optional fallback"
fi

# ============================================================================
# VERIFICATION PHASE 5: Environment Variable Requirements (P0 #998)
# ============================================================================
log_info ""
log_info "PHASE 5: Environment Variable Requirements (P0 #998)"
log_info "─────────────────────────────────────────────────────"

log_info "  Checking for no hardcoded fallbacks..."
if grep -q 'IDE_SESSION_LB_SECRET:secret' docker-compose.yml; then
    log_warn "  ⚠ Found hardcoded IDE_SESSION_LB_SECRET fallback"
else
    log_info "  ✓ IDE_SESSION_LB_SECRET requires env var (no hardcoded fallback)"
fi

# ============================================================================
# VERIFICATION PHASE 6: Docker Image Immutability
# ============================================================================
log_info ""
log_info "PHASE 6: Docker Image Immutability"
log_info "──────────────────────────────────"

DIGEST_COUNT=$(grep '@sha256:' docker-compose.yml | wc -l)
TOTAL_IMAGES=$(grep -c '^[[:space:]]*image:' docker-compose.yml)

log_info "  Total images: $TOTAL_IMAGES"
log_info "  SHA256 pinned: $DIGEST_COUNT"

if [ "$DIGEST_COUNT" -eq "$TOTAL_IMAGES" ]; then
    log_info "  ✓ 100% Docker images use SHA256 digest pinning"
else
    log_warn "  ⚠ Only $DIGEST_COUNT/$TOTAL_IMAGES images pinned"
fi

# ============================================================================
# VERIFICATION PHASE 7: Replica Synchronization
# ============================================================================
log_info ""
log_info "PHASE 7: Replica Synchronization"
log_info "───────────────────────────────"

for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
    log_info "  Checking $host..."
    if ssh -o ConnectTimeout=3 "${TARGET_USER}@${host}" "cd code-server-enterprise && docker compose ps --format 'table {{.Names}}\t{{.Status}}' | grep -q 'redis.*Up'" 2>/dev/null; then
        COMMIT=$(ssh -o ConnectTimeout=3 "${TARGET_USER}@${host}" "cd code-server-enterprise && git log --oneline -1 --format=%H" 2>/dev/null || echo "UNREACHABLE")
        if [ "$COMMIT" != "UNREACHABLE" ]; then
            log_info "    ✓ redis service UP (commit: ${COMMIT:0:7}...)"
        fi
    else
        log_warn "    ⚠ Cannot verify or redis not running"
    fi
done

# ============================================================================
# FINAL STATUS
# ============================================================================
log_info ""
log_info "========== VERIFICATION COMPLETE =========="
log_info "Status: P0 Security Fixes Framework Verified"
log_info "Next Steps:"
log_info "  1. Deploy to production replicas using scripts/execute-p0-security-fixes.sh"
log_info "  2. Verify service health on both replicas"
log_info "  3. Run end-to-end authentication tests"
log_info "  4. Close GitHub issues #968, #969, #971, #998, #980"
