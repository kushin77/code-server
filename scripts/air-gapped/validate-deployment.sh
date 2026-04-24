#!/usr/bin/env bash
# @file        scripts/air-gapped/validate-deployment.sh
# @module      air-gapped/deployment-validation
# @description Validate air-gapped deployment configuration and network isolation
#
# This script performs comprehensive checks to ensure the air-gapped deployment
# is properly isolated, all services are healthy, and no external network
# calls are being made.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Global state
# ────────────────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# ────────────────────────────────────────────────────────────────────────────
# Test helpers
# ────────────────────────────────────────────────────────────────────────────
test_pass() {
  local test_name="$1"
  log_info "✓ PASS: $test_name"
  ((PASS_COUNT++))
}

test_fail() {
  local test_name="$1"
  local reason="${2:-}"
  log_error "✗ FAIL: $test_name"
  [[ -n "$reason" ]] && log_error "  Reason: $reason"
  ((FAIL_COUNT++))
}

test_warn() {
  local test_name="$1"
  local reason="${2:-}"
  log_warn "⚠ WARN: $test_name"
  [[ -n "$reason" ]] && log_warn "  Reason: $reason"
  ((WARN_COUNT++))
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Services are running
# ────────────────────────────────────────────────────────────────────────────
test_services_running() {
  log_info ""
  log_info "=== Service Health Checks ==="
  
  local required_services=(
    "code-server"
    "postgres"
    "redis"
    "synapse"
    "element-web"
    "caddy"
    "prometheus"
    "grafana"
    "alertmanager"
  )
  
  for service in "${required_services[@]}"; do
    local status
    status=$(docker-compose -f docker-compose-air-gapped.yml ps --services --filter "status=running" | grep -c "$service" || true)
    
    if [[ $status -eq 1 ]]; then
      test_pass "Service running: $service"
    else
      test_fail "Service not running: $service"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Network isolation (internal network has no external routing)
# ────────────────────────────────────────────────────────────────────────────
test_network_isolation() {
  log_info ""
  log_info "=== Network Isolation Checks ==="
  
  # Check that internal network is marked as internal
  local internal_net
  # shellcheck disable=SC2046
  internal_net=$(docker network inspect -f '{{.Internal}}' $(docker network ls -q -f name=net-internal) 2>/dev/null || echo "false")
  
  if [[ "$internal_net" == "true" ]]; then
    test_pass "Internal network is isolated (no external routing)"
  else
    test_fail "Internal network may not be properly isolated"
  fi
  
  # Verify no default gateway on internal network
  local gw
  # shellcheck disable=SC2046
  gw=$(docker network inspect -f '{{index .IPAM.Config 0 | .Gateway}}' $(docker network ls -q -f name=net-internal) 2>/dev/null || echo "")
  
  if [[ -z "$gw" ]] || [[ "$gw" == "<nil>" ]]; then
    test_pass "Internal network has no default gateway (proper isolation)"
  else
    test_warn "Internal network has gateway: $gw (may allow unintended routing)"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Federation disabled in Synapse
# ────────────────────────────────────────────────────────────────────────────
test_federation_disabled() {
  log_info ""
  log_info "=== Federation Configuration Checks ==="
  
  # Check that federation is disabled in Synapse config
  if [[ -f "$SCRIPT_DIR/synapse-air-gapped.yaml" ]]; then
    if grep -q "federation_domain_whitelist:" "$SCRIPT_DIR/synapse-air-gapped.yaml" 2>/dev/null; then
      test_pass "Federation whitelist configured in Synapse"
    else
      test_fail "Federation whitelist not found in Synapse config"
    fi
    
    if grep -q "allow_public_rooms_without_auth: false" "$SCRIPT_DIR/synapse-air-gapped.yaml" 2>/dev/null; then
      test_pass "Public rooms disabled"
    else
      test_warn "Public rooms not explicitly disabled"
    fi
  else
    test_warn "Synapse air-gapped config not found at expected location"
  fi
  
  # Test: Federation endpoint returns 404
  local fed_status
  fed_status=$(curl -s -o /dev/null -w "%{http_code}" https://localhost:8448/.well-known/matrix/server 2>/dev/null || echo "000")
  
  if [[ "$fed_status" == "404" ]] || [[ "$fed_status" == "000" ]]; then
    test_pass "Federation endpoint disabled (404 or unreachable)"
  else
    test_fail "Federation endpoint accessible (HTTP $fed_status)"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test: All images are pre-loaded (no Docker Hub pulls)
# ────────────────────────────────────────────────────────────────────────────
test_images_preloaded() {
  log_info ""
  log_info "=== Image Pre-Loading Checks ==="
  
  local required_images=(
    "code-server-enterprise:dev"
    "ollama/ollama:0.1.27"
    "postgres:15-alpine"
    "redis:7-alpine"
    "matrixdotorg/synapse:v1.95"
    "vectorim/element-web:v1.11.50"
    "caddy:2.7-alpine"
    "prom/prometheus:v2.48"
    "grafana/grafana:10.2"
    "prom/alertmanager:v0.26"
  )
  
  for image in "${required_images[@]}"; do
    if docker image inspect "$image" &>/dev/null; then
      test_pass "Image pre-loaded: $image"
    else
      test_fail "Image missing: $image"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Internal DNS resolution
# ────────────────────────────────────────────────────────────────────────────
test_internal_dns() {
  log_info ""
  log_info "=== Internal DNS Checks ==="
  
  # Test internal DNS from container
  local dns_test
  dns_test=$(docker run --rm --network net-app alpine:latest nslookup synapse 2>/dev/null | grep -c "Address:" || true)
  
  if [[ $dns_test -gt 0 ]]; then
    test_pass "Internal DNS resolves container names"
  else
    test_warn "Internal DNS may not be properly configured"
  fi
  
  # Check /etc/hosts or DNS config for matrix.internal
  if grep -q "matrix.internal" /etc/hosts 2>/dev/null || grep -q "matrix.internal" /etc/resolv.conf 2>/dev/null; then
    test_pass "Internal domain configured in DNS"
  else
    test_warn "Internal domain (matrix.internal) not in /etc/hosts or resolv.conf"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test: No external HTTP/HTTPS connections allowed
# ────────────────────────────────────────────────────────────────────────────
test_no_external_network() {
  log_info ""
  log_info "=== Network Egress Checks ==="
  
  # Check firewall rules (if iptables is available)
  if command -v iptables &>/dev/null; then
    local outbound_deny
    outbound_deny=$(iptables -L -n | grep -c "net-internal.*DROP" || true)
    
    if [[ $outbound_deny -gt 0 ]]; then
      test_pass "Firewall rules block net-internal outbound"
    else
      test_warn "Firewall rules for net-internal not verified"
    fi
  else
    test_warn "iptables not available (cannot verify firewall rules)"
  fi
  
  # Try connecting to external host from internal network container (should fail or timeout)
  log_info "Testing external connectivity (should timeout)..."
  local timeout=5
  if timeout $timeout docker run --rm --network net-internal alpine:latest \
      wget -O /dev/null -q https://www.google.com 2>/dev/null || true; then
    test_fail "External network connectivity detected (unexpected!)"
  else
    test_pass "No external network connectivity (as expected)"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Service health endpoints
# ────────────────────────────────────────────────────────────────────────────
test_service_health() {
  log_info ""
  log_info "=== Service Health Endpoints ==="
  
  local health_checks=(
    "http://localhost:8080/healthz|code-server"
    "http://localhost:8008/_matrix/client/versions|synapse"
    "http://localhost:9090/-/healthy|prometheus"
    "http://localhost:3000/api/health|grafana"
    "http://localhost:9093/-/healthy|alertmanager"
  )
  
  for check in "${health_checks[@]}"; do
    IFS='|' read -r url service <<< "$check"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
      test_pass "Service healthy: $service (HTTP $status)"
    else
      test_fail "Service unhealthy: $service (HTTP $status)"
    fi
  done
}

# ────────────────────────────────────────────────────────────────────────────
# Test: Element Web configuration
# ────────────────────────────────────────────────────────────────────────────
test_element_config() {
  log_info ""
  log_info "=== Element Web Configuration Checks ==="
  
  if [[ -f "$SCRIPT_DIR/element-config-air-gapped.json" ]]; then
    # Check that integration server is empty
    if ! grep -q '"integrations_ui_url"' "$SCRIPT_DIR/element-config-air-gapped.json" 2>/dev/null || \
       grep -q '"integrations_ui_url": ""' "$SCRIPT_DIR/element-config-air-gapped.json" 2>/dev/null; then
      test_pass "Integrations UI disabled in Element config"
    else
      test_warn "Integrations UI may be enabled in Element config"
    fi
    
    # Check that identity server is empty
    if ! grep -q '"identity_server_url"' "$SCRIPT_DIR/element-config-air-gapped.json" 2>/dev/null || \
       grep -q '"identity_server_url": ""' "$SCRIPT_DIR/element-config-air-gapped.json" 2>/dev/null || \
       grep -q '"identity_server_url": null' "$SCRIPT_DIR/element-config-air-gapped.json" 2>/dev/null; then
      test_pass "Identity server disabled in Element config"
    else
      test_warn "Identity server may be enabled in Element config"
    fi
  else
    test_warn "Element air-gapped config not found"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Print summary
# ────────────────────────────────────────────────────────────────────────────
print_summary() {
  log_info ""
  log_info "========================================================================"
  log_info "Validation Summary"
  log_info "========================================================================"
  log_info "✓ Passed: $PASS_COUNT"
  log_info "✗ Failed: $FAIL_COUNT"
  log_info "⚠ Warnings: $WARN_COUNT"
  log_info ""
  
  if [[ $FAIL_COUNT -eq 0 ]]; then
    log_info "✓ All critical checks passed!"
    log_info ""
    if [[ $WARN_COUNT -gt 0 ]]; then
      log_warn "⚠ $WARN_COUNT warning(s) found - review recommendations above"
    fi
    return 0
  else
    log_error "✗ $FAIL_COUNT critical issue(s) found - remediate above"
    return 1
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main entry point
# ────────────────────────────────────────────────────────────────────────────
main() {
  log_info "========================================================================"
  log_info "Air-Gapped Deployment Validation"
  log_info "========================================================================"
  log_info ""
  
  # Run all tests
  test_images_preloaded
  test_services_running
  test_network_isolation
  test_federation_disabled
  test_internal_dns
  test_no_external_network
  test_service_health
  test_element_config
  
  # Print summary and exit with appropriate code
  print_summary
}

main "$@"
