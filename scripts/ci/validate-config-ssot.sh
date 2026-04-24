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
  local required_files=(
    "docker-compose.yml"
    "Caddyfile"
    "terraform/variables.tf"
    "terraform/on-prem.tfvars"
  )
  
  for file in "${required_files[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${file}" ]]; then
      log_error "Required file not found: ${file}"
      untracked=$((untracked + 1))
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
  
  local missing=0
  
  for var in "${required_vars[@]}"; do
    if ! grep -r "\${${var}}" "${REPO_ROOT}"/docker-compose.yml "${REPO_ROOT}"/Caddyfile 2>/dev/null | grep -q .; then
      log_warning "Environment variable not referenced in infrastructure: ${var}"
    else
      log_success "Variable referenced: ${var}"
    fi
  done
  
  return 0
}

# Validate no hardcoded credentials
validate_no_credentials() {
  log_info "Scanning for hardcoded credentials..."
  
  local violations=0
  
  # Check for common credential patterns
  for pattern in 'password=' 'secret=' 'token=' 'key=' 'api_key='; do
    if grep -ri "${pattern}" "${REPO_ROOT}"/{docker-compose.yml,Caddyfile,terraform/} 2>/dev/null | grep -v '\${' | grep -q .; then
      log_error "Potential hardcoded credential pattern found: ${pattern}"
      violations=$((violations + 1))
    fi
  done
  
  return $([ ${violations} -eq 0 ] && echo 0 || echo 1)
}

# Generate compliance report
generate_report() {
  local vc_status="$1"
  local env_status="$2"
  local cred_status="$3"
  
  local overall_status="PASS"
  [[ "${vc_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${cred_status}" == "FAIL" ]] && overall_status="FAIL"
  
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "${overall_status}",
  "checks": {
    "version_control": "${vc_status}",
    "env_variables": "${env_status}",
    "no_credentials": "${cred_status}"
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
  
  validate_version_control || vc_status="FAIL"
  validate_env_var_pattern || env_status="FAIL"
  validate_no_credentials || cred_status="FAIL"
  
  generate_report "${vc_status}" "${env_status}" "${cred_status}"
  
  if [[ "${vc_status}" == "FAIL" ]] || [[ "${cred_status}" == "FAIL" ]]; then
    log_error "Configuration SSOT validation FAILED"
    exit 1
  fi
  
  log_success "Configuration SSOT validation PASSED"
}

main "$@"