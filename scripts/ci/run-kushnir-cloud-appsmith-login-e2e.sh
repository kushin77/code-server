#!/usr/bin/env bash
# @file        scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh
# @module      ci/e2e
# @description Run VPN-gated Playwright smoke tests for Appsmith login and auth redirects
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

APEX_DOMAIN="${APEX_DOMAIN:-localhost}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://${APEX_DOMAIN}}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
IDE_BASE_URL="${IDE_BASE_URL:-https://${IDE_DOMAIN}}"
APPSMITH_EXPECTED_REDIRECT_URI="${APPSMITH_EXPECTED_REDIRECT_URI:-${PORTAL_BASE_URL}/login/oauth2/code/github}"
TEST_SPEC="${TEST_SPEC:-tests/e2e/specs/kushnir-cloud-appsmith-login.spec.ts}"
E2E_DIR="${E2E_DIR:-tests/e2e}"
REQUIRE_VPN="${REQUIRE_VPN:-1}"
REQUIRE_QA_STORAGE_STATE="${REQUIRE_QA_STORAGE_STATE:-1}"
REQUIRE_SINGLE_LOGIN="${REQUIRE_SINGLE_LOGIN:-1}"
DETERMINISTIC_E2E_RUNNER="$SCRIPT_DIR/run-deterministic-e2e-suite.sh"

require_dir "$E2E_DIR"
require_file "$TEST_SPEC"
require_file "$E2E_DIR/playwright.config.ts"

run_playwright_tests() {
  local npx_cmd

  npx_cmd="$(command -v npx 2>/dev/null || true)"

  if [[ -n "$npx_cmd" ]]; then
    env PORTAL_BASE_URL="$PORTAL_BASE_URL" IDE_BASE_URL="$IDE_BASE_URL" APPSMITH_EXPECTED_REDIRECT_URI="$APPSMITH_EXPECTED_REDIRECT_URI" REQUIRE_SINGLE_LOGIN="$REQUIRE_SINGLE_LOGIN" TEST_BASE_URL="$PORTAL_BASE_URL" E2E_FLAKE_OUTPUT_DIR="${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}" "$DETERMINISTIC_E2E_RUNNER" --suite-name "appsmith-login" --output-dir "${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}" -- "$npx_cmd" playwright test --config "$E2E_DIR/playwright.config.ts" "$TEST_SPEC"
    return 0
  fi

  log_fatal "npx is not available. Ensure Node.js 18+ is installed."
}

if [[ "$REQUIRE_VPN" == "1" ]]; then
  if [[ -f "scripts/ci/check-vpn-gate.sh" ]]; then
    log_info "Validating VPN gate before running production login E2E"
    bash scripts/ci/check-vpn-gate.sh
  else
    log_fatal "VPN gate script not found: scripts/ci/check-vpn-gate.sh"
  fi
fi

if [[ "$REQUIRE_QA_STORAGE_STATE" == "1" && -z "${PLAYWRIGHT_STORAGE_STATE:-}" ]]; then
  log_fatal "PLAYWRIGHT_STORAGE_STATE is required for QA-authenticated checks"
fi

log_info "Running Appsmith login tests"
log_info "Portal: $PORTAL_BASE_URL"
log_info "IDE: $IDE_BASE_URL"
log_info "Appsmith expected redirect URI: $APPSMITH_EXPECTED_REDIRECT_URI"
log_info "Require single-login sentinel: $REQUIRE_SINGLE_LOGIN"

run_playwright_tests

log_info "Appsmith login E2E finished"
