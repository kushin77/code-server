#!/bin/bash
# @file scripts/ops/setup-opa-service.sh
# @module infrastructure/opa-integration
# @description P0-1552 Phase 3: Deploy OPA as Docker Compose service with policy bundle loading
# @governance GOV-002: All policy decisions logged and audited
# @usage setup-opa-service.sh [--check] [--deploy]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
OPA_CONFIG="${REPO_ROOT}/config/opa-config.yaml"
OPA_BUNDLE_DIR="${REPO_ROOT}/policies"
OPA_DECISION_LOG="${REPO_ROOT}/artifacts/opa-decision-log.json"

mkdir -p "$(dirname "${OPA_CONFIG}" "${OPA_DECISION_LOG}")"

wait_for_opa_healthy() {
  local max_attempts=30
  local attempt=0

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if curl -sf http://localhost:8181/health > /dev/null 2>&1; then
      return 0
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  return 1
}

# Generate OPA configuration
generate_opa_config() {
  log_info "Generating OPA configuration..."
  
  cat > "${OPA_CONFIG}" <<'EOF'
services:
  localhost:
    url: http://opa:8181

bundles:
  policies:
    service: localhost
    resource: /bundles/policies.tar.gz
    polling:
      min_delay_seconds: 60
      max_delay_seconds: 300

decision_logs:
  console:
    level: info

EOF
  
  log_success "OPA configuration generated at ${OPA_CONFIG}"
}

# Validate OPA policies syntax
validate_opa_policies() {
  log_info "Validating OPA policy syntax..."
  
  if ! command -v opa &> /dev/null; then
    log_error "OPA CLI not found - install via 'brew install opa' or 'choco install opa'"
    return 1
  fi
  
  if ! opa fmt -d "${OPA_BUNDLE_DIR}" --check 2>/dev/null; then
    log_error "OPA policy formatting issues detected"
    return 1
  fi
  
  log_success "All OPA policies validated"
  return 0
}

# Verify OPA service in docker-compose.yml
verify_opa_in_compose() {
  log_info "Verifying OPA service definition in docker-compose.yml..."
  
  if ! grep -q 'opa:' "${REPO_ROOT}/docker-compose.yml" 2>/dev/null; then
    log_error "OPA service not found in docker-compose.yml"
    return 1
  fi
  
  if ! grep -q 'openpolicyagent/opa' "${REPO_ROOT}/docker-compose.yml"; then
    log_error "OPA image reference not found"
    return 1
  fi
  
  log_success "OPA service definition verified in docker-compose.yml"
  return 0
}

# Deploy OPA service
deploy_opa() {
  log_info "Deploying OPA service..."
  
  cd "${REPO_ROOT}"
  
  if docker compose ps opa 2>/dev/null | grep -q running; then
    log_info "OPA service already running, stopping..."
    docker compose stop opa || true
  fi
  
  log_info "Starting OPA service..."
  docker compose up -d opa

  if wait_for_opa_healthy; then
    log_success "OPA service is healthy"
    return 0
  fi

  log_error "OPA service failed to start within the expected time window"
  return 1
}

# Test policy evaluation
test_policy_evaluation() {
  log_info "Testing policy evaluation..."
  
  # Test a simple policy decision
  local test_input='{"action": "deploy", "target_env": "staging"}'
  
  if curl -sf -X POST http://localhost:8181/v1/data/core/production_gate -H 'Content-Type: application/json' -d "${test_input}" > /dev/null 2>&1; then
    log_success "OPA policy evaluation test passed"
    return 0
  else
    log_error "OPA policy evaluation test failed"
    return 1
  fi
}

main() {
  local check_only=false
  local deploy=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check_only=true
        shift
        ;;
      --deploy)
        deploy=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "OPA Service Setup"
  
  generate_opa_config || exit 1
  validate_opa_policies || exit 1
  verify_opa_in_compose || exit 1
  
  if [[ "${check_only}" == "true" ]]; then
    log_success "Checks passed - OPA ready to deploy"
    return 0
  fi
  
  if [[ "${deploy}" == "true" ]]; then
    deploy_opa || exit 1
    test_policy_evaluation || exit 1
    log_success "OPA service deployed and tested successfully"
  fi
}

main "$@"