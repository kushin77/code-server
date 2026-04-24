#!/usr/bin/env bash
# @file        scripts/ci/run-collaboration-synthetic-monitor.sh
# @module      ci/e2e
# @description Run the collaboration synthetic Playwright monitor and export Prometheus-friendly metrics.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

E2E_DIR="${E2E_DIR:-tests/e2e}"
SUITE_NAME="collaboration-synthetic-monitor"
OUTPUT_DIR="${E2E_FLAKE_OUTPUT_DIR:-artifacts/triage}"
DEFAULT_SIGNATURES_FILE="$SCRIPT_DIR/../../config/test-flake-signatures.json"
SIGNATURES_FILE="${E2E_FLAKE_SIGNATURES_FILE:-$DEFAULT_SIGNATURES_FILE}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://kushnir.cloud}"
IDE_BASE_URL="${IDE_BASE_URL:-https://ide.kushnir.cloud}"
TEST_BASE_URL="${TEST_BASE_URL:-$IDE_BASE_URL}"
AUTH_STORAGE_STATE="${PLAYWRIGHT_STORAGE_STATE:-}"
METRICS_FILE="$OUTPUT_DIR/${SUITE_NAME}.prom"

require_command bash

log_info "Preparing deterministic Playwright kit"
bash "$SCRIPT_DIR/setup-e2e-playwright.sh"

mkdir -p "$OUTPUT_DIR"

if [[ -z "$AUTH_STORAGE_STATE" ]]; then
  log_warn "PLAYWRIGHT_STORAGE_STATE not set; authenticated continuity scenario will be skipped"
fi

log_info "Running collaboration synthetic monitor against $TEST_BASE_URL"

(
  cd "$E2E_DIR"
  PORTAL_BASE_URL="$PORTAL_BASE_URL" \
  IDE_BASE_URL="$IDE_BASE_URL" \
  TEST_BASE_URL="$TEST_BASE_URL" \
  PLAYWRIGHT_STORAGE_STATE="$AUTH_STORAGE_STATE" \
  SYNTHETIC_METRICS_FILE="$METRICS_FILE" \
  SYNTHETIC_RUN_LABEL="$SUITE_NAME" \
  E2E_FLAKE_OUTPUT_DIR="$OUTPUT_DIR" \
  E2E_FLAKE_SIGNATURES_FILE="$SIGNATURES_FILE" \
  bash "$SCRIPT_DIR/run-deterministic-e2e-suite.sh" \
    --suite-name "$SUITE_NAME" \
    --output-dir "$OUTPUT_DIR" \
    --signatures-file "$SIGNATURES_FILE" \
    -- playwright test specs/collaboration-synthetic-monitor.spec.ts
)

if [[ -f "$METRICS_FILE" ]]; then
  log_info "Synthetic metrics written to $METRICS_FILE"
else
  log_warn "Synthetic metrics file was not created"
fi
