#!/usr/bin/env bash

################################################################################
# @file check-merged-branch-cleanup.sh
# @module github-governance
# @description Fail CI when merged branches remain on remote past cleanup grace
# @governance GOV-002: Immutable, version-controlled, idempotent infrastructure
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)"
REPORT_FILE="${PROJECT_ROOT}/artifacts/merged-branch-cleanup-report.md"

GRACE_HOURS="${BRANCH_CLEANUP_GRACE_HOURS:-24}"
EXCLUDE_REGEX="${BRANCH_CLEANUP_EXCLUDE_REGEX:-^(main|master|develop|development|staging|production|release/.*|hotfix/.*|gh-readonly-queue/.*)$}"
STRICT_MODE=1

if [[ "${1:-}" == "--warn-only" ]]; then
  STRICT_MODE=0
fi

log_branch_cleanup() {
  printf '[%s] [INFO] [BRANCH-CLEANUP] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_success() {
  printf '[%s] [SUCCESS] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

ensure_remote_refs() {
  log_branch_cleanup "Fetching origin refs for cleanup analysis"
  git fetch --prune origin \
    '+refs/heads/*:refs/remotes/origin/*' \
    '+refs/heads/main:refs/remotes/origin/main' >/dev/null
}

main() {
  cd "${PROJECT_ROOT}"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "Not inside a git work tree"
    exit 2
  fi

  ensure_remote_refs

  if ! git show-ref --verify --quiet refs/remotes/origin/main; then
    log_error "refs/remotes/origin/main not found"
    exit 2
  fi

  local now_epoch
  now_epoch="$(date +%s)"

  local -a stale_merged=()
  local examined=0

  while IFS= read -r ref; do
    local branch="${ref#origin/}"

    [[ -z "${branch}" || "${branch}" == "HEAD" || "${branch}" == "origin" ]] && continue
    [[ "${branch}" =~ ${EXCLUDE_REGEX} ]] && continue
    git show-ref --verify --quiet "refs/remotes/origin/${branch}" || continue

    examined=$((examined + 1))

    if git merge-base --is-ancestor "refs/remotes/origin/${branch}" "refs/remotes/origin/main"; then
      local tip_epoch
      tip_epoch="$(git log -1 --format=%ct "refs/remotes/origin/${branch}")"

      local age_hours=$(( (now_epoch - tip_epoch) / 3600 ))
      if (( age_hours > GRACE_HOURS )); then
        local tip_sha
        tip_sha="$(git rev-parse --short "refs/remotes/origin/${branch}")"
        stale_merged+=("${branch}|${age_hours}|${tip_sha}")
      fi
    fi
  done < <(git for-each-ref refs/remotes/origin/* --format='%(refname:short)' | sort)

  mkdir -p "$(dirname "${REPORT_FILE}")"
  {
    echo "# Merged Branch Cleanup Report"
    echo
    echo "Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo "Grace period (hours): ${GRACE_HOURS}"
    echo "Examined remote branches: ${examined}"
    echo "Stale merged branches: ${#stale_merged[@]}"
    echo

    if (( ${#stale_merged[@]} > 0 )); then
      echo "## Violations"
      echo
      echo "| Branch | Age (hours) | Tip SHA |"
      echo "|---|---:|---|"
      for row in "${stale_merged[@]}"; do
        IFS='|' read -r b age sha <<<"${row}"
        echo "| ${b} | ${age} | ${sha} |"
      done
      echo
      echo "Required action: delete each stale merged branch from remote."
    else
      echo "No stale merged branches found."
    fi
  } > "${REPORT_FILE}"

  log_branch_cleanup "Report: ${REPORT_FILE}"

  if (( ${#stale_merged[@]} == 0 )); then
    log_success "Merged branch cleanup check: COMPLIANT"
    exit 0
  fi

  if (( STRICT_MODE == 1 )); then
    log_error "Merged branch cleanup check: ${#stale_merged[@]} violation(s)"
    exit 1
  fi

  log_warn "Merged branch cleanup check: violations detected (warn-only mode)"
  exit 0
}

main "$@"
