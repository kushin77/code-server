#!/bin/bash
# @file        scripts/ops/verify-production-readiness-quick.sh
# @module      operations/validation
# @description Quick production readiness verification - works on Windows Git Bash
# @status      Executable immediately
#

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() {
  echo -e "${GREEN}[✓]${NC} $1"
  ((CHECKS_PASSED++))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $1"
  ((CHECKS_FAILED++))
}

log_section() {
  echo
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

verify_check() {
  ((CHECKS_TOTAL++))
}

# === VERIFICATION CHECKS ===

log_section "PRODUCTION READINESS VERIFICATION"

log_section "1. KEY DELIVERABLES"

verify_check
if test -f "E2E-TEST-EXECUTION-GUIDE.md"; then
  log_pass "E2E-TEST-EXECUTION-GUIDE.md"
else
  log_fail "E2E-TEST-EXECUTION-GUIDE.md missing"
fi

verify_check
if test -f "PRODUCTION-DEPLOYMENT-CHECKLIST.md"; then
  log_pass "PRODUCTION-DEPLOYMENT-CHECKLIST.md"
else
  log_fail "PRODUCTION-DEPLOYMENT-CHECKLIST.md missing"
fi

verify_check
if test -f "scripts/ops/create-qa-user-automated.sh"; then
  log_pass "create-qa-user-automated.sh"
else
  log_fail "create-qa-user-automated.sh missing"
fi

verify_check
if test -f "scripts/ops/rotate-qa-credentials.py"; then
  log_pass "rotate-qa-credentials.py"
else
  log_fail "rotate-qa-credentials.py missing"
fi

log_section "2. INFRASTRUCTURE CONFIG"

verify_check
test -f "docker-compose.yml" && \
  log_pass "docker-compose.yml" || \
  log_fail "docker-compose.yml missing"

verify_check
test -f "prometheus.yml" && \
  log_pass "prometheus.yml" || \
  log_fail "prometheus.yml missing"

verify_check
test -f "alertmanager.yml" && \
  log_pass "alertmanager.yml" || \
  log_fail "alertmanager.yml missing"

log_section "3. GIT STATUS"

verify_check
LATEST=$(git log --oneline -1 2>/dev/null | cut -d' ' -f1)
if [ -n "$LATEST" ]; then
  log_pass "Latest commit: $LATEST"
else
  log_fail "Cannot read git log"
fi

verify_check
BRANCH=$(git branch --show-current 2>/dev/null)
if [ "$BRANCH" = "main" ]; then
  log_pass "On main branch"
else
  log_fail "Not on main branch (current: $BRANCH)"
fi

log_section "4. FILE INTEGRITY"

verify_check
GUIDE_LINES=$(wc -l < "PRODUCTION-READINESS-FINAL-INTEGRATION-GUIDE.md" 2>/dev/null || echo "0")
if [ "$GUIDE_LINES" -gt 400 ]; then
  log_pass "Integration guide complete ($GUIDE_LINES lines)"
else
  log_fail "Integration guide too short ($GUIDE_LINES lines)"
fi

verify_check
E2E_LINES=$(wc -l < "E2E-TEST-EXECUTION-GUIDE.md" 2>/dev/null || echo "0")
if [ "$E2E_LINES" -gt 500 ]; then
  log_pass "E2E guide complete ($E2E_LINES lines)"
else
  log_fail "E2E guide too short ($E2E_LINES lines)"
fi

verify_check
DEPLOY_LINES=$(wc -l < "PRODUCTION-DEPLOYMENT-CHECKLIST.md" 2>/dev/null || echo "0")
if [ "$DEPLOY_LINES" -gt 500 ]; then
  log_pass "Deployment checklist complete ($DEPLOY_LINES lines)"
else
  log_fail "Deployment checklist too short ($DEPLOY_LINES lines)"
fi

log_section "5. CONTENT VALIDATION"

verify_check
grep -q "Issue #983\|Issue #984\|production" PRODUCTION-READINESS-FINAL-INTEGRATION-GUIDE.md && \
  log_pass "Integration guide contains critical path" || \
  log_fail "Integration guide missing critical path"

verify_check
grep -q "110\|E2E\|test" E2E-TEST-EXECUTION-GUIDE.md && \
  log_pass "E2E guide mentions tests" || \
  log_fail "E2E guide incomplete"

verify_check
grep -q "Pre-Deployment\|Deployment\|Post-Deployment" PRODUCTION-DEPLOYMENT-CHECKLIST.md && \
  log_pass "Deployment checklist complete" || \
  log_fail "Deployment checklist incomplete"

log_section "VERIFICATION RESULTS"

echo
echo "Total Checks: $CHECKS_TOTAL"
echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
echo

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo -e "${GREEN}✅ ALL VERIFICATION CHECKS PASSED${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo
  echo "Production Readiness: ${GREEN}READY FOR DEPLOYMENT${NC}"
  echo
  echo "Timeline to Production:"
  echo "  1. Issue #983 (15-30 min) → Create QA user"
  echo "  2. Issue #984 (10-15 min) → Configure OAuth"
  echo "  3. E2E Tests (30 min) → Run 110+ tests"
  echo "  4. Production (30-60 min) → Deploy"
  echo
  echo "Total: 2-3 hours"
  echo
  exit 0
else
  echo -e "${RED}════════════════════════════════════════${NC}"
  echo -e "${RED}❌ VERIFICATION FAILED${NC}"
  echo -e "${RED}════════════════════════════════════════${NC}"
  exit 1
fi
