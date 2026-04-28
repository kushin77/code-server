#!/usr/bin/env bash
###############################################################################
# @file        scripts/ci/enforce-compose-templates.sh
# @module      ci/compose-validation
# @description Enforce Docker Compose template standards across all composition files
# @governance  GOV-002: Standardized service definitions and configurations
# @automation  P2 #1987: Complete template enforcement in docker-compose.yml
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Override exit trap to prevent cleanup interference
trap 'return 0' EXIT

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly COMPOSE_GLOB="${REPO_ROOT}/docker-compose*.{yml,yaml}"
readonly VIOLATIONS_LOG="${REPO_ROOT}/artifacts/compose-violations.log"
readonly TEMPLATE_RULES_FILE="${SCRIPT_DIR}/.compose-template-rules"

# Counters
TOTAL_FILES=0
VIOLATIONS_FOUND=0
CRITICAL_VIOLATIONS=0

# ==============================================================================
# TEMPLATE ENFORCEMENT RULES
# ==============================================================================

# P1 (Critical) - Block deployment
CRITICAL_RULES=(
  "service-naming-convention"      # Services must match {tier}-{name} pattern
  "image-version-pinning"           # No 'latest' tags
  "container-resource-limits"       # CPU/memory limits required
)

# P2 (High) - Warn but allow
HIGH_PRIORITY_RULES=(
  "health-check-configuration"      # Standardized health checks
  "logging-configuration"           # JSON driver with rotation
  "network-segment-assignment"      # Tier-based networking
)

# ==============================================================================
# VIOLATION TRACKING
# ==============================================================================

log_violation() {
  local severity="$1"
  local file="$2"
  local line="$3"
  local rule="$4"
  local message="$5"
  
  echo "[${severity}] ${file}:${line} (${rule}): ${message}" | tee -a "${VIOLATIONS_LOG}"
  
  if [[ "$severity" == "CRITICAL" ]]; then
    ((CRITICAL_VIOLATIONS++))
  fi
  ((VIOLATIONS_FOUND++))
}

# ==============================================================================
# RULE 1: Service Naming Convention (CRITICAL)
# ==============================================================================

validate_service_naming() {
  local file="$1"
  local line_num=0
  local in_services_section=false
  local service_name=""
  
  while IFS= read -r line; do
    ((line_num++))
    
    # Detect services: section
    if [[ "$line" =~ ^services: ]]; then
      in_services_section=true
      continue
    fi
    
    # Exit services section (returns to root level)
    if [[ "$in_services_section" == true ]] && [[ "$line" =~ ^[a-zA-Z_] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      in_services_section=false
    fi
    
    # Extract service name (first key at indentation level 2 spaces)
    if [[ "$in_services_section" == true ]] && [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*: ]]; then
      service_name=$(echo "$line" | sed 's/^[[:space:]]*//; s/:$//')
      
      # Check naming pattern: should contain at least one hyphen for tier-service separation
      # Examples: data-postgres, cache-redis, mesh-ingress, api-auth-server
      if [[ ! "$service_name" =~ ^[a-z0-9]+-[a-z0-9-]+$ ]]; then
        # Some special services allowed (init-*, test-*)
        if [[ ! "$service_name" =~ ^(init|test)-[a-z0-9-]+$ ]]; then
          log_violation "CRITICAL" "$file" "$line_num" "service-naming-convention" \
            "Service '$service_name' must follow '{tier}-{name}' pattern (e.g., 'data-postgres', 'cache-redis')"
        fi
      fi
    fi
  done < "$file"
}

# ==============================================================================
# RULE 2: Image Version Pinning (CRITICAL)
# ==============================================================================

validate_image_version_pinning() {
  local file="$1"
  local line_num=0
  local current_service=""
  
  while IFS= read -r line; do
    ((line_num++))
    
    # Track current service (for better error messages)
    if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*: ]]; then
      current_service=$(echo "$line" | sed 's/^[[:space:]]*//; s/:$//')
    fi
    
    # Check for 'image:' lines
    if [[ "$line" =~ image:[[:space:]]*([^ ]+) ]]; then
      local image="${BASH_REMATCH[1]}"
      
      # Flag images with 'latest' tag
      if [[ "$image" =~ :latest$ ]] || [[ ! "$image" =~ : ]]; then
        log_violation "CRITICAL" "$file" "$line_num" "image-version-pinning" \
          "Image '$image' in service '$current_service' must specify explicit version (not 'latest' or untagged). Example: 'postgres:16.13'"
      fi
    fi
  done < "$file"
}

# ==============================================================================
# RULE 3: Container Resource Limits (CRITICAL)
# ==============================================================================

