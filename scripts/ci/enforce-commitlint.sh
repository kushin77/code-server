#!/usr/bin/env bash
# @file scripts/ci/enforce-commitlint.sh
# @description Enforce commitlint rules against commits in a PR range or recent commits.
# @usage enforce-commitlint.sh [--base <ref>] [--head <ref>]
# Closes #3180

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

BASE="${1:-origin/main}"
HEAD="${2:-HEAD}"

log_info "Commitlint: checking commits in ${BASE}..${HEAD}"

if ! command -v npx &>/dev/null; then
  log_error "npx not available — cannot run commitlint"
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/commitlint.config.cjs" ]]; then
  log_error "commitlint.config.cjs not found at repo root"
  exit 1
fi

# Get commit range
COMMITS=$(git log --format="%H %s" "${BASE}..${HEAD}" 2>/dev/null || true)

if [[ -z "${COMMITS}" ]]; then
  log_info "No commits in range ${BASE}..${HEAD} — nothing to lint"
  exit 0
fi

FAIL=0
while IFS= read -r line; do
  HASH="${line%% *}"
  MSG=$(git log -1 --format="%s" "${HASH}")
  if ! echo "${MSG}" | npx --no-install commitlint --config "${REPO_ROOT}/commitlint.config.cjs" 2>/dev/null; then
    log_error "Commit ${HASH:0:8} fails commitlint: ${MSG}"
    FAIL=$((FAIL + 1))
  fi
done <<< "${COMMITS}"

if [[ ${FAIL} -gt 0 ]]; then
  log_error "commitlint: ${FAIL} commit(s) failed — fix commit messages before merging"
  exit 1
fi

log_info "commitlint: all commits in range passed"
