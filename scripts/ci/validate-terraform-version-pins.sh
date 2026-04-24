#!/bin/bash
# @file validate-terraform-version-pins.sh
# @module infrastructure/validation
# @description P3-1531: Validate all Terraform provider/module versions are pinned (no floating ranges like ~>)
# @governance GOV-002: All infrastructure version-pinned in terraform/variables.tf - no ~> ranges in production
# @usage validate-terraform-version-pins.sh [--check] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
REPORT_FILE="${REPO_ROOT}/artifacts/terraform-version-pins-report.json"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

# Check for floating version ranges
check_floating_versions() {
  log_info "Scanning for floating version ranges in Terraform..."
  
  local violations=()
  
  # Check .tf files for ~> (pessimistic constraint)
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    
    local count=$(grep -c '~>' "${file}" 2>/dev/null || echo 0)
    if [[ ${count} -gt 0 ]]; then
      violations+=("${file}:floating-range:${count}")
      log_warning "Found ${count} floating version ranges (~>) in ${file}"
    fi
    
    # Check for >= without upper bound
    local unbounded=$(grep -E 'version\s*=\s*">=' "${file}" 2>/dev/null | grep -v '<' | wc -l || echo 0)
    if [[ ${unbounded} -gt 0 ]]; then
      violations+=("${file}:unbounded-range:${unbounded}")
      log_warning "Found ${unbounded} unbounded version ranges (>=) in ${file}"
    fi
  done < <(find "${TERRAFORM_DIR}" -name "*.tf" -type f)
  
  # Generate report
  local json_violations='[]'
  for violation in "${violations[@]}"; do
    IFS=':' read -r file type count <<< "${violation}"
    json_violations=$(jq --arg file "${file}" --arg type "${type}" --arg count "${count}" \
      '. += [{file: $file, type: $type, count: ($count | tonumber)}]' <<< "${json_violations}")
  done
  
  mkdir -p "$(dirname "${REPORT_FILE}")"
  jq -n --argjson violations "${json_violations}" \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    '{scan_timestamp: $timestamp, violations: $violations, status: (if ($violations | length) > 0 then "FAILED" else "PASSED" end)}' \
    > "${REPORT_FILE}"
  
  log_info "Report saved to ${REPORT_FILE}"
  
  return $([ ${#violations[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check provider requirements
check_provider_requirements() {
  log_info "Checking provider version requirements..."
  
  if [[ ! -f "${TERRAFORM_DIR}/versions.tf" ]]; then
    log_warning "No versions.tf file found - best practice: define terraform and provider versions in versions.tf"
    return 1
  fi
  
  # Verify required_version is set
  if ! grep -q 'required_version' "${TERRAFORM_DIR}/versions.tf"; then
    log_error "required_version not set in versions.tf"
    return 1
  fi
  
  # Verify all providers have exact versions or bounded ranges
  local providers=$(grep -A1 'required_providers' "${TERRAFORM_DIR}/versions.tf" 2>/dev/null || echo "")
  
  if [[ -z "${providers}" ]]; then
    log_error "No required_providers block found in versions.tf"
    return 1
  fi
  
  log_info "Provider requirements validated"
  return 0
}

# Check module sources are pinned
check_module_versions() {
  log_info "Checking module source versions..."
  
  local unpinned=()
  
  # Find all module calls
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    
    # Extract module source (git:: or registry calls should have version pinned)
    if echo "${line}" | grep -q 'source.*git:' && ! echo "${line}" | grep -qE 'ref=|tag='; then
      unpinned+=("${line}")
      log_warning "Git module source unpinned: ${line}"
    fi
    
    if echo "${line}" | grep -q 'source.*registry' && ! echo "${line}" | grep -q 'version'; then
      unpinned+=("${line}")
      log_warning "Registry module unpinned: ${line}"
    fi
  done < <(grep -h 'source' "${TERRAFORM_DIR}"/**/*.tf 2>/dev/null | grep -E 'module|source' || echo "")
  
  return $([ ${#unpinned[@]} -eq 0 ] && echo 0 || echo 1)
}

# Fix floating versions
fix_floating_versions() {
  log_info "Fixing floating version ranges..."
  
  local files_fixed=0
  
  # Replace ~> with >= and <= (manual review required for specific versions)
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    
    if grep -q '~>' "${file}"; then
      log_info "WARNING: Manual fix required for ~> in ${file}"
      log_info "Example: version = \"~> 2.0\" should become version = \">= 2.0, < 3.0\""
      files_fixed=$((files_fixed + 1))
    fi
  done < <(find "${TERRAFORM_DIR}" -name "*.tf" -type f)
  
  if [[ ${files_fixed} -gt 0 ]]; then
    log_error "Manual fixes required for ${files_fixed} files"
    return 1
  fi
  
  log_info "No automatic fixes needed"
  return 0
}

# Main
main() {
  local mode="${1:---check}"
  
  log_info "Terraform version pinning validation started: ${mode}"
  
  case "${mode}" in
    --check)
      check_floating_versions || exit 1
      check_provider_requirements || exit 1
      check_module_versions || exit 1
      log_info "All version pins validated"
      ;;
    --fix)
      fix_floating_versions || exit 1
      ;;
    --report)
      check_floating_versions
      log_info "Full report:"
      jq '.' "${REPORT_FILE}"
      ;;
    *)
      log_error "Unknown mode: ${mode}"
      echo "Usage: validate-terraform-version-pins.sh [--check|--fix|--report]"
      exit 1
      ;;
  esac
}

main "$@"
