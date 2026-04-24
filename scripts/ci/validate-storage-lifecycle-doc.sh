#!/usr/bin/env bash
# @file        scripts/ci/validate-storage-lifecycle-doc.sh
# @module      governance/storage
# @description Validate the storage lifecycle strategy document and its cleanup references
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

readonly STORAGE_DOC="docs/operations/STORAGE-LIFECYCLE.md"
readonly AUDIT_SCRIPT="scripts/ops/audit-idle-resources.sh"

check_contains() {
  local pattern="$1"
  local description="$2"

  if grep -qE "$pattern" "$STORAGE_DOC"; then
    log_info "Found ${description}"
  else
    log_fatal "Missing ${description} in ${STORAGE_DOC}"
  fi
}

main() {
  require_file "$STORAGE_DOC"
  require_file "$AUDIT_SCRIPT"

  check_contains 'Docker images' 'image retention policy'
  check_contains 'Docker volumes' 'volume retention policy'
  check_contains 'NAS hot backups' 'NAS backup retention policy'
  check_contains 'cleanup-stale-branches\.sh' 'stale branch cleanup reference'
  check_contains 'audit-idle-resources\.sh' 'idle resource audit reference'
  check_contains 'docker system df' 'storage validation command'

  check_contains 'docker stats --no-stream' 'idle container metrics command'
  check_contains 'gh api rate_limit' 'GitHub rate limit check'

  log_info "Storage lifecycle documentation validation passed"
}

main "$@"