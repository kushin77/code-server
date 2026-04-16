#!/bin/bash
# Phase 2.1: OIDC Issuer Health Check & Validation
# Comprehensive testing suite for workload identity federation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OIDC_NAMESPACE="oidc-issuer"
OIDC_ISSUER_URL="https://oidc.kushnir.cloud"
OIDC_ISSUER_SERVICE="oidc-issuer.oidc-issuer.svc.cluster.local:8888"
APEX_DOMAIN="kushnir.cloud"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TEST_RESULTS=0
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
# Test 1: Kubernetes Deployment Health
# ============================================================================

test_k8s_deployment_health() {
  echo ""
  log_info "=== Test 1: Kubernetes Deployment Health ==="

  # Check namespace
  if kubectl get namespace "$OIDC_NAMESPACE" &>/dev/null; then
    log_success "Namespace '$OIDC_NAMESPACE' exists"
  else
    log_fail "Namespace '$OIDC_NAMESPACE' not found"
    return 1
  fi

  # Check deployment
  if ! kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer &>/dev/null; then
    log_fail "Deployment 'oidc-issuer' not found"
    return 1
  fi

  # Check ready replicas
  local ready=$(kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer -o jsonpath='{.status.readyReplicas}')
  local desired=$(kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer -o jsonpath='{.spec.replicas}')

  if [[ "$ready" -eq "$desired" && "$ready" -gt 0 ]]; then
    log_success "OIDC issuer: $ready/$desired replicas ready"
  else
    log_fail "OIDC issuer: $ready/$desired replicas ready (expected $desired)"
  fi

  # Check service
  if kubectl get service -n "$OIDC_NAMESPACE" oidc-issuer &>/dev/null; then
    log_success "Service 'oidc-issuer' exists"
  else
    log_fail "Service 'oidc-issuer' not found"
  fi

  # Check pods running
  local running_pods=$(kubectl get pods -n "$OIDC_NAMESPACE" -l app=oidc-issuer -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}')
  if [[ -n "$running_pods" ]]; then
    log_success "OIDC issuer pods running:"
    echo "$running_pods" | while read -r pod phase; do
      if [[ "$phase" == "Running" ]]; then
        echo "  ✓ $pod: $phase"
      else
        echo "  ✗ $pod: $phase"
      fi
    done
  else
    log_fail "No OIDC issuer pods found"
  fi
}

# ============================================================================
# Test 2: OIDC Endpoint Connectivity
# ============================================================================

test_oidc_endpoints() {
  echo ""
  log_info "=== Test 2: OIDC Endpoint Connectivity (Internal) ==="

  # Get first OIDC issuer pod
  local oidc_pod=$(kubectl get pods -n "$OIDC_NAMESPACE" -l app=oidc-issuer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -z "$oidc_pod" ]]; then
    log_fail "No OIDC issuer pod found"
    return 1
  fi

  # Test health endpoint
  log_info "Testing health endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/healthz -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
    log_success "Health endpoint (http://localhost:8888/healthz)"
  else
    log_fail "Health endpoint unreachable"
  fi

  # Test discovery endpoint
  log_info "Testing discovery endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/.well-known/openid-configuration | grep -q '"issuer"'; then
    log_success "Discovery endpoint (/.well-known/openid-configuration)"
  else
    log_fail "Discovery endpoint not responding"
  fi

  # Test JWKS endpoint
  log_info "Testing JWKS endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/.well-known/jwks.json | grep -q '"keys"'; then
    log_success "JWKS endpoint (/.well-known/jwks.json)"
  else
    log_fail "JWKS endpoint not responding"
  fi
}

# ============================================================================
# Test 3: Service Account Configuration
# ============================================================================

