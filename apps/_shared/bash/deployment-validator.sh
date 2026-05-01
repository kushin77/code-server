#!/usr/bin/env bash
# @file apps/_shared/bash/deployment-validator.sh
# @module shared/deployment
# @description Reusable deployment validation library for scripts
# @governance GOV-002: Centralized validation logic to ensure consistency
# @exports validate_docker_compose, validate_service_health, validate_resources, validate_compliance

# Trap handlers for library (executed by caller if script runs directly)
trap 'exit 1' ERR
trap ':' EXIT

# Prevent multiple sourcing
if [[ -n "${_DEPLOYMENT_VALIDATOR_SOURCED:-}" ]]; then
  return 0
fi
_DEPLOYMENT_VALIDATOR_SOURCED="true"

# Color codes for output
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[1;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# Validation counters
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

# ============================================================================
# DOCKER COMPOSE VALIDATION
# ============================================================================

validate_docker_compose() {
  local compose_file="${1:-.}"
  local silent="${2:-false}"
  
  if [[ "$silent" != "true" ]]; then
    echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Validating Docker Compose: $compose_file"
  fi
  
  if [[ ! -f "$compose_file" ]]; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Docker Compose file not found: $compose_file"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  if ! docker-compose -f "$compose_file" config > /dev/null 2>&1; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Invalid Docker Compose syntax: $compose_file"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

validate_all_docker_compose_files() {
  local pattern="${1:-docker-compose*.yml}"
  local failed=0
  
  for file in $pattern; do
    [[ -f "$file" ]] || continue
    if ! validate_docker_compose "$file" true; then
      failed+=1
    fi
  done
  
  if [[ $failed -eq 0 ]]; then
    echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} All Docker Compose files valid"
    return 0
  else
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} $failed Docker Compose files invalid"
    return 1
  fi
}

# ============================================================================
# SERVICE HEALTH VALIDATION
# ============================================================================

validate_service_health() {
  local service_name="$1"
  local health_endpoint="${2:-http://localhost:8000/health}"
  local timeout="${3:-10}"
  
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Checking health: $service_name"
  
  if ! timeout "$timeout" curl -sf "$health_endpoint" > /dev/null 2>&1; then
    echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Service unreachable: $service_name at $health_endpoint"
    VALIDATION_WARNINGS+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

validate_docker_container_health() {
  local container_name="$1"
  
  if ! docker inspect "$container_name" > /dev/null 2>&1; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Container not found: $container_name"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  local health_status=$(docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
  
  case "$health_status" in
    healthy)
      echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Container healthy: $container_name"
      VALIDATION_PASSED+=1
      return 0
      ;;
    unhealthy)
      echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Container unhealthy: $container_name"
      VALIDATION_FAILED+=1
      return 1
      ;;
    starting)
      echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Container starting: $container_name"
      VALIDATION_WARNINGS+=1
      return 1
      ;;
    *)
      echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Container status unknown: $container_name ($health_status)"
      VALIDATION_WARNINGS+=1
      return 0
      ;;
  esac
}

# ============================================================================
# RESOURCE VALIDATION
# ============================================================================

validate_disk_space() {
  local min_mb="${1:-1000}"
  local path="${2:-/}"
  
  local available=$(df "$path" 2>/dev/null | awk 'NR==2 {print $4}')
  
  if [[ $available -lt $min_mb ]]; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Insufficient disk space at $path: ${available}MB < ${min_mb}MB required"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Disk space available at $path: ${available}MB"
  VALIDATION_PASSED+=1
  return 0
}

validate_memory_available() {
  local min_mb="${1:-1000}"
  
  local available=$(free 2>/dev/null | awk 'NR==2 {print $7}')
  
  if [[ $available -lt $min_mb ]]; then
    echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Low memory available: ${available}MB < ${min_mb}MB recommended"
    VALIDATION_WARNINGS+=1
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Memory available: ${available}MB"
  VALIDATION_PASSED+=1
  return 0
}

# ============================================================================
# COMPLIANCE VALIDATION
# ============================================================================

validate_script_syntax() {
  local script_file="$1"
  
  if [[ ! -f "$script_file" ]]; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Script not found: $script_file"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  if ! bash -n "$script_file" 2>/dev/null; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Script syntax error: $script_file"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

validate_ssot_compliance() {
  local script_file="$1"
  
  if ! grep -q "source.*init.sh" "$script_file" 2>/dev/null; then
    echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} SSOT compliance warning: $script_file does not source init.sh"
    VALIDATION_WARNINGS+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

validate_image_pinning() {
  local compose_file="${1:-.}"
  
  if ! grep -q "sha256:" "$compose_file" 2>/dev/null; then
    echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Image pinning warning: $compose_file lacks sha256 digests"
    VALIDATION_WARNINGS+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

# ============================================================================
# GIT VALIDATION
# ============================================================================

validate_git_clean() {
  if ! git diff --quiet 2>/dev/null; then
    echo -e "${COLOR_ERROR}[Validator]${COLOR_RESET} Git repository has uncommitted changes"
    VALIDATION_FAILED+=1
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Git repository clean"
  VALIDATION_PASSED+=1
  return 0
}

validate_git_branch() {
  local required_branch="${1:-main}"
  local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  
  if [[ "$current_branch" != "$required_branch" ]]; then
    echo -e "${COLOR_WARN}[Validator]${COLOR_RESET} Branch warning: on $current_branch, expected $required_branch"
    VALIDATION_WARNINGS+=1
    return 1
  fi
  
  VALIDATION_PASSED+=1
  return 0
}

# ============================================================================
# REPORTING
# ============================================================================

get_validation_summary() {
  local total=$((VALIDATION_PASSED + VALIDATION_FAILED + VALIDATION_WARNINGS))
  
  echo
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Summary:"
  echo "  Passed:    $VALIDATION_PASSED"
  echo "  Failed:    $VALIDATION_FAILED"
  echo "  Warnings:  $VALIDATION_WARNINGS"
  echo "  Total:     $total"
  echo
  
  if [[ $VALIDATION_FAILED -gt 0 ]]; then
    return 1
  fi
  
  return 0
}

reset_validation_counters() {
  VALIDATION_PASSED=0
  VALIDATION_FAILED=0
  VALIDATION_WARNINGS=0
}

# ============================================================================
# COMPOSITE VALIDATIONS
# ============================================================================

validate_deployment_readiness() {
  local checks_passed=0
  
  reset_validation_counters
  
  echo -e "${COLOR_SUCCESS}[Validator]${COLOR_RESET} Running deployment readiness checks..."
  echo
  
  # Docker Compose validation
  if validate_all_docker_compose_files; then
    checks_passed+=1
  fi
  
  # Git validation
  if validate_git_clean; then
    checks_passed+=1
  fi
  
  if validate_git_branch "main"; then
    checks_passed+=1
  fi
  
  # Disk space check
  if validate_disk_space 1000; then
    checks_passed+=1
  fi
  
  # Memory check
  if validate_memory_available 1000; then
    checks_passed+=1
  fi
  
  get_validation_summary
  
  return $([[ $VALIDATION_FAILED -eq 0 ]] && echo 0 || echo 1)
}

# Export functions
export -f validate_docker_compose
export -f validate_all_docker_compose_files
export -f validate_service_health
export -f validate_docker_container_health
export -f validate_disk_space
export -f validate_memory_available
export -f validate_script_syntax
export -f validate_ssot_compliance
export -f validate_image_pinning
export -f validate_git_clean
export -f validate_git_branch
export -f get_validation_summary
export -f reset_validation_counters
export -f validate_deployment_readiness
