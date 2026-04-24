#!/usr/bin/env bash
# @file        scripts/ops/verify-e2e-qa-setup.sh
# @module      operations/testing
# @description Comprehensive verification of E2E QA user setup (Issue #984)
# @owner       qa-team
# @status      Ready for immediate use post-#983
#
# Purpose: Validate that all components required for E2E testing are properly configured
#
# Usage:
#   bash scripts/ops/verify-e2e-qa-setup.sh [--full]
#   bash scripts/ops/verify-e2e-qa-setup.sh --check-gsm
#   bash scripts/ops/verify-e2e-qa-setup.sh --check-oauth
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
QA_USER_EMAIL="${QA_USER_EMAIL:-qa@kushnir.cloud}"
GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
TEST_BASE_URL="${TEST_BASE_URL:-https://kushnir.cloud}"
FULL_CHECK="false"
CHECK_GSM="false"
CHECK_OAUTH="false"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() {
  echo -e "${GREEN}[✓]${NC} $1"
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $1"
  ((FAIL_COUNT++))
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $1"
  ((WARN_COUNT++))
}

log_info() {
  echo -e "${BLUE}[i]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --full)
      FULL_CHECK="true"
      shift
      ;;
    --check-gsm)
      CHECK_GSM="true"
      shift
      ;;
    --check-oauth)
      CHECK_OAUTH="true"
      shift
      ;;
    *)
      log_fail "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Main verification flow
main() {
  echo "========================================="
  echo "E2E QA Setup Verification"
  echo "========================================="
  echo "QA User: $QA_USER_EMAIL"
  echo "GCP Project: $GCP_PROJECT"
  echo "Test URL: $TEST_BASE_URL"
  echo

  # Check 1: Allowed emails whitelist
  check_allowed_emails

  # Check 2: .env.schema.json configuration
  check_env_schema

  # Check 3: GSM secrets (optional, requires gcloud auth)
  if [[ "$CHECK_GSM" == "true" ]] || [[ "$FULL_CHECK" == "true" ]]; then
    check_gsm_secrets
  else
    log_info "Skipping GSM check (use --full or --check-gsm to enable)"
  fi

  # Check 4: oauth2-proxy configuration
  if [[ "$CHECK_OAUTH" == "true" ]] || [[ "$FULL_CHECK" == "true" ]]; then
    check_oauth_config
  else
    log_info "Skipping OAuth check (use --full or --check-oauth to enable)"
  fi

  # Check 5: E2E test infrastructure
  check_e2e_infrastructure

  # Summary
  echo
  echo "========================================="
  echo "Verification Summary"
  echo "========================================="
  echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
  echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
  echo -e "  ${YELLOW}Warnings: $WARN_COUNT${NC}"
  echo

  if [[ $FAIL_COUNT -gt 0 ]]; then
    log_fail "Verification FAILED - See issues above"
    return 1
  else
    log_pass "All checks passed!"
    return 0
  fi
}

check_allowed_emails() {
  echo "Check 1: Allowed Emails Whitelist"
  echo "-----------------------------------"

  if [[ ! -f "allowed-emails.txt" ]]; then
    log_fail "allowed-emails.txt not found"
    return 1
  fi

  if grep -q "^${QA_USER_EMAIL}$" allowed-emails.txt; then
    log_pass "$QA_USER_EMAIL is in allowed-emails.txt"
  else
    log_fail "$QA_USER_EMAIL NOT found in allowed-emails.txt"
    log_info "  Add to allowed-emails.txt: $QA_USER_EMAIL"
    return 1
  fi

  echo
}

check_env_schema() {
  echo "Check 2: Environment Schema Configuration"
  echo "-----------------------------------------"

  if [[ ! -f ".env.schema.json" ]]; then
    log_fail ".env.schema.json not found"
    return 1
  fi

  # Check for E2E_USER_EMAIL
  if grep -q '"E2E_USER_EMAIL"' .env.schema.json; then
    log_pass "E2E_USER_EMAIL defined in schema"
  else
    log_fail "E2E_USER_EMAIL NOT in schema"
  fi

  # Check for E2E_USER_PASSWORD
  if grep -q '"E2E_USER_PASSWORD"' .env.schema.json; then
    log_pass "E2E_USER_PASSWORD defined in schema"
  else
    log_fail "E2E_USER_PASSWORD NOT in schema"
  fi

  # Check for sensitive marking
  if grep -A 2 '"E2E_USER_PASSWORD"' .env.schema.json | grep -q '"secret": true'; then
    log_pass "E2E_USER_PASSWORD marked as sensitive"
  else
    log_warn "E2E_USER_PASSWORD may not be marked sensitive in schema"
  fi

  echo
}

