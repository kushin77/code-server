#!/usr/bin/env bash
# @file        scripts/ci/capture-playwright-storage-state.sh
# @module      ci/e2e
# @description Capture authenticated Playwright storage state from E2E service account credentials.
#              Authenticates to TARGET_URL using provided credentials and saves browser context
#              storage state to a JSON file for use in non-interactive test runs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Environment inputs (can be set by caller)
E2E_DIR="${E2E_DIR:-tests/e2e}"
TARGET_URL="${TARGET_URL:-https://ide.kushnir.cloud}"
E2E_USER_EMAIL="${E2E_USER_EMAIL:-}"
E2E_USER_PASSWORD="${E2E_USER_PASSWORD:-}"
E2E_OAUTH_TOKEN="${E2E_OAUTH_TOKEN:-}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/playwright-storage-state.json}"
HEADLESS="${HEADLESS:-true}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ci/capture-playwright-storage-state.sh [OPTIONS]

Environment variables:
  TARGET_URL              URL to authenticate to (default: https://ide.kushnir.cloud)
  E2E_USER_EMAIL          E2E service account email (required for password auth)
  E2E_USER_PASSWORD       E2E service account password (required for password auth)
  E2E_OAUTH_TOKEN         OAuth token for E2E account (alternative to email/password)
  OUTPUT_FILE             Where to save storage state JSON (default: /tmp/playwright-storage-state.json)
  HEADLESS                Run in headless mode (default: true)

Example (password-based):
  E2E_USER_EMAIL=e2e@example.com \
  E2E_USER_PASSWORD=secret123 \
  bash scripts/ci/capture-playwright-storage-state.sh

Example (OAuth token-based):
  E2E_OAUTH_TOKEN=ya29.a0...token... \
  bash scripts/ci/capture-playwright-storage-state.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Validate inputs
if [[ -z "$E2E_OAUTH_TOKEN" && ( -z "$E2E_USER_EMAIL" || -z "$E2E_USER_PASSWORD" ) ]]; then
  log_fatal "Either E2E_OAUTH_TOKEN or both E2E_USER_EMAIL and E2E_USER_PASSWORD must be set"
fi

# Ensure Node.js and Playwright are available
require_command "node" "Node.js is required"

log_info "Setting up Playwright kit for storage state capture"
bash "$SCRIPT_DIR/setup-e2e-playwright.sh"

# Create a temporary capture script inside E2E_DIR so local node_modules are visible
CAPTURE_SCRIPT="$(cd "$E2E_DIR" && mktemp "$PWD/capture.XXXXXX.mjs")"
trap "rm -f $CAPTURE_SCRIPT" EXIT

log_info "Generating Playwright capture script"
cat > "$CAPTURE_SCRIPT" << 'PLAYWRIGHT_SCRIPT'
import { chromium } from '@playwright/test';

async function captureStorageState() {
  const targetUrl = process.env.TARGET_URL || 'https://ide.kushnir.cloud';
  const userEmail = process.env.E2E_USER_EMAIL || '';
  const userPassword = process.env.E2E_USER_PASSWORD || '';
  const oauthToken = process.env.E2E_OAUTH_TOKEN || '';
  const outputFile = process.env.OUTPUT_FILE || '/tmp/playwright-storage-state.json';
  const headless = process.env.HEADLESS !== 'false';

  const browser = await chromium.launch({ headless });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    console.log(`[capture] Navigating to ${targetUrl}/oauth2/start?rd=/`);
    await page.goto(`${targetUrl}/oauth2/start?rd=/`, { waitUntil: 'networkidle' });

    const currentUrl = page.url();
    console.log(`[capture] Current URL: ${currentUrl}`);

    // Check if we're at OAuth login or already authenticated
    const isAtLoginFlow = currentUrl.includes('oauth2') || currentUrl.includes('accounts.google.com');

    if (isAtLoginFlow && userEmail && userPassword) {
      console.log(`[capture] Authenticating with email: ${userEmail}`);
      
      // This is a simplified password auth flow; adjust selectors based on actual OAuth form
      // For Google OAuth, the flow may vary; this is a template pattern
      try {
        await page.fill('input[type="email"]', userEmail, { timeout: 5000 });
        await page.press('input[type="email"]', 'Enter');
        await page.waitForNavigation({ waitUntil: 'networkidle', timeout: 10000 });
        
        await page.fill('input[type="password"]', userPassword, { timeout: 5000 });
        await page.press('input[type="password"]', 'Enter');
        await page.waitForNavigation({ waitUntil: 'networkidle', timeout: 10000 });
      } catch (err) {
        console.warn(`[capture] Standard OAuth form not found; may already be authenticated. Error: ${err}`);
      }
    } else if (isAtLoginFlow && oauthToken) {
      console.warn('[capture] OAuth token provided but browser-based OAuth flow cannot be skipped with token');
      console.warn('[capture] Token-based auth requires backend/API-level setup, not browser automation');
    }

    // Wait for redirect back to app
    await page.waitForURL(targetUrl + '/**', { timeout: 30000 });
    console.log(`[capture] Redirected to app; capturing storage state`);

    // Capture storage state
    const storageState = await context.storageState();
    const fs = await import('fs');
    fs.writeFileSync(outputFile, JSON.stringify(storageState, null, 2));
    console.log(`[capture] Storage state saved to: ${outputFile}`);

  } catch (error) {
    console.error(`[capture] Error during authentication: ${error}`);
    throw error;
  } finally {
    await context.close();
    await browser.close();
  }
}

captureStorageState().catch(err => {
  console.error('[capture] Fatal error:', err);
  process.exit(1);
});
PLAYWRIGHT_SCRIPT

log_info "Compiling and running capture script"

(
  cd "$E2E_DIR"

  export TARGET_URL
  export E2E_USER_EMAIL
  export E2E_USER_PASSWORD
  export E2E_OAUTH_TOKEN
  export OUTPUT_FILE
  export HEADLESS

  node "$CAPTURE_SCRIPT"
)

if [[ ! -f "$OUTPUT_FILE" ]]; then
  log_fatal "Storage state capture failed; output file not created at $OUTPUT_FILE"
fi

log_info "Storage state captured successfully"
log_info "Next: encode with prepare-playwright-storage-state.sh"
log_info "  bash scripts/ci/prepare-playwright-storage-state.sh $OUTPUT_FILE"
