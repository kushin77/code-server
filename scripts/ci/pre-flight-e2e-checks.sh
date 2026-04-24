#!/usr/bin/env bash
# @file        scripts/ci/pre-flight-e2e-checks.sh
# @module      ci/e2e-testing
# @description Pre-flight validation for E2E test execution (Issues #986-990 readiness)
# @owner       qa-team
# @status      Ready for immediate use
#
# Purpose: Verify all prerequisites are met before running E2E tests
#
# Usage:
#   bash scripts/ci/pre-flight-e2e-checks.sh
#   bash scripts/ci/pre-flight-e2e-checks.sh --strict (fail on any warning)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
STRICT_MODE="${STRICT_MODE:-false}"
CHECK_NETWORK="${CHECK_NETWORK:-true}"
CHECK_VPN="${CHECK_VPN:-false}"  # Optional, depends on deployment
QUIET="${QUIET:-false}"

# Test configuration
TEST_BASE_URL="${TEST_BASE_URL:-https://kushnir.cloud}"
E2E_USER_EMAIL="${E2E_USER_EMAIL:-}"
E2E_USER_PASSWORD="${E2E_USER_PASSWORD:-}"

# Tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m'

log_pass() {
  [[ "$QUIET" == "true" ]] && return 0
  echo -e "${GREEN}[✓]${NC} $1"
  ((PASS_COUNT++))
}

log_fail() {
  [[ "$QUIET" == "true" ]] || echo -e "${RED}[✗]${NC} $1"
  ((FAIL_COUNT++))
}

log_warn() {
  [[ "$QUIET" == "true" ]] || echo -e "${YELLOW}[!]${NC} $1"
  ((WARN_COUNT++))
}

log_skip() {
  [[ "$QUIET" == "true" ]] || echo -e "${GRAY}[↷]${NC} $1"
  ((SKIP_COUNT++))
}

log_info() {
  [[ "$QUIET" == "true" ]] || echo -e "${BLUE}[i]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict)
      STRICT_MODE="true"
      shift
      ;;
    --no-network)
      CHECK_NETWORK="false"
      shift
      ;;
    --check-vpn)
      CHECK_VPN="true"
      shift
      ;;
    --quiet)
      QUIET="true"
      shift
      ;;
    *)
      log_fail "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Main preflight checks
main() {
  if [[ "$QUIET" != "true" ]]; then
    echo "========================================="
    echo "E2E Test Preflight Checks"
    echo "========================================="
    echo "Test URL: $TEST_BASE_URL"
    echo
  fi

  # Category 1: Node.js and npm
  check_nodejs_environment

  # Category 2: Dependencies
  check_dependencies

  # Category 3: Test files and configuration
  check_test_files

  # Category 4: Environment variables
  check_environment_variables

  # Category 5: Network connectivity
  if [[ "$CHECK_NETWORK" == "true" ]]; then
    check_network_connectivity
  fi

  # Category 6: VPN connectivity (optional)
  if [[ "$CHECK_VPN" == "true" ]]; then
    check_vpn_connectivity
  fi

  # Category 7: Storage and disk space
  check_storage

  # Summary
  if [[ "$QUIET" != "true" ]]; then
    print_summary
  fi

  # Exit code
  if [[ $FAIL_COUNT -gt 0 ]]; then
    return 1
  elif [[ $WARN_COUNT -gt 0 ]] && [[ "$STRICT_MODE" == "true" ]]; then
    return 1
  else
    return 0
  fi
}

