#!/bin/bash
# Post-deployment verification for Issue #984
# Comprehensive validation that OAuth whitelist + GSM credentials are properly configured

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Functions
log_check() {
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  echo -e "${BLUE}[CHECK $TOTAL_CHECKS]${NC} $1"
}

log_pass() {
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  echo -e "  ${GREEN}✓ PASS${NC}: $1"
}

log_fail() {
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
  echo -e "  ${RED}✗ FAIL${NC}: $1"
}

log_warn() {
  WARNINGS=$((WARNINGS + 1))
  echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
}

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Issue #984 Post-Deployment Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Section 1: OAuth2-Proxy Service Health
# ============================================================================
echo -e "${YELLOW}Section 1: OAuth2-Proxy Service Health${NC}"
echo ""

log_check "oauth2-proxy container is running"
if timeout 10 ssh akushnir@192.168.168.31 \
    "docker ps -f name=oauth2-proxy --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" &>/dev/null; then
  log_pass "oauth2-proxy container is UP"
else
  log_fail "oauth2-proxy container is not running"
fi
echo ""

log_check "oauth2-proxy health endpoint responding"
if timeout 10 ssh akushnir@192.168.168.31 \
    "curl -s -m 5 http://localhost:4180/health 2>/dev/null | grep -q -E 'OK|healthy'" &>/dev/null; then
  log_pass "oauth2-proxy health check passed"
else
  log_fail "oauth2-proxy health check failed"
fi
echo ""

log_check "oauth2-proxy process has no restart loops"
RESTART_COUNT=$(timeout 10 ssh akushnir@192.168.168.31 \
    "docker inspect oauth2-proxy 2>/dev/null | jq '.[] | .RestartCount' || echo '0'" || echo "0")
if [ "$RESTART_COUNT" -lt 3 ]; then
  log_pass "oauth2-proxy restart count is healthy ($RESTART_COUNT)"
else
  log_fail "oauth2-proxy has restarted $RESTART_COUNT times (possible crash loop)"
fi
echo ""

log_check "oauth2-proxy logs for errors"
ERROR_COUNT=$(timeout 10 ssh akushnir@192.168.168.31 \
    "docker logs oauth2-proxy 2>&1 | tail -50 | grep -i 'error\|panic\|fatal' | wc -l" || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
  log_pass "No errors in recent oauth2-proxy logs"
else
  log_warn "Found $ERROR_COUNT error lines in oauth2-proxy logs (review manually)"
fi
echo ""

# ============================================================================
# Section 2: OAuth Whitelist Configuration
# ============================================================================
echo -e "${YELLOW}Section 2: OAuth Whitelist Configuration${NC}"
echo ""

log_check "QA_EMAIL environment variable set"
if timeout 10 ssh akushnir@192.168.168.31 \
    "docker exec oauth2-proxy env | grep -q 'QA_EMAIL='" &>/dev/null; then
  QA_EMAIL=$(timeout 10 ssh akushnir@192.168.168.31 \
      "docker exec oauth2-proxy env | grep 'QA_EMAIL=' | cut -d= -f2" || echo "unknown")
  log_pass "QA_EMAIL configured: $QA_EMAIL"
else
  log_fail "QA_EMAIL environment variable not set in oauth2-proxy container"
fi
echo ""

log_check "OAuth2-proxy configuration includes whitelist"
CONFIG_CHECK=$(timeout 10 ssh akushnir@192.168.168.31 \
    "docker exec oauth2-proxy grep -i 'whitelist\|email_domain\|allowed' /etc/oauth2-proxy/oauth2-proxy.cfg 2>/dev/null | wc -l" || echo "0")
if [ "$CONFIG_CHECK" -gt 0 ]; then
  log_pass "Whitelist configuration found in oauth2-proxy config"
else
  log_warn "Whitelist configuration not found (may use environment variables only)"
fi
echo ""

# ============================================================================
# Section 3: GSM Secret Verification
# ============================================================================
echo -e "${YELLOW}Section 3: Google Secret Manager Verification${NC}"
echo ""

log_check "GCP service account credentials present"
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] || command -v gcloud &>/dev/null; then
  log_pass "GCP credentials available"
else
  log_warn "GCP credentials not detected (may use Workload Identity)"
fi
echo ""

log_check "GSM secret: qa-user-email"
if timeout 10 gcloud secrets versions access latest --secret="qa-user-email" &>/dev/null 2>&1; then
  log_pass "GSM secret 'qa-user-email' accessible"
else
  log_fail "Cannot access GSM secret 'qa-user-email'"
fi
echo ""

log_check "GSM secret: qa-oauth-whitelist"
if timeout 10 gcloud secrets versions access latest --secret="qa-oauth-whitelist" &>/dev/null 2>&1; then
  log_pass "GSM secret 'qa-oauth-whitelist' accessible"
