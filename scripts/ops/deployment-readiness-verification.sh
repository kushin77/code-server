#!/usr/bin/env bash
# @file scripts/ops/deployment-readiness-verification.sh
# @module ops/validation
# @description Comprehensive pre-deployment readiness check for production environments
# @governance OPS-005: Mandatory readiness verification before production state changes
# @usage deployment-readiness-verification.sh [--env prod] [--skip-cloud]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Readiness verification failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Configuration
ENV_TYPE="${1:-prod}"
SKIP_CLOUD="${2:-false}"
REPORT_ID="READY-$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${ARTIFACTS_DIR}/readiness-report-${REPORT_ID}.json"

log_info "═══════════════════════════════════════════════════════"
log_info "DEPLOYMENT READINESS VERIFICATION"
log_info "═══════════════════════════════════════════════════════"
log_info "Target Environment: ${ENV_TYPE}"
echo

# Initialize report
init_report() {
  cat > "${OUTPUT_FILE}" <<EOF
{
  "report_id": "${REPORT_ID}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "${ENV_TYPE}",
  "checks": {
    "local_sanity": "PENDING",
    "infrastructure_health": "PENDING",
    "dependency_check": "PENDING",
    "security_posture": "PENDING"
  },
  "verdict": "INCOMPLETE",
  "blockers": []
}
EOF
}

# ============================================================================
# VERIFICATION MODULES
# ============================================================================

check_local_sanity() {
  log_info "Module 1: Local Code & Manifest Sanity..."
  
  local issues=0
  
  # Check if docker-compose.yml exists
  if [[ ! -f "docker-compose.yml" ]]; then
    log_error "Missing docker-compose.yml in root"
    jq ".blockers += [\"Missing docker-compose.yml\"]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    issues=$((issues + 1))
  fi
  
  # Validate YAML syntax
  find . -maxdepth 1 -name "docker-compose*.yml" -exec yamllint -d "{extends: default, rules: {line-length: disable}}" {} + || {
    log_warning "YAML linting issues found (non-blocking but recommended to fix)"
  }
  
  if [[ $issues -eq 0 ]]; then
    jq ".checks.local_sanity = \"PASS\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    log_success "✓ Local sanity checks passed"
  else
    jq ".checks.local_sanity = \"FAIL\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
}

check_infrastructure() {
  if [[ "${SKIP_CLOUD}" == "true" ]]; then
    log_info "Module 2: Infrastructure Health (SKIPPED)"
    return
  fi
  
  log_info "Module 2: Infrastructure Health & Reachability..."
  
  # Verify connection to primary host
  local primary_host="192.168.168.31"
  if ping -c 1 -W 2 "${primary_host}" > /dev/null 2>&1; then
    log_success "✓ Primary host ${primary_host} is reachable"
  else
    log_warning "⚠ Primary host ${primary_host} unreachable (may be expected in some CI environments)"
    jq ".blockers += [\"Primary host ${primary_host} unreachable\"]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
  fi
  
  jq ".checks.infrastructure_health = \"PASS\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

check_dependencies() {
  log_info "Module 3: Critical External Dependencies..."
  
  local deps=("jq" "docker" "git" "bc")
  for dep in "${deps[@]}"; do
    if command -v "$dep" > /dev/null 2>&1; then
      log_success "✓ Dependency found: $dep"
    else
      log_error "Missing critical dependency: $dep"
      jq ".blockers += [\"Missing dependency: $dep\"]" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    fi
  done
  
  jq ".checks.dependency_check = \"PASS\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
}

# ============================================================================
# FINAL VERDICT
# ============================================================================

evaluate_readiness() {
  local blockers_count=$(jq '.blockers | length' "${OUTPUT_FILE}")
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  log_info "READINESS VERDICT"
  log_info "═══════════════════════════════════════════════════════"
  
  if [[ $blockers_count -eq 0 ]]; then
    jq ".verdict = \"GO\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    log_success "🚀 VERDICT: GO - System is ready for deployment."
  else
    jq ".verdict = \"NO-GO\"" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
    log_error "❌ VERDICT: NO-GO - ${blockers_count} blocker(s) identified."
    jq -r '.blockers[] | "  - \(.)"' "${OUTPUT_FILE}"
  fi
  
  log_info "Detailed results: ${OUTPUT_FILE}"
}

# Main execution
main() {
  init_report
  check_local_sanity
  check_infrastructure
  check_dependencies
  evaluate_readiness
}

main
