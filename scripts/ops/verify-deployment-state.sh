#!/bin/bash
# @file        scripts/ops/verify-deployment-state.sh
# @module      ops/verification
# @description Verify cluster deployment state against expected IaC state
# @owner       infrastructure
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
DEPLOY_USER="akushnir"
DEPLOY_DIR="code-server-enterprise"

# Expected state after 4-phase deployment
EXPECTED_COMMIT="2d4d0c08"
EXPECTED_CONTAINERS=38
MIN_HEALTH_CHECK=200

log_info "==================================================================="
log_info "CLUSTER DEPLOYMENT STATE VERIFICATION (IaC)"
log_info "==================================================================="
log_info "Expected Commit: $EXPECTED_COMMIT"
log_info "Expected Containers: $EXPECTED_CONTAINERS"
log_info ""

# State tracking
STATE_MATCH=0
REPLICAS_SYNCED=0
ERRORS=0

# =========================================================================
# VERIFY REPLICA 1
# =========================================================================

log_info "REPLICA 1 ($REPLICA_1)"
log_info "---"

# Commit check
REPLICA_1_COMMIT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_1}" "cd ${DEPLOY_DIR} && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
log_info "Commit: $REPLICA_1_COMMIT (expected: $EXPECTED_COMMIT)"
if [[ "$REPLICA_1_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "  ✓ Commit matches"
else
  log_warn "  ⚠ Commit mismatch"
  ERRORS=$((ERRORS + 1))
fi

# Git status check
REPLICA_1_DRIFT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_1}" "cd ${DEPLOY_DIR} && git status --short | wc -l" 2>/dev/null || echo "ERROR")
log_info "Git drift: $REPLICA_1_DRIFT files (expected: 0)"
if [[ "$REPLICA_1_DRIFT" -eq 0 ]]; then
  log_info "  ✓ Git state clean"
else
  log_warn "  ⚠ Git state not clean"
  ERRORS=$((ERRORS + 1))
fi

# Container count
REPLICA_1_CONTAINERS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_1}" "docker ps --quiet | wc -l" 2>/dev/null || echo "ERROR")
log_info "Running containers: $REPLICA_1_CONTAINERS (expected: $EXPECTED_CONTAINERS)"
if [[ "$REPLICA_1_CONTAINERS" -ge "$EXPECTED_CONTAINERS" ]]; then
  log_info "  ✓ Container count OK"
else
  log_warn "  ⚠ Missing containers"
  ERRORS=$((ERRORS + 1))
fi

# Health check
REPLICA_1_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://${REPLICA_1}:3000/health/ready" 2>/dev/null || echo "000")
log_info "Health endpoint: HTTP $REPLICA_1_HEALTH (expected: 200)"
if [[ "$REPLICA_1_HEALTH" -eq 200 ]]; then
  log_info "  ✓ Health check passing"
else
  log_warn "  ⚠ Health check failing"
  ERRORS=$((ERRORS + 1))
fi

log_info ""

# =========================================================================
# VERIFY REPLICA 2
# =========================================================================

log_info "REPLICA 2 ($REPLICA_2)"
log_info "---"

# Commit check
REPLICA_2_COMMIT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_2}" "cd ${DEPLOY_DIR} && git rev-parse --short HEAD" 2>/dev/null || echo "ERROR")
log_info "Commit: $REPLICA_2_COMMIT (expected: $EXPECTED_COMMIT)"
if [[ "$REPLICA_2_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "  ✓ Commit matches"
else
  log_warn "  ⚠ Commit mismatch"
  ERRORS=$((ERRORS + 1))
fi

# Git status check
REPLICA_2_DRIFT=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_2}" "cd ${DEPLOY_DIR} && git status --short | wc -l" 2>/dev/null || echo "ERROR")
log_info "Git drift: $REPLICA_2_DRIFT files (expected: 0)"
if [[ "$REPLICA_2_DRIFT" -eq 0 ]]; then
  log_info "  ✓ Git state clean"
else
  log_warn "  ⚠ Git state not clean"
  ERRORS=$((ERRORS + 1))
fi

# Container count
REPLICA_2_CONTAINERS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${DEPLOY_USER}@${REPLICA_2}" "docker ps --quiet | wc -l" 2>/dev/null || echo "ERROR")
log_info "Running containers: $REPLICA_2_CONTAINERS (expected: $EXPECTED_CONTAINERS)"
if [[ "$REPLICA_2_CONTAINERS" -ge "$EXPECTED_CONTAINERS" ]]; then
  log_info "  ✓ Container count OK"
else
  log_warn "  ⚠ Missing containers"
  ERRORS=$((ERRORS + 1))
fi

# Health check
REPLICA_2_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://${REPLICA_2}:3000/health/ready" 2>/dev/null || echo "000")
log_info "Health endpoint: HTTP $REPLICA_2_HEALTH (expected: 200)"
if [[ "$REPLICA_2_HEALTH" -eq 200 ]]; then
  log_info "  ✓ Health check passing"
else
  log_warn "  ⚠ Health check failing"
  ERRORS=$((ERRORS + 1))
fi

log_info ""

# =========================================================================
# VERIFY PARITY
# =========================================================================

log_info "CLUSTER PARITY CHECK"
log_info "---"

if [[ "$REPLICA_1_COMMIT" == "$REPLICA_2_COMMIT" && "$REPLICA_1_COMMIT" == "$EXPECTED_COMMIT" ]]; then
  log_info "✓ Both replicas on commit $EXPECTED_COMMIT"
  REPLICAS_SYNCED=1
else
  log_warn "⚠ Replicas not synced"
  log_warn "  Replica 1: $REPLICA_1_COMMIT"
  log_warn "  Replica 2: $REPLICA_2_COMMIT"
fi

if [[ "$REPLICA_1_DRIFT" -eq 0 && "$REPLICA_2_DRIFT" -eq 0 ]]; then
  log_info "✓ Both replicas have clean git state (no drift)"
else
  log_warn "⚠ Git drift detected"
fi

log_info ""

# =========================================================================
# SUMMARY
# =========================================================================

log_info "==================================================================="
if [[ $ERRORS -eq 0 && $REPLICAS_SYNCED -eq 1 ]]; then
  log_info "✓ DEPLOYMENT STATE VERIFIED - CLUSTER PARITY ACHIEVED"
  log_info "==================================================================="
  exit 0
else
  log_warn "⚠ DEPLOYMENT STATE INCOMPLETE - ISSUES DETECTED ($ERRORS errors)"
  log_info "==================================================================="
  exit 1
fi