check_nodejs_environment() {
  [[ "$QUIET" != "true" ]] && echo "1. Node.js Environment"
  [[ "$QUIET" != "true" ]] && echo "----------------------"

  # Check Node.js
  if command -v node &> /dev/null; then
    local node_version
    node_version=$(node --version)
    log_pass "Node.js available: $node_version"
  else
    log_fail "Node.js not found - Required for Playwright"
    return 1
  fi

  # Check npm
  if command -v npm &> /dev/null; then
    local npm_version
    npm_version=$(npm --version)
    log_pass "npm available: $npm_version"
  else
    log_fail "npm not found - Required for test execution"
    return 1
  fi

  # Check npm scripts
  if [[ -f "package.json" ]]; then
    if grep -q '"test"' package.json; then
      log_pass "Test script defined in package.json"
    else
      log_warn "Test script not found in package.json"
    fi
  else
    log_fail "package.json not found"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_dependencies() {
  [[ "$QUIET" != "true" ]] && echo "2. Required Dependencies"
  [[ "$QUIET" != "true" ]] && echo "------------------------"

  # Check node_modules exists
  if [[ -d "node_modules" ]]; then
    log_pass "node_modules directory exists"
  else
    log_warn "node_modules not found - Run 'npm install' before tests"
  fi

  # Check Playwright
  if [[ -d "node_modules/@playwright" ]]; then
    log_pass "Playwright dependencies installed"
  else
    log_warn "Playwright not installed - Run 'npm install' first"
  fi

  # Check test spec files
  local spec_count
  spec_count=$(find tests/e2e/specs -name "*.spec.ts" 2>/dev/null | wc -l)
  if [[ $spec_count -gt 0 ]]; then
    log_pass "Found $spec_count E2E test spec files"
  else
    log_fail "No test spec files found in tests/e2e/specs/"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_test_files() {
  [[ "$QUIET" != "true" ]] && echo "3. Test Files and Configuration"
  [[ "$QUIET" != "true" ]] && echo "-------------------------------"

  # Check playwright.config.ts
  if [[ -f "tests/e2e/playwright.config.ts" ]]; then
    log_pass "Playwright config exists"
  else
    log_fail "playwright.config.ts not found"
  fi

  # Check fixtures
  if [[ -f "tests/e2e/fixtures.ts" ]]; then
    log_pass "Test fixtures defined"
  else
    log_warn "fixtures.ts not found - shared test setup may not work"
  fi

  # Check artifacts directory
  if [[ ! -d "artifacts" ]]; then
    log_warn "artifacts/ directory does not exist - will be created on test run"
  else
    log_pass "artifacts/ directory exists"
  fi

  # Check playwright-report
  if [[ -d "artifacts/playwright-report" ]]; then
    log_info "Previous playwright report found - will be overwritten"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_environment_variables() {
  [[ "$QUIET" != "true" ]] && echo "4. Environment Variables"
  [[ "$QUIET" != "true" ]] && echo "------------------------"

  # Check TEST_BASE_URL
  if [[ -n "$TEST_BASE_URL" ]]; then
    log_pass "TEST_BASE_URL set: $TEST_BASE_URL"
  else
    log_warn "TEST_BASE_URL not set - Will use default: https://kushnir.cloud"
  fi

  # Check E2E credentials
  if [[ -n "$E2E_USER_EMAIL" ]]; then
    log_pass "E2E_USER_EMAIL set (length: ${#E2E_USER_EMAIL})"
  else
    log_warn "E2E_USER_EMAIL not set - OAuth tests will be skipped or fail"
  fi

  if [[ -n "$E2E_USER_PASSWORD" ]]; then
    log_pass "E2E_USER_PASSWORD set (length: ${#E2E_USER_PASSWORD})"
  else
    log_warn "E2E_USER_PASSWORD not set - Authenticated tests will be skipped"
  fi

  # Check PLAYWRIGHT_WORKERS
  if [[ -n "${PLAYWRIGHT_WORKERS:-}" ]]; then
    log_pass "PLAYWRIGHT_WORKERS set: $PLAYWRIGHT_WORKERS"
  else
    log_info "PLAYWRIGHT_WORKERS not set - Will use default: 1"
  fi

  # Check CI environment
  if [[ -n "${CI:-}" ]]; then
    log_pass "Running in CI environment"
  else
    log_info "Running in local/development environment"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_network_connectivity() {
  [[ "$QUIET" != "true" ]] && echo "5. Network Connectivity"
  [[ "$QUIET" != "true" ]] && echo "-----------------------"

  # Check DNS resolution
  if command -v nslookup &> /dev/null; then
    local domain
    domain=$(echo "$TEST_BASE_URL" | sed -E 's|https?://([^/]+).*|\1|')
    if nslookup "$domain" &> /dev/null; then
      log_pass "DNS resolution works: $domain"
    else
      log_fail "Cannot resolve domain: $domain"
    fi
  else
    log_skip "nslookup not available - skipping DNS check"
  fi

  # Check HTTPS connectivity
  if command -v curl &> /dev/null; then
    if curl -s -I --connect-timeout 5 "$TEST_BASE_URL" > /dev/null 2>&1; then
      log_pass "HTTPS connectivity OK: $TEST_BASE_URL"
    else
      log_fail "Cannot reach test URL: $TEST_BASE_URL"
    fi
  else
    log_skip "curl not available - skipping connectivity check"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_vpn_connectivity() {
  [[ "$QUIET" != "true" ]] && echo "6. VPN Connectivity (Optional)"
  [[ "$QUIET" != "true" ]] && echo "------------------------------"

  # Check if on production network
  if [[ "$TEST_BASE_URL" == *"kushnir.cloud"* ]]; then
    if command -v ping &> /dev/null; then
      if ping -c 1 -W 2 192.168.168.31 &> /dev/null; then
        log_pass "Production network reachable (192.168.168.31)"
      else
        log_warn "Production network not reachable - E2E tests may fail"
        log_info "  Ensure VPN is connected to 192.168.168.0/24"
      fi
    else
      log_skip "ping not available - cannot check VPN"
    fi
  else
    log_skip "Not production URL - skipping VPN check"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

check_storage() {
  [[ "$QUIET" != "true" ]] && echo "7. Storage and Disk Space"
  [[ "$QUIET" != "true" ]] && echo "--------------------------"

  # Check available disk space
  if command -v df &> /dev/null; then
    local available_kb
    available_kb=$(df "$(pwd)" | awk 'NR==2 {print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    
    if [[ $available_gb -gt 1 ]]; then
      log_pass "Disk space available: ${available_gb}GB"
    else
      log_warn "Low disk space: ${available_gb}GB (need at least 1GB for test artifacts)"
    fi
  else
    log_skip "df not available - cannot check disk space"
  fi

  # Check test artifacts directory
  if [[ -d "artifacts" ]]; then
    local artifacts_size
    artifacts_size=$(du -sh artifacts 2>/dev/null | awk '{print $1}')
    log_info "Artifacts directory size: $artifacts_size"
  fi

  [[ "$QUIET" != "true" ]] && echo
}

print_summary() {
  echo "========================================="
  echo "Preflight Check Summary"
  echo "========================================="
  echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
  echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
  echo -e "  ${YELLOW}Warnings: $WARN_COUNT${NC}"
  echo -e "  ${GRAY}Skipped: $SKIP_COUNT${NC}"
  echo

  if [[ $FAIL_COUNT -eq 0 ]]; then
    if [[ $WARN_COUNT -eq 0 ]]; then
      log_pass "All checks passed - Ready for E2E testing!"
    else
      log_warn "Some warnings found - Tests may fail"
    fi
  else
    log_fail "Failed checks - Please fix issues before running tests"
  fi

  echo
  echo "Next Steps:"
  if [[ -z "$E2E_USER_EMAIL" ]] || [[ -z "$E2E_USER_PASSWORD" ]]; then
    echo "1. Set E2E credentials from GSM:"
    echo "   source scripts/fetch-gsm-secrets.sh"
    echo
  fi

  if [[ ! -d "node_modules" ]]; then
    echo "1. Install dependencies:"
    echo "   npm install"
    echo
  fi

  echo "2. Run E2E tests:"
  echo "   npm test --cwd tests/e2e"
  echo
  echo "3. View results:"
  echo "   open artifacts/playwright-report/index.html"
  echo
}

# Run main
if main; then
  exit 0
else
  exit 1
fi
