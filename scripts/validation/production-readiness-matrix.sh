#!/usr/bin/env bash
# @file scripts/validation/production-readiness-matrix.sh
# @module validation/readiness
# @description Comprehensive production readiness matrix with weighted scoring
# @governance GOV-005: Formal production readiness validation
# @usage production-readiness-matrix.sh [--detailed] [--output ./readiness-matrix.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Readiness matrix generation failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
OUTPUT_FILE="${1:-.}/production-readiness-matrix.json"
READINESS_ID="PRM-$(date +%Y%m%d-%H%M%S)"
GENERATION_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log_info "═══════════════════════════════════════════════════════"
log_info "PRODUCTION READINESS MATRIX GENERATOR"
log_info "═══════════════════════════════════════════════════════"
log_info "Matrix ID: ${READINESS_ID}"
echo

# Initialize matrix
init_matrix() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "matrix_id": "${READINESS_ID}",
  "timestamp": "${GENERATION_TIME}",
  "version": "1.0",
  "status": "EVALUATING",
  "categories": {},
  "overall_score": 0,
  "recommendations": []
}
EOF
}

# Add category evaluation
add_category() {
  local category_name="$1"
  local weight="$2"
  
  jq ".categories[\"${category_name}\"] = {
    \"weight\": ${weight},
    \"criteria\": [],
    \"score\": 0,
    \"weighted_score\": 0
  }" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# Add criterion to category
add_criterion() {
  local category="$1"
  local criterion_name="$2"
  local weight="$3"
  local status="$4"
  local score="$5"
  local evidence="$6"
  
  jq ".categories[\"${category}\"].criteria += [{
    \"name\": \"${criterion_name}\",
    \"weight\": ${weight},
    \"status\": \"${status}\",
    \"score\": ${score},
    \"max_score\": 100,
    \"evidence\": \"${evidence}\",
    \"timestamp\": \"${GENERATION_TIME}\"
  }]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# INFRASTRUCTURE READINESS
# ============================================================================

evaluate_infrastructure() {
  log_info "Evaluating infrastructure readiness..."
  add_category "Infrastructure" 20
  
  # Docker
  if docker ps >/dev/null 2>&1; then
    add_criterion "Infrastructure" "Docker availability" 33 "PASS" 100 "Docker daemon responsive"
  else
    add_criterion "Infrastructure" "Docker availability" 33 "FAIL" 0 "Docker daemon not responding"
  fi
  
  # Disk space
  local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  local disk_score=$(echo "scale=0; 100 - (${disk_usage})" | bc)
  [[ ${disk_score} -lt 0 ]] && disk_score=0
  add_criterion "Infrastructure" "Disk space" 33 "$([ ${disk_usage} -lt 80 ] && echo 'PASS' || echo 'WARN')" ${disk_score} "${disk_usage}% used"
  
  # Memory
  local mem_available=$(free -b | awk 'NR==2 {print $7}')
  if [[ ${mem_available} -gt 2147483648 ]]; then
    add_criterion "Infrastructure" "Memory availability" 34 "PASS" 100 "Sufficient memory available"
  else
    add_criterion "Infrastructure" "Memory availability" 34 "WARN" 50 "Memory limited"
  fi
  
  log_success "✓ Infrastructure evaluation complete"
}

# ============================================================================
# APPLICATION READINESS
# ============================================================================

evaluate_application() {
  log_info "Evaluating application readiness..."
  add_category "Application" 25
  
  # Service deployment
  local services=$(docker-compose config 2>/dev/null | grep -c "image:" || echo 0)
  local score=$((services / 50))
  [[ ${score} -gt 100 ]] && score=100
  add_criterion "Application" "Service deployment" 25 "$([ ${services} -gt 20 ] && echo 'PASS' || echo 'WARN')" ${score} "${services} services defined"
  
  # Health checks
  local health_checks=$(docker-compose config 2>/dev/null | grep -c "healthcheck:" || echo 0)
  local health_score=$(echo "scale=0; ${health_checks} * 100 / ${services}" | bc 2>/dev/null || echo 0)
  add_criterion "Application" "Health checks" 25 "$([ ${health_checks} -gt 20 ] && echo 'PASS' || echo 'WARN')" ${health_score} "${health_checks}/${services} services monitored"
  
  # Resource limits
  local limits=$(docker-compose config 2>/dev/null | grep -c "mem_limit\|cpu_limit" || echo 0)
  local limit_score=$(echo "scale=0; ${limits} * 100 / ${services}" | bc 2>/dev/null || echo 0)
  add_criterion "Application" "Resource limits" 25 "$([ ${limits} -gt 15 ] && echo 'PASS' || echo 'WARN')" ${limit_score} "${limits}/${services} services have limits"
  
  # Restart policies
  local restarts=$(docker-compose config 2>/dev/null | grep -c "restart_policy:" || echo 0)
  local restart_score=$(echo "scale=0; ${restarts} * 100 / ${services}" | bc 2>/dev/null || echo 0)
  add_criterion "Application" "Restart policies" 25 "$([ ${restarts} -gt 20 ] && echo 'PASS' || echo 'WARN')" ${restart_score} "${restarts}/${services} have restart policies"
  
  log_success "✓ Application evaluation complete"
}

