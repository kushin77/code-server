#!/usr/bin/env bash
# @file        scripts/ci/run-kushnir-cloud-appsmith-login-puppeteer.sh
# @module      ci/e2e
# @description Run Puppeteer parity checks for kushnir.cloud login and IDE landing flows.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://kushnir.cloud}"
IDE_BASE_URL="${IDE_BASE_URL:-https://ide.kushnir.cloud}"
PUPPETEER_TIMEOUT_MS="${PUPPETEER_TIMEOUT_MS:-45000}"
E2E_DIR="${E2E_DIR:-tests/e2e}"

require_dir "$E2E_DIR"
require_file "$SCRIPT_DIR/puppeteer-parity-probe.cjs"

run_puppeteer_parity() {
  local node_cmd
  local probe_script_path

  node_cmd="$(command -v node 2>/dev/null || true)"

  if [[ -n "$node_cmd" ]]; then
    probe_script_path="$SCRIPT_DIR/puppeteer-parity-probe.cjs"

    PORTAL_BASE_URL="$PORTAL_BASE_URL" IDE_BASE_URL="$IDE_BASE_URL" PUPPETEER_TIMEOUT_MS="$PUPPETEER_TIMEOUT_MS" E2E_DIR="$E2E_DIR" \
      "$node_cmd" "$probe_script_path"
    return 0
  fi

  log_fatal "Node.js is required for Puppeteer parity execution"
}

log_info "Running Puppeteer parity check"
log_info "Portal: $PORTAL_BASE_URL"
log_info "IDE: $IDE_BASE_URL"

run_puppeteer_parity

log_info "Puppeteer parity check finished"
