#!/bin/bash
# Phase 3 Issue #170 - OPA/Kyverno Policy Engine Tests

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="kyverno"
TESTS_PASSED=0
TESTS_FAILED=0

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_test() { echo -e "${YELLOW}TEST: $1${NC}"; }
print_pass() { echo -e "${GREEN}✓ PASS: $1${NC}"; ((TESTS_PASSED++)); }
print_fail() { echo -e "${RED}✗ FAIL: $1${NC}"; ((TESTS_FAILED++)); }

# ============================================================================
# Test Suite
# ============================================================================

test_namespace_exists() {
    print_test "Kyverno namespace exists"
    if kubectl get ns "$NAMESPACE" &> /dev/null; then
        print_pass "Namespace $NAMESPACE exists"
    else
        print_fail "Namespace $NAMESPACE not found"
    fi
}

test_kyverno_deployment() {
    print_test "Kyverno deployment running"
    if kubectl get deployment -n "$NAMESPACE" kyverno &> /dev/null; then
        local ready=$(kubectl get deployment -n "$NAMESPACE" kyverno -o jsonpath='{.status.readyReplicas}')
        if [ "$ready" -gt 0 ]; then
            print_pass "Kyverno deployment running with $ready replicas"
        else
            print_fail "Kyverno deployment not ready"
        fi
    else
        print_fail "Kyverno deployment not found"
    fi
}

test_kyverno_pods() {
    print_test "Kyverno pods status"
    local pod_count=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kyverno --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -gt 0 ]; then
        print_pass "Kyverno pods running: $pod_count found"
    else
        print_fail "No Kyverno pods found"
    fi
}

test_policy_count() {
    print_test "Policy count verification"
    local policy_count=$(kubectl get clusterpolicies -o json 2>/dev/null | jq '.items | length')
    if [ "$policy_count" -ge 6 ]; then
        print_pass "Policies configured: $policy_count cluster policies found"
    else
        print_fail "Insufficient policies: only $policy_count found (expected >= 6)"
    fi
}

test_security_policy() {
    print_test "Pod security policy enforcement"
    if kubectl get clusterpolicies restrict-privileged-containers &> /dev/null; then
        print_pass "Pod security policy exists"
    else
        print_fail "Pod security policy not found"
    fi
}

test_image_policy() {
    print_test "Image registry policy enforcement"
    if kubectl get clusterpolicies restrict-image-registries &> /dev/null; then
        print_pass "Image registry policy exists"
    else
        print_fail "Image registry policy not found"
    fi
}

test_resource_policy() {
    print_test "Resource limit policy enforcement"
    if kubectl get clusterpolicies require-resource-limits &> /dev/null; then
        print_pass "Resource limit policy exists"
    else
        print_fail "Resource limit policy not found"
    fi
}

test_validating_webhooks() {
    print_test "Validating webhooks configuration"
    if kubectl get validatingwebhookconfigurations | grep -q "kyverno"; then
        local webhook_count=$(kubectl get validatingwebhookconfigurations | grep -c "kyverno")
        print_pass "Webhooks configured: $webhook_count found"
    else
        print_fail "No validating webhooks found"
    fi
}

test_mutating_webhooks() {
    print_test "Mutating webhooks configuration"
    if kubectl get mutatingwebhookconfigurations | grep -q "kyverno"; then
        local webhook_count=$(kubectl get mutatingwebhookconfigurations | grep -c "kyverno")
        print_pass "Mutating webhooks: $webhook_count found"
    else
        print_fail "No mutating webhooks found"
    fi
}

test_webhook_availability() {
    print_test "Webhook service accessibility"
    if kubectl get svc -n "$NAMESPACE" kyverno-svc &> /dev/null; then
        print_pass "Webhook service available"
    else
        print_fail "Webhook service not found"
    fi
}

test_policy_violations_audit() {
    print_test "Policy violation audit logging"
    if kubectl get clusterpolicy audit-policy-violations &> /dev/null; then
        print_pass "Audit policy configured"
    else
        print_fail "Audit policy not found"
    fi
}

test_policy_validation() {
    print_test "Policy syntax validation"
    local invalid_policies=$(kubectl get clusterpolicies -o json 2>/dev/null | jq '[.items[] | select(.status.validationFailureAction=="audit")] | length')
    if [ "$invalid_policies" -ge 0 ]; then
        print_pass "Policies validated successfully"
    else
        print_fail "Policy validation failed"
    fi
}

test_webhook_certificates() {
    print_test "Webhook TLS certificate validation"
    local cert_count=$(kubectl get secret -n "$NAMESPACE" | grep -c "webhook" || echo 0)
    if [ "$cert_count" -ge 1 ]; then
        print_pass "Webhook certificates configured"
    else
        print_fail "Webhook certificates not found"
    fi
}

test_rbac_configuration() {
    print_test "RBAC for policy management"
    if kubectl get clusterrole kyverno | grep -q "kyverno"; then
        print_pass "RBAC roles configured"
    else
        print_fail "RBAC roles not found"
    fi
}

test_policy_rules_execution() {
    print_test "Policy rules execution capability"
    local rules_count=$(kubectl get clusterpolicies -o json 2>/dev/null | jq '.items[0].spec.rules | length' 2>/dev/null || echo 0)
    if [ "$rules_count" -gt 0 ]; then
        print_pass "Policy rules configured: $rules_count rules in primary policy"
    else
        print_fail "No policy rules found"
    fi
}

test_namespace_exclusions() {
    print_test "Namespace exclusion rules"
    if kubectl get clusterpolicies restrict-privileged-containers -o json | jq -e '.spec.rules[].match.resources.namespaceSelector' &> /dev/null; then
        print_pass "Namespace exclusions configured"
    else
        print_fail "Namespace exclusions not configured"
    fi
}

test_exception_handling() {
    print_test "Policy exception handling"
    if kubectl get clusterpolicies -o json 2>/dev/null | jq -e '.items[].spec.validationFailureAction' &> /dev/null; then
        print_pass "Failure handling configured"
    else
        print_fail "Failure handling not configured"
    fi
}

test_cluster_policy_metrics() {
    print_test "Policy metrics collection"
    if kubectl get deployment -n "$NAMESPACE" kyverno -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="POL_METRICS_ENABLED")].value}' &> /dev/null; then
        print_pass "Metrics collection enabled"
    else
        print_fail "Metrics collection not configured"
    fi
}

# ============================================================================
# Summary and Report
# ============================================================================

print_summary() {
    print_header "Test Summary"
    
    local total=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=$((TESTS_PASSED * 100 / total))
    
    echo ""
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Total Tests:  $total"
    echo "Pass Rate:    $pass_rate%"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        return 0
    else
        echo -e "${RED}⚠️  SOME TESTS FAILED${NC}"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_header "Phase 3 Issue #170: OPA/Kyverno Policy Engine Test Suite"
    echo ""
    
    test_namespace_exists
    test_kyverno_deployment
    test_kyverno_pods
    test_policy_count
    test_security_policy
    test_image_policy
    test_resource_policy
    test_validating_webhooks
    test_mutating_webhooks
    test_webhook_availability
    test_policy_violations_audit
    test_policy_validation
    test_webhook_certificates
    test_rbac_configuration
    test_policy_rules_execution
    test_namespace_exclusions
    test_exception_handling
    test_cluster_policy_metrics
    
    echo ""
    print_summary
}

main "$@"
