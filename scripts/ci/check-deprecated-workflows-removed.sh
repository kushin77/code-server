#!/usr/bin/env bash
# @file        scripts/ci/check-deprecated-workflows-removed.sh
# @module      ci/governance
# @description Guard to ensure deprecated workflows remain deleted; prevents accidental reintroduction

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Deprecated workflow files that should NOT exist (have been removed)
DEPRECATED_WORKFLOWS=(
  ".github/workflows/shell-lint.yml"
  ".github/workflows/validate-linux-only.yml"
  ".github/workflows/workflow-lint.yml"
)

check_deprecated_workflows_removed() {
  local failed=0
  
  for workflow in "${DEPRECATED_WORKFLOWS[@]}"; do
    if [[ -f "$workflow" ]]; then
      log_error "[$workflow] Deprecated workflow file still exists - must be removed"
      failed=$((failed + 1))
    else
      log_info "[✓] $workflow: confirmed removed"
    fi
  done
  
  if [[ $failed -gt 0 ]]; then
    log_fatal "Deprecated workflows guard FAILED: $failed deprecated workflows were reintroduced"
  fi
  
  log_info "✓ Deprecated workflows guard passed (checked=${#DEPRECATED_WORKFLOWS[@]})"
  return 0
}

check_deprecated_workflows_removed "$@"
