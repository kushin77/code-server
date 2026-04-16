#!/bin/bash
# @file        scripts/validate-rbac-enforcement-phase3.sh
# @module      testing
# @description validate rbac enforcement phase3 — on-prem code-server
# @owner       platform
# @status      active
# Phase 3: RBAC Enforcement Health Check & Validation
# Comprehensive testing suite for authorization controls

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RBAC_NAMESPACE="default"
APEX_DOMAIN="kushnir.cloud"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TEST_PASSED=0
TEST_FAILED=0

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
  ((TEST_PASSED++))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $*"
  ((TEST_FAILED++))
}

log_warning() { log_warn "$@"; }

# ============================================================================
# Test 1: Role Definitions
# ============================================================================

test_role_definitions() {
  echo ""
  log_info "=== Test 1: Role Definitions ==="

  local roles=("code-server-role" "postgresql-role" "redis-role" "prometheus-role" "grafana-role" "ollama-role" "alertmanager-role" "jaeger-role")
  
  for role in "${roles[@]}"; do
    if kubectl get role "$role" -n "$RBAC_NAMESPACE" &>/dev/null; then
      log_success "Role '$role' exists"
      # Get rule count
      local rule_count=$(kubectl get role "$role" -n "$RBAC_NAMESPACE" -o jsonpath='{.rules | length}')
      echo "  Rules: $rule_count"
    else
      log_fail "Role '$role' not found"
    fi
  done
}

# ============================================================================
# Test 2: Role Bindings
# ============================================================================

test_role_bindings() {
  echo ""
  log_info "=== Test 2: Role Bindings ==="

  local bindings=("code-server-rolebinding" "postgresql-rolebinding" "redis-rolebinding" "prometheus-rolebinding" "grafana-rolebinding" "ollama-rolebinding" "alertmanager-rolebinding" "jaeger-rolebinding")
  
  for binding in "${bindings[@]}"; do
    if kubectl get rolebinding "$binding" -n "$RBAC_NAMESPACE" &>/dev/null; then
      log_success "RoleBinding '$binding' exists"
      # Get subject count
      local subject_count=$(kubectl get rolebinding "$binding" -n "$RBAC_NAMESPACE" -o jsonpath='{.subjects | length}')
      echo "  Subjects: $subject_count"
    else
      log_fail "RoleBinding '$binding' not found"
    fi
  done
}

# ============================================================================
# Test 3: Service Account RBAC Permissions
# ============================================================================

test_service_account_permissions() {
  echo ""
  log_info "=== Test 3: Service Account RBAC Permissions ==="

  local service_accounts=("code-server-sa" "postgresql-sa" "redis-sa" "prometheus-sa" "grafana-sa" "ollama-sa" "alertmanager-sa" "jaeger-sa")
  
  for sa in "${service_accounts[@]}"; do
    if kubectl get serviceaccount "$sa" -n "$RBAC_NAMESPACE" &>/dev/null; then
      log_success "ServiceAccount '$sa' exists"
      
      # Check if service account has role bindings
      if kubectl get rolebindings -n "$RBAC_NAMESPACE" -o jsonpath='{.items[*].subjects[?(@.name=="'$sa'")].name}' | grep -q "$sa"; then
        echo "  Has role binding: YES"
      else
        log_warning "  Has role binding: NO"
      fi
    else
      log_fail "ServiceAccount '$sa' not found"
    fi
  done
}

# ============================================================================
# Test 4: ClusterRole & ClusterRoleBinding
# ============================================================================

test_cluster_role_bindings() {
  echo ""
  log_info "=== Test 4: Cluster-Wide Role Bindings ==="

  if kubectl get clusterrole service-cross-namespace-role &>/dev/null; then
    log_success "ClusterRole 'service-cross-namespace-role' exists"
  else
    log_fail "ClusterRole 'service-cross-namespace-role' not found"
  fi

  if kubectl get clusterrolebinding service-cross-namespace-binding &>/dev/null; then
    log_success "ClusterRoleBinding 'service-cross-namespace-binding' exists"
    local subject_count=$(kubectl get clusterrolebinding service-cross-namespace-binding -o jsonpath='{.subjects | length}')
    echo "  Subjects: $subject_count"
  else
    log_fail "ClusterRoleBinding 'service-cross-namespace-binding' not found"
  fi
}

