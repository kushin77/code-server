#!/usr/bin/env bash
# @file scripts/dx/onboard-developer.sh
# @description Phase 9 - One-shot developer onboarding bootstrap.
# Tracks GitHub issue #2402.

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

DRY_RUN=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run|-n) DRY_RUN=1 ;;
    esac
done

START_TS=$(date +%s)
ARTIFACT="${REPO_ROOT}/artifacts/onboarding-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "${ARTIFACT}")"

PASS=0; WARN=0; FAIL=0
results=()

check() {
    local name="$1"; local cmd="$2"; local required="${3:-required}"
    if eval "${cmd}" >/dev/null 2>&1; then
        results+=("PASS  | ${name}")
        PASS=$((PASS + 1))
        log_success "  ${name}: PASS"
    else
        if [ "${required}" = "required" ]; then
            results+=("FAIL  | ${name}")
            FAIL=$((FAIL + 1))
            log_warning "  ${name}: FAIL"
        else
            results+=("WARN  | ${name} (optional)")
            WARN=$((WARN + 1))
            log_warning "  ${name}: WARN (optional)"
        fi
    fi
}

log_info "=== Developer Onboarding Bootstrap (Phase 9) ==="
log_info "Dry-run: ${DRY_RUN}"

# 1. Toolchain probes
check "git installed"        "command -v git"
check "bash >= 4"            "[ \"\${BASH_VERSINFO[0]}\" -ge 4 ]"
check "python3 installed"    "command -v python3"
check "node installed (opt)" "command -v node" optional
check "docker installed"     "command -v docker"
check "docker compose v2"    "docker compose version" optional

# 2. Repo state
check "repo is a git checkout"    "git -C ${REPO_ROOT} rev-parse --is-inside-work-tree"
check "_base-config.env present"  "[ -f ${REPO_ROOT}/scripts/_common/_base-config.env ]"
check "init.sh present"           "[ -f ${REPO_ROOT}/scripts/_common/init.sh ]"
check "docker-compose.yml present" "[ -f ${REPO_ROOT}/docker-compose.yml ]"

# 3. Hooks
HOOK="${REPO_ROOT}/.git/hooks/pre-commit"
if [ "${DRY_RUN}" -eq 0 ] && [ ! -x "${HOOK}" ] && [ -x "${REPO_ROOT}/scripts/ci/install-pre-commit-hook.sh" ]; then
    log_info "Installing pre-commit hook..."
    bash "${REPO_ROOT}/scripts/ci/install-pre-commit-hook.sh" >/dev/null 2>&1 || true
fi
check "pre-commit hook installed" "[ -x ${HOOK} ]" optional

# 4. Smoke
check "full deployment dry-run"   "bash ${REPO_ROOT}/scripts/ops/full-deployment-test.sh --dry-run >/dev/null 2>&1"

ELAPSED=$(( $(date +%s) - START_TS ))

{
    printf '# Developer Onboarding Bootstrap\n\n'
    printf 'Tracks GitHub issue #2402.\n\n'
    printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Elapsed: **%d seconds** (target: < 1800s = 30 min)\n\n' "${ELAPSED}"
    printf '## Checks\n\n'
    printf '| Result | Check |\n|---|---|\n'
    for r in "${results[@]}"; do printf '| %s |\n' "${r}"; done
    printf '\n## Summary\n\n'
    printf -- '- Pass: %d\n- Warn: %d\n- Fail: %d\n\n' "${PASS}" "${WARN}" "${FAIL}"
    if [ "${FAIL}" -eq 0 ]; then
        printf '✅ Onboarding ready. Next steps:\n\n'
        printf '1. Read `docs/planning/master-execution-roadmap.md`.\n'
        printf '2. Pick an open issue tagged `good-first-issue` or your team area.\n'
        printf '3. Run `bash scripts/ops/full-deployment-test.sh --dry-run` after each change.\n'
    else
        printf '❌ Fix the FAIL rows above before continuing.\n'
    fi
} > "${ARTIFACT}"

log_success "Onboarding report: ${ARTIFACT}"
log_info "Elapsed: ${ELAPSED}s (target: <1800s)"
[ "${FAIL}" -eq 0 ] || exit 1
exit 0
