#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/health-check-and-rollback.sh
# @module      ops/health-check-and-rollback
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/health-check-and-rollback.sh
# @description IaC Lifecycle Control - Health check with automatic rollback triggers (#1531)
# @governance GOV-002 - Immutable, idempotent health checking and remediation
# @automation Runs on every deployment to validate system state and trigger rollback on failure
# @prerequisite Must source scripts/_common/init.sh

set -euo pipefail

# Source bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
readonly HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"
readonly HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
readonly AUTO_ROLLBACK_ON_FAILURE="${AUTO_ROLLBACK_ON_FAILURE:-true}"
readonly ROLLBACK_FAILURE_THRESHOLD="${ROLLBACK_FAILURE_THRESHOLD:-3}"

# Health check endpoints (from canonical config)
declare -A HEALTH_ENDPOINTS=(
  ["caddy"]="code-server-caddy"
  ["execution-scheduler"]="code-server-execution-scheduler"
  ["opa"]="code-server-opa"
  ["oauth2-proxy"]="code-server-oauth2-proxy"
  ["redpanda"]="code-server-redpanda"
  ["postgres"]="code-server-postgres"
  ["redis"]="code-server-redis"
)

# Service dependencies for validation
declare -A SERVICE_DEPS=(
  ["execution-scheduler"]="postgres,redis,redpanda"
  ["opa"]="postgres"
  ["caddy"]="execution-scheduler,opa"
)

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================
trap 'log_error "Health check failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Health check complete"; true' EXIT

# ==============================================================================
# HEALTH CHECK FUNCTIONS
# ==============================================================================

get_git_sha() {
  git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# Run a Docker health check on a remote host.
check_remote_container_health() {
  local host="$1"
  local container="$2"

  ssh -o BatchMode=yes -o ConnectTimeout=10 -l akushnir -p 22 "$host" \
    "docker inspect --format '{{.State.Health.Status}}' ${container} 2>/dev/null" \
    | grep -Eq '^(healthy|no-health)$'
}

# Check HTTP endpoint health
check_http_health() {
  local service="$1"
  local endpoint="$2"
  local timeout="${HEALTH_CHECK_TIMEOUT}"
  
  if curl -fsS --max-time "${timeout}" "${endpoint}" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Check TCP port health
check_port_health() {
  local service="$1"
  local host_port="$2"
  local timeout="${HEALTH_CHECK_TIMEOUT}"
  
  # Extract host and port
  local host="${host_port%%:*}"
  local port="${host_port##*:}"
  
  timeout "${timeout}" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null
  return $?
}

# Main health check for a service
check_service_health() {
  local service="$1"
  local container_name="${HEALTH_ENDPOINTS[$service]:-}"
  local retry_count=0
  
  if [ -z "$container_name" ]; then
    log_warn "No health endpoint configured for service: $service"
    return 1
  fi
  
  if [ -z "${PRIMARY_HOST:-}" ] || [ -z "${REPLICA_HOST:-}" ]; then
    log_warn "PRIMARY_HOST/REPLICA_HOST not set; cannot run remote health checks"
    return 1
  fi

  local host
  while [ $retry_count -lt "$HEALTH_CHECK_RETRIES" ]; do
    for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
      if check_remote_container_health "$host" "$container_name"; then
        log_info "✅ $service health check passed on ${host}"
        return 0
      fi
    done
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt "$HEALTH_CHECK_RETRIES" ]; then
      log_warn "Health check for $service failed (attempt $retry_count/$HEALTH_CHECK_RETRIES), retrying..."
      sleep 2
    fi
  done
  
  log_error "❌ $service health check FAILED after $HEALTH_CHECK_RETRIES retries"
  return 1
}

# ==============================================================================
# DEPENDENCY VALIDATION
# ==============================================================================

# Validate all service dependencies are running
validate_dependencies() {
  local service="$1"
  local deps="${SERVICE_DEPS[$service]:-}"
  
  if [ -z "$deps" ]; then
    return 0  # No dependencies defined
  fi
  
  # Split comma-separated dependencies
  IFS=',' read -ra dep_array <<< "$deps"
  
  for dep in "${dep_array[@]}"; do
    if ! check_service_health "$dep"; then
      log_error "Dependency $dep for $service is unhealthy"
      return 1
    fi
  done
  
  return 0
}

# ==============================================================================
# COMPREHENSIVE HEALTH CHECK
# ==============================================================================

run_full_health_check() {
  local failed_services=()
  local total_checks=0
  local passed_checks=0
  
  log_info "Starting comprehensive health check..."
  log_info "Configuration: interval=${HEALTH_CHECK_INTERVAL}s, timeout=${HEALTH_CHECK_TIMEOUT}s, retries=${HEALTH_CHECK_RETRIES}"
  
  # Check each configured service
  for service in "${!HEALTH_ENDPOINTS[@]}"; do
    total_checks=$((total_checks + 1))
    
    if validate_dependencies "$service" && check_service_health "$service"; then
      passed_checks=$((passed_checks + 1))
    else
      failed_services+=("$service")
    fi
  done
  
  # Report summary
  log_info "Health check summary: $passed_checks/$total_checks services healthy"
  
  if [ ${#failed_services[@]} -gt 0 ]; then
    log_error "Failed services: ${failed_services[*]}"
    return 1
  fi
  
  return 0
}

# ==============================================================================
# AUTOMATIC ROLLBACK LOGIC
# ==============================================================================

# Get timestamp of last stable deployment
get_last_stable_deployment() {
  local state_dir="${REPO_ROOT}/.bootstrap-state"
  
  if [ -d "$state_dir" ]; then
    ls -1t "$state_dir"/init-*.json 2>/dev/null | head -2 | tail -1 | xargs basename -a 2>/dev/null | sed 's/init-//;s/.json//' || echo ""
  else
    echo ""
  fi
}

# Trigger automatic rollback
trigger_auto_rollback() {
  local failure_count="$1"
  
  if [ "$AUTO_ROLLBACK_ON_FAILURE" != "true" ]; then
    log_warn "Auto-rollback disabled, manual intervention required"
    return 1
  fi
  
  if [ "$failure_count" -ge "$ROLLBACK_FAILURE_THRESHOLD" ]; then
    log_error "Consecutive failure threshold reached ($failure_count >= $ROLLBACK_FAILURE_THRESHOLD), initiating auto-rollback..."
    
    # Call the standard rollback script
    if [ -f "${REPO_ROOT}/scripts/ops/rollback.sh" ]; then
      bash "${REPO_ROOT}/scripts/ops/rollback.sh" auto
      return $?
    else
      log_error "Rollback script not found: ${REPO_ROOT}/scripts/ops/rollback.sh"
      return 1
    fi
  fi
  
  return 0
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  local consecutive_failures=0
  local last_failure_time=0
  
  log_info "IaC Health Check & Auto-Rollback System Started"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Git SHA: $(get_git_sha)"
  
  # Initial health check
  if ! run_full_health_check; then
    consecutive_failures=1
    last_failure_time=$(date +%s)
    
    log_error "Initial health check failed"
    trigger_auto_rollback "$consecutive_failures"
    exit 1
  fi
  
  log_success "✅ All systems healthy"
  exit 0
}

# ==============================================================================
# EXECUTION
# ==============================================================================

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
