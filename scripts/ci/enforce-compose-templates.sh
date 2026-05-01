#!/usr/bin/env bash
###############################################################################
# @file        scripts/ci/enforce-compose-templates.sh
# @module      ci/compose-validation
# @description Enforce Docker Compose template standards
# @governance  GOV-002: Standardized service definitions and configurations
###############################################################################

set -euo pipefail

trap "log_error 'Script failed at line $LINENO'; exit 1" ERR
trap "log_info 'Performing cleanup...'; rm -f /tmp/*.tmp 2>/dev/null || true" EXIT
# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'rm -f /tmp/compose-*.tmp 2>/dev/null || true' EXIT

# ==============================================================================
# Configuration
# ==============================================================================

VIOLATIONS_FOUND=0
CRITICAL_VIOLATIONS=0

# ==============================================================================
# Logging
# ==============================================================================

log_violation() {
  local severity="$1"
  local file="$2"
  local rule="$3"
  local message="$4"
  
  if [[ "$severity" == "CRITICAL" ]]; then
    log_error "  [$rule] $message"
    CRITICAL_VIOLATIONS+=1
  else
    log_warn "  [$rule] $message"
  fi
  VIOLATIONS_FOUND+=1
}

# ==============================================================================
# Validation Rules
# ==============================================================================

validate_image_pinning() {
  local file="$1"
  
  # Check for 'latest' tags - modern practice is to use digests
  if grep -n "image:.*:latest" "$file" > /dev/null 2>&1; then
    log_violation "CRITICAL" "$file" "image-latest" "Images with ':latest' tag should be pinned"
  fi
}

validate_yaml_syntax() {
  local file="$1"
  
  # Validate YAML
  if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
    log_violation "CRITICAL" "$file" "yaml-syntax" "Invalid YAML syntax"
    return 1
  fi
  
  return 0
}

validate_service_structure() {
  local file="$1"
  
  # Check for basic structure
  if ! grep -q "^services:" "$file"; then
    log_violation "CRITICAL" "$file" "structure" "Missing 'services:' section"
    return 1
  fi
  
  return 0
}

validate_health_checks() {
  local file="$1"
  
  # Count health checks vs services
  local service_count=$(grep -c "^  [a-z]" "$file" || true)
  local healthcheck_count=$(grep -c "healthcheck:" "$file" || true)
  
  if [[ $service_count -gt 10 ]] && [[ $healthcheck_count -lt 5 ]]; then
    log_violation "WARN" "$file" "health-checks" "Limited health checks for service count"
  fi
}

validate_resource_limits() {
  local file="$1"
  
  # Count deploy sections
  local resource_count=$(grep -c "deploy:" "$file" || true)
  local service_count=$(grep -c "^  [a-z]" "$file" || true)
  
  if [[ $service_count -gt 10 ]] && [[ $resource_count -lt 5 ]]; then
    log_violation "WARN" "$file" "resource-limits" "Limited resource limits defined"
  fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  log_info "Docker Compose Template Enforcement"
  log_info "===================================="
  echo ""
  
  # Compose files to check
  local compose_files=(
    "docker-compose.yml"
    "docker-compose.prod.yml"
    "docker-compose.enterprise.yml"
    "docker-compose.observability.yml"
    "docker-compose.redpanda.yml"
    "docker-compose.ai.yml"
    "docker-compose.cluster.yml"
    "docker-compose.edge-agent.yml"
    "docker-compose.override.yml"
  )
  
  local files_checked=0
  
  for filename in "${compose_files[@]}"; do
    if [[ -f "$filename" ]]; then
      files_checked+=1
      log_info "Checking: $filename"
      
      validate_yaml_syntax "$filename" || continue
      validate_service_structure "$filename" || continue
      
      validate_image_pinning "$filename"
      validate_health_checks "$filename"
      validate_resource_limits "$filename"
      
      log_info ""
    fi
  done
  
  # Report
  echo ""
  log_info "===================================="
  log_info "Results:"
  log_info "  Files checked: $files_checked"
  log_info "  Violations found: $VIOLATIONS_FOUND"
  log_info "  Critical violations: $CRITICAL_VIOLATIONS"
  echo ""
  
  if [[ $CRITICAL_VIOLATIONS -gt 0 ]]; then
    log_error "FAILED: Critical violations found"
    exit 1
  elif [[ $VIOLATIONS_FOUND -gt 0 ]]; then
    log_warn "WARNING: Non-critical issues found (see above)"
    exit 0
  else
    log_success "✓ All templates compliant!"
    exit 0
  fi
}

main "$@"
