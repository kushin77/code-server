#!/usr/bin/env bash
# @file        scripts/ci/validate-identity-governance.sh
# @module      governance/identity
# @description Validate identity and credential inventories plus their bootstrap scripts
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

readonly REQUIRED_FILES=(
  "docs/security/SSH-KEY-INVENTORY.md"
  "docs/security/SERVICE-ACCOUNT-INVENTORY.md"
  "scripts/ops/setup-passwordless-sudo.sh"
  "scripts/ops/rotate-qa-credentials.py"
)

check_contains() {
  local file_path="$1"
  local pattern="$2"
  local description="$3"

  if grep -qE "$pattern" "$file_path"; then
    log_info "Found ${description} in ${file_path}"
  else
    log_fatal "Missing ${description} in ${file_path}"
  fi
}

main() {
  log_info "Validating identity and credential governance"

  for file_path in "${REQUIRED_FILES[@]}"; do
    require_file "$file_path"
    log_info "Found required file: ${file_path}"
  done

  check_contains "docs/security/SSH-KEY-INVENTORY.md" '~/.ssh/id_rsa_onprem' 'canonical deployment SSH key'
  check_contains "docs/security/SSH-KEY-INVENTORY.md" 'akushnir' 'deployment key owner'
  check_contains "docs/security/SERVICE-ACCOUNT-INVENTORY.md" 'github-actions@kushin77-ops\.iam\.gserviceaccount\.com' 'GitHub Actions service account'
  check_contains "scripts/ops/setup-passwordless-sudo.sh" 'source "\$\{SCRIPT_DIR\}/scripts/_common/init\.sh"' 'canonical init bootstrap'
  check_contains "scripts/ops/setup-passwordless-sudo.sh" 'init_repo' 'repository context initialization'
  check_contains "scripts/ops/rotate-qa-credentials.py" 'datetime\.now\(timezone\.utc\)' 'timezone-aware audit timestamp'

  log_info "Identity and credential governance validation passed"
}

main "$@"