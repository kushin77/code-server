#!/usr/bin/env bash
# @file        scripts/ci/check-deprecated-script-shims.sh
# @module      ci/governance
# @description Enforce archived shim status and canonical active script surfaces for deprecated script remediation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Retired shim files that must remain archived marker stubs only.
RETIRED_SHIMS=(
  "scripts/common-functions.sh"
  "scripts/logging.sh"
)

# Canonical scripts from legacy evidence that must remain active and present.
CANONICAL_ACTIVE_SURFACES=(
  "scripts/code-server-entrypoint.sh"
  "scripts/git-credential-gsm"
  "scripts/ops/drift-detect.sh"
)

ARCHIVE_MARKER="# ARCHIVED: Deprecated and archived file"
DO_NOT_USE_MARKER="# DO NOT USE THIS FILE"

validate_retired_shims() {
  local retired
  for retired in "${RETIRED_SHIMS[@]}"; do
    local retired_path="$REPO_ROOT/$retired"

    if [[ ! -f "$retired_path" ]]; then
      log_error "Retired shim marker file missing: $retired"
      return 1
    fi

    if grep -q '^#!/usr/bin/env bash' "$retired_path"; then
      log_error "Retired shim appears executable/script-like (unexpected shebang): $retired"
      return 1
    fi

    if ! grep -qF "$ARCHIVE_MARKER" "$retired_path"; then
      log_error "Retired shim missing archive marker: $retired"
      return 1
    fi

    if ! grep -qF "$DO_NOT_USE_MARKER" "$retired_path"; then
      log_error "Retired shim missing explicit do-not-use marker: $retired"
      return 1
    fi
  done

  return 0
}

validate_active_surfaces() {
  local active
  for active in "${CANONICAL_ACTIVE_SURFACES[@]}"; do
    if [[ ! -f "$REPO_ROOT/$active" ]]; then
      log_error "Required active script surface missing: $active"
      return 1
    fi
  done

  return 0
}

validate_no_active_references() {
  local pattern='scripts/common-functions\.sh|scripts/logging\.sh'

  if grep -RInE "$pattern" \
    "$REPO_ROOT/scripts" "$REPO_ROOT/tests" "$REPO_ROOT/.github/workflows" \
    --exclude-dir='_archive' --exclude='*.md' --exclude='*.json' --exclude='*.lock' \
    --exclude='check-deprecated-script-shims.sh' --exclude='deprecated-script-shims-guard.yml' >/tmp/deprecated-shim-ref-scan.log 2>/dev/null; then
    log_error "Detected references to retired shims in active execution surfaces"
    cat /tmp/deprecated-shim-ref-scan.log >&2 || true
    return 1
  fi

  rm -f /tmp/deprecated-shim-ref-scan.log 2>/dev/null || true
  return 0
}

check_deprecated_shims() {
  validate_retired_shims
  validate_active_surfaces
  validate_no_active_references

  log_success "Deprecated script shim guard passed"
}

check_deprecated_shims "$@"
