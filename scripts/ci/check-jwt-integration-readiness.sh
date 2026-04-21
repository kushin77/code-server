#!/bin/bash
# @file        scripts/ci/check-jwt-integration-readiness.sh
# @module      auth/verification
# @description Verify JWT authentication components are ready for Phase 2B integration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

check_file() {
  local file="$1"
  local description="$2"
  
  if [ -f "$file" ]; then
    echo "✅ $description"
    ((CHECKS_PASSED++))
  else
    echo "❌ $description (missing: $file)"
    ((CHECKS_FAILED++))
  fi
}

check_content() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  
  if [ ! -f "$file" ]; then
    echo "❌ $description (file not found: $file)"
    ((CHECKS_FAILED++))
    return 1
  fi
  
  if grep -q "$pattern" "$file"; then
    echo "✅ $description"
    ((CHECKS_PASSED++))
  else
    echo "❌ $description (pattern not found in $file)"
    ((CHECKS_FAILED++))
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2A: Core Components Check
# ─────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 2A: JWT Core Components Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/jwt-validator.ts" \
  "JWT Validator implementation"

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/jwt-token-client.ts" \
  "JWT Token Client implementation"

check_file \
  "$PROJECT_ROOT/apps/backend/src/middleware/jwt-auth.ts" \
  "JWT Auth Middleware implementation"

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/jwt-redis-cache.ts" \
  "JWT Redis Cache implementation"

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/__tests__/jwt-validator.test.ts" \
  "JWT Validator unit tests"

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/index.ts" \
  "JWT Auth module exports"

check_file \
  "$PROJECT_ROOT/docs/PHASE-2-SERVICE-TO-SERVICE-AUTH.md" \
  "Phase 2A documentation"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2B: Integration Components Check
# ─────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 2B: API Integration Readiness Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""

check_file \
  "$PROJECT_ROOT/apps/backend/src/services/auth/integration-example.ts" \
  "Integration example with incoming validation and outgoing token acquisition"

check_file \
  "$PROJECT_ROOT/apps/session-broker/src/jwt-auth-integration.ts" \
  "Session-broker JWT auth adapter"

check_file \
  "$PROJECT_ROOT/docs/PHASE-2B-API-INTEGRATION.md" \
  "Phase 2B integration guide"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Dependency Check
# ─────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo "Dependency Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""

check_content \
  "$PROJECT_ROOT/apps/backend/package.json" \
  '"jose"' \
  "Backend has jose dependency"

check_content \
  "$PROJECT_ROOT/apps/session-broker/package.json" \
  '"jose"' \
  "Session-broker has jose dependency"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════════"
echo "VERIFICATION RESULTS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Passed: $CHECKS_PASSED"
echo "Failed: $CHECKS_FAILED"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo "✅ ALL CHECKS PASSED - Ready for Phase 2B integration"
  exit 0
else
  echo "❌ SOME CHECKS FAILED - Review missing components above"
  exit 1
fi
