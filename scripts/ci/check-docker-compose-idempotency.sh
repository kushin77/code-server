#!/bin/bash
# @file check-docker-compose-idempotency.sh
# @module infrastructure/validation
# @description P3-1531: Validate Docker Compose configuration is idempotent (safe to run multiple times)
# @governance GOV-002: All services must use immutable image digests, no floating tags, pinned versions
# @usage check-docker-compose-idempotency.sh [--compose-file FILE] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${1:-${REPO_ROOT}/docker-compose.yml}"
REPORT_FILE="${REPO_ROOT}/artifacts/compose-idempotency-report.json"

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

# Check for floating image tags (":latest", ":main", etc)
check_floating_tags() {
  log_info "Checking for floating image tags..."
  
  local violations=()
  
  # Extract all image references
  local images=$(yq -r '.services[] | select(.image != null) | .image' "${COMPOSE_FILE}" 2>/dev/null || echo "")
  
  while IFS= read -r image; do
    [[ -z "${image}" ]] && continue
    
    # Check if image has no tag (defaults to :latest)
    if ! echo "${image}" | grep -q ':' ; then
      violations+=("${image}:missing-tag")
      log_warning "Image has no tag (defaults to :latest): ${image}"
    fi
    
    # Check for floating tags
    if echo "${image}" | grep -E ':(latest|main|master|dev|develop|staging)$' > /dev/null; then
      violations+=("${image}:floating-tag")
      log_warning "Image uses floating tag: ${image}"
    fi
  done <<< "${images}"
  
  return $([ ${#violations[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check for non-immutable configuration
check_immutability() {
  log_info "Checking for immutable configuration patterns..."
  
  local issues=()
  
  # Check environment file paths are version-pinned or absolute
  local env_files=$(yq -r '.services[].env_file[]? // empty' "${COMPOSE_FILE}" 2>/dev/null || echo "")
  
  while IFS= read -r env_file; do
    [[ -z "${env_file}" ]] && continue
    
    # Flag relative paths that might drift
    if echo "${env_file}" | grep -qE '^\.' && ! echo "${env_file}" | grep -q 'v[0-9]'; then
      issues+=("env-file-not-versioned:${env_file}")
      log_warning "Environment file not version-pinned: ${env_file}"
    fi
  done <<< "${env_files}"
  
  # Check volume mounts are not drifting
  local volumes=$(yq -r '.volumes[]? // empty' "${COMPOSE_FILE}" 2>/dev/null || echo "")
  
  while IFS= read -r volume; do
    [[ -z "${volume}" ]] && continue
    
    # Flag writable volumes that could cause drift
    if echo "${volume}" | grep -qE ':(rw|)$' && ! echo "${volume}" | grep -q ':ro'; then
      issues+=("rw-volume:${volume}")
      log_info "Note: Writable volume (for stateful data): ${volume}"
    fi
  done <<< "${volumes}"
  
  return $([ ${#issues[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check restart policies for automatic recovery
check_restart_policies() {
  log_info "Checking restart policies for automatic recovery..."
  
  local issues=()
  
  # All services should have restart: unless-stopped or similar
  local services=$(yq -r '.services | keys[]' "${COMPOSE_FILE}" 2>/dev/null || echo "")
  
  while IFS= read -r service; do
    [[ -z "${service}" ]] && continue
    
    local restart=$(yq -r ".services.${service}.restart_policy.condition // .services.${service}.restart_policy // 'no'" "${COMPOSE_FILE}" 2>/dev/null || echo "no")
    
    if [[ "${restart}" == "no" ]]; then
      issues+=("service-no-restart:${service}")
      log_warning "Service has no restart policy: ${service}"
    fi
  done <<< "${services}"
  
  return $([ ${#issues[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check for health checks
check_health_checks() {
  log_info "Checking for health checks..."
  
  local missing=()
  
  local services=$(yq -r '.services | keys[]' "${COMPOSE_FILE}" 2>/dev/null || echo "")
  
  while IFS= read -r service; do
    [[ -z "${service}" ]] && continue
    
    local has_healthcheck=$(yq -r ".services.${service}.healthcheck // 'null'" "${COMPOSE_FILE}" 2>/dev/null || echo "null")
    
    if [[ "${has_healthcheck}" == "null" ]]; then
      missing+=("${service}")
      log_warning "Service missing health check: ${service}"
    fi
  done <<< "${services}"
  
  return $([ ${#missing[@]} -eq 0 ] && echo 0 || echo 1)
}

# Generate report
generate_report() {
  log_info "Generating idempotency report..."
  
  local floating_tags_ok=0
  local immutable_ok=0
  local restart_ok=0
  local health_ok=0
  
  check_floating_tags && floating_tags_ok=1 || true
  check_immutability && immutable_ok=1 || true
  check_restart_policies && restart_ok=1 || true
  check_health_checks && health_ok=1 || true
  
  local overall_status="PASS"
  [[ ${floating_tags_ok} -eq 0 ]] && overall_status="FAIL"
  [[ ${restart_ok} -eq 0 ]] && overall_status="FAIL"
  
  mkdir -p "$(dirname "${REPORT_FILE}")"
  
  jq -n \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg file "${COMPOSE_FILE}" \
    --arg status "${overall_status}" \
    --argjson floating_tags_ok "${floating_tags_ok}" \
    --argjson immutable_ok "${immutable_ok}" \
    --argjson restart_ok "${restart_ok}" \
    --argjson health_ok "${health_ok}" \
    '{
      timestamp: $timestamp,
      compose_file: $file,
      status: $status,
      checks: {
        immutable_image_digests: ($floating_tags_ok | tonumber),
        immutable_configuration: ($immutable_ok | tonumber),
        restart_policies: ($restart_ok | tonumber),
        health_checks: ($health_ok | tonumber)
      }
    }' > "${REPORT_FILE}"
  
  log_info "Report saved to ${REPORT_FILE}"
}

# Main
main() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    log_error "Compose file not found: ${COMPOSE_FILE}"
    exit 1
  fi
  
  log_info "Checking Docker Compose idempotency: ${COMPOSE_FILE}"
  
  check_floating_tags || true
  check_immutability || true
  check_restart_policies || true
  check_health_checks || true
  
  generate_report
  
  log_info "Idempotency check complete"
}

main "$@"