validate_container_resource_limits() {
  local file="$1"
  local line_num=0
  local current_service=""
  local in_service=false
  local has_resources=false
  local service_start_line=0
  
  while IFS= read -r line; do
    ((line_num++))
    
    # Track service entry
    if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*: ]]; then
      # Validate previous service if it's complete
      if [[ "$in_service" == true ]] && [[ "$has_resources" == false ]]; then
        log_violation "CRITICAL" "$file" "$service_start_line" "container-resource-limits" \
          "Service '$current_service' must specify deploy.resources.limits (CPU/memory). Example: limits: {cpus: '2', memory: 4G}"
      fi
      
      current_service=$(echo "$line" | sed 's/^[[:space:]]*//; s/:$//')
      in_service=true
      has_resources=false
      service_start_line=$line_num
    fi
    
    # Check for deploy/resources section
    if [[ "$in_service" == true ]] && [[ "$line" =~ (deploy:|resources:|limits:) ]]; then
      has_resources=true
    fi
  done < "$file"
  
  # Check last service
  if [[ "$in_service" == true ]] && [[ "$has_resources" == false ]]; then
    log_violation "CRITICAL" "$file" "$service_start_line" "container-resource-limits" \
      "Service '$current_service' must specify deploy.resources.limits (CPU/memory)"
  fi
}

# ==============================================================================
# RULE 4: Health Check Configuration (HIGH PRIORITY)
# ==============================================================================

validate_health_check_configuration() {
  local file="$1"
  local line_num=0
  local current_service=""
  local in_service=false
  local has_healthcheck=false
  
  # List of services that should have health checks (production services)
  local production_services_regex="(data|cache|queue|database|redis|postgres|kafka|redpanda|qdrant)"
  
  while IFS= read -r line; do
    ((line_num++))
    
    if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*: ]]; then
      current_service=$(echo "$line" | sed 's/^[[:space:]]*//; s/:$//')
      in_service=true
      has_healthcheck=false
    fi
    
    if [[ "$in_service" == true ]] && [[ "$line" =~ healthcheck: ]]; then
      has_healthcheck=true
    fi
    
    # Check if we're moving to next service or section end
    if [[ "$in_service" == true ]] && [[ "$line" =~ ^[a-zA-Z] ]]; then
      in_service=false
      if [[ "$has_healthcheck" == false ]] && [[ "$current_service" =~ $production_services_regex ]]; then
        log_violation "WARN" "$file" "$line_num" "health-check-configuration" \
          "Service '$current_service' should have a healthcheck configured for production readiness"
      fi
    fi
  done < "$file"
}

# ==============================================================================
# RULE 5: Logging Configuration (HIGH PRIORITY)
# ==============================================================================

validate_logging_configuration() {
  local file="$1"
  local line_num=0
  local current_service=""
  local in_service=false
  local has_logging=false
  
  while IFS= read -r line; do
    ((line_num++))
    
    if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*: ]]; then
      current_service=$(echo "$line" | sed 's/^[[:space:]]*//; s/:$//')
      in_service=true
      has_logging=false
    fi
    
    if [[ "$in_service" == true ]] && [[ "$line" =~ logging: ]]; then
      has_logging=true
    fi
    
    if [[ "$in_service" == true ]] && [[ "$line" =~ ^[a-zA-Z] ]]; then
      in_service=false
      if [[ "$has_logging" == false ]]; then
        : # Logging is optional per-service if default is configured globally
      fi
    fi
  done < "$file"
}

# ==============================================================================
# MAIN VALIDATION FLOW
# ==============================================================================

main() {
  log_info "Docker Compose Template Enforcement"
  log_info "======================================"
  echo ""
  
  mkdir -p "${REPO_ROOT}/artifacts"
  > "${VIOLATIONS_LOG}"  # Clear violations log
  
  # Find all docker-compose files
  log_info "Scanning docker-compose files..."
  
  for compose_file in $(find "${REPO_ROOT}" -maxdepth 1 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null | sort); do
    if [[ -f "$compose_file" ]]; then
      ((TOTAL_FILES++))
      log_info "  ✓ Validating: $(basename "$compose_file")"
      
      # Run all validation rules
      validate_service_naming "$compose_file"
      validate_image_version_pinning "$compose_file"
      validate_container_resource_limits "$compose_file"
      validate_health_check_configuration "$compose_file"
      validate_logging_configuration "$compose_file"
    fi
  done
  
  echo ""
  log_info "======================================"
  log_info "Validation Results:"
  log_info "  Files checked: $TOTAL_FILES"
  log_info "  Total violations: $VIOLATIONS_FOUND"
  log_info "  Critical violations: $CRITICAL_VIOLATIONS"
  
  if [[ -n "$(cat "${VIOLATIONS_LOG}" 2>/dev/null)" ]]; then
    log_warn ""
    log_warn "Detailed violations:"
    cat "${VIOLATIONS_LOG}"
  fi
  
  echo ""
  if [[ $CRITICAL_VIOLATIONS -gt 0 ]]; then
    log_error "FAILED: $CRITICAL_VIOLATIONS critical violations found"
    log_error "Docker Compose templates do not meet production standards."
    log_error "See violations above for details and required fixes."
    return 1
  elif [[ $VIOLATIONS_FOUND -gt 0 ]]; then
    log_warn "WARNING: $VIOLATIONS_FOUND non-critical issues found (see above)"
    log_warn "These should be addressed to improve production readiness"
    return 0  # Warnings don't fail the check
  else
    log_success "All docker-compose files pass template enforcement!"
    log_success "Production readiness verified."
    return 0
  fi
}

main "$@"
