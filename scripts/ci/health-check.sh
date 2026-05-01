#!/usr/bin/env bash
# @file scripts/ci/health-check.sh
# @module ci/health-checking
# @description Rapid health check for critical services before deployment
# @governance GOV-002: Fast validation to catch critical issues early
# @usage health-check.sh [--services service1,service2] [--timeout 30]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Health check complete"; rm -f /tmp/health-check-*.tmp 2>/dev/null || true' EXIT

# Configuration
TIMEOUT="${1:-30}"
CRITICAL_SERVICES=(
  "postgres:5432"
  "redis:6379"
  "redpanda:9092"
  "grafana:3000"
  "prometheus:9090"
)

REMOTE_CONTAINER_PREFIX="${REMOTE_CONTAINER_PREFIX:-code-server}"

check_remote_container_health() {
  local host="$1"
  local container="$2"

  ssh -o BatchMode=yes -o ConnectTimeout=10 -l akushnir -p 22 "$host" \
    "docker inspect --format '{{.State.Health.Status}}' ${container} 2>/dev/null" \
    | grep -Eq '^(healthy|no-health)$'
}

log_info "═══════════════════════════════════════════════════════"
log_info "CRITICAL SERVICES HEALTH CHECK"
log_info "═══════════════════════════════════════════════════════"

# Check if service is running
check_service_health() {
  local service_host="$1"
  local timeout="$2"

  IFS=':' read -r service_name service_port <<< "${service_host}"

  if [[ -z "${PRIMARY_HOST:-}" || -z "${REPLICA_HOST:-}" ]]; then
    log_warn "⚠ PRIMARY_HOST/REPLICA_HOST not configured"
    return 1
  fi

  local host
  local container_name="${REMOTE_CONTAINER_PREFIX}-${service_name}"

  for host in "${PRIMARY_HOST}" "${REPLICA_HOST}"; do
    log_info "Checking ${container_name} on ${host}..."
    if check_remote_container_health "$host" "$container_name"; then
      log_success "✓ ${container_name} is healthy on ${host}"
      return 0
    fi
  done

  log_error "✗ ${container_name} is unhealthy on all hosts"
  return 1
}

# Check remote stack status
check_remote_stack_status() {
  log_info "Checking remote stack services..."

  if [[ -z "${PRIMARY_HOST:-}" || -z "${REPLICA_HOST:-}" ]]; then
    log_warn "⚠ PRIMARY_HOST/REPLICA_HOST not configured"
    return 1
  fi

  local host
  local service
  local unhealthy=0

  for host in "${PRIMARY_HOST}" "${REPLICA_HOST}"; do
    for service in "${CRITICAL_SERVICES[@]}"; do
      service_name="${service%%:*}"
      container_name="${REMOTE_CONTAINER_PREFIX}-${service_name}"

      log_info "Checking ${container_name} on ${host}..."
      if check_remote_container_health "$host" "$container_name"; then
        log_success "✓ ${container_name} is healthy on ${host}"
      else
        log_error "✗ ${container_name} is unhealthy on ${host}"
        unhealthy+=1
      fi
    done
  done

  if [[ ${unhealthy} -gt 0 ]]; then
    log_warn "⚠ Found ${unhealthy} unhealthy remote services"
    return 1
  fi

  log_success "✓ All remote critical services healthy"
  return 0
}

# Check critical system resources
check_system_resources() {
  log_info "Checking system resources..."
  
  local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  local memory_usage=$(free | awk 'NR==2 {printf("%.0f\n", ($3/$2)*100)}')
  
  if [[ ${disk_usage} -gt 90 ]]; then
    log_warn "⚠ Disk usage high: ${disk_usage}%"
  else
    log_success "✓ Disk usage: ${disk_usage}%"
  fi
  
  if [[ ${memory_usage} -gt 85 ]]; then
    log_warn "⚠ Memory usage high: ${memory_usage}%"
  else
    log_success "✓ Memory usage: ${memory_usage}%"
  fi
}

# Verify deployment scripts
check_deployment_scripts() {
  log_info "Verifying deployment scripts..."
  
  local invalid_count=0
  while IFS= read -r script; do
    if ! bash -n "${script}" 2>/dev/null; then
      invalid_count+=1
      log_error "✗ Script syntax error: ${script}"
    fi
  done < <(find scripts/ops -name "*.sh" -type f)
  
  if [[ ${invalid_count} -eq 0 ]]; then
    log_success "✓ All deployment scripts valid"
  else
    log_error "✗ Found ${invalid_count} invalid scripts"
    return 1
  fi
}

# Main execution
main() {
  local failed=0
  
  log_info "Starting health checks (timeout: ${TIMEOUT}s)..."
  echo
  
  # Check remote stack
  if ! check_remote_stack_status; then
    failed+=1
  fi
  echo
  
  # Check critical services
  for service in "${CRITICAL_SERVICES[@]}"; do
    if ! check_service_health "${service}" "${TIMEOUT}"; then
      failed+=1
    fi
  done
  echo
  
  # Check system resources
  check_system_resources
  echo
  
  # Check deployment scripts
  if ! check_deployment_scripts; then
    failed+=1
  fi
  echo
  
  log_info "═══════════════════════════════════════════════════════"
  
  if [[ ${failed} -eq 0 ]]; then
    log_success "✓ HEALTH CHECK PASSED - All systems operational"
    return 0
  else
    log_error "✗ HEALTH CHECK FAILED - ${failed} issues found"
    return 1
  fi
}

# Execute main
main
