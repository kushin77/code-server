#!/usr/bin/env bash
# @file        scripts/dev/check-config-drift.sh
# @module      governance/validation
# @description Detect configuration drift - hardcoded values that should reference SSOT files
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log_header() {
    log_info "=== Configuration Drift Detection ===" 
}
generate_report() {
    log_info ""
    log_info "=== Drift Detection Report ==="

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        log_info "✓ No configuration drift detected"
    else
        log_error "Configuration drift validation failed"
    fi

    return "$EXIT_CODE"
}

main() {
    log_header

    EXIT_CODE=0

    if [[ -f "$SCRIPT_DIR/validate-config-ssot.sh" ]]; then
        log_info "Running canonical config SSOT validator..."
        bash "$SCRIPT_DIR/validate-config-ssot.sh" --check-only || EXIT_CODE=1
    else
        log_warn "Missing canonical validator: $SCRIPT_DIR/validate-config-ssot.sh"
        EXIT_CODE=1
    fi

    if [[ -f "$SCRIPT_DIR/ci/detect-config-drift.sh" ]]; then
        log_info "Running canonical CI drift detector..."
        bash "$SCRIPT_DIR/ci/detect-config-drift.sh" || EXIT_CODE=1
    else
        log_warn "Missing canonical drift detector: $SCRIPT_DIR/ci/detect-config-drift.sh"
        EXIT_CODE=1
    fi

    if [[ -f "$SCRIPT_DIR/ci/sync-documentation-gaps.sh" ]]; then
        log_info "Verifying documentation gap sync..."
        bash "$SCRIPT_DIR/ci/sync-documentation-gaps.sh" --check-only || EXIT_CODE=1
    else
        log_warn "Missing documentation gap sync script: $SCRIPT_DIR/ci/sync-documentation-gaps.sh"
        EXIT_CODE=1
    fi

    generate_report
}

main "$@"