test_service_accounts() {
  echo ""
  log_info "=== Test 3: Service Account Configuration ==="

  local services=("code-server-sa" "postgresql-sa" "redis-sa" "prometheus-sa" "grafana-sa" "ollama-sa" "alertmanager-sa" "jaeger-sa")

  for sa in "${services[@]}"; do
    if kubectl get serviceaccount "$sa" -n default &>/dev/null; then
      log_success "ServiceAccount '$sa' exists"
    else
      log_fail "ServiceAccount '$sa' not found"
    fi
  done
}

# ============================================================================
# Test 4: RBAC Configuration
# ============================================================================

test_rbac_configuration() {
  echo ""
  log_info "=== Test 4: RBAC Configuration ==="

  # Check ClusterRole
  if kubectl get clusterrole workload-identity-token-requestor &>/dev/null; then
    log_success "ClusterRole 'workload-identity-token-requestor' exists"
  else
    log_fail "ClusterRole 'workload-identity-token-requestor' not found"
  fi

  # Check ClusterRoleBinding
  if kubectl get clusterrolebinding workload-identity-token-requestors &>/dev/null; then
    log_success "ClusterRoleBinding 'workload-identity-token-requestors' exists"
  else
    log_fail "ClusterRoleBinding 'workload-identity-token-requestors' not found"
  fi

  # Check OIDC issuer ClusterRole
  if kubectl get clusterrole oidc-issuer-role &>/dev/null; then
    log_success "ClusterRole 'oidc-issuer-role' exists"
  else
    log_fail "ClusterRole 'oidc-issuer-role' not found"
  fi

  # Check OIDC issuer ClusterRoleBinding
  if kubectl get clusterrolebinding oidc-issuer-rolebinding &>/dev/null; then
    log_success "ClusterRoleBinding 'oidc-issuer-rolebinding' exists"
  else
    log_fail "ClusterRoleBinding 'oidc-issuer-rolebinding' not found"
  fi
}

# ============================================================================
# Test 5: ConfigMap & Secrets
# ============================================================================

test_configmaps_and_secrets() {
  echo ""
  log_info "=== Test 5: ConfigMap & Secrets ==="

  # Check OIDC issuer config
  if kubectl get configmap -n "$OIDC_NAMESPACE" oidc-issuer-config &>/dev/null; then
    log_success "ConfigMap 'oidc-issuer-config' exists"
  else
    log_fail "ConfigMap 'oidc-issuer-config' not found"
  fi

  # Check signing key secret
  if kubectl get secret -n "$OIDC_NAMESPACE" oidc-signing-key &>/dev/null; then
    log_success "Secret 'oidc-signing-key' exists"
  else
    log_fail "Secret 'oidc-signing-key' not found"
  fi

  # Check workload identity mapping
  if kubectl get configmap -n default workload-identity-mapping &>/dev/null; then
    log_success "ConfigMap 'workload-identity-mapping' exists"
  else
    log_fail "ConfigMap 'workload-identity-mapping' not found"
  fi

  # Check token validation config
  if kubectl get configmap -n default oidc-token-validation-config &>/dev/null; then
    log_success "ConfigMap 'oidc-token-validation-config' exists"
  else
    log_fail "ConfigMap 'oidc-token-validation-config' not found"
  fi
}

# ============================================================================
# Test 6: Logs & Errors
# ============================================================================

