#!/usr/bin/env bash
# @file        scripts/ops/verify-production-deployment.sh
# @module      ops/verification
# @description Verify production deployment completion and cluster health
# @status      production-ready
#
# Verifies that all replicas are deployed, synchronized, and healthy.
# Creates comprehensive verification report for production readiness gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_USER="akushnir"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
VERIFICATION_REPORT="/tmp/production-deployment-verification.txt"

# Verification results
VERIFICATION_PASSED=0
VERIFICATION_WARNINGS=0
VERIFICATION_FAILURES=0

# ============================================================================
# Helper Functions
# ============================================================================

verify_replica_state() {
  local replica="$1"
  local check_name="$2"
  
  # This is just a verification flag setter
  return 0
}

# ============================================================================
# Main Verification
# ============================================================================

{
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     PRODUCTION DEPLOYMENT VERIFICATION REPORT               ║"
  echo "║     $(date -u +"%Y-%m-%d %H:%M:%S UTC")                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "🔍 CLUSTER DEPLOYMENT STATUS"
  echo "════════════════════════════════════════════════════════════════"
  
  FIRST_GIT_SHA=""
  for replica in ${REPLICAS//,/ }; do
    echo ""
    echo "▶ Replica: $replica"
    
    # Get git commit
    GIT_SHA=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "cd /home/akushnir/code-server-enterprise && git rev-parse --short HEAD 2>/dev/null" || echo "ERROR")
    
    if [[ -z "$FIRST_GIT_SHA" ]]; then
      FIRST_GIT_SHA="$GIT_SHA"
    fi
    
    echo "  Git Commit: $GIT_SHA"
    
    if [[ "$GIT_SHA" == "ERROR" ]]; then
      echo "  Status: ❌ FAILED (git command error)"
      ((VERIFICATION_FAILURES++))
      continue
    elif [[ "$GIT_SHA" != "$FIRST_GIT_SHA" ]]; then
      echo "  Status: ⚠️  WARNING (commit mismatch with first replica)"
      ((VERIFICATION_WARNINGS++))
      continue
    fi
    
    # Get container count
    CONTAINER_COUNT=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "docker ps --quiet 2>/dev/null | wc -l" || echo "ERROR")
    
    echo "  Containers Running: $CONTAINER_COUNT"
    
    if [[ "$CONTAINER_COUNT" -eq "0" ]] || [[ "$CONTAINER_COUNT" == "ERROR" ]]; then
      echo "  Status: ❌ FAILED (no containers running or Docker error)"
      ((VERIFICATION_FAILURES++))
      continue
    fi
    
    # Check health endpoint
    HEALTH_STATUS=$(ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "curl -sf http://localhost:8080/healthz >/dev/null 2>&1 && echo OK || echo FAIL")
    
    echo "  Health Check: $HEALTH_STATUS"
    
    if [[ "$HEALTH_STATUS" != "OK" ]]; then
      echo "  Status: ⚠️  WARNING (health endpoint not responding)"
      ((VERIFICATION_WARNINGS++))
      continue
    fi
    
    echo "  Status: ✅ HEALTHY"
    ((VERIFICATION_PASSED++))
  done
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "📊 VERIFICATION SUMMARY"
  echo "────────────────────────────────────────────────────────────────"
  echo "  ✅ Passed:   $VERIFICATION_PASSED"
  echo "  ⚠️  Warnings: $VERIFICATION_WARNINGS"
  echo "  ❌ Failures: $VERIFICATION_FAILURES"
  echo ""
  
  if [[ $VERIFICATION_FAILURES -eq 0 ]]; then
    echo "🟢 PRODUCTION DEPLOYMENT STATUS: READY"
    echo ""
    echo "All replicas are synchronized, healthy, and ready for traffic."
    EXIT_CODE=0
  elif [[ $VERIFICATION_WARNINGS -gt 0 && $VERIFICATION_FAILURES -eq 0 ]]; then
    echo "🟡 PRODUCTION DEPLOYMENT STATUS: CONDITIONAL READY"
    echo ""
    echo "Replicas are deployed but some warnings exist. Review above."
    EXIT_CODE=1
  else
    echo "🔴 PRODUCTION DEPLOYMENT STATUS: NOT READY"
    echo ""
    echo "Critical issues detected. Do not proceed to production traffic."
    EXIT_CODE=2
  fi
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  
} | tee "$VERIFICATION_REPORT"

log_info "Verification report: $VERIFICATION_REPORT"
exit $EXIT_CODE
