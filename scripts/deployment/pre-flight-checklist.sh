#!/usr/bin/env bash
# @file scripts/deployment/pre-flight-checklist.sh
# @module deployment/checklist
# @description Comprehensive pre-flight deployment checklist automation
# @governance GOV-003: Mandatory verification before production deployment
# @usage pre-flight-checklist.sh [--strict] [--output ./checklist-report.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Checklist failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
STRICT_MODE="${1:-}"
OUTPUT_FILE="${2:-.}/pre-flight-checklist.json"
CHECKLIST_ID="CHECKLIST-$(date +%s)"

log_info "═══════════════════════════════════════════════════════"
log_info "PRE-FLIGHT DEPLOYMENT CHECKLIST"
log_info "═══════════════════════════════════════════════════════"
log_info "Checklist ID: ${CHECKLIST_ID}"
echo

# Initialize checklist JSON
init_checklist_json() {
  cat > "${OUTPUT_FILE}" <<'EOF'
{
  "checklist_id": "",
  "timestamp": "",
  "status": "IN_PROGRESS",
  "items": [],
  "passed": 0,
  "failed": 0,
  "warnings": 0,
  "summary": {}
}
EOF
}

# Add checklist item
add_item() {
  local category="$1"
  local item_name="$2"
  local status="$3"
  local details="${4:-}"
  
  jq ".items += [{
    \"category\": \"${category}\",
    \"name\": \"${item_name}\",
    \"status\": \"${status}\",
    \"details\": \"${details}\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  case "${status}" in
    PASS) jq '.passed += 1' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}" ;;
    FAIL) jq '.failed += 1' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}" ;;
    WARN) jq '.warnings += 1' "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}" ;;
  esac
}

# ============================================================================
# INFRASTRUCTURE CHECKS
# ============================================================================

check_infrastructure() {
  log_info "Checking infrastructure..."
  
  # Docker daemon
  if docker ps >/dev/null 2>&1; then
    add_item "Infrastructure" "Docker daemon running" "PASS" "Docker is responsive"
    log_success "✓ Docker daemon"
  else
    add_item "Infrastructure" "Docker daemon running" "FAIL" "Docker daemon not responsive"
    log_error "✗ Docker daemon not running"
  fi
  
  # Docker compose
  if command -v docker-compose >/dev/null 2>&1; then
    add_item "Infrastructure" "Docker Compose installed" "PASS" "$(docker-compose --version)"
    log_success "✓ Docker Compose"
  else
    add_item "Infrastructure" "Docker Compose installed" "FAIL" "Docker Compose not found"
    log_error "✗ Docker Compose missing"
  fi
  
  # Disk space
  local disk_available=$(df / | awk 'NR==2 {print $4}')
  if [[ ${disk_available} -gt 5242880 ]]; then
    add_item "Infrastructure" "Disk space available" "PASS" "${disk_available}KB free"
    log_success "✓ Disk space: ${disk_available}KB"
  else
    add_item "Infrastructure" "Disk space available" "WARN" "${disk_available}KB free (< 5GB)"
    log_warn "⚠ Low disk space: ${disk_available}KB"
  fi
  
  # Memory
  local memory_available=$(free -b | awk 'NR==2 {print $7}')
  if [[ ${memory_available} -gt 2147483648 ]]; then
    add_item "Infrastructure" "Memory available" "PASS" "$(numfmt --to=iec ${memory_available} 2>/dev/null || echo ${memory_available}B)"
    log_success "✓ Memory available"
  else
    add_item "Infrastructure" "Memory available" "WARN" "Low memory"
    log_warn "⚠ Low memory available"
  fi
}

# ============================================================================
# CODE QUALITY CHECKS
# ============================================================================

check_code_quality() {
  log_info "Checking code quality..."
  
  # Git clean
  if [ -z "$(git status --short)" ]; then
    add_item "Code Quality" "Working tree clean" "PASS" "No uncommitted changes"
    log_success "✓ Working tree clean"
  else
    add_item "Code Quality" "Working tree clean" "FAIL" "Uncommitted changes detected"
    log_error "✗ Working tree not clean"
  fi
  
  # Bash syntax
  local script_errors=0
  while IFS= read -r script; do
    if ! bash -n "$script" 2>/dev/null; then
      script_errors+=1
    fi
  done < <(find scripts -name "*.sh" -type f)
  
  if [[ ${script_errors} -eq 0 ]]; then
    add_item "Code Quality" "Bash script syntax" "PASS" "All scripts valid"
    log_success "✓ Bash syntax valid"
  else
    add_item "Code Quality" "Bash script syntax" "FAIL" "${script_errors} scripts with errors"
    log_error "✗ Found ${script_errors} syntax errors"
  fi
  
  # YAML validation
  local yaml_errors=0
  while IFS= read -r yaml_file; do
    if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
      yaml_errors+=1
    fi
  done < <(find . -name "*.yml" -o -name "*.yaml" | grep -E "docker-compose|\.ssot" || true)
  
  if [[ ${yaml_errors} -eq 0 ]]; then
    add_item "Code Quality" "YAML validation" "PASS" "All YAML files valid"
    log_success "✓ YAML valid"
  else
    add_item "Code Quality" "YAML validation" "FAIL" "${yaml_errors} YAML files invalid"
    log_error "✗ Found ${yaml_errors} YAML errors"
  fi
}

