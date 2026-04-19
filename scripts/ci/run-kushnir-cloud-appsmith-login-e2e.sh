#!/usr/bin/env bash
# @file        scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh
# @module      ci/e2e
# @description Run VPN-gated Playwright smoke tests for kushnir.cloud Appsmith login and auth redirects
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Git Bash on Windows may not inherit Node.js PATH from PowerShell.
if ! command -v node >/dev/null 2>&1; then
  if [[ -x "/c/Program Files/nodejs/node.exe" ]]; then
    node() { "/c/Program Files/nodejs/node.exe" "$@"; }
    npx() { cmd.exe //c npx "$@"; }
  elif [[ -x "/mnt/c/Program Files/nodejs/node.exe" ]]; then
    node() { "/mnt/c/Program Files/nodejs/node.exe" "$@"; }
    npx() { cmd.exe //c npx "$@"; }
  fi
fi

PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://kushnir.cloud}"
IDE_BASE_URL="${IDE_BASE_URL:-https://ide.kushnir.cloud}"
APPSMITH_EXPECTED_REDIRECT_URI="${APPSMITH_EXPECTED_REDIRECT_URI:-${PORTAL_BASE_URL}/login/oauth2/code/google}"
TEST_SPEC="${TEST_SPEC:-tests/e2e/specs/kushnir-cloud-appsmith-login.spec.ts}"
E2E_DIR="${E2E_DIR:-tests/e2e}"
REQUIRE_VPN="${REQUIRE_VPN:-1}"
REQUIRE_QA_STORAGE_STATE="${REQUIRE_QA_STORAGE_STATE:-1}"
REQUIRE_SINGLE_LOGIN="${REQUIRE_SINGLE_LOGIN:-1}"

require_command "node" "node is required"
require_command "npx" "npx is required"
require_dir "$E2E_DIR"
require_file "$TEST_SPEC"
require_file "$E2E_DIR/playwright.config.ts"

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

log_info "Running kushnir.cloud Appsmith login tests"
log_info "Portal: $PORTAL_BASE_URL"
log_info "IDE: $IDE_BASE_URL"
log_info "Appsmith expected redirect URI: $APPSMITH_EXPECTED_REDIRECT_URI"
log_info "Require single-login sentinel: $REQUIRE_SINGLE_LOGIN"

env PORTAL_BASE_URL="$PORTAL_BASE_URL" IDE_BASE_URL="$IDE_BASE_URL" APPSMITH_EXPECTED_REDIRECT_URI="$APPSMITH_EXPECTED_REDIRECT_URI" REQUIRE_SINGLE_LOGIN="$REQUIRE_SINGLE_LOGIN" TEST_BASE_URL="$PORTAL_BASE_URL" npx playwright test --config "$E2E_DIR/playwright.config.ts" "$TEST_SPEC"

log_info "kushnir.cloud Appsmith login E2E finished"
