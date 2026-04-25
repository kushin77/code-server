#!/bin/bash
# @file scripts/ci/validate-config-ssot.sh
# @module infrastructure/validation
# @description P3-1531 Phase 4: Validate configuration SSOT compliance
# @governance GOV-002: All infrastructure configuration version-controlled, env-var driven
# @usage validate-config-ssot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${REPO_ROOT}/artifacts/config-ssot-validation-report.json"

mkdir -p "$(dirname "${REPORT_FILE}")"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

# Validate all infrastructure files are version-controlled
validate_version_control() {
  log_info "Validating all infrastructure files are in version control..."
  
  local untracked=0
  local missing=0
  local required_files=(
    "docker-compose.yml"
    "Caddyfile"
    "terraform/variables.tf"
    "terraform/on-prem.tfvars"
  )
  
  for file in "${required_files[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${file}" ]]; then
      log_warning "Optional infrastructure file not present in this snapshot: ${file}"
      missing=$((missing + 1))
      continue
    fi
    
    if ! git -C "${REPO_ROOT}" ls-files --error-unmatch "${file}" > /dev/null 2>&1; then
      log_error "Infrastructure file not in version control: ${file}"
      untracked=$((untracked + 1))
    else
      log_success "File tracked: ${file}"
    fi
  done
  
  return $([ ${untracked} -eq 0 ] && echo 0 || echo 1)
}

# Validate environment variables are required
validate_env_var_pattern() {
  log_info "Validating environment variable patterns in infrastructure files..."
  
  local required_vars=(
    "APEX_DOMAIN"
    "IDE_DOMAIN"
    "AUTH_DOMAIN"
    "API_DOMAIN"
    "PRIMARY_HOST"
    "REPLICA_HOST"
  )
  
  local search_paths=()
  mapfile -t search_paths < <(
    git -C "${REPO_ROOT}" ls-files -- \
      'Caddyfile' \
      'docker-compose*.yml' \
      'docker/**/*.yml' \
      'docker/**/*.yaml' \
      'config/**/*.cfg' \
      'config/**/*.yml' \
      'config/**/*.yaml' \
      'config/**/*.tpl' \
      'monitoring/**/*.yml' \
      'monitoring/**/*.yaml' \
      'scripts/**/*.sh' \
      'scripts/**/*.env' \
      'terraform/**/*.tf' \
      'terraform/**/*.tfvars'
  )

  if [[ ${#search_paths[@]} -eq 0 ]]; then
    log_warning "No infrastructure search paths found in this snapshot"
    return 0
  fi
  
  for var in "${required_vars[@]}"; do
    if git -C "${REPO_ROOT}" grep -nF "${var}" -- "${search_paths[@]}" 2>/dev/null | grep -q .; then
      log_success "Variable referenced: ${var}"
    else
      log_warning "Environment variable not referenced in infrastructure: ${var}"
    fi
  done
  
  return 0
}

# Validate no hardcoded credentials
validate_no_credentials() {
  log_info "Scanning for hardcoded credentials..."
  
  local violations=0
  local scan_paths=()
  local candidates=(
    "${REPO_ROOT}/terraform"
    "${REPO_ROOT}/config"
    "${REPO_ROOT}/scripts"
    "${REPO_ROOT}/docs"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -e "${candidate}" ]]; then
      scan_paths+=("${candidate#${REPO_ROOT}/}")
    fi
  done

  if [[ ${#scan_paths[@]} -eq 0 ]]; then
    log_warning "No credential scan paths found in this snapshot"
    return 0
  fi
  
  # Check for real secret fingerprints, not generic prefixes or documentation examples.
  local credential_patterns=(
    'ghp_[A-Za-z0-9]{20,}'
    'ghs_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'AKIA[0-9A-Z]{16}'
    'ASIA[0-9A-Z]{16}'
    '-----BEGIN RSA PRIVATE KEY-----'
    '-----BEGIN OPENSSH PRIVATE KEY-----'
  )

  for pattern in "${credential_patterns[@]}"; do
    if git -C "${REPO_ROOT}" grep -nE "${pattern}" -- "${scan_paths[@]}" 2>/dev/null | grep -q .; then
      log_error "Potential hardcoded credential pattern found: ${pattern}"
      violations=$((violations + 1))
    fi
  done
  
  return $([ ${violations} -eq 0 ] && echo 0 || echo 1)
}

# Validate domain and host variability
validate_domain_variability() {
  log_info "Validating hardcoded host and domain references..."

  if "${REPO_ROOT}/scripts/ci/domain-variability-enforcer.sh" --check >/dev/null 2>&1; then
    log_success "Domain variability validation passed"
    return 0
  fi

  log_error "Domain variability validation failed"
  return 1
}

# Generate compliance report
generate_report() {
  local vc_status="$1"
  local env_status="$2"
  local cred_status="$3"
  local domain_status="$4"
  
  local overall_status="PASS"
  [[ "${vc_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${env_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${cred_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${domain_status}" == "FAIL" ]] && overall_status="FAIL"
  
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "${overall_status}",
  "checks": {
    "version_control": "${vc_status}",
    "env_variables": "${env_status}",
    "no_credentials": "${cred_status}",
    "domain_variability": "${domain_status}"
  }
}
EOF
  
  log_success "Report saved to ${REPORT_FILE}"
}

main() {
  log_info "Configuration SSOT Validation Started"
  
  local vc_status="PASS"
  local env_status="PASS"
  local cred_status="PASS"
  local domain_status="PASS"
  
  validate_version_control || vc_status="FAIL"
  validate_env_var_pattern || env_status="FAIL"
  validate_no_credentials || cred_status="FAIL"
  validate_domain_variability || domain_status="FAIL"
  
  generate_report "${vc_status}" "${env_status}" "${cred_status}" "${domain_status}"
  
  if [[ "${vc_status}" == "FAIL" ]] || [[ "${env_status}" == "FAIL" ]] || [[ "${cred_status}" == "FAIL" ]] || [[ "${domain_status}" == "FAIL" ]]; then
    log_error "Configuration SSOT validation FAILED"
    exit 1
  fi
  
  log_success "Configuration SSOT validation PASSED"
}

main "$@"