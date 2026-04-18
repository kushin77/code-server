#!/usr/bin/env bash
# @file        scripts/ci/validate-issue-linkage.sh
# @module      ci/governance
# @description Validate commit subjects include issue linkage keywords in the active commit range.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

require_command "git" "git is required for issue linkage validation"

resolve_range() {
    if [[ -n "${LINKAGE_RANGE:-}" ]]; then
        echo "${LINKAGE_RANGE}"
        return
    fi

    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/main"; then
        echo "origin/main..HEAD"
        return
    fi

    echo ""
}

is_merge_like_subject() {
    local subject="$1"
    [[ "$subject" =~ ^Merge\  ]] || [[ "$subject" =~ ^merge\( ]]
}

has_issue_linkage() {
    local subject="$1"
    [[ "$subject" =~ (Fixes|Closes|Resolves|Relates\ to)\ #[0-9]+ ]]
}

main() {
    local range
    range="$(resolve_range "${1:-}")"

    if [[ -z "$range" ]]; then
        log_warn "No commit range available; skipping linkage validation"
        return 0
    fi

    log_info "Validating commit issue linkage in range: ${range}"

    local commits
    commits="$(git log --format='%H	%s' "$range" 2>/dev/null || true)"

    if [[ -z "$commits" ]]; then
        log_info "No commits found in range; linkage validation passed"
        return 0
    fi

    local failed=0
    while IFS=$'\t' read -r sha subject; do
        if is_merge_like_subject "$subject"; then
            continue
        fi

        if ! has_issue_linkage "$subject"; then
            log_error "Missing issue linkage in commit ${sha:0:12}: $subject"
            failed=1
        fi
    done <<< "$commits"

    if [[ $failed -ne 0 ]]; then
        log_fatal "Issue linkage validation failed. Use 'Fixes #N' or 'Relates to #N' in commit subjects."
    fi

    log_info "Issue linkage validation passed"
}

main "$@"