# ============================================================================
# Test 5: RBAC Policy Configuration
# ============================================================================

test_rbac_policy_config() {
  echo ""
  log_info "=== Test 5: RBAC Policy Configuration ==="

  if kubectl get configmap rbac-audit-config -n "$RBAC_NAMESPACE" &>/dev/null; then
    log_success "RBAC audit config ConfigMap exists"
  else
    log_fail "RBAC audit config ConfigMap not found"
  fi

  if kubectl get configmap service-authorization-policies -n "$RBAC_NAMESPACE" &>/dev/null; then
    log_success "Service authorization policies ConfigMap exists"
    # Verify it has policy definitions
    if kubectl get configmap service-authorization-policies -n "$RBAC_NAMESPACE" -o jsonpath='{.data}' | grep -q "code-server"; then
      log_success "Code-server policy defined"
    else
      log_fail "Code-server policy not found"
    fi
  else
    log_fail "Service authorization policies ConfigMap not found"
  fi
}

# ============================================================================
# Test 6: Test RBAC Enforcement (kubectl auth can-i)
# ============================================================================

test_rbac_enforcement() {
  echo ""
  log_info "=== Test 6: RBAC Enforcement Verification ==="

  # Test: code-server-sa can read configmaps
  if kubectl auth can-i get configmaps --as=system:serviceaccount:default:code-server-sa -n default &>/dev/null; then
    log_success "code-server-sa can read configmaps (allowed)"
  else
    log_fail "code-server-sa cannot read configmaps (may be restricted)"
  fi

  # Test: code-server-sa cannot write secrets
  if ! kubectl auth can-i update secrets --as=system:serviceaccount:default:code-server-sa -n default &>/dev/null; then
    log_success "code-server-sa cannot update secrets (restricted as expected)"
  else
    log_warning "code-server-sa can update secrets (should be restricted)"
  fi

  # Test: postgresql-sa can read secrets
  if kubectl auth can-i get secrets --as=system:serviceaccount:default:postgresql-sa -n default &>/dev/null; then
    log_success "postgresql-sa can read secrets (allowed)"
  else
    log_fail "postgresql-sa cannot read secrets (should be allowed)"
  fi

  # Test: prometheus-sa can read endpoints
  if kubectl auth can-i get endpoints --as=system:serviceaccount:default:prometheus-sa -n default &>/dev/null; then
    log_success "prometheus-sa can read endpoints (allowed)"
  else
    log_fail "prometheus-sa cannot read endpoints (should be allowed)"
  fi
}

# ============================================================================
# Test 7: Caddy Middleware Configuration
# ============================================================================

test_caddy_middleware() {
  echo ""
  log_info "=== Test 7: Caddy RBAC Middleware Configuration ==="

  local caddy_middleware_file="$PROJECT_ROOT/config/caddy/rbac-enforcement-middleware.caddyfile"
  
  if [[ -f "$caddy_middleware_file" ]]; then
    log_success "RBAC middleware file exists"
    
    # Check for JWT validation snippet
    if grep -q "jwt_validation" "$caddy_middleware_file"; then
      log_success "JWT validation middleware defined"
    else
      log_fail "JWT validation middleware not found"
    fi
    
    # Check for rate limiting
    if grep -q "rate_limit" "$caddy_middleware_file"; then
      log_success "Rate limiting configured"
    else
      log_fail "Rate limiting not configured"
    fi
    
    # Check for RBAC audit logging
    if grep -q "rbac_audit" "$caddy_middleware_file"; then
      log_success "RBAC audit logging configured"
    else
      log_fail "RBAC audit logging not configured"
    fi
  else
    log_fail "RBAC middleware file not found"
  fi
}

