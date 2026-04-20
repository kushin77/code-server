#!/usr/bin/env bash
# @file        scripts/ci/check-deprecated-doc-stubs.sh
# @module      ci/documentation
# @description Ensure deprecated governance/status copies remain pointer-only stubs with canonical SSOT links.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

deprecated_docs=(
  "docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md"
  "docs/governance/elite-best-practices/meta/META-DOCUMENT-STANDARDS.md"
  "docs/governance/elite-best-practices/deep/INDEXING-AND-META.md"
  "docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md"
  "docs/status/REPO-FUNCTIONALITY-REVIEW.md"
)

for doc in "${deprecated_docs[@]}"; do
  path="$REPO_ROOT/$doc"

  require_file "$path"

  if ! grep -q '^# DEPRECATED: Archived pointer-only stub\.$' "$path"; then
    log_error "Missing standardized deprecation header in $doc"
    exit 1
  fi

  if ! grep -q '^# Canonical references:' "$path"; then
    log_error "Missing canonical reference block in $doc"
    exit 1
  fi

  if ! grep -q 'docs/SHARED-LIBRARIES.md' "$path"; then
    log_error "Missing shared-library canonical pointer in $doc"
    exit 1
  fi

  if ! grep -q 'Issue tracking SSOT: GitHub Issues' "$path"; then
    log_error "Missing issue-tracking SSOT pointer in $doc"
    exit 1
  fi

  line_count="$(wc -l < "$path")"
  if [[ "$line_count" -gt 8 ]]; then
    log_error "Deprecated stub exceeds pointer-only size budget in $doc (lines=$line_count)"
    exit 1
  fi
done

log_success "Deprecated document stub guard passed"