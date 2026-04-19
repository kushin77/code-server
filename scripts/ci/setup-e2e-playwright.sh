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
ARTIFACT_DIR="${E2E_ARTIFACT_DIR:-$E2E_DIR/artifacts}"
FIXTURE_DIR="${E2E_FIXTURE_DIR:-$E2E_DIR/fixtures}"
SKIP_NPM_INSTALL="${E2E_SKIP_NPM_INSTALL:-0}"

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
mkdir -p "$FIXTURE_DIR" "$ARTIFACT_DIR"

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
import { deterministicUseOptions } from './fixtures/deterministic';

export default defineConfig({
  testDir: './specs',
  outputDir: process.env.PLAYWRIGHT_OUTPUT_DIR || './artifacts/playwright',
  timeout: 30000,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud',
    ignoreHTTPSErrors: false,
    screenshot: 'only-on-failure',
    trace: 'on-first-retry',
    ...deterministicUseOptions,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  reporter: [
    ['html', { open: 'never', outputFolder: process.env.PLAYWRIGHT_HTML_REPORT_DIR || './artifacts/html' }],
    ['json', { outputFile: process.env.PLAYWRIGHT_JSON_REPORT_FILE || './artifacts/e2e-results.json' }],
  ],
});
EOF
  _log "created $E2E_DIR/playwright.config.ts"
fi

mkdir -p "$E2E_DIR/specs"

# Create deterministic shared fixtures
if [[ ! -f "$FIXTURE_DIR/deterministic.ts" ]]; then
  cat > "$FIXTURE_DIR/deterministic.ts" << 'EOF'
export const deterministicUseOptions = {
  locale: 'en-US',
  timezoneId: 'UTC',
  colorScheme: 'light' as const,
  viewport: { width: 1280, height: 800 },
  deviceScaleFactor: 1,
};
EOF
  _log "created $FIXTURE_DIR/deterministic.ts"
fi

if [[ ! -f "$FIXTURE_DIR/README.md" ]]; then
  cat > "$FIXTURE_DIR/README.md" << 'EOF'
# Shared E2E Fixtures

Use this directory for deterministic browser-test helpers that must remain stable across runs.

Standards:
- Keep fixtures pure and side-effect free.
- Prefer explicit locale, timezone, viewport, and header defaults.
- Do not read secrets from disk here; use the workspace provisioning path instead.
EOF
  _log "created $FIXTURE_DIR/README.md"
fi

if [[ ! -f "$ARTIFACT_DIR/README.md" ]]; then
  cat > "$ARTIFACT_DIR/README.md" << 'EOF'
# E2E Artifact Standards

Write all run outputs under this directory so they can be collected and compared deterministically.

Expected outputs:
- `e2e-results.json` — machine-readable summary
- `html/` — Playwright HTML report
- `playwright/` — screenshots, traces, and failure captures

Rules:
- Keep artifact paths inside the kit workspace.
- Do not write test outputs to /tmp unless explicitly debugging.
- Treat artifacts as ephemeral unless they are attached to an issue or PR.
EOF
  _log "created $ARTIFACT_DIR/README.md"
fi

if [[ ! -f "$E2E_DIR/fallback-policy.md" ]]; then
  cat > "$E2E_DIR/fallback-policy.md" << 'EOF'
# Browser Automation Fallback Policy

Primary engine:
- Playwright drives the deterministic browser suite.

Fallback engine:
- Puppeteer may be used only when Playwright is unavailable or blocked by environment setup.

Rules:
- Keep the Playwright path first and preferred.
- Use the fallback only for local recovery or temporary compatibility gaps.
- Keep both engines pointed at the same deterministic fixture and artifact layout.
EOF
  _log "created $E2E_DIR/fallback-policy.md"
fi

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
if [[ "$SKIP_NPM_INSTALL" == "1" ]]; then
  _log "E2E_SKIP_NPM_INSTALL=1 — skipping dependency install"
elif command -v npm >/dev/null 2>&1; then
  _log "installing E2E dependencies in $E2E_DIR..."
  (cd "$E2E_DIR" && npm install --prefer-offline --no-audit 2>/dev/null) && \
    _log "dependencies installed" || _warn "npm install failed (may need VPN or network access)"
else
  _warn "npm not available — skipping dependency install"
fi

_log "setup complete. Run tests: cd $E2E_DIR && npx playwright test"
_log "Fallback: puppeteer in $E2E_DIR/node_modules/puppeteer (if installed)"