else
  log_fail "Cannot access GSM secret 'qa-oauth-whitelist'"
fi
echo ""

log_check "GSM secrets are recent (created/updated during #984)"
SECRET_AGE=$(timeout 10 gcloud secrets describe qa-oauth-whitelist \
    --format='get(updated)' 2>/dev/null | xargs -I {} date -d {} +%s || echo "0")
NOW=$(date +%s)
AGE_MINUTES=$(( (NOW - SECRET_AGE) / 60 ))

if [ "$AGE_MINUTES" -lt 120 ]; then
  log_pass "GSM secret is recent ($AGE_MINUTES minutes old)"
else
  log_warn "GSM secret is $AGE_MINUTES minutes old (verify it was updated during #984)"
fi
echo ""

# ============================================================================
# Section 4: Database Configuration
# ============================================================================
echo -e "${YELLOW}Section 4: Database & Configuration${NC}"
echo ""

log_check "PostgreSQL is running"
if timeout 10 ssh akushnir@192.168.168.31 \
    "docker ps -f name=postgres --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" &>/dev/null; then
  log_pass "PostgreSQL container is UP"
else
  log_fail "PostgreSQL container is not running"
fi
echo ""

log_check ".env file contains QA configuration"
if [ -f ".env" ]; then
  if grep -q "QA_EMAIL" .env; then
    log_pass "QA_EMAIL configured in .env"
  else
    log_warn "QA_EMAIL not found in local .env (may be set in container)"
  fi
else
  log_warn ".env file not found locally"
fi
echo ""

log_check "terraform state shows #984 resources"
if [ -f "terraform/terraform.tfstate" ]; then
  if grep -q "qa_oauth_whitelist\|qa-user" terraform/terraform.tfstate; then
    log_pass "Terraform state includes #984 resources"
  else
    log_warn "Terraform state does not show #984-specific resources"
  fi
else
  log_warn "terraform.tfstate not found"
fi
echo ""

# ============================================================================
# Section 5: Connectivity & Access Control
# ============================================================================
echo -e "${YELLOW}Section 5: Connectivity & Access Control${NC}"
echo ""

log_check "oauth2-proxy port 4180 is accessible"
if timeout 10 ssh akushnir@192.168.168.31 \
    "netstat -tlnp 2>/dev/null | grep -q ':4180' || ss -tlnp 2>/dev/null | grep -q ':4180'" &>/dev/null; then
  log_pass "oauth2-proxy port 4180 is listening"
else
  log_warn "Port 4180 status unclear (may still be accessible via docker network)"
fi
echo ""

log_check "Reverse proxy (caddy) is running"
if timeout 10 ssh akushnir@192.168.168.31 \
    "docker ps -f name=caddy --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" &>/dev/null; then
  log_pass "Caddy reverse proxy is UP"
else
  log_fail "Caddy is not running (users cannot reach oauth2-proxy)"
fi
echo ""

log_check "Code-Server service is running"
if timeout 10 ssh akushnir@192.168.168.31 \
    "docker ps -f name=code-server --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" &>/dev/null; then
  log_pass "Code-Server is UP"
else
  log_fail "Code-Server is not running"
fi
echo ""

# ============================================================================
# Section 6: E2E Test Readiness
# ============================================================================
echo -e "${YELLOW}Section 6: E2E Test Readiness${NC}"
echo ""

log_check "Node.js environment available"
if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  log_pass "Node.js available ($NODE_VER)"
else
  log_fail "Node.js not available - E2E tests cannot run"
fi
echo ""

log_check "Playwright test framework installed"
if [ -d "node_modules/playwright" ] || [ -d "node_modules/@playwright/test" ]; then
  log_pass "Playwright installed"
else
  log_warn "Playwright not installed locally"
fi
echo ""

log_check "E2E test environment variables configured"
if [ -f ".env" ] && grep -q "TEST_BASE_URL\|IDE_BASE_URL" .env; then
  log_pass "E2E test URLs configured"
else
  log_warn "E2E test URLs may not be configured"
fi
echo ""

# ============================================================================
# Final Summary
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Total checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
  echo -e "${GREEN}✅ Issue #984 deployment successful!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Execute E2E tests: bash scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh"
  echo "  2. Comment on Issue #984 with test results"
  echo "  3. Close Issue #984 when tests pass"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Deployment verification found critical issues${NC}"
  echo ""
  echo "Failed checks indicate:"
  echo "  - oauth2-proxy not running or health checks failing"
  echo "  - GSM secrets not accessible"
  echo "  - Database or core services down"
  echo ""
  echo "Consider running ISSUE-984-ROLLBACK-PROCEDURE.sh if deployment is fundamentally broken."
  echo ""
  exit 1
fi
