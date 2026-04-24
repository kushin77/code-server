#!/usr/bin/env bash
# @file        scripts/ci/validate-disaster-recovery-doc.sh
# @module      governance/disaster-recovery
# @description Validate the disaster recovery strategy document and its links to automation
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

readonly DR_DOC="docs/operations/DISASTER-RECOVERY.md"

check_contains() {
  local pattern="$1"
  local description="$2"

  if grep -qE "$pattern" "$DR_DOC"; then
    log_info "Found ${description}"
  else
    log_fatal "Missing ${description} in ${DR_DOC}"
  fi
}

main() {
  require_file "$DR_DOC"

  check_contains 'RTO' 'RTO target'
  check_contains 'RPO' 'RPO target'
  check_contains 'run-resilience-campaign\.sh' 'resilience campaign automation reference'
  check_contains 'run-playwright-failover-continuity\.sh' 'failover continuity automation reference'
  check_contains 'Sequential Reboot' 'sequential reboot procedure'
  check_contains 'Chaos Engineering' 'chaos engineering suite'
  check_contains 'Backup Policy' 'backup policy section'

  log_info "Disaster recovery documentation validation passed"
}

main "$@"