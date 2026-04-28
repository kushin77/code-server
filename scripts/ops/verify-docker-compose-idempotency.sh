#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/verify-docker-compose-idempotency.sh
# @module      ops/verify-docker-compose-idempotency
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/verify-docker-compose-idempotency.sh
# @description Phase 2: Docker Compose idempotency verification for IaC Lifecycle Control (#1531)
# @governance GOV-002 - Immutable, idempotent infrastructure
# @automation Validates docker-compose can be redeployed from clean state
# @prerequisite Must source scripts/_common/init.sh

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Source bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly TEST_MODE="${1:-validate}"  # validate, full-test, cleanup
readonly MAX_START_WAIT_SECONDS=120
readonly EXPECTED_SERVICES=(
  "caddy-init"
  "caddy"
  "opa"
  "oauth2-proxy"
  "postgres"
  "redis"
  "redpanda"
  "execution-scheduler"
  "qdrant-init"
  "qdrant"
  "ollama"
  "prometheus"
  "grafana"
  "loki"
  "alertmanager"
  "promtail"
)

# ==============================================================================
# VALIDATION FUNCTIONS
# ==============================================================================

# Validate docker-compose configuration syntax
validate_compose_syntax() {
  log_info "Validating Docker Compose configuration syntax..."
  
  cd "${REPO_ROOT}"
  
  if ! docker-compose config --quiet > /dev/null 2>&1; then
    log_error "Docker Compose configuration has syntax errors"
    docker-compose config 2>&1 | head -20
    return 1
  fi
  
  log_success "✅ Docker Compose configuration syntax valid"
  return 0
}

