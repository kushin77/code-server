#!/usr/bin/env bash
# @file        scripts/ci/validate-e2e-playwright-kit.sh
# @module      ci/e2e
# @description Validate the deterministic Playwright browser automation kit scaffold.
#
# Usage: bash scripts/ci/validate-e2e-playwright-kit.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_command "bash" "bash is required"
require_command "grep" "grep is required"
require_command "mktemp" "mktemp is required"

log_info "Validating deterministic Playwright kit in $TMP_DIR"

E2E_DIR="$TMP_DIR/e2e" E2E_SKIP_NPM_INSTALL=1 bash "$SCRIPT_DIR/setup-e2e-playwright.sh"

require_file "$TMP_DIR/e2e/package.json"
require_file "$TMP_DIR/e2e/playwright.config.ts"
require_file "$TMP_DIR/e2e/specs/oauth-login.spec.ts"
require_file "$TMP_DIR/e2e/fixtures/deterministic.ts"
require_file "$TMP_DIR/e2e/fixtures/README.md"
require_file "$TMP_DIR/e2e/artifacts/README.md"
require_file "$TMP_DIR/e2e/fallback-policy.md"

grep -qF "deterministicUseOptions" "$TMP_DIR/e2e/playwright.config.ts" || log_fatal "playwright.config.ts does not import deterministic fixtures"
grep -qF "outputFolder" "$TMP_DIR/e2e/playwright.config.ts" || log_fatal "playwright.config.ts missing HTML report output folder"
grep -qF "outputFile" "$TMP_DIR/e2e/playwright.config.ts" || log_fatal "playwright.config.ts missing JSON report output file"
grep -qF "Do not write test outputs to /tmp" "$TMP_DIR/e2e/artifacts/README.md" || log_fatal "artifact standards missing ephemeral guidance"
grep -qF "Playwright drives the deterministic browser suite" "$TMP_DIR/e2e/fallback-policy.md" || log_fatal "fallback policy missing Playwright primary rule"

log_info "Deterministic Playwright kit validation passed"