# ============================================================================
# DEPLOYMENT READINESS CHECKS
# ============================================================================

check_deployment_readiness() {
  log_info "Checking deployment readiness..."
  
  # Deployment script exists
  if [ -f scripts/ops/deployment-coordinator.sh ]; then
    add_item "Deployment Readiness" "Deployment coordinator" "PASS" "Script available"
    log_success "✓ Deployment coordinator available"
  else
    add_item "Deployment Readiness" "Deployment coordinator" "FAIL" "Script missing"
    log_error "✗ Deployment coordinator missing"
  fi
  
  # Rollback capability
  if [ -f scripts/ops/rollback-manager.sh ]; then
    add_item "Deployment Readiness" "Rollback capability" "PASS" "Rollback script available"
    log_success "✓ Rollback script available"
  else
    add_item "Deployment Readiness" "Rollback capability" "FAIL" "Rollback script missing"
    log_error "✗ Rollback script missing"
  fi
  
  # Validation frameworks
  if [ -f apps/_shared/bash/deployment-validator.sh ] && [ -f apps/_shared/bash/service-config-validator.sh ]; then
    add_item "Deployment Readiness" "Validation frameworks" "PASS" "Both validators available"
    log_success "✓ Validation frameworks available"
  else
    add_item "Deployment Readiness" "Validation frameworks" "FAIL" "Validators missing"
    log_error "✗ Validation frameworks missing"
  fi
}

# ============================================================================
# SECURITY CHECKS
# ============================================================================

check_security() {
  log_info "Checking security posture..."
  
  # Secrets not in git
  if ! git log --all --full-history -- .env 2>/dev/null | grep -q "commit"; then
    add_item "Security" "Secrets not in git history" "PASS" "No secrets committed"
    log_success "✓ No secrets in git history"
  else
    add_item "Security" "Secrets not in git history" "WARN" "Potential secrets in history"
    log_warn "⚠ Check for secrets in git history"
  fi
  
  # Image pinning
  local pinned_images=$(grep -r "@sha256:" docker-compose*.yml 2>/dev/null | wc -l || echo 0)
  local total_images=$(docker-compose config 2>/dev/null | grep "image:" | wc -l || echo 0)
  
  if [[ ${total_images} -eq 0 ]] || [[ ${pinned_images} -eq ${total_images} ]]; then
    add_item "Security" "Container image pinning" "PASS" "All images pinned with sha256"
    log_success "✓ Image pinning: 100%"
  else
    add_item "Security" "Container image pinning" "WARN" "${pinned_images}/${total_images} images pinned"
    log_warn "⚠ Only ${pinned_images}/${total_images} images pinned"
  fi
}

# ============================================================================
# COMPLIANCE CHECKS
# ============================================================================

check_compliance() {
  log_info "Checking compliance..."
  
  # SSOT compliance
  if [ -f .ssot-compliance.yml ]; then
    add_item "Compliance" "SSOT configuration exists" "PASS" ".ssot-compliance.yml present"
    log_success "✓ SSOT configuration present"
  else
    add_item "Compliance" "SSOT configuration exists" "WARN" ".ssot-compliance.yml missing"
    log_warn "⚠ SSOT configuration missing"
  fi
  
  # Audit logs
  if [ -f .secrets-audit.log ] && [ -s .secrets-audit.log ]; then
    add_item "Compliance" "Audit trail" "PASS" "Audit logs present"
    log_success "✓ Audit trail active"
  else
    add_item "Compliance" "Audit trail" "WARN" "No audit logs"
    log_warn "⚠ Audit trail not yet initialized"
  fi
}

# ============================================================================
# FINAL REPORT
# ============================================================================

finalize_checklist() {
  log_info "Finalizing checklist..."
  
  local passed=$(jq '.passed' "${OUTPUT_FILE}")
  local failed=$(jq '.failed' "${OUTPUT_FILE}")
  local warnings=$(jq '.warnings' "${OUTPUT_FILE}")
  
  local overall_status="READY"
  if [[ ${failed} -gt 0 ]]; then
    overall_status="NOT_READY"
  fi
  
  jq ".status = \"${overall_status}\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  jq ".summary = {
    \"total_items\": $(jq '.items | length' "${OUTPUT_FILE}"),
    \"passed\": ${passed},
    \"failed\": ${failed},
    \"warnings\": ${warnings},
    \"pass_rate\": $(echo "scale=1; ${passed} * 100 / (${passed} + ${failed} + ${warnings})" | bc),
    \"deployment_ready\": $([ ${failed} -eq 0 ] && echo 'true' || echo 'false'),
    \"checklist_id\": \"${CHECKLIST_ID}\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "DEPLOYMENT READINESS REPORT"
  log_info "═══════════════════════════════════════════════════════"
  jq '.summary' "${OUTPUT_FILE}"
  
  echo
  if [[ ${failed} -eq 0 ]]; then
    log_success "✓ DEPLOYMENT READY"
    return 0
  else
    log_error "✗ DEPLOYMENT NOT READY - ${failed} critical issues"
    return 1
  fi
}

# Main execution
main() {
  init_checklist_json
  check_infrastructure
  check_code_quality
  check_deployment_readiness
  check_security
  check_compliance
  finalize_checklist
}

main