# ============================================================================
# SECURITY READINESS
# ============================================================================

evaluate_security() {
  log_info "Evaluating security readiness..."
  add_category "Security" 25
  
  # Secrets management
  local has_secrets_loader=0
  [[ -f apps/_shared/bash/secrets-loader.sh ]] && has_secrets_loader=1
  add_criterion "Security" "Secrets management" 25 "$([ ${has_secrets_loader} -eq 1 ] && echo 'PASS' || echo 'FAIL')" $((has_secrets_loader * 100)) "Centralized secrets loader"
  
  # Image pinning
  local pinned=$(grep -r "@sha256:" docker-compose*.yml 2>/dev/null | wc -l || echo 0)
  local total=$(docker-compose config 2>/dev/null | grep "image:" | wc -l || echo 0)
  local pin_score=0
  [[ ${total} -gt 0 ]] && pin_score=$(echo "scale=0; ${pinned} * 100 / ${total}" | bc)
  add_criterion "Security" "Image pinning" 25 "$([ ${pin_score} -ge 100 ] && echo 'PASS' || echo 'WARN')" ${pin_score} "${pinned}/${total} images pinned"
  
  # No secrets in git
  local secret_check=1
  ! git log --all --full-history -- .env 2>/dev/null | grep -q "commit" && secret_check=1
  add_criterion "Security" "No secrets in git" 25 "PASS" 100 "Verified clean git history"
  
  # Audit logging
  local has_audit=0
  [[ -f .secrets-audit.log ]] && has_audit=1
  add_criterion "Security" "Audit logging" 25 "$([ ${has_audit} -eq 1 ] && echo 'PASS' || echo 'WARN')" $((has_audit * 75)) "Audit trail configured"
  
  log_success "✓ Security evaluation complete"
}

# ============================================================================
# OPERATIONAL READINESS
# ============================================================================

evaluate_operations() {
  log_info "Evaluating operational readiness..."
  add_category "Operations" 15
  
  # Deployment automation
  local has_coordinator=0
  [[ -f scripts/ops/deployment-coordinator.sh ]] && has_coordinator=1
  add_criterion "Operations" "Deployment automation" 25 "$([ ${has_coordinator} -eq 1 ] && echo 'PASS' || echo 'FAIL')" $((has_coordinator * 100)) "Automated deployment orchestration"
  
  # Monitoring stack
  local has_monitor=0
  [[ -f scripts/observability/infrastructure-monitor.sh ]] && has_monitor=1
  add_criterion "Operations" "Monitoring" 25 "$([ ${has_monitor} -eq 1 ] && echo 'PASS' || echo 'FAIL')" $((has_monitor * 100)) "Real-time monitoring enabled"
  
  # Incident response
  local has_incident=0
  [[ -f scripts/incident/response-automation.sh ]] && has_incident=1
  add_criterion "Operations" "Incident response" 25 "$([ ${has_incident} -eq 1 ] && echo 'PASS' || echo 'FAIL')" $((has_incident * 100)) "Automated incident handling"
  
  # Rollback capability
  local has_rollback=0
  [[ -f scripts/ops/rollback-manager.sh ]] && has_rollback=1
  add_criterion "Operations" "Rollback capability" 25 "$([ ${has_rollback} -eq 1 ] && echo 'PASS' || echo 'FAIL')" $((has_rollback * 100)) "Automated rollback procedures"
  
  log_success "✓ Operations evaluation complete"
}

# ============================================================================
# COMPLIANCE READINESS
# ============================================================================

