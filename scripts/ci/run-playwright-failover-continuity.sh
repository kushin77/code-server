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
TEST_BASE_URL="${TEST_BASE_URL:-https://ide.kushnir.cloud}"
FAILOVER_TRIGGER_CMD="${FAILOVER_TRIGGER_CMD:-}"
CONTINUITY_MODE="${CONTINUITY_MODE:-auth}"

if [[ "$CONTINUITY_MODE" == "auth" ]]; then
  if [[ -z "$PLAYWRIGHT_STORAGE_STATE" ]]; then
    log_fatal "PLAYWRIGHT_STORAGE_STATE is required when CONTINUITY_MODE=auth"
  fi
  require_file "$PLAYWRIGHT_STORAGE_STATE"
elif [[ "$CONTINUITY_MODE" != "unauth" ]]; then
  log_fatal "Unsupported CONTINUITY_MODE='$CONTINUITY_MODE' (use 'auth' or 'unauth')"
fi

require_command "node" "Node.js is required for Playwright"

log_info "Preparing deterministic Playwright kit"
bash "$SCRIPT_DIR/setup-e2e-playwright.sh"

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

test('unauthenticated continuity across failover window', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/oauth2|accounts\.google\.com/);

  await page.waitForTimeout(waitMs);
  await page.goto('/');
  await expect(page).toHaveURL(/oauth2|accounts\.google\.com/);
});
EOF
fi

if [[ -n "$FAILOVER_TRIGGER_CMD" ]]; then
  log_info "Executing failover trigger command in background"
  bash -lc "$FAILOVER_TRIGGER_CMD" &
fi

log_info "Running failover continuity test against $TEST_BASE_URL"
(
  cd "$E2E_DIR"
  TEST_BASE_URL="$TEST_BASE_URL" \
  FAILOVER_WAIT_MS="$FAILOVER_WAIT_MS" \
  CONTINUITY_MODE="$CONTINUITY_MODE" \
  PLAYWRIGHT_STORAGE_STATE="$PLAYWRIGHT_STORAGE_STATE" \
  npx playwright test specs/failover-session-continuity.spec.ts
)

log_info "Playwright failover continuity test completed"