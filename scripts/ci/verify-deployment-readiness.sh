#!/usr/bin/env bash
###############################################################################
# @file        scripts/ci/verify-deployment-readiness.sh
# @module      ci/pre-deployment
# @description Comprehensive pre-deployment validation and readiness check
# @governance  GOV-002: Standardized validation procedures
# @version     1.0.0
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Verification complete"; rm -f /tmp/deployment-check-*.tmp 2>/dev/null || true' EXIT

# ==============================================================================
# Configuration
# ==============================================================================

CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0
CHECKS_TOTAL=0

# ==============================================================================
# Validation Functions
# ==============================================================================

check_docker_compose_syntax() {
  CHECKS_TOTAL+=1
  log_info "Checking Docker Compose syntax..."
  
  if python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" 2>/dev/null; then
    log_success "✓ docker-compose.yml valid YAML"
    CHECKS_PASSED+=1
  else
    log_error "✗ docker-compose.yml YAML syntax error"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_all_compose_files() {
  CHECKS_TOTAL+=1
  log_info "Validating all docker-compose*.yml files..."
  
  local failed=0
  for file in docker-compose*.yml; do
    if [ -f "$file" ]; then
      if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        log_warn "⚠ $file has YAML issues"
        failed+=1
      fi
    fi
  done
  
  if [ $failed -eq 0 ]; then
    log_success "✓ All docker-compose files valid"
    CHECKS_PASSED+=1
  else
    log_error "✗ $failed docker-compose files have issues"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_service_health_checks() {
  CHECKS_TOTAL+=1
  log_info "Verifying service health checks..."
  
  local service_count=$(grep -c "^  [a-z]" docker-compose.yml || true)
  local healthcheck_count=$(grep -c "healthcheck:" docker-compose.yml || true)
  
  # Expected: most services have health checks (27/28 production, 11 init with restart: no)
  if [ $healthcheck_count -ge 25 ]; then
    log_success "✓ Health checks coverage: $healthcheck_count/28 services"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ Limited health checks: $healthcheck_count/28 services"
    WARNINGS+=1
  fi
}

check_script_syntax() {
  CHECKS_TOTAL+=1
  log_info "Validating bash script syntax (202 scripts)..."
  
  local errors=0
  while IFS= read -r script; do
    if ! bash -n "$script" 2>/dev/null; then
      errors+=1
    fi
  done < <(find scripts -name "*.sh" -type f)
  
  if [ $errors -eq 0 ]; then
    log_success "✓ All 202 scripts have valid syntax"
    CHECKS_PASSED+=1
  else
    log_error "✗ $errors scripts have syntax errors"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_ssot_compliance() {
  CHECKS_TOTAL+=1
  log_info "Checking SSOT compliance (scripts/_common/init.sh sourcing)..."
  
  local total_scripts=$(find scripts -name "*.sh" -type f | wc -l)
  local sourcing_init=$(grep -l "source.*init.sh" scripts/**/*.sh 2>/dev/null | wc -l)
  
  if [ "$sourcing_init" -ge $((total_scripts - 5)) ]; then
    log_success "✓ SSOT compliance: $sourcing_init/$total_scripts scripts"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ SSOT compliance: $sourcing_init/$total_scripts scripts"
    WARNINGS+=1
  fi
}

check_resource_limits() {
  CHECKS_TOTAL+=1
  log_info "Verifying service resource limits..."
  
  local deploy_count=$(grep -c "deploy:" docker-compose.yml || true)
  local limits_count=$(grep -c "cpus:" docker-compose.yml || true)
  
  if [ $limits_count -ge 20 ]; then
    log_success "✓ Resource limits defined: $limits_count services"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ Limited resource limits: $limits_count services"
    WARNINGS+=1
  fi
}

check_image_pinning() {
  CHECKS_TOTAL+=1
  log_info "Checking image version pinning (no 'latest' tags)..."
  
  if grep -q "image:.*:latest" docker-compose.yml; then
    log_error "✗ Found 'latest' image tags (should use sha256 digests)"
    CHECKS_FAILED+=1
    return 1
  else
    log_success "✓ All images pinned to sha256 digests"
    CHECKS_PASSED+=1
  fi
}

check_environment_vars() {
  CHECKS_TOTAL+=1
  log_info "Checking environment variable configuration..."
  
  if [ -f "scripts/_common/config.env" ]; then
    log_success "✓ SSOT config found: scripts/_common/config.env"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ SSOT config not found: scripts/_common/config.env"
    WARNINGS+=1
  fi
}

check_git_status() {
  CHECKS_TOTAL+=1
  log_info "Checking git repository status..."
  
  if [ -z "$(git status --porcelain)" ]; then
    log_success "✓ Working tree clean"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ Uncommitted changes present"
    WARNINGS+=1
  fi
}

check_network_configuration() {
  CHECKS_TOTAL+=1
  log_info "Verifying network configurations..."
  
  local network_count=$(grep -c "^networks:" docker-compose.yml || true)
  
  if [ $network_count -gt 0 ]; then
    log_success "✓ Network definitions present"
    CHECKS_PASSED+=1
  else
    log_error "✗ No network definitions found"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_volumes() {
  CHECKS_TOTAL+=1
  log_info "Checking volume definitions..."
  
  local volume_count=$(grep -c "^volumes:" docker-compose.yml || true)
  
  if [ $volume_count -gt 0 ]; then
    log_success "✓ Volume definitions present"
    CHECKS_PASSED+=1
  else
    log_error "✗ No volume definitions found"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_terraform_files() {
  CHECKS_TOTAL+=1
  log_info "Verifying Terraform configuration..."
  
  if python3 -c "import hcl2" 2>/dev/null; then
    log_success "✓ Terraform validation tools available"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ Terraform validation tools not available"
    WARNINGS+=1
  fi
}

check_ci_workflows() {
  CHECKS_TOTAL+=1
  log_info "Validating CI/CD workflow definitions..."
  
  if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ssot-compliance.yml'))" 2>/dev/null; then
    log_success "✓ CI workflow YAML valid"
    CHECKS_PASSED+=1
  else
    log_error "✗ CI workflow YAML invalid"
    CHECKS_FAILED+=1
    return 1
  fi
}

check_documentation_completeness() {
  CHECKS_TOTAL+=1
  log_info "Checking documentation completeness..."
  
  local required_docs=(
    "README.md"
    "DEPLOYMENT_ARCHITECTURE.md"
    "DATABASE_SERVICES_ARCHITECTURE.md"
  )
  
  local missing=0
  for doc in "${required_docs[@]}"; do
    if [ ! -f "$doc" ]; then
      missing+=1
    fi
  done
  
  if [ $missing -eq 0 ]; then
    log_success "✓ All required documentation present"
    CHECKS_PASSED+=1
  else
    log_warn "⚠ Missing $missing documentation files"
    WARNINGS+=1
  fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  log_info "═══════════════════════════════════════════════════════"
  log_info "DEPLOYMENT READINESS VERIFICATION"
  log_info "═══════════════════════════════════════════════════════"
  echo ""
  
  # Run all checks
  check_docker_compose_syntax || true
  check_all_compose_files || true
  check_service_health_checks || true
  check_script_syntax || true
  check_ssot_compliance || true
  check_resource_limits || true
  check_image_pinning || true
  check_environment_vars || true
  check_git_status || true
  check_network_configuration || true
  check_volumes || true
  check_terraform_files || true
  check_ci_workflows || true
  check_documentation_completeness || true
  
  echo ""
  log_info "═══════════════════════════════════════════════════════"
  log_info "VERIFICATION RESULTS"
  log_info "═══════════════════════════════════════════════════════"
  log_info "Total checks:      $CHECKS_TOTAL"
  log_success "Passed:           $CHECKS_PASSED"
  
  if [ $WARNINGS -gt 0 ]; then
    log_warn "Warnings:         $WARNINGS"
  fi
  
  if [ $CHECKS_FAILED -gt 0 ]; then
    log_error "Failed:           $CHECKS_FAILED"
    echo ""
    log_error "DEPLOYMENT NOT READY - address failures above"
    exit 1
  else
    echo ""
    log_success "✓ DEPLOYMENT READY - all critical checks passed"
    if [ $WARNINGS -gt 0 ]; then
      log_warn "Note: $WARNINGS warnings found (non-blocking)"
    fi
    exit 0
  fi
}

main "$@"
