#!/usr/bin/env bash
# Pre-deployment verification for Issue #984 execution
# Runs comprehensive checks before starting OAuth whitelist configuration
# Exit code 0 = All checks passed, safe to proceed
# Exit code 1 = One or more checks failed, do NOT proceed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
echo -e "${BLUE}Issue #984 Pre-Deployment Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Section 1: GitHub Prerequisites
# ============================================================================
echo -e "${YELLOW}Section 1: GitHub & Issue Prerequisites${NC}"
echo ""

log_check "Issue #983 status"
ISSUE_983_STATE=$(gh issue view 983 --repo kushin77/code-server --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
if [ "$ISSUE_983_STATE" = "CLOSED" ]; then
  log_pass "Issue #983 is CLOSED - QA user created"
else
  log_fail "Issue #983 is still $ISSUE_983_STATE - Cannot proceed without QA user password"
fi
echo ""

log_check "Issue #984 status"
ISSUE_984_STATE=$(gh issue view 984 --repo kushin77/code-server --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
if [ "$ISSUE_984_STATE" = "OPEN" ]; then
  log_pass "Issue #984 is OPEN - Ready for configuration"
else
  log_fail "Issue #984 is $ISSUE_984_STATE - Expected OPEN state"
fi
echo ""

log_check "GitHub CLI authentication"
if gh auth status &>/dev/null; then
  log_pass "GitHub CLI authenticated"
else
  log_fail "GitHub CLI not authenticated - Run: gh auth login"
fi
echo ""

# ============================================================================
# Section 2: Infrastructure Prerequisites
# ============================================================================
echo -e "${YELLOW}Section 2: Infrastructure Prerequisites${NC}"
echo ""

log_check "SSH access to production host"
if timeout 5 ssh -o ConnectTimeout=5 akushnir@192.168.168.31 "echo OK" &>/dev/null; then
  log_pass "SSH to 192.168.168.31 working"
else
  log_fail "Cannot SSH to 192.168.168.31 - Check VPN/network connectivity"
fi
echo ""

log_check "Git repository status"
if [ -d ".git" ]; then
  log_pass "Git repository initialized"
  
  # Check for uncommitted changes
  if git status --porcelain | grep -q .; then
    log_warn "Uncommitted changes in working directory - Consider committing first"
  else
    log_pass "Working directory clean - No uncommitted changes"
  fi
else
  log_fail "Not in a git repository"
fi
echo ""

log_check "Terraform availability"
if command -v terraform &>/dev/null; then
  TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || echo "unknown")
  log_pass "Terraform available (version: $TF_VERSION)"
else
  log_fail "Terraform not installed or not in PATH"
fi
echo ""

# ============================================================================
# Section 3: Required Files & Configuration
# ============================================================================
echo -e "${YELLOW}Section 3: Required Files & Configuration${NC}"
echo ""

log_check "ISSUE-984-QUICK-EXECUTION.md exists"
if [ -f "ISSUE-984-QUICK-EXECUTION.md" ]; then
  log_pass "Execution guide present"
else
  log_fail "ISSUE-984-QUICK-EXECUTION.md not found - Required for deployment"
fi
echo ""

log_check "terraform/main.tf exists"
if [ -f "terraform/main.tf" ]; then
  log_pass "Terraform configuration present"
else
  log_fail "terraform/main.tf not found"
fi
echo ""

log_check "docker-compose.yml exists"
if [ -f "docker-compose.yml" ]; then
  log_pass "Docker Compose configuration present"
else
  log_fail "docker-compose.yml not found"
fi
echo ""

log_check ".env file exists"
if [ -f ".env" ]; then
  log_pass ".env file present"
  
  # Check for required QA variables
  if grep -q "QA_EMAIL" .env; then
    log_pass "QA_EMAIL configured"
  else
    log_warn "QA_EMAIL not found in .env - Will need to set during #984"
  fi
else
  log_warn ".env file not found - Will be created during terraform apply"
fi
echo ""

# ============================================================================
# Section 4: Production Environment Health
# ============================================================================
echo -e "${YELLOW}Section 4: Production Environment Health${NC}"
echo ""

log_check "Production docker-compose is running"
if timeout 10 ssh akushnir@192.168.168.31 "docker ps 2>/dev/null | wc -l" &>/dev/null; then
  SERVICE_COUNT=$(timeout 10 ssh akushnir@192.168.168.31 "docker ps -q 2>/dev/null | wc -l" || echo "0")
  if [ "$SERVICE_COUNT" -gt "5" ]; then
    log_pass "Production services running ($SERVICE_COUNT containers)"
  else
    log_warn "Low container count ($SERVICE_COUNT) - Check production health"
  fi
else
  log_fail "Cannot access production Docker daemon"
fi
echo ""

log_check "PostgreSQL database responsive"
if timeout 10 ssh akushnir@192.168.168.31 "docker exec postgres pg_isready -h localhost 2>/dev/null" &>/dev/null; then
  log_pass "PostgreSQL database is responsive"
else
  log_warn "PostgreSQL not responding - May impact #984 execution"
fi
echo ""

log_check "OAuth2-proxy service status"
if timeout 10 ssh akushnir@192.168.168.31 "docker ps -f name=oauth2-proxy --format '{{.Status}}' 2>/dev/null | grep -q Up" 2>/dev/null; then
  log_pass "OAuth2-proxy container is running"
else
  log_fail "OAuth2-proxy not running - Required for #984 execution"
fi
echo ""

# ============================================================================
# Section 5: Google Cloud Prerequisites
# ============================================================================
echo -e "${YELLOW}Section 5: Google Cloud Prerequisites${NC}"
echo ""

log_check "GCP credentials available"
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  log_pass "GCP service account credentials set"
else
  log_warn "GOOGLE_APPLICATION_CREDENTIALS not set - Will use Application Default Credentials"
fi
echo ""

log_check "gcloud CLI installed"
if command -v gcloud &>/dev/null; then
  log_pass "gcloud CLI available"
else
  log_warn "gcloud CLI not found - Some GSM operations may be manual"
fi
echo ""

# ============================================================================
# Section 6: E2E Test Prerequisites
# ============================================================================
echo -e "${YELLOW}Section 6: E2E Test Prerequisites${NC}"
echo ""

log_check "Node.js installed"
if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version)
  log_pass "Node.js available ($NODE_VERSION)"
else
  log_fail "Node.js not installed - Required for E2E tests after #984"
fi
echo ""

log_check "Playwright installed"
if [ -d "node_modules/playwright" ] || [ -d "node_modules/@playwright/test" ]; then
  log_pass "Playwright available"
else
  log_warn "Playwright not installed - Will need npm install before E2E tests"
fi
echo ""

log_check "E2E test files present"
if find scripts/e2e -name "*.spec.ts" 2>/dev/null | grep -q "oauth\|login"; then
  log_pass "E2E test files found"
else
  log_warn "E2E test files not found in expected location"
fi
echo ""

# ============================================================================
# Final Summary
# ============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Total checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
  echo -e "${GREEN}✅ All critical checks passed!${NC}"
  echo ""
  echo "Ready to execute Issue #984:"
  echo "  bash ISSUE-984-QUICK-EXECUTION.md"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Critical checks failed - Do NOT proceed with #984${NC}"
  echo ""
  echo "Failed checks must be resolved before deployment:"
  echo "  - Issue #983 must be CLOSED (QA user created)"
  echo "  - SSH connectivity to 192.168.168.31 required"
  echo "  - OAuth2-proxy must be running on production"
  echo ""
  exit 1
fi
