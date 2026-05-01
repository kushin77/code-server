#!/bin/bash
# @file domain-variability-enforcer.sh
# @module infrastructure/governance
# @description P3-1531: Enforce domain and config variability - replace hardcoded domains with env vars
# @governance GOV-002: IaC, Immutable, Idempotent - All domain references must be env-var driven
# @usage domain-variability-enforcer.sh [--check] [--fix] [--report]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${REPO_ROOT}/artifacts/domain-variability-report.json"

source "${REPO_ROOT}/scripts/_common/init.sh"
source "${REPO_ROOT}/scripts/_common/hosts.sh"

# Critical domain and host strings that must be templated
declare -A REFERENCE_VARS=(
  ["${APEX_DOMAIN}"]='${APEX_DOMAIN}'
  ["${IDE_DOMAIN}"]='${IDE_DOMAIN}'
  ["${AUTH_DOMAIN}"]='${AUTH_DOMAIN}'
  ["${API_DOMAIN}"]='${API_DOMAIN}'
  ["${REGISTRY_DOMAIN}"]='${REGISTRY_DOMAIN}'
  ["${PRIMARY_HOST}"]='${PRIMARY_HOST}'
  ["${REPLICA_HOST}"]='${REPLICA_HOST}'
)

TARGET_FILES=(
  "${REPO_ROOT}/Caddyfile"
  "${REPO_ROOT}/docker-compose.yml"
  "${REPO_ROOT}/terraform/on-prem.tfvars"
  "${REPO_ROOT}/docs/runbooks/infrastructure-lifecycle-runbook.md"
  "${REPO_ROOT}/scripts/_common/rollback-manager.sh"
)

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

# Find all hardcoded domain references
find_hardcoded_domains() {
  log_info "Scanning for hardcoded domain references..."
  
  local violations=()
  
  # Scan infrastructure files
  for file in "${TARGET_FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    
    for reference in "${!REFERENCE_VARS[@]}"; do
      # Skip if reference is already templated
      if grep -q "\${.*DOMAIN}" "${file}" 2>/dev/null; then
        continue
      fi
      
      # Check for hardcoded domain or host reference
      if grep -q "${reference}" "${file}" 2>/dev/null; then
        local count=$(grep -c "${reference}" "${file}" 2>/dev/null || echo 0)
        violations+=("${file}:${reference}:${count}")
        log_warning "Found ${count} hardcoded references to '${reference}' in ${file}"
      fi
    done
  done
  
  mkdir -p "$(dirname "${REPORT_FILE}")"
  {
    printf '{\n'
    printf '  "scan_timestamp": "%s",\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf '  "violations": [\n'
    local first_violation="true"
    for violation in "${violations[@]}"; do
      IFS=':' read -r file reference count <<< "${violation}"
      if [[ "${first_violation}" == "false" ]]; then
        printf ',\n'
      fi
      first_violation="false"
      printf '    {"file": "%s", "reference": "%s", "count": %s}' "${file}" "${reference}" "${count}"
    done
    printf '\n  ],\n'
    if [[ ${#violations[@]} -gt 0 ]]; then
      printf '  "status": "FOUND_VIOLATIONS"\n'
    else
      printf '  "status": "CLEAN"\n'
    fi
    printf '}\n'
  } > "${REPORT_FILE}"
  
  return $([ ${#violations[@]} -eq 0 ] && echo 0 || echo 1)
}

# Fix hardcoded domains
fix_hardcoded_domains() {
  log_info "Fixing hardcoded domain references..."
  
  local files_modified=0
  
  for file in "${TARGET_FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    
    local file_modified=0
    for reference in "${!REFERENCE_VARS[@]}"; do
      local var="${REFERENCE_VARS[${reference}]}"
      
      # Only fix if not already templated
      if ! grep -q "\${.*DOMAIN}" "${file}" 2>/dev/null; then
        local before=$(grep -c "${reference}" "${file}" 2>/dev/null || echo 0)
        if [[ "${before}" -gt 0 ]]; then
          sed -i "s|${reference}|${var}|g" "${file}"
          local after=$(grep -c "${reference}" "${file}" 2>/dev/null || echo 0)
          log_info "Fixed ${reference} in ${file}: ${before} → ${after}"
          file_modified=1
        fi
      fi
    done
    
    if [[ ${file_modified} -eq 1 ]]; then
      files_modified=$((files_modified + 1))
    fi
  done
  
  log_info "Fixed domains in ${files_modified} files"
  return $([ ${files_modified} -eq 0 ] && echo 1 || echo 0)
}

# Validate environment variables exist
validate_env_vars() {
  log_info "Validating required environment variables..."
  
  local missing_vars=()
  local required_vars=("APEX_DOMAIN" "IDE_DOMAIN" "AUTH_DOMAIN" "API_DOMAIN" "REGISTRY_DOMAIN" "PRIMARY_HOST" "REPLICA_HOST")
  
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing_vars+=("${var}")
    fi
  done
  
  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Missing required environment variables: ${missing_vars[*]}"
    return 1
  fi
  
  log_info "All required environment variables present"
  return 0
}

# Main
main() {
  local mode="${1:---check}"
  
  case "${mode}" in
    --check)
      find_hardcoded_domains
      ;;
    --fix)
      validate_env_vars || exit 1
      fix_hardcoded_domains
      ;;
    --report)
      find_hardcoded_domains
      jq '.' "${REPORT_FILE}"
      ;;
    *)
      log_error "Unknown mode: ${mode}"
      echo "Usage: domain-variability-enforcer.sh [--check|--fix|--report]"
      exit 1
      ;;
  esac
}

main "$@"