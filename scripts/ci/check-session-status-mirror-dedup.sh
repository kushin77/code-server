#!/usr/bin/env bash
# @file        scripts/ci/check-session-status-mirror-dedup.sh
# @module      ci/governance
# @description Prevent duplicate session status mirrors between docs/status and historical session records.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

pairs=(
  "docs/operations/session-history/historical/2026/ops-record-apr16-phase-status-s3.md|docs/status/SESSION-3-FINAL-STATUS.md"
  "docs/operations/session-history/historical/2026/ops-record-apr17-phase2-p2418-s5.md|docs/status/SESSION-5-PHASE-2-COMPLETE-AND-P2-418-STARTED.md"
  "docs/operations/session-history/historical/2026/ops-record-apr17-phase21-deploy-s4.md|docs/status/SESSION-4-PHASE-2-1-DEPLOYMENT-COMPLETE.md"
  "docs/operations/session-history/historical/2026/ops-record-apr16-remediation-s3.md|docs/status/SESSION-3-REMEDIATION-SUMMARY.md"
  "docs/operations/session-history/historical/2026/ops-record-apr16-phase-overview-s2.md|docs/status/SESSION-2-APRIL-16-2026-SUMMARY.md"
)

failed=0
checked=0

for pair in "${pairs[@]}"; do
  archive_rel="${pair%%|*}"
  canonical_rel="${pair##*|}"

  archive="$REPO_ROOT/$archive_rel"
  canonical="$REPO_ROOT/$canonical_rel"

  require_file "$archive"
  require_file "$canonical"

  checked=$((checked + 1))

  archive_hash="$(sha256sum "$archive" | awk '{print $1}')"
  canonical_hash="$(sha256sum "$canonical" | awk '{print $1}')"

  if [[ "$archive_hash" == "$canonical_hash" ]]; then
    log_error "Duplicate mirror detected: $archive_rel == $canonical_rel"
    failed=1
    continue
  fi

  if ! grep -q "$canonical_rel" "$archive"; then
    log_error "Pointer missing canonical reference in $archive_rel"
    log_error "Expected to find: $canonical_rel"
    failed=1
    continue
  fi

  log_info "Dedup policy OK: $archive_rel -> $canonical_rel"
done

if [[ "$failed" -ne 0 ]]; then
  log_fatal "Session status mirror dedup guard failed"
fi

log_success "Session status mirror dedup guard passed (checked=$checked)"