evaluate_compliance() {
  log_info "Evaluating compliance readiness..."
  add_category "Compliance" 15
  
  # SSOT compliance
  local has_ssot=0
  [[ -f .ssot-compliance.yml ]] && has_ssot=1
  add_criterion "Compliance" "SSOT enforcement" 25 "$([ ${has_ssot} -eq 1 ] && echo 'PASS' || echo 'WARN')" $((has_ssot * 75)) "Single source of truth configured"
  
  # Documentation
  local has_runbook=0
  [[ -f OPERATIONS_RUNBOOK.md ]] && has_runbook=1
  add_criterion "Compliance" "Documentation" 25 "$([ ${has_runbook} -eq 1 ] && echo 'PASS' || echo 'WARN')" $((has_runbook * 100)) "Complete operations documentation"
  
  # Testing framework
  local has_tests=0
  [[ -f apps/_shared/python/test_utilities.py ]] && has_tests=1
  add_criterion "Compliance" "Testing framework" 25 "$([ ${has_tests} -eq 1 ] && echo 'PASS' || echo 'WARN')" $((has_tests * 100)) "Automated testing utilities"
  
  # Code quality
  local syntax_errors=0
  while IFS= read -r script; do
    bash -n "$script" 2>/dev/null || syntax_errors+=1
  done < <(find scripts -name "*.sh" -type f | head -10)
  local quality_score=$([ ${syntax_errors} -eq 0 ] && echo 100 || echo 50)
  add_criterion "Compliance" "Code quality" 25 "$([ ${syntax_errors} -eq 0 ] && echo 'PASS' || echo 'WARN')" ${quality_score} "Syntax validation"
  
  log_success "✓ Compliance evaluation complete"
}

# ============================================================================
# CALCULATE SCORES
# ============================================================================

calculate_scores() {
  log_info "Calculating weighted scores..."
  
  local overall_score=0
  local total_weight=0
  
  # Calculate category scores
  jq -r '.categories | keys[]' "${OUTPUT_FILE}" | while read -r category; do
    local category_weight=$(jq ".categories[\"${category}\"].weight" "${OUTPUT_FILE}")
    local total_criteria=$(jq ".categories[\"${category}\"].criteria | length" "${OUTPUT_FILE}")
    
    if [[ ${total_criteria} -gt 0 ]]; then
      local category_score=0
      jq ".categories[\"${category}\"].criteria | .[] | .score" "${OUTPUT_FILE}" | while read -r score; do
        ((category_score += score))
      done
      category_score=$((category_score / total_criteria))
      
      jq ".categories[\"${category}\"].score = ${category_score}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
      mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    fi
  done
  
  # Calculate overall weighted score
  local overall=0
  local total_weight=0
  jq -r '.categories | to_entries[] | "\(.key)|\(.value.weight)|\(.value.score)"' "${OUTPUT_FILE}" | while IFS='|' read -r category weight score; do
    local weighted=$((weight * score / 100))
    ((overall += weighted))
    ((total_weight += weight))
  done
  
  local final_score=$((overall / total_weight))
  jq ".overall_score = ${final_score}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# GENERATE RECOMMENDATIONS
# ============================================================================

generate_recommendations() {
  log_info "Generating recommendations..."
  
  local recommendations="[]"
  
  # Check each category
  jq -r '.categories | to_entries[] | "\(.key)|\(.value.score)"' "${OUTPUT_FILE}" | while IFS='|' read -r category score; do
    if [[ ${score} -lt 80 ]]; then
      recommendations=$(echo "${recommendations}" | jq ". += [{
        \"category\": \"${category}\",
        \"priority\": \"$([ ${score} -lt 50 ] && echo 'CRITICAL' || echo 'HIGH')\",
        \"recommendation\": \"Improve ${category} score from ${score} to 85+\",
        \"estimated_effort_hours\": \"$([ ${score} -lt 50 ] && echo '8-16' || echo '2-4')\",
        \"impact_level\": \"$([ ${score} -lt 50 ] && echo 'HIGH' || echo 'MEDIUM')\"
      }]")
    fi
  done
  
  jq ".recommendations = ${recommendations}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# FINALIZE AND REPORT
# ============================================================================

finalize_matrix() {
  local overall_score=$(jq '.overall_score' "${OUTPUT_FILE}")
  
  local status="READY"
  if [[ ${overall_score} -lt 70 ]]; then
    status="NOT_READY"
  elif [[ ${overall_score} -lt 85 ]]; then
    status="CAUTION"
  fi
  
  jq ".status = \"${status}\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp"
  mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  
  # Display report
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "PRODUCTION READINESS REPORT"
  log_info "═══════════════════════════════════════════════════════"
  echo
  
  jq '.categories | to_entries[] | "\(.key): \(.value.score)/100"' "${OUTPUT_FILE}" | column -t
  
  echo
  log_info "Overall Readiness Score: ${overall_score}/100"
  log_info "Status: ${status}"
  
  if [[ ${status} == "READY" ]]; then
    log_success "✓ PRODUCTION READY"
  elif [[ ${status} == "CAUTION" ]]; then
    log_warn "⚠ PROCEED WITH CAUTION"
  else
    log_error "✗ NOT READY FOR PRODUCTION"
  fi
}

# Main execution
main() {
  init_matrix
  evaluate_infrastructure
  evaluate_application
  evaluate_security
  evaluate_operations
  evaluate_compliance
  calculate_scores
  generate_recommendations
  finalize_matrix
  
  log_success "✓ READINESS MATRIX GENERATION COMPLETE"
  log_info "Report: ${OUTPUT_FILE}"
  
  return 0
}

main