test_logs() {
  echo ""
  log_info "=== Test 6: Pod Logs Analysis ==="

  # Get pod logs and check for errors
  local oidc_pod=$(kubectl get pods -n "$OIDC_NAMESPACE" -l app=oidc-issuer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [[ -z "$oidc_pod" ]]; then
    log_fail "Cannot check logs - no pod found"
    return 1
  fi

  # Check for fatal errors
  local error_count=$(kubectl logs -n "$OIDC_NAMESPACE" "$oidc_pod" 2>/dev/null | grep -c "error\|fatal\|panic" || echo "0")
  if [[ "$error_count" -eq 0 ]]; then
    log_success "No critical errors in OIDC issuer logs"
  else
    log_fail "Found $error_count error messages in logs"
    log_warning "Recent logs:"
    kubectl logs -n "$OIDC_NAMESPACE" "$oidc_pod" | tail -20
  fi
}

# ============================================================================
# Test 7: Network Policy
# ============================================================================

test_network_policy() {
  echo ""
  log_info "=== Test 7: Network Policy ==="

  if kubectl get networkpolicy -n "$OIDC_NAMESPACE" oidc-issuer-network-policy &>/dev/null; then
    log_success "NetworkPolicy 'oidc-issuer-network-policy' exists"
  else
    log_warning "NetworkPolicy not found (may be optional)"
  fi
}

# ============================================================================
# Test 8: Prometheus Monitoring
# ============================================================================

test_prometheus_monitoring() {
  echo ""
  log_info "=== Test 8: Prometheus Monitoring ==="

  if kubectl get servicemonitor -n "$OIDC_NAMESPACE" oidc-issuer-monitor &>/dev/null; then
    log_success "ServiceMonitor 'oidc-issuer-monitor' exists"
  else
    log_fail "ServiceMonitor not found (Prometheus metrics may not be collected)"
  fi
}

# ============================================================================
# Test 9: Caddy Configuration
# ============================================================================

test_caddy_configuration() {
  echo ""
  log_info "=== Test 9: Caddy Reverse Proxy Configuration ==="

  if grep -q "oidc.${APEX_DOMAIN}" "${PROJECT_ROOT}/Caddyfile" 2>/dev/null; then
    log_success "OIDC routing found in Caddyfile"
  else
    log_warning "OIDC routing not found in Caddyfile - may need manual configuration"
  fi

  # Check if Caddy config file exists
  if [[ -f "${PROJECT_ROOT}/config/caddy/oidc-issuer-routing.caddyfile" ]]; then
    log_success "OIDC routing config file exists"
  else
    log_fail "OIDC routing config file not found"
  fi
}

# ============================================================================
# Test 10: High Availability
# ============================================================================

test_high_availability() {
  echo ""
  log_info "=== Test 10: High Availability Configuration ==="

  # Check HPA
  if kubectl get hpa -n "$OIDC_NAMESPACE" oidc-issuer-hpa &>/dev/null; then
    log_success "HorizontalPodAutoscaler 'oidc-issuer-hpa' exists"
  else
    log_fail "HPA not found (auto-scaling disabled)"
  fi

  # Check PDB
  if kubectl get pdb -n "$OIDC_NAMESPACE" oidc-issuer-pdb &>/dev/null; then
    log_success "PodDisruptionBudget 'oidc-issuer-pdb' exists"
  else
    log_fail "PDB not found (disruption protection disabled)"
  fi

  # Check pod anti-affinity (optional but good practice)
  local pod_spec=$(kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer -o jsonpath='{.spec.template.spec.affinity}')
  if [[ "$pod_spec" == *"podAntiAffinity"* ]]; then
    log_success "Pod anti-affinity configured"
  else
    log_warning "Pod anti-affinity not configured (pods may be on same node)"
  fi
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║      Phase 2.1: OIDC Issuer Health Check Summary              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Test Results:"
  echo "  Passed: ${GREEN}${TEST_PASSED}${NC}"
  echo "  Failed: ${RED}${TEST_FAILED}${NC}"
  echo ""

  if [[ "$TEST_FAILED" -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed! OIDC issuer is healthy and ready for production${NC}"
    return 0
  else
    echo -e "${RED}❌ Some tests failed. Please review above and address issues.${NC}"
    return 1
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 2.1: OIDC Issuer Health Check & Validation Suite       ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  test_k8s_deployment_health
  test_oidc_endpoints
  test_service_accounts
  test_rbac_configuration
  test_configmaps_and_secrets
  test_logs
  test_network_policy
  test_prometheus_monitoring
  test_caddy_configuration
  test_high_availability

  print_summary
}

main "$@"

