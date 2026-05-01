#!/usr/bin/env bash
# @file apps/_shared/bash/service-config-validator.sh
# @module shared/services
# @description Service configuration validation library
# @governance GOV-002: Enforce consistent service configuration standards
# @exports validate_service_image, validate_service_ports, validate_service_environment, validate_service_volumes

# Trap handlers for library
trap 'exit 1' ERR
trap ':' EXIT

# Prevent multiple sourcing
if [[ -n "${_SERVICE_CONFIG_VALIDATOR_SOURCED:-}" ]]; then
  return 0
fi
_SERVICE_CONFIG_VALIDATOR_SOURCED="true"

# Color codes
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[1;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# ============================================================================
# IMAGE VALIDATION
# ============================================================================

validate_service_image() {
  local service_name="$1"
  local image_spec="$2"
  
  # Check for digest pinning
  if [[ ! "$image_spec" =~ @sha256: ]]; then
    echo -e "${COLOR_ERROR}[ServiceValidator]${COLOR_RESET} Image not pinned with digest: $service_name uses $image_spec"
    return 1
  fi
  
  # Extract registry/image part
  local image_part="${image_spec%%@*}"
  
  # Validate image format
  if [[ ! "$image_part" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*/[a-zA-Z0-9._/-]+$ ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Image format unusual: $service_name uses $image_part"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Image valid: $service_name"
  return 0
}

# ============================================================================
# PORT VALIDATION
# ============================================================================

validate_service_ports() {
  local service_name="$1"
  shift
  local ports=("$@")
  
  if [[ ${#ports[@]} -eq 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} No ports exposed: $service_name"
    return 0
  fi
  
  local valid_ports=0
  for port in "${ports[@]}"; do
    # Validate port format (host:container or just container)
    if [[ "$port" =~ ^[0-9]+:[0-9]+$ ]] || [[ "$port" =~ ^[0-9]+$ ]]; then
      valid_ports+=1
    else
      echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Invalid port format in $service_name: $port"
    fi
  done
  
  if [[ $valid_ports -gt 0 ]]; then
    echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Ports valid for $service_name ($valid_ports ports)"
    return 0
  fi
  
  return 1
}

# ============================================================================
# ENVIRONMENT VARIABLE VALIDATION
# ============================================================================

validate_service_environment() {
  local service_name="$1"
  shift
  local env_vars=("$@")
  
  if [[ ${#env_vars[@]} -eq 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} No environment variables set: $service_name"
    return 0
  fi
  
  local valid_vars=0
  local sensitive_vars=()
  
  for var in "${env_vars[@]}"; do
    # Check format KEY=VALUE or KEY
    if [[ "$var" =~ ^[A-Z_][A-Z0-9_]*= ]] || [[ "$var" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      valid_vars+=1
      
      # Flag potential sensitive data
      if [[ "$var" =~ (PASSWORD|SECRET|TOKEN|KEY|AUTH) ]]; then
        sensitive_vars+=("$var")
      fi
    fi
  done
  
  if [[ ${#sensitive_vars[@]} -gt 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Sensitive variables in $service_name: ${#sensitive_vars[@]} found"
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Consider using secrets management instead of env vars"
  fi
  
  if [[ $valid_vars -gt 0 ]]; then
    echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Environment valid for $service_name ($valid_vars vars)"
    return 0
  fi
  
  return 1
}

# ============================================================================
# VOLUME VALIDATION
# ============================================================================

validate_service_volumes() {
  local service_name="$1"
  shift
  local volumes=("$@")
  
  if [[ ${#volumes[@]} -eq 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} No volumes defined: $service_name (ephemeral data)"
    return 0
  fi
  
  local valid_volumes=0
  local missing_paths=()
  
  for volume in "${volumes[@]}"; do
    # Named volume (name:path) or path (path:path) or path with modes (path:path:ro)
    if [[ "$volume" =~ ^[^:]+:[^:]+$ ]] || [[ "$volume" =~ ^[^:]+:[^:]+:[a-z]+$ ]]; then
      valid_volumes+=1
      
      # For local paths, check if they exist on host (extracted from host:container format)
      local host_path="${volume%%:*}"
      if [[ "$host_path" == /* ]] && [[ ! -e "$host_path" ]]; then
        missing_paths+=("$host_path")
      fi
    fi
  done
  
  if [[ ${#missing_paths[@]} -gt 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Volume paths missing in $service_name: ${#missing_paths[@]} paths"
  fi
  
  if [[ $valid_volumes -gt 0 ]]; then
    echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Volumes valid for $service_name ($valid_volumes volumes)"
    return 0
  fi
  
  return 1
}

# ============================================================================
# RESOURCE LIMITS VALIDATION
# ============================================================================

validate_service_resources() {
  local service_name="$1"
  local memory_limit="$2"
  local cpu_limit="$3"
  
  local has_limits=false
  
  if [[ -n "$memory_limit" ]]; then
    # Validate memory format (e.g., 512M, 1G)
    if [[ "$memory_limit" =~ ^[0-9]+[KMG]?$ ]]; then
      echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Memory limit set for $service_name: $memory_limit"
      has_limits=true
    else
      echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Invalid memory format for $service_name: $memory_limit"
    fi
  fi
  
  if [[ -n "$cpu_limit" ]]; then
    # Validate CPU format (e.g., 0.5, 1, 2)
    if [[ "$cpu_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} CPU limit set for $service_name: $cpu_limit"
      has_limits=true
    else
      echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Invalid CPU format for $service_name: $cpu_limit"
    fi
  fi
  
  if [[ "$has_limits" == false ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} No resource limits for $service_name (unlimited resources)"
    return 1
  fi
  
  return 0
}

# ============================================================================
# HEALTH CHECK VALIDATION
# ============================================================================

validate_service_healthcheck() {
  local service_name="$1"
  local endpoint="$2"
  local interval="${3:-30}"
  local timeout="${4:-10}"
  local retries="${5:-3}"
  
  # Validate interval (5-300 seconds recommended)
  if [[ $interval -lt 5 ]] || [[ $interval -gt 300 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Health interval unusual for $service_name: ${interval}s"
  fi
  
  # Validate timeout (1-60 seconds)
  if [[ $timeout -lt 1 ]] || [[ $timeout -gt 60 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Health timeout unusual for $service_name: ${timeout}s"
  fi
  
  # Validate retries (1-10)
  if [[ $retries -lt 1 ]] || [[ $retries -gt 10 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} Health retries unusual for $service_name: ${retries}"
  fi
  
  echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Health check valid for $service_name"
  return 0
}

# ============================================================================
# DEPENDENCY VALIDATION
# ============================================================================

validate_service_dependencies() {
  local service_name="$1"
  shift
  local dependencies=("$@")
  
  if [[ ${#dependencies[@]} -eq 0 ]]; then
    echo -e "${COLOR_WARN}[ServiceValidator]${COLOR_RESET} No dependencies defined for $service_name (standalone service)"
    return 0
  fi
  
  echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Dependencies valid for $service_name (${#dependencies[@]} services)"
  return 0
}

# ============================================================================
# COMPOSITE SERVICE VALIDATION
# ============================================================================

validate_service_config() {
  local service_name="$1"
  local image="$2"
  local ports="${3:-}"
  local memory="${4:-}"
  local cpu="${5:-}"
  
  echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Validating service: $service_name"
  
  local failed=0
  
  # Validate image
  if ! validate_service_image "$service_name" "$image"; then
    failed+=1
  fi
  
  # Validate resources if specified
  if [[ -n "$memory" ]] || [[ -n "$cpu" ]]; then
    if ! validate_service_resources "$service_name" "$memory" "$cpu"; then
      failed+=1
    fi
  fi
  
  if [[ $failed -gt 0 ]]; then
    echo -e "${COLOR_ERROR}[ServiceValidator]${COLOR_RESET} Service validation failed: $service_name"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[ServiceValidator]${COLOR_RESET} Service valid: $service_name"
  return 0
}

# Export all functions
export -f validate_service_image
export -f validate_service_ports
export -f validate_service_environment
export -f validate_service_volumes
export -f validate_service_resources
export -f validate_service_healthcheck
export -f validate_service_dependencies
export -f validate_service_config
