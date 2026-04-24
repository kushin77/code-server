#!/usr/bin/env bash
# @file        scripts/ci/run-playwright-failover-continuity.sh
# @module      ci/e2e
# @description Run authenticated Playwright continuity checks across a failover window.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

E2E_DIR="${E2E_DIR:-tests/e2e}"
PLAYWRIGHT_STORAGE_STATE="${PLAYWRIGHT_STORAGE_STATE:-}"
FAILOVER_WAIT_MS="${FAILOVER_WAIT_MS:-45000}"
APEX_DOMAIN="${APEX_DOMAIN:-localhost}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"
TEST_BASE_URL="${TEST_BASE_URL:-https://${IDE_DOMAIN}}"
EXPECTED_BASE_HOST="${EXPECTED_BASE_HOST:-${IDE_DOMAIN}}"
FAILOVER_TRIGGER_CMD="${FAILOVER_TRIGGER_CMD:-}"
CONTINUITY_MODE="${CONTINUITY_MODE:-auth}"
DETERMINISTIC_E2E_RUNNER="$SCRIPT_DIR/run-deterministic-e2e-suite.sh"
DEFAULT_FLAKE_SIGNATURES_FILE="$SCRIPT_DIR/../../config/test-flake-signatures.json"
FLAKE_SIGNATURES_FILE="${E2E_FLAKE_SIGNATURES_FILE:-$DEFAULT_FLAKE_SIGNATURES_FILE}"

resolve_node_command() {
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  return 1
}

# shellcheck disable=SC2034
NODE_CMD="$(resolve_node_command || true)"

resolve_npx_command() {
  if command -v npx >/dev/null 2>&1; then
    command -v npx
    return 0
  fi
  return 1
}

NPX_CMD="$(resolve_npx_command || true)"

if [[ "$CONTINUITY_MODE" == "auth" ]]; then
  if [[ -z "$PLAYWRIGHT_STORAGE_STATE" ]]; then
    log_fatal "PLAYWRIGHT_STORAGE_STATE is required when CONTINUITY_MODE=auth"
  fi
  require_file "$PLAYWRIGHT_STORAGE_STATE"
elif [[ "$CONTINUITY_MODE" != "unauth" ]]; then
  log_fatal "Unsupported CONTINUITY_MODE='$CONTINUITY_MODE' (use 'auth' or 'unauth')"
fi

log_info "Preparing deterministic Playwright kit"
bash "$SCRIPT_DIR/setup-e2e-playwright.sh"
require_file "$FLAKE_SIGNATURES_FILE"

mkdir -p "$E2E_DIR/specs"

if [[ "$CONTINUITY_MODE" == "auth" ]]; then
cat > "$E2E_DIR/specs/failover-session-continuity.spec.ts" << 'EOF'
import { test, expect } from '@playwright/test';

const waitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');

test('authenticated session continuity across failover window', async ({ browser }) => {
  const context = await browser.newContext({
    storageState: process.env.PLAYWRIGHT_STORAGE_STATE,
  });
  const page = await context.newPage();

  await page.goto('/');
  await expect(page).not.toHaveURL(/oauth2|accounts\.google\.com/);

  await page.waitForTimeout(waitMs);
  await page.reload({ waitUntil: 'domcontentloaded' });

  await expect(page).not.toHaveURL(/oauth2|accounts\.google\.com/);

  await context.close();
});
EOF
else
cat > "$E2E_DIR/specs/failover-session-continuity.spec.ts" << 'EOF'
import { test, expect } from '@playwright/test';

const waitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');
const expectedBaseHost = process.env.EXPECTED_BASE_HOST || '';

test('unauthenticated continuity across failover window', async ({ page }) => {
  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(response).not.toBeNull();
  expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(response?.status() || 0);
  expect(page.url()).toContain(expectedBaseHost);

  await page.waitForTimeout(waitMs);
  const reloadResponse = await page.reload({ waitUntil: 'domcontentloaded' });
  expect(reloadResponse).not.toBeNull();
  expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(reloadResponse?.status() || 0);
  expect(page.url()).toContain(expectedBaseHost);
});
EOF
fi

if [[ -n "$FAILOVER_TRIGGER_CMD" ]]; then
  log_info "Executing failover trigger command in background"
  bash -lc "$FAILOVER_TRIGGER_CMD" &
fi

log_info "Running failover continuity test against $TEST_BASE_URL"
if [[ -n "$NPX_CMD" ]]; then
  (
    cd "$E2E_DIR"
    TEST_BASE_URL="$TEST_BASE_URL" \
    EXPECTED_BASE_HOST="$EXPECTED_BASE_HOST" \
    FAILOVER_WAIT_MS="$FAILOVER_WAIT_MS" \
    CONTINUITY_MODE="$CONTINUITY_MODE" \
    PLAYWRIGHT_STORAGE_STATE="$PLAYWRIGHT_STORAGE_STATE" \
    E2E_FLAKE_SIGNATURES_FILE="$FLAKE_SIGNATURES_FILE" \
    E2E_FLAKE_OUTPUT_DIR="${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}" \
    "$DETERMINISTIC_E2E_RUNNER" --suite-name "failover-continuity" --output-dir "${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}" -- "$NPX_CMD" playwright test specs/failover-session-continuity.spec.ts
  )
else
  log_fatal "npx is not available. Ensure Node.js 18+ is installed or WSL Node.js is configured in PATH. (Linux-native mandate enforced—PowerShell fallback removed per #885)"
fi

log_info "Playwright failover continuity test completed"