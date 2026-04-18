#!/usr/bin/env bash
# @file        scripts/ci/validate-issue-linkage.sh
# @module      governance/issue-linkage
# @description Validate that non-merge commits include GitHub issue linkage.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

cd "${REPO_ROOT}"

STRICT_ISSUE_LINKAGE="${STRICT_ISSUE_LINKAGE:-true}"

resolve_range() {
    if [[ -n "${LINKAGE_RANGE:-}" ]]; then
        echo "${LINKAGE_RANGE}"
        return
    fi

    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi

    if [[ -n "${GITHUB_BASE_REF:-}" ]] && git show-ref --verify --quiet "refs/remotes/origin/${GITHUB_BASE_REF}"; then
        echo "origin/${GITHUB_BASE_REF}...HEAD"
        return
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/main"; then
        echo "origin/main..HEAD"
        return
    fi

    echo "HEAD~1..HEAD"
}

is_exempt_subject() {
    local subject="$1"

    if [[ "$subject" =~ ^Merge\  ]] || [[ "$subject" =~ ^merge\( ]]; then
        return 0
    fi
    if [[ "$subject" =~ \[skip-issue-link\] ]]; then
        return 0
    fi
    if [[ "$subject" =~ ^(chore\(deps\)|build\(deps\)|release:) ]]; then
        return 0
    fi
    return 1
}

has_issue_linkage() {
    local message="$1"

    [[ "$message" =~ (Fixes|Closes|Resolves|Relates\ to)\ \#[0-9]+ ]] && return 0
    [[ "$message" =~ \(\#[0-9]+\) ]] && return 0
    [[ "$message" =~ \#[0-9]+ ]] && return 0
    return 1
}

main() {
    local range
    range="$(resolve_range "${1:-}")"

    if [[ -z "$range" ]]; then
        log_warn "No commit range available; skipping issue linkage validation"
        return 0
    fi

    log_info "Validating commit issue linkage in range: ${range}"

    local failed=0
    while read -r sha; do
        [[ -z "${sha:-}" ]] && continue
        read -r subject || break

        if is_exempt_subject "$subject"; then
            log_info "Exempt commit: ${sha:0:12} ${subject}"
            continue
        fi

        if ! has_issue_linkage "$subject"; then
            log_error "Missing issue linkage in commit ${sha:0:12}: $subject"
            failed=1
        fi
    done < <(git log --format='%H%n%s' "$range" 2>/dev/null || true)

    if [[ $failed -ne 0 ]]; then
        if [[ "$STRICT_ISSUE_LINKAGE" == "true" ]]; then
            log_fatal "Issue linkage validation failed. Use 'Fixes #N' or 'Relates to #N' in commit message."
        fi
        log_warn "Issue linkage warnings only (STRICT_ISSUE_LINKAGE=false)"
        return 0
    fi

    log_info "Issue linkage validation passed"
}

main "$@"
