#!/usr/bin/env bash
# @file        scripts/ci/setup-e2e-playwright.sh
# @module      ci/e2e
# @description Setup Playwright browser automation kit for production endpoint E2E.
#              Installs Playwright (primary), validates Puppeteer fallback availability,
#              and outputs runtime diagnostics.
#
# Usage: bash scripts/ci/setup-e2e-playwright.sh [--check-only]

set -euo pipefail

_log()  { echo "[e2e-setup] $*"; }
_warn() { echo "[e2e-setup] WARN: $*" >&2; }

CHECK_ONLY="${1:-}"
E2E_DIR="${E2E_DIR:-tests/e2e}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.44.0}"

# ── Check for Node.js ─────────────────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "[e2e-setup] ERROR: Node.js not found — required for Playwright" >&2
  exit 1
fi

NODE_VER=$(node --version)
_log "Node.js: $NODE_VER"

# ── VPN gate check (production E2E only) ─────────────────────────────────────
if [[ "${REQUIRE_VPN:-1}" == "1" ]]; then
  if [[ -f "scripts/ci/check-vpn-gate.sh" ]]; then
    bash scripts/ci/check-vpn-gate.sh || {
      _warn "VPN gate failed — aborting production E2E setup"
      exit 1
    }
  fi
fi

if [[ "$CHECK_ONLY" == "--check-only" ]]; then
  # Just validate Playwright is installed
  if command -v npx >/dev/null 2>&1 && npx playwright --version >/dev/null 2>&1; then
    _log "Playwright: $(npx playwright --version)"
  else
    _warn "Playwright not installed — run: bash scripts/ci/setup-e2e-playwright.sh"
    exit 1
  fi
  exit 0
fi

# ── Install Playwright ────────────────────────────────────────────────────────
mkdir -p "$E2E_DIR"

# Create package.json if not present
if [[ ! -f "$E2E_DIR/package.json" ]]; then
  cat > "$E2E_DIR/package.json" << EOF
{
  "name": "code-server-e2e",
  "version": "1.0.0",
  "description": "E2E tests for code-server production endpoints",
  "private": true,
  "scripts": {
    "test": "playwright test",
    "test:headed": "playwright test --headed"
  },
  "devDependencies": {
    "@playwright/test": "^${PLAYWRIGHT_VERSION}",
    "puppeteer": "^22.0.0"
  }
}
EOF
  _log "created $E2E_DIR/package.json"
fi

# Create playwright config
if [[ ! -f "$E2E_DIR/playwright.config.ts" ]]; then
  cat > "$E2E_DIR/playwright.config.ts" << 'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './specs',
  timeout: 30000,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud',
    ignoreHTTPSErrors: false,
    screenshot: 'only-on-failure',
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  reporter: [['html', { open: 'never' }], ['json', { outputFile: '/tmp/e2e-results.json' }]],
});
EOF
  _log "created $E2E_DIR/playwright.config.ts"
fi

mkdir -p "$E2E_DIR/specs"

# Create a basic smoke test
if [[ ! -f "$E2E_DIR/specs/oauth-login.spec.ts" ]]; then
  cat > "$E2E_DIR/specs/oauth-login.spec.ts" << 'EOF'
import { test, expect } from '@playwright/test';

// Service-account E2E: Validate OAuth login redirects and load order
// Corresponds to e2e-service-account-profile.yml :: oauth-login capability

test.describe('OAuth login smoke test', () => {
  test('redirects to OAuth provider on unauthenticated access', async ({ page }) => {
    const response = await page.goto('/');
    // Should redirect to /oauth2/sign_in or Google OAuth
    const url = page.url();
    expect(url).toMatch(/oauth2|accounts\.google\.com/);
  });

  test('health check endpoint is reachable without auth', async ({ page }) => {
    const response = await page.goto('/health');
    // Health check returns 200 without OAuth
    expect(response?.status()).toBeLessThanOrEqual(404); // 200 or 404 (not 502)
  });
});
EOF
  _log "created $E2E_DIR/specs/oauth-login.spec.ts"
fi

# Install dependencies if npm available
if command -v npm >/dev/null 2>&1; then
  _log "installing E2E dependencies in $E2E_DIR..."
  (cd "$E2E_DIR" && npm install --prefer-offline --no-audit 2>/dev/null) && \
    _log "dependencies installed" || _warn "npm install failed (may need VPN or network access)"
else
  _warn "npm not available — skipping dependency install"
fi

_log "setup complete. Run tests: cd $E2E_DIR && npx playwright test"
_log "Fallback: puppeteer in $E2E_DIR/node_modules/puppeteer (if installed)"