check_gsm_secrets() {
  echo "Check 3: Google Secret Manager Secrets"
  echo "--------------------------------------"

  # Check gcloud availability
  if ! command -v gcloud &> /dev/null; then
    log_warn "gcloud CLI not available - skipping GSM checks"
    echo
    return 0
  fi

  # Check qa-user-email secret
  if gcloud secrets describe qa-user-email --project="$GCP_PROJECT" &> /dev/null; then
    log_pass "GSM secret 'qa-user-email' exists"
    local secret_value
    secret_value=$(gcloud secrets versions access latest --secret=qa-user-email --project="$GCP_PROJECT" 2>/dev/null || echo "")
    if [[ -n "$secret_value" && "$secret_value" == *"@"* ]]; then
      log_pass "  Value contains email format (expected)"
    else
      log_warn "  Value may not be properly set"
    fi
  else
    log_fail "GSM secret 'qa-user-email' NOT found"
  fi

  # Check qa-user-password secret
  if gcloud secrets describe qa-user-password --project="$GCP_PROJECT" &> /dev/null; then
    log_pass "GSM secret 'qa-user-password' exists"
    local pwd_value
    pwd_value=$(gcloud secrets versions access latest --secret=qa-user-password --project="$GCP_PROJECT" 2>/dev/null || echo "")
    if [[ "$pwd_value" == "PLACEHOLDER_SET_AFTER_GOOGLE_WORKSPACE_LOGIN" ]]; then
      log_warn "  Password is still placeholder - needs actual password set"
    elif [[ -z "$pwd_value" ]]; then
      log_warn "  Password value is empty"
    elif [[ ${#pwd_value} -lt 8 ]]; then
      log_fail "  Password appears too short (< 8 chars)"
    else
      log_pass "  Password is set and appears valid"
    fi
  else
    log_fail "GSM secret 'qa-user-password' NOT found"
  fi

  echo
}

check_oauth_config() {
  echo "Check 4: oauth2-proxy Configuration"
  echo "------------------------------------"

  # Check oauth2-proxy.cfg
  if [[ ! -f "oauth2-proxy.cfg" ]]; then
    log_fail "oauth2-proxy.cfg not found"
    return 1
  fi

  # Check email_domains configuration
  if grep -q "email_domains" oauth2-proxy.cfg; then
    log_pass "email_domains configured in oauth2-proxy.cfg"
  else
    log_warn "email_domains not explicitly configured (may use allowed emails list)"
  fi

  # Check allowed-emails reference
  if grep -q "allowed_emails_file\|allowed-emails" oauth2-proxy.cfg; then
    log_pass "oauth2-proxy.cfg references allowed emails configuration"
  else
    log_warn "oauth2-proxy.cfg may not reference allowed emails file"
  fi

  # Check docker-compose service
  if [[ -f "docker-compose.yml" ]]; then
    if grep -q "oauth2-proxy:" docker-compose.yml; then
      log_pass "oauth2-proxy service found in docker-compose.yml"
      
      # Check for volume mount of allowed-emails.txt
      if grep -A 10 "oauth2-proxy:" docker-compose.yml | grep -q "allowed-emails.txt"; then
        log_pass "allowed-emails.txt mounted in oauth2-proxy container"
      else
        log_warn "allowed-emails.txt mount not explicitly visible in config"
      fi
    else
      log_fail "oauth2-proxy service NOT in docker-compose.yml"
    fi
  fi

  echo
}

check_e2e_infrastructure() {
  echo "Check 5: E2E Test Infrastructure"
  echo "--------------------------------"

  # Check Playwright config
  if [[ -f "tests/e2e/playwright.config.ts" ]]; then
    log_pass "Playwright config exists (tests/e2e/playwright.config.ts)"
  else
    log_fail "Playwright config not found"
  fi

  # Check E2E test files
  local spec_count
  spec_count=$(find tests/e2e -name "*.spec.ts" 2>/dev/null | wc -l)
  if [[ $spec_count -gt 0 ]]; then
    log_pass "Found $spec_count E2E test spec files"
  else
    log_fail "No E2E test spec files found"
  fi

  # Check fixtures
  if [[ -f "tests/e2e/fixtures.ts" ]]; then
    if grep -q "E2E_USER_EMAIL\|E2E_USER_PASSWORD" tests/e2e/fixtures.ts; then
      log_pass "E2E fixtures configured with QA user environment variables"
    else
      log_warn "E2E fixtures may not reference QA user credentials"
    fi
  else
    log_warn "E2E fixtures file not found"
  fi

  # Check package.json test scripts
  if [[ -f "package.json" ]]; then
    if grep -q '"test"' package.json; then
      log_pass "Test scripts found in package.json"
    else
      log_warn "package.json may not have test scripts configured"
    fi
  fi

  echo
}

# Next steps summary
print_next_steps() {
  if [[ $FAIL_COUNT -eq 0 ]]; then
    echo "Next Steps for E2E Testing:"
    echo "1. Execute Issue #983 (QA user creation)"
    echo "   Reference: scripts/ops/create-qa-user-automated.sh"
    echo
    echo "2. Set QA password in GSM:"
    echo "   gcloud secrets versions add qa-user-password --data-file=- --project=$GCP_PROJECT < <(echo -n 'PASSWORD_HERE')"
    echo
    echo "3. Restart oauth2-proxy:"
    echo "   docker compose restart oauth2-proxy"
    echo
    echo "4. Run E2E tests:"
    echo "   npm test --cwd tests/e2e"
    echo
    echo "5. Verify results:"
    echo "   Reference: E2E-TEST-EXECUTION-GUIDE.md"
  fi
}

# Run main
if main; then
  print_next_steps
  exit 0
else
  echo "See failures above - resolve before proceeding to E2E testing"
  exit 1
fi
