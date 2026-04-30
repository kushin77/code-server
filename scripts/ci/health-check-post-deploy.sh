#!/bin/bash
# @file health-check-post-deploy.sh
# @module infrastructure/validation
# @description P3-1531 Phase 2: Post-deployment health verification with automatic rollback on failure
# @governance GOV-002: Health checks mandatory post-deployment, auto-rollback if critical services fail
# @usage health-check-post-deploy.sh [--endpoint ENDPOINT] [--timeout SECONDS] [--auto-rollback]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source shared helpers and normalize environment file line endings
source "${REPO_ROOT}/scripts/_common/init.sh"

# Source infrastructure configuration
source_env_file "${REPO_ROOT}/.env.infrastructure"

# Default endpoint templated from environment
DEFAULT_ENDPOINT="${API_HEALTH_ENDPOINT:=${API_PROTOCOL:-http}://${API_HOST:-localhost}:${API_PORT:-8080}/health}"
DEFAULT_TIMEOUT=300
HEALTH_REPORT="${REPO_ROOT}/artifacts/health-check-report.json"

mkdir -p "$(dirname "${HEALTH_REPORT}")"

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

probe_http_code() {
  local endpoint="$1"
  local code

  code=$(curl -s -o /dev/null -w '%{http_code}' "${endpoint}" 2>/dev/null || echo "000")
  if [[ "${code}" != "000" ]]; then
    echo "${code}"
    return 0
  fi

  if [[ -n "${PRIMARY_HOST:-}" ]]; then
    local remote_user="${REMOTE_USER:-akushnir}"
    code=$(ssh -o BatchMode=yes "${remote_user}@${PRIMARY_HOST}" \
      "curl -s -o /dev/null -w '%{http_code}' '${endpoint}' 2>/dev/null || echo 000" 2>/dev/null || echo "000")
    echo "${code}"
    return 0
  fi

  echo "000"
}

check_endpoint_health() {
  local endpoint="$1"
  local timeout="$2"
  
  log_info "Checking endpoint health: ${endpoint} (timeout: ${timeout}s)"

  if [[ "${timeout}" -le 0 ]]; then
    local http_code
    http_code=$(probe_http_code "${endpoint}")
    if [[ "${http_code}" == "200" ]]; then
      log_success "Endpoint healthy (HTTP ${http_code})"
      return 0
    fi
    log_error "Endpoint health check failed (HTTP ${http_code})"
    return 1
  fi
  
  local start_time=$(date +%s)
  local attempt=0
  local max_attempts=30
  
  while [[ $(($(date +%s) - start_time)) -lt ${timeout} ]]; do
    attempt=$((attempt + 1))
    
    local http_code
    http_code=$(probe_http_code "${endpoint}")
    
    if [[ "${http_code}" == "200" ]]; then
      log_success "Endpoint healthy (HTTP ${http_code})"
      return 0
    fi
    
    log_warning "Attempt ${attempt}: HTTP ${http_code}, retrying in 10s..."
    sleep 10
  done
  
  log_error "Endpoint health check failed after ${timeout}s"
  return 1
}

check_docker_services() {
  log_info "Checking Docker Compose service health..."
  
  cd "${REPO_ROOT}"
  local unhealthy=0
  
  # Get all services
  local services=$(docker compose ps --services 2>/dev/null || echo "")
  
  while IFS= read -r service; do
    [[ -z "${service}" ]] && continue
    
    # Check if service is running
    local state=$(docker compose ps "${service}" --format json 2>/dev/null | grep -o '"State":"[^"]*"' | cut -d'"' -f4)
    
    if [[ "${state}" != "running" ]]; then
      log_error "Service ${service} is not running (state: ${state})"
      unhealthy=$((unhealthy + 1))
    else
      log_success "Service ${service} is running"
    fi
  done <<< "${services}"
  
  return $([ ${unhealthy} -eq 0 ] && echo 0 || echo 1)
}

check_disk_space() {
  log_info "Checking disk space..."
  
  local usage=$(df -h "${REPO_ROOT}" | awk 'NR==2 {print $5}' | tr -d '%')
  local threshold=90
  
  if [[ ${usage} -gt ${threshold} ]]; then
    log_error "Disk usage critical: ${usage}% (threshold: ${threshold}%)"
    return 1
  fi
  
  log_success "Disk usage nominal: ${usage}%"
  return 0
}

check_memory() {
  log_info "Checking system memory..."
  
  # Memory check depends on OS
  if command -v free &> /dev/null; then
    local usage=$(free | awk 'NR==2 {printf int($3/$2 * 100)}')
    local threshold=90
    
    if [[ ${usage} -gt ${threshold} ]]; then
      log_warning "Memory usage high: ${usage}% (threshold: ${threshold}%)"
    else
      log_success "Memory usage nominal: ${usage}%"
    fi
  fi
  
  return 0
}

generate_health_report() {
  local endpoint_status="$1"
  local services_status="$2"
  local disk_status="$3"
  local memory_status="$4"
  
  local overall_status="PASS"
  [[ "${endpoint_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${services_status}" == "FAIL" ]] && overall_status="FAIL"
  [[ "${disk_status}" == "FAIL" ]] && overall_status="FAIL"
  
  cat > "${HEALTH_REPORT}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "${overall_status}",
  "checks": {
    "endpoint": "${endpoint_status}",
    "services": "${services_status}",
    "disk_space": "${disk_status}",
    "memory": "${memory_status}"
  }
}
EOF
  
  log_info "Health report saved to ${HEALTH_REPORT}"
}

main() {
  local endpoint="${DEFAULT_ENDPOINT}"
  local timeout="${DEFAULT_TIMEOUT}"
  local auto_rollback="false"
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --endpoint)
        endpoint="$2"
        shift 2
        ;;
      --timeout)
        timeout="$2"
        shift 2
        ;;
      --auto-rollback)
        auto_rollback="true"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Post-deployment health check initiated"
  
  local endpoint_status="PASS"
  local services_status="PASS"
  local disk_status="PASS"
  local memory_status="PASS"
  
  check_endpoint_health "${endpoint}" "${timeout}" || endpoint_status="FAIL"
  check_docker_services || services_status="FAIL"
  check_disk_space || disk_status="FAIL"
  check_memory || memory_status="FAIL"
  
  generate_health_report "${endpoint_status}" "${services_status}" "${disk_status}" "${memory_status}"
  
  # Determine overall status
  local overall_failed=0
  [[ "${endpoint_status}" == "FAIL" ]] && overall_failed=1
  [[ "${services_status}" == "FAIL" ]] && overall_failed=1
  [[ "${disk_status}" == "FAIL" ]] && overall_failed=1
  
  if [[ ${overall_failed} -eq 1 ]]; then
    log_error "Health checks FAILED"
    
    if [[ "${auto_rollback}" == "true" ]]; then
      log_warning "Auto-rollback triggered due to health check failure"
      "${SCRIPT_DIR}/automated-rollback.sh" compose --health-check || log_error "Rollback also failed"
    fi
    
    exit 1
  fi
  
  log_success "All health checks PASSED"
  return 0
}

main "$@"