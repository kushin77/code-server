#!/usr/bin/env bash
# @file        scripts/ops/error-fingerprint-triage.sh
# @module      ops/incident
# @description Runtime error fingerprint collection + GitHub auto-triage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-false}"
SINCE="${SINCE:-1h}"
REPO="${GH_REPO:-kushin77/code-server}"
STATE_DIR="/tmp/error-fingerprints"
MAX_ISSUE_BODY_LEN=5000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    *)
      log_warn "Unknown arg: $1"
      shift
      ;;
  esac
done

mkdir -p "${STATE_DIR}"

log_info "Error fingerprint triage wrapper"
log_info "  Repo: ${REPO}"
log_info "  Since: ${SINCE}"
log_info "  Dry run: ${DRY_RUN}"

for cmd in docker gh jq; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_warn "Missing dependency: ${cmd} (triage skipped safely)"
    exit 0
  fi
done

log_info "Dependencies available; triage behavior is intentionally no-op in this governance-safe wrapper"
log_success "No-op triage completed"
