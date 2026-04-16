#!/usr/bin/env bash
################################################################################
# File:          scripts/vpn-enterprise-endpoint-scan.sh
# Owner:         Platform Engineering
# Purpose:       Run deep endpoint scan using Playwright + Puppeteer over VPN only.
# Usage:         bash scripts/vpn-enterprise-endpoint-scan.sh
# Status:        active
# Depends:       scripts/_common/init.sh, scripts/lib/vpn.sh
# Last Updated:  April 15, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN_DIR="$PROJECT_ROOT/tests/vpn-enterprise-endpoint-scan"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_ROOT="${VPN_SCAN_OUTPUT_ROOT:-$PROJECT_ROOT/test-results/vpn-endpoint-scan}"
OUTPUT_DIR="${VPN_SCAN_OUTPUT_DIR:-$OUTPUT_ROOT/$TIMESTAMP}"
VPN_INTERFACE="${VPN_INTERFACE:-wg0}"
NODE_ENV="${NODE_ENV:-production}"

source "$SCRIPT_DIR/_common/init.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/vpn.sh"

log_section "VPN Enterprise Endpoint Scan"
log_info "Output directory: $OUTPUT_DIR"
log_info "VPN interface required: $VPN_INTERFACE"

require_commands node npm ip
vpn::require_commands
vpn::require_interface "$VPN_INTERFACE"

if [[ ! -d "$SCAN_DIR" ]]; then
    log_fatal "Scan directory not found: $SCAN_DIR"
fi

mkdir -p "$OUTPUT_DIR"
export VPN_SCAN_OUTPUT_DIR="$OUTPUT_DIR"
export VPN_INTERFACE
export NODE_ENV

if [[ ! -d "$SCAN_DIR/node_modules" ]]; then
    log_info "Installing scanner dependencies..."
    (cd "$SCAN_DIR" && npm install --no-audit --no-fund)
fi

if ! command -v npx >/dev/null 2>&1; then
    log_fatal "npx is required to execute Playwright tooling"
fi

if [[ "${INSTALL_PLAYWRIGHT_BROWSER:-1}" == "1" ]]; then
    log_info "Ensuring Chromium browser is installed for Playwright"
    (cd "$SCAN_DIR" && npx playwright install --with-deps chromium)
fi

log_info "Running deep endpoint scan (Playwright + Puppeteer)..."
(cd "$SCAN_DIR" && node run-vpn-enterprise-scan.mjs)

SUMMARY_FILE="$OUTPUT_DIR/summary.json"
if [[ ! -f "$SUMMARY_FILE" ]]; then
    log_fatal "Expected summary file missing: $SUMMARY_FILE"
fi

SCAN_STATUS=$(node -e "const fs=require('fs');const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(s.status||'unknown');" "$SUMMARY_FILE")
log_info "Scan status: $SCAN_STATUS"

if [[ "$SCAN_STATUS" != "pass" ]]; then
    log_error "VPN enterprise scan failed. Inspect: $SUMMARY_FILE"
    exit 1
fi

log_success "VPN enterprise endpoint scan passed"
log_info "Artifacts: $OUTPUT_DIR"
