#!/bin/bash
# @file domain-variability-enforcer.sh
# @module infrastructure/governance
# @description P3-1531: Enforce domain and config variability - replace hardcoded kushnir.cloud with env vars
# @governance GOV-002: IaC, Immutable, Idempotent - All domain references must be env-var driven
# @usage domain-variability-enforcer.sh [--check] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${REPO_ROOT}/artifacts/domain-variability-report.json"

# Critical domain strings that must be templated
declare -A DOMAIN_VARS=(
  ["kushnir.cloud"]='${APEX_DOMAIN}'
  ["ide.kushnir.cloud"]='${IDE_DOMAIN}'
  ["auth.kushnir.cloud"]='${AUTH_DOMAIN}'
  ["api.kushnir.cloud"]='${API_DOMAIN}'
  ["registry.kushnir.cloud"]='${REGISTRY_DOMAIN}'
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
  for file in "${REPO_ROOT}"/{Caddyfile,docker-compose.yml,terraform/on-prem.tfvars}; do
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    
    for domain in "${!DOMAIN_VARS[@]}"; do
      # Skip if domain is already templated
      if grep -q "\${.*DOMAIN}" "${file}" 2>/dev/null; then
        continue
      fi
      
      # Check for hardcoded domain
      if grep -q "${domain}" "${file}" 2>/dev/null; then
        local count=$(grep -c "${domain}" "${file}" 2>/dev/null || echo 0)
        violations+=("${file}:${domain}:${count}")
        log_warning "Found ${count} hardcoded references to '${domain}' in ${file}"
      fi
    done
  done
  
  # Generate JSON report
  local json_violations='[]'
  for violation in "${violations[@]}"; do
    IFS=':' read -r file domain count <<< "${violation}"
    json_violations=$(jq --arg file "${file}" --arg domain "${domain}" --arg count "${count}" \
      '. += [{file: $file, domain: $domain, count: ($count | tonumber)}]' <<< "${json_violations}")
  done
  
  mkdir -p "$(dirname "${REPORT_FILE}")"
  jq -n --argjson violations "${json_violations}" \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    '{scan_timestamp: $timestamp, violations: $violations, status: (if ($violations | length) > 0 then "FOUND_VIOLATIONS" else "CLEAN" end)}' \
    > "${REPORT_FILE}"
  
  return $([ ${#violations[@]} -eq 0 ] && echo 0 || echo 1)
}

# Fix hardcoded domains
fix_hardcoded_domains() {
  log_info "Fixing hardcoded domain references..."
  
  local files_modified=0
  
  for file in "${REPO_ROOT}"/{Caddyfile,docker-compose.yml,terraform/on-prem.tfvars}; do
    if [[ ! -f "${file}" ]]; then
      continue
    fi
    
    local file_modified=0
    for domain in "${!DOMAIN_VARS[@]}"; do
      local var="${DOMAIN_VARS[${domain}]}"
      
      # Only fix if not already templated
      if ! grep -q "\${.*DOMAIN}" "${file}" 2>/dev/null; then
        local before=$(grep -c "${domain}" "${file}" 2>/dev/null || echo 0)
        if [[ "${before}" -gt 0 ]]; then
          sed -i "s|${domain}|${var}|g" "${file}"
          local after=$(grep -c "${domain}" "${file}" 2>/dev/null || echo 0)
          log_info "Fixed ${domain} in ${file}: ${before} → ${after}"
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
  local required_vars=("APEX_DOMAIN" "IDE_DOMAIN" "AUTH_DOMAIN" "API_DOMAIN" "REGISTRY_DOMAIN")
  
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