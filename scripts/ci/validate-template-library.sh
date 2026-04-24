#!/usr/bin/env bash
# @file        scripts/ci/validate-template-library.sh
# @module      governance/templates
# @description Validate the canonical GitHub, Compose, and Terraform template library
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

readonly REQUIRED_FILES=(
  ".github/pull_request_template.md"
  ".github/ISSUE_TEMPLATE/bug.yml"
  ".github/ISSUE_TEMPLATE/feature.yml"
  ".github/ISSUE_TEMPLATE/task.yml"
  ".github/ISSUE_TEMPLATE/epic.yml"
  ".github/ISSUE_TEMPLATE/infrastructure.yml"
  ".github/ISSUE_TEMPLATE/security.yml"
  ".github/ISSUE_TEMPLATE/governance-waiver.md"
  ".github/ISSUE_TEMPLATE/governance-remediation.md"
  "docs/templates/TEMPLATE-GUIDE.md"
  "docker-compose.service.yml.tpl"
)

readonly REQUIRED_DIRS=(
  "terraform/modules/_template"
)

main() {
  log_info "Validating repository template library"

  for file_path in "${REQUIRED_FILES[@]}"; do
    require_file "${file_path}"
    log_info "Found template file: ${file_path}"
  done

  for dir_path in "${REQUIRED_DIRS[@]}"; do
    require_dir "${dir_path}"
    log_info "Found template directory: ${dir_path}"
  done

  log_info "Template library validation passed"
}

main "$@"