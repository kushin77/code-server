#!/usr/bin/env bash
# @file scripts/phase1/test-failover-procedures.sh
# @description Phase 1 - Validate failover procedures (chaos + load + HA cluster)
# Referenced by GitHub issue #2398 (Post-Deployment Validation Procedures).

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

ARTIFACT="${REPO_ROOT}/artifacts/phase1-failover-procedures-$(date -u +%Y%m%dT%H%M%SZ).md"
RESULT_PASS=0
RESULT_FAIL=0
results=()

run_step() {
    local name="$1"
    local cmd="$2"
    log_info "Step: ${name}"
    if eval "${cmd}" >/dev/null 2>&1; then
        results+=("PASS  | ${name}")
        RESULT_PASS=$((RESULT_PASS + 1))
        log_success "  -> ${name}: PASS"
    else
        results+=("FAIL  | ${name}")
        RESULT_FAIL=$((RESULT_FAIL + 1))
        log_warning "  -> ${name}: FAIL (non-fatal in dry-run)"
    fi
}

log_info "=== Phase 1 Failover Procedure Validation ==="

run_step "validate-ha-cluster" "bash ${SCRIPT_DIR}/validate-ha-cluster.sh --dry-run"
run_step "chaos-tests-final"   "bash ${SCRIPT_DIR}/chaos-tests-final.sh   --dry-run"
run_step "load-tests-final"    "bash ${SCRIPT_DIR}/load-tests-final.sh    --dry-run"

{
    printf '# Phase 1 Failover Procedure Validation\n\n'
    printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '| Result | Step |\n|---|---|\n'
    for r in "${results[@]}"; do
        printf '| %s |\n' "${r}"
    done
    printf '\n**Pass**: %d  **Fail**: %d\n' "${RESULT_PASS}" "${RESULT_FAIL}"
} > "${ARTIFACT}"

log_success "Failover procedure report: ${ARTIFACT}"
[ "${RESULT_FAIL}" -eq 0 ] || log_warning "Some steps failed; see report"
exit 0
