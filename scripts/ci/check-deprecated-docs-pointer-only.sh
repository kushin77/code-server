#!/usr/bin/env bash
# @file        scripts/ci/check-deprecated-docs-pointer-only.sh
# @module      ci/governance
# @description Guard to ensure deprecated documentation files remain pointer-only (redirects to canonical sources)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Deprecated documentation files that should contain only redirects/pointers
DEPRECATED_DOCS=(
  "docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md"
  "docs/governance/elite-best-practices/meta/META-DOCUMENT-STANDARDS.md"
  "docs/governance/elite-best-practices/deep/INDEXING-AND-META.md"
  "docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md"
  "docs/status/REPO-FUNCTIONALITY-REVIEW.md"
)

# Maximum size for redirect document (bytes)
MAX_REDIRECT_SIZE=300

check_deprecated_docs_pointer_only() {
  local failed=0
  
  for doc in "${DEPRECATED_DOCS[@]}"; do
    if [[ ! -f "$doc" ]]; then
      log_warn "Deprecated doc not found: $doc (may have been removed)"
      continue
    fi
    
    # Check file size - redirect pointers should be small
    local size=$(wc -c < "$doc" 2>/dev/null || echo 0)
    if [[ $size -gt $MAX_REDIRECT_SIZE ]]; then
      log_error "[$doc] File too large ($size bytes) - contains content, not redirect pointer"
      failed=$((failed + 1))
      continue
    fi
    
    # Check that it contains DEPRECATED marker (indicates pointer/redirect)
    if ! grep -q "DEPRECATED\|deprecated\|See canonical" "$doc" 2>/dev/null; then
      log_error "[$doc] Missing DEPRECATED/redirect marker - must be pointer-only"
      failed=$((failed + 1))
      continue
    fi
    
    log_info "[✓] $(basename "$doc"): redirect pointer OK"
  done
  
  if [[ $failed -gt 0 ]]; then
    log_fatal "Deprecated docs guard FAILED: $failed files contain content instead of redirects"
  fi
  
  log_info "✓ Deprecated docs guard passed (checked=${#DEPRECATED_DOCS[@]})"
  return 0
}

check_deprecated_docs_pointer_only "$@"