# ============================================================================
# Test 8: Service-to-Service Authorization Policies
# ============================================================================

test_service_policies() {
  echo ""
  log_info "=== Test 8: Service-to-Service Authorization Policies ==="

  # Get the policy ConfigMap
  local policies=$(kubectl get configmap service-authorization-policies -n "$RBAC_NAMESPACE" -o jsonpath='{.data.policies\.json}' 2>/dev/null || echo "")
  
  if [[ -n "$policies" ]]; then
    # Check for code-server policy
    if echo "$policies" | grep -q '"service": "code-server"'; then
      log_success "code-server authorization policy defined"
      if echo "$policies" | grep -q '"allowedCalls": \["postgresql"'; then
        log_success "code-server can call postgresql"
      fi
    else
      log_fail "code-server authorization policy not found"
    fi
    
    # Check for postgresql policy
    if echo "$policies" | grep -q '"service": "postgresql"'; then
      log_success "postgresql authorization policy defined"
    else
      log_fail "postgresql authorization policy not found"
    fi
  else
    log_fail "Service authorization policies not found"
  fi
}

# ============================================================================
# Test 9: RBAC Audit Logging (in database)
# ============================================================================

test_audit_logging() {
  echo ""
  log_info "=== Test 9: RBAC Audit Logging ==="

  # Check if PostgreSQL has audit table
  local postgres_pod=$(kubectl get pods -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [[ -n "$postgres_pod" ]]; then
    if kubectl exec "$postgres_pod" -- psql -U postgres -d postgres -c "SELECT * FROM rbac_audit_log LIMIT 1;" &>/dev/null; then
      log_success "RBAC audit table exists in PostgreSQL"
    else
      log_warning "RBAC audit table not found (may need to be created)"
    fi
  else
    log_warning "PostgreSQL pod not found - cannot verify audit table"
  fi
}

# ============================================================================
# Test 10: Overall RBAC Health
# ============================================================================

test_overall_health() {
  echo ""
  log_info "=== Test 10: Overall RBAC Health ==="

  # Check total role count
  local role_count=$(kubectl get roles -n "$RBAC_NAMESPACE" -l phase=3 -o jsonpath='{.items | length}')
  if [[ "$role_count" -ge 8 ]]; then
    log_success "All 8 roles deployed"
  else
    log_fail "Only $role_count roles found (expected 8)"
  fi

  # Check total rolebinding count
  local binding_count=$(kubectl get rolebindings -n "$RBAC_NAMESPACE" -l phase=3 -o jsonpath='{.items | length}')
  if [[ "$binding_count" -ge 8 ]]; then
    log_success "All 8 role bindings deployed"
  else
    log_fail "Only $binding_count role bindings found (expected 8)"
  fi

  # Check ClusterRoleBinding
  if kubectl get clusterrolebinding service-cross-namespace-binding &>/dev/null; then
    log_success "ClusterRoleBinding exists for cross-namespace access"
  else
    log_fail "ClusterRoleBinding not found"
  fi
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║      Phase 3: RBAC Enforcement Health Check Summary           ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Test Results:"
  echo "  Passed: ${GREEN}${TEST_PASSED}${NC}"
  echo "  Failed: ${RED}${TEST_FAILED}${NC}"
  echo ""

  if [[ "$TEST_FAILED" -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed! RBAC enforcement is operational${NC}"
    return 0
  else
    echo -e "${RED}❌ Some tests failed. Please review and address issues.${NC}"
    return 1
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 3: RBAC Enforcement Health Check & Validation Suite    ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  test_role_definitions
  test_role_bindings
  test_service_account_permissions
  test_cluster_role_bindings
  test_rbac_policy_config
  test_rbac_enforcement
  test_caddy_middleware
  test_service_policies
  test_audit_logging
  test_overall_health

  print_summary
}

main "$@"

