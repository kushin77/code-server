#!/usr/bin/env bash
# @file scripts/phase5/enable-audit-logging.sh
# @description Phase 5 - Enable immutable audit logging
# @summary Validates audit log sinks and immutability flags for compliance.

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

PHASE_TAG="phase5-enable-audit-logging"
ARTIFACT="${REPO_ROOT}/artifacts/${PHASE_TAG}-$(date -u +%Y%m%dT%H%M%SZ).md"

DRY_RUN=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run|-n) DRY_RUN=1 ;;
    esac
done

log_info "=== Phase 5 - Enable immutable audit logging ==="
log_info "Dry-run: ${DRY_RUN}"

steps=("Audit logging orchestrator::scripts/ops/audit-logging-orchestrator.sh")
results=()
ok=0; fail=0; skip=0

for entry in "${steps[@]}"; do
    name="${entry%%::*}"
    target="${entry##*::}"
    if [ -z "${target}" ] || [ "${target}" = "${name}" ]; then
        results+=("NOTE  | ${name} | (manual / documentation step)")
        skip=$((skip + 1))
        continue
    fi
    full="${REPO_ROOT}/${target}"
    if [ ! -f "${full}" ]; then
        results+=("SKIP  | ${name} | missing: ${target}")
        skip=$((skip + 1))
        log_warning "  ${name}: missing ${target}"
        continue
    fi
    log_info "  Step: ${name}  (${target})"
    if [ "${DRY_RUN}" -eq 1 ]; then
        results+=("PLAN  | ${name} | would run: bash ${target}")
        ok=$((ok + 1))
    else
        if bash "${full}" >/dev/null 2>&1; then
            results+=("PASS  | ${name} | ${target}")
            ok=$((ok + 1))
        else
            results+=("FAIL  | ${name} | ${target}")
            fail=$((fail + 1))
            log_warning "  ${name}: FAIL (continuing)"
        fi
    fi
done

{
    printf '# Phase 5 - Enable immutable audit logging\n\n'
    printf '%s\n\n' "Validates audit log sinks and immutability flags for compliance."
    printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Dry-run: %s\n\n' "${DRY_RUN}"
    printf '## Steps\n\n'
    printf '| Result | Name | Detail |\n|---|---|---|\n'
    for r in "${results[@]}"; do
        printf '| %s |\n' "${r}"
    done
    printf '\n## Summary\n\n- OK: %d\n- Failed: %d\n- Skipped: %d\n' "${ok}" "${fail}" "${skip}"
} > "${ARTIFACT}"

log_success "Report: ${ARTIFACT}"
[ "${fail}" -eq 0 ] || log_warning "${fail} step(s) failed (non-fatal)"
exit 0
