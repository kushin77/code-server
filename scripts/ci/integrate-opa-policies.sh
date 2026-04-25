#!/bin/bash
# @file scripts/ci/integrate-opa-policies.sh
# @module infrastructure/policy-integration
# @description P0-1552 Phase 4: Integrate OPA policy checks into CI/CD pipeline
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage integrate-opa-policies.sh <terraform|docker-compose|conftest>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source shared helpers and normalize environment file line endings
source "${REPO_ROOT}/scripts/_common/init.sh"

# Source infrastructure configuration
source_env_file "${REPO_ROOT}/.env.infrastructure"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

# Evaluate Terraform against OPA policies
evaluate_terraform_policies() {
  log_info "Evaluating Terraform configuration against OPA policies..."
  
  cd "${REPO_ROOT}/terraform"
  
  if ! command -v conftest &> /dev/null; then
    log_error "conftest not found - install via 'brew install conftest'"
    return 1
  fi
  
  # Run terraform plan and evaluate with OPA
  if terraform plan -json 2>/dev/null | conftest test -p "${REPO_ROOT}/policies" -; then
    log_success "Terraform policies passed"
    return 0
  else
    log_error "Terraform policy violations detected"
    return 1
  fi
}

# Evaluate Docker Compose against OPA policies
evaluate_docker_compose_policies() {
  log_info "Evaluating Docker Compose against OPA policies..."
  
  cd "${REPO_ROOT}"
  
  if ! command -v conftest &> /dev/null; then
    log_error "conftest not found"
    return 1
  fi
  
  # Evaluate docker-compose.yml for policy violations
  if conftest test -p "${REPO_ROOT}/policies/infrastructure" docker-compose.yml 2>/dev/null; then
    log_success "Docker Compose policies passed"
    return 0
  else
    log_error "Docker Compose policy violations detected"
    return 1
  fi
}

# Run conftest on policy files themselves
evaluate_policy_tests() {
  log_info "Running OPA policy unit tests..."
  
  if ! command -v opa &> /dev/null; then
    log_error "OPA CLI not found"
    return 1
  fi
  
  # Run OPA test suite
  if opa test -v "${REPO_ROOT}/policies" 2>/dev/null; then
    log_success "All policy unit tests passed"
    return 0
  else
    log_error "Policy unit tests failed"
    return 1
  fi
}

# Query OPA runtime for policy decisions
query_opa_decision() {
  log_info "Querying OPA runtime for policy decision..."
  
  local policy="$1"
  local input="$2"
  local opa_url="${OPA_ENDPOINT:-http://localhost:8181}"
  
  if ! curl -sf -X POST "${opa_url}/v1/data/${policy}" \
    -H 'Content-Type: application/json' \
    -d "${input}" > /dev/null 2>&1; then
    log_error "Failed to query OPA policy: ${policy}"
    return 1
  fi
  
  log_success "OPA policy decision returned successfully"
  return 0
}

main() {
  local integration_type="${1:-}"
  
  if [[ -z "${integration_type}" ]]; then
    log_error "Usage: integrate-opa-policies.sh <terraform|docker-compose|policy-tests|runtime-query>"
    exit 1
  fi
  
  case "${integration_type}" in
    terraform)
      evaluate_terraform_policies || exit 1
      ;;
    docker-compose)
      evaluate_docker_compose_policies || exit 1
      ;;
    policy-tests)
      evaluate_policy_tests || exit 1
      ;;
    runtime-query)
      query_opa_decision "core.production_gate" '{"action": "deploy", "target_env": "staging"}' || exit 1
      ;;
    *)
      log_error "Unknown integration type: ${integration_type}"
      exit 1
      ;;
  esac
  
  log_success "OPA policy integration check passed"
}

main "$@"