#!/bin/bash
# @file validate-terraform-version-pins.sh
# @module infrastructure/validation
# @description P3-1531: Validate all Terraform provider/module versions are pinned (no floating ranges like ~>)
# @governance GOV-002: All infrastructure version-pinned in terraform/variables.tf - no ~> ranges in production
# @usage validate-terraform-version-pins.sh [--check] [--fix] [--report]

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform}"
readonly REPORT_FILE="${REPORT_FILE:-${REPO_ROOT}/artifacts/terraform-version-pins-report.txt}"
readonly ALLOWED_FLOATING_PATTERNS="${ALLOWED_FLOATING_PATTERNS:-}"  # Empty = no floating allowed

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

check_floating_versions() {
  log_info Scanning for floating version ranges in Terraform
  local violations=0
  local report_lines=()

  while IFS= read -r file; do
    [ -z "$file" ] && continue

    if grep -q '~>' "$file"; then
      local count=$(grep -c '~>' "$file")
      violations=$((violations + count))
      report_lines+=("$file|floating-range|$count")
      log_warning "Found $count floating version ranges (~>) in $file"
    fi

    if grep -E 'version[[:space:]]*=[[:space:]]*"[^"]*>=.*"' "$file" | grep -vq '<'; then
      local count=1
      violations=$((violations + count))
      report_lines+=("$file|unbounded-range|$count")
      log_warning "Found unbounded version range (>= without <) in $file"
    fi
  done < <(find "$TERRAFORM_DIR" -name "*.tf" -type f)

  mkdir -p $(dirname "$REPORT_FILE")
  {
    echo scan_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo status=$([ $violations -gt 0 ] && echo FAILED || echo PASSED)
    echo violations=$violations
    for line in "${report_lines[@]}"; do
      echo violation=$line
    done
  } > "$REPORT_FILE"

  log_info Report saved to $REPORT_FILE
  [ $violations -eq 0 ] && return 0 || return 1
}

check_provider_requirements() {
  log_info Checking provider version requirements

  if [ ! -f "$TERRAFORM_DIR/versions.tf" ]; then
    log_warning No versions.tf file found - best practice: define terraform and provider versions in versions.tf
    return 1
  fi

  if ! grep -q required_version "$TERRAFORM_DIR/versions.tf"; then
    log_error required_version not set in versions.tf
    return 1
  fi

  if ! grep -q required_providers "$TERRAFORM_DIR/versions.tf"; then
    log_error No required_providers block found in versions.tf
    return 1
  fi

  log_info Provider requirements validated
  return 0
}

check_module_versions() {
  log_info Checking module source versions
  local unpinned=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if echo "$line" | grep -q 'source.*git:' && ! echo "$line" | grep -qE 'ref=|tag='; then
      unpinned=$((unpinned + 1))
      log_warning "Git module source unpinned: $line"
    fi
    if echo "$line" | grep -q 'source.*registry' && ! echo "$line" | grep -q 'version'; then
      unpinned=$((unpinned + 1))
      log_warning "Registry module unpinned: $line"
    fi
  done < <(grep -R -h 'source' "$TERRAFORM_DIR" --include='*.tf' 2>/dev/null || true)

  [ $unpinned -eq 0 ] && return 0 || return 1
}

fix_floating_versions() {
  log_info Fixing floating version ranges
  local files_fixed=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if grep -q '~>' "$file"; then
      log_info "WARNING: Manual fix required for ~> in $file"
      log_info 'Example: version = "~> 2.0" should become version = ">= 2.0, < 3.0"'
      files_fixed=$((files_fixed + 1))
    fi
  done < <(find "$TERRAFORM_DIR" -name "*.tf" -type f)

  if [ $files_fixed -gt 0 ]; then
    log_error "Manual fixes required for $files_fixed files"
    return 1
  fi

  log_info No floating versions found
  return 0
}

main() {
  if [ ! -d "$TERRAFORM_DIR" ]; then
    log_warning Terraform directory not found, skipping version pin validation
    return 0
  fi

  log_info Checking Terraform version pins: $TERRAFORM_DIR

  local floating_status=0
  local provider_status=0
  local module_status=0

  check_floating_versions || floating_status=$?
  check_provider_requirements || provider_status=$?
  check_module_versions || module_status=$?

  if [[ $floating_status -ne 0 || $provider_status -ne 0 || $module_status -ne 0 ]]; then
    log_error Terraform version pin validation failed
    return 1
  fi

  log_info Terraform version pin validation complete
}

main "$@"