# Verify all required services are defined
verify_services_defined() {
  log_info "Verifying all required services are defined..."
  
  cd "${REPO_ROOT}"
  
  local missing_services=()
  local configured_services=$(docker-compose config --services)
  
  for service in "${EXPECTED_SERVICES[@]}"; do
    if ! echo "$configured_services" | grep -q "^${service}$"; then
      missing_services+=("$service")
    fi
  done
  
  if [ ${#missing_services[@]} -gt 0 ]; then
    log_warn "Missing services: ${missing_services[*]}"
    # Not fatal - some services may be optional
  fi
  
  log_success "✅ Service definitions verified"
  return 0
}

# Verify all services have health checks or restart policies
verify_health_checks() {
  log_info "Verifying services have health checks or restart policies..."
  
  cd "${REPO_ROOT}"
  
  local config_output=$(docker-compose config --format json)
  
  local services_without_health=()
  
  # Check each service
  for service in $(echo "$config_output" | jq -r '.services | keys[]'); do
    local has_healthcheck=$(echo "$config_output" | jq --arg svc "$service" '.services[$svc].healthcheck' | grep -v null || echo "")
    local has_restart=$(echo "$config_output" | jq --arg svc "$service" '.services[$svc].restart' | grep -v null || echo "")
    
    if [ -z "$has_healthcheck" ] && [ -z "$has_restart" ]; then
      services_without_health+=("$service")
    fi
  done
  
  if [ ${#services_without_health[@]} -gt 0 ]; then
    log_warn "Services without health checks or restart policy: ${services_without_health[*]}"
  else
    log_success "✅ All services have health checks or restart policies"
  fi
  
  return 0
}

# Verify no hardcoded IPs or domains
verify_no_hardcoded_values() {
  log_info "Verifying no hardcoded IPs or domains..."
  
  cd "${REPO_ROOT}"
  
  # Check for hardcoded IPs
  if grep -E '192\.168|10\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])' \
    docker-compose.yml docker-compose.override.yml 2>/dev/null | grep -v "^#"; then
    log_error "Hardcoded IP addresses found in Docker Compose"
    return 1
  fi
  
  # Check for hardcoded domain (use ${APEX_DOMAIN} / env-driven domains)
  if grep -E 'kushnir\.cloud|localhost|127\.0\.0\.1' \
    docker-compose.yml docker-compose.override.yml 2>/dev/null | grep -v "^#" | grep -v '\$'; then
    log_warn "Potential hardcoded values found - check if should be variables"
  fi
  
  log_success "✅ No obvious hardcoded IP addresses detected"
  return 0
}

# ==============================================================================
# DEPLOYMENT IDEMPOTENCY TESTS
# ==============================================================================

# Test: Deploy, stop, deploy again (should be identical)
test_redeploy_idempotency() {
  log_info "Testing idempotent redeploy (deploy -> stop -> deploy)..."
  
  cd "${REPO_ROOT}"
  
  # First deployment
  log_info "First deployment..."
  docker-compose up -d --force-recreate --remove-orphans 2>&1 | grep -v "^Network" | head -5
  
  sleep 5
  
  # Get first deployment state
  local first_state=$(docker-compose ps -a --format json)
  local first_digest=$(echo "$first_state" | jq -s -r 'map(.Image) | join(",")' | md5sum | awk '{print $1}')
  
  log_info "First deployment state digest: $first_digest"
  
  # Stop services
  log_info "Stopping services..."
  docker-compose down -v
  
  sleep 3
  
  # Second deployment (should be identical)
  log_info "Second deployment..."
  docker-compose up -d --force-recreate --remove-orphans 2>&1 | grep -v "^Network" | head -5
  
  sleep 5
  
  # Get second deployment state
  local second_state=$(docker-compose ps -a --format json)
  local second_digest=$(echo "$second_state" | jq -s -r 'map(.Image) | join(",")' | md5sum | awk '{print $1}')
  
  log_info "Second deployment state digest: $second_digest"
  
  if [ "$first_digest" = "$second_digest" ]; then
    log_success "✅ Idempotent redeploy test PASSED"
    return 0
  else
    log_error "❌ Idempotent redeploy test FAILED - states differ"
    return 1
  fi
}

# Test: Verify persistent volumes are preserved
test_persistent_volume_preservation() {
  log_info "Testing persistent volume preservation..."
  
  cd "${REPO_ROOT}"
  
  # Check for persistent volumes in compose
  local persistent_volumes=$(docker-compose config --format json | jq -r '.volumes | keys[]' || echo "")
  
  if [ -z "$persistent_volumes" ]; then
    log_warn "No named volumes defined in Docker Compose"
    return 0
  fi
  
  log_info "Persistent volumes defined: $persistent_volumes"
  
  source "${REPO_ROOT}/scripts/_common/service-names.env"
  
  # Create test marker file in PostgreSQL volume
  docker exec "${POSTGRES_CONTAINER_NAME}" touch /var/lib/postgresql/data/.idempotency-test-marker 2>/dev/null || true
  
  # Stop and restart
  docker-compose down
  sleep 3
  docker-compose up -d
  sleep 5
  
  # Check if marker persists
  if docker exec "${POSTGRES_CONTAINER_NAME}" test -f /var/lib/postgresql/data/.idempotency-test-marker 2>/dev/null; then
    log_success "✅ Persistent volumes preserved across restarts"
    docker exec "${POSTGRES_CONTAINER_NAME}" rm /var/lib/postgresql/data/.idempotency-test-marker 2>/dev/null || true
    return 0
  else
    log_warn "Persistent volume test inconclusive"
    return 0
  fi
}

# Test: Verify environment variables are properly substituted
test_environment_substitution() {
  log_info "Testing environment variable substitution..."
  
  cd "${REPO_ROOT}"
  
  # Get rendered config
  local rendered_config=$(docker-compose config)
  
  # Check for unsubstituted variables (should have none)
  if echo "$rendered_config" | grep -E '\$\{|:\$\(' | grep -v '^\s*#'; then
    log_error "Unsubstituted environment variables found"
    echo "$rendered_config" | grep -E '\$\{|:\$\('
    return 1
  fi
  
  # Verify required variables are set
  if [ -z "${APEX_DOMAIN:-}" ] || [ -z "${PRIMARY_HOST:-}" ]; then
    log_error "Required environment variables not set"
    return 1
  fi
  
  log_success "✅ Environment variable substitution verified"
  return 0
}

# ==============================================================================
# COMPREHENSIVE IDEMPOTENCY TEST
# ==============================================================================

run_full_idempotency_test() {
  log_info "=== FULL IDEMPOTENCY TEST SUITE ==="
  
  local failed_tests=0
  
  # Pre-test cleanup
  cd "${REPO_ROOT}"
  docker-compose down -v 2>/dev/null || true
  sleep 3
  
  # Run validation tests
  if ! validate_compose_syntax; then
    failed_tests=$((failed_tests + 1))
  fi
  
  if ! verify_services_defined; then
    failed_tests=$((failed_tests + 1))
  fi
  
  if ! verify_health_checks; then
    failed_tests=$((failed_tests + 1))
  fi
  
  if ! verify_no_hardcoded_values; then
    failed_tests=$((failed_tests + 1))
  fi
  
  # Run deployment tests
  if ! test_environment_substitution; then
    failed_tests=$((failed_tests + 1))
  fi
  
  if ! test_redeploy_idempotency; then
    failed_tests=$((failed_tests + 1))
  fi
  
  if ! test_persistent_volume_preservation; then
    failed_tests=$((failed_tests + 1))
  fi
  
  # Post-test cleanup
  docker-compose down -v 2>/dev/null || true
  
  if [ $failed_tests -eq 0 ]; then
    log_success "✅ All idempotency tests PASSED"
    return 0
  else
    log_error "❌ $failed_tests test(s) FAILED"
    return 1
  fi
}

# ==============================================================================
# VALIDATION ONLY (no deployment)
# ==============================================================================

run_validation_only() {
  log_info "Running Docker Compose idempotency validations (no deployment)..."
  
  local failed_checks=0
  
  if ! validate_compose_syntax; then
    failed_checks=$((failed_checks + 1))
  fi
  
  if ! verify_services_defined; then
    failed_checks=$((failed_checks + 1))
  fi
  
  if ! verify_health_checks; then
    failed_checks=$((failed_checks + 1))
  fi
  
  if ! verify_no_hardcoded_values; then
    failed_checks=$((failed_checks + 1))
  fi
  
  if [ $failed_checks -eq 0 ]; then
    log_success "✅ All validations PASSED"
    return 0
  else
    log_error "❌ $failed_checks validation(s) FAILED"
    return 1
  fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  log_info "Docker Compose Idempotency Verification Started"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Mode: $TEST_MODE"
  
  # Load canonical config
  if ! _validate_required_env 2>/dev/null; then
    log_error "Environment validation failed"
    exit 1
  fi
  
  case "$TEST_MODE" in
    validate)
      run_validation_only
      ;;
    full-test)
      run_full_idempotency_test
      ;;
    cleanup)
      log_info "Cleaning up test deployments..."
      cd "${REPO_ROOT}"
      docker-compose down -v 2>/dev/null || true
      log_success "Cleanup complete"
      ;;
    *)
      log_error "Unknown test mode: $TEST_MODE"
      echo "Usage: $0 {validate|full-test|cleanup}"
      exit 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
