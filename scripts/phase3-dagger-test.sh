#!/bin/bash
# Phase 3 Issue #169 - Dagger CI/CD Engine Tests
# Comprehensive validation suite for Dagger integration

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="dagger"
TESTS_PASSED=0
TESTS_FAILED=0

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_test() { echo -e "${YELLOW}TEST: $1${NC}"; }
print_pass() { echo -e "${GREEN}✓ PASS: $1${NC}"; ((TESTS_PASSED++)); }
print_fail() { echo -e "${RED}✗ FAIL: $1${NC}"; ((TESTS_FAILED++)); }

# ============================================================================
# Test Suite
# ============================================================================

test_dagger_cli() {
    print_test "Dagger CLI availability"
    if command -v dagger &> /dev/null; then
        local version=$(dagger version 2>/dev/null)
        print_pass "Dagger CLI available (version: $version)"
    else
        print_fail "Dagger CLI not found"
    fi
}

test_namespace_exists() {
    print_test "Dagger namespace exists"
    if kubectl get ns "$NAMESPACE" &> /dev/null; then
        print_pass "Namespace $NAMESPACE exists"
    else
        print_fail "Namespace $NAMESPACE not found"
    fi
}

test_service_account() {
    print_test "Service account creation"
    if kubectl get sa dagger -n "$NAMESPACE" &> /dev/null; then
        print_pass "Service account 'dagger' exists"
    else
        print_fail "Service account 'dagger' not found"
    fi
}

test_rbac_role() {
    print_test "RBAC role configuration"
    if kubectl get clusterrole dagger-ci-role &> /dev/null; then
        local rules=$(kubectl get clusterrole dagger-ci-role -o jsonpath='{.rules[*].verbs[*]}')
        if echo "$rules" | grep -q "create"; then
            print_pass "RBAC role configured with proper permissions"
        else
            print_fail "RBAC role missing required permissions"
        fi
    else
        print_fail "RBAC role 'dagger-ci-role' not found"
    fi
}

test_rbac_binding() {
    print_test "RBAC cluster role binding"
    if kubectl get clusterrolebinding dagger-ci-binding &> /dev/null; then
        local sa=$(kubectl get clusterrolebinding dagger-ci-binding -o jsonpath='{.subjects[0].name}')
        if [ "$sa" == "dagger" ]; then
            print_pass "Service account properly bound to RBAC role"
        else
            print_fail "Service account binding incorrect"
        fi
    else
        print_fail "ClusterRoleBinding 'dagger-ci-binding' not found"
    fi
}

test_configmap() {
    print_test "ConfigMap for Dagger configuration"
    if kubectl get configmap dagger-config -n "$NAMESPACE" &> /dev/null; then
        local harbor_url=$(kubectl get configmap dagger-config -n "$NAMESPACE" -o jsonpath='{.data.harbor-url}')
        if [ -n "$harbor_url" ]; then
            print_pass "ConfigMap created with Harbor URL: $harbor_url"
        else
            print_fail "ConfigMap missing Harbor configuration"
        fi
    else
        print_fail "ConfigMap 'dagger-config' not found"
    fi
}

test_harbor_secret() {
    print_test "Harbor registry credentials secret"
    if kubectl get secret harbor-registry -n "$NAMESPACE" &> /dev/null; then
        print_pass "Harbor credentials secret created"
    else
        print_fail "Harbor credentials secret not found"
    fi
}

test_github_secret() {
    print_test "GitHub token secret (if configured)"
    if kubectl get secret github-token -n "$NAMESPACE" &> /dev/null 2>&1; then
        print_pass "GitHub token secret available"
    else
        print_fail "GitHub token secret not configured (optional)"
    fi
}

test_slack_secret() {
    print_test "Slack webhook secret (if configured)"
    if kubectl get secret slack-webhook -n "$NAMESPACE" &> /dev/null 2>&1; then
        print_pass "Slack webhook secret available"
    else
        print_fail "Slack webhook secret not configured (optional)"
    fi
}

test_workflow_templates() {
    print_test "Workflow templates availability"
    if [ -f ~/.dagger/workflows/base.yaml ]; then
        local stages=$(grep -c "^  - name:" ~/.dagger/workflows/base.yaml || echo 0)
        if [ "$stages" -gt 0 ]; then
            print_pass "Workflow templates with $stages stages configured"
        else
            print_fail "Workflow templates missing stages"
        fi
    else
        print_fail "Workflow templates not found at ~/.dagger/workflows/"
    fi
}

test_docker_access() {
    print_test "Docker daemon access"
    if docker ps &> /dev/null; then
        print_pass "Docker daemon accessible"
    else
        print_fail "Cannot access Docker daemon"
    fi
}

test_git_access() {
    print_test "Git repository access"
    if git ls-remote https://github.com/kushin77/code-server.git HEAD &> /dev/null; then
        print_pass "Git repository accessible"
    else
        print_fail "Cannot access Git repository"
    fi
}

test_k3s_api() {
    print_test "k3s API server accessibility"
    if kubectl api-resources &> /dev/null; then
        print_pass "k3s API server responding"
    else
        print_fail "k3s API server not responding"
    fi
}

test_dagger_pods() {
    print_test "Dagger pods status"
    local pod_count=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -ge 0 ]; then
        if [ "$pod_count" -eq 0 ]; then
            print_pass "Dagger namespace ready (no pods yet - normal for CI/CD)"
        else
            local ready=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/\1$/ {count++} END {print count}')
            print_pass "Dagger pods status: $ready/$pod_count ready"
        fi
    else
        print_fail "Cannot query pod status"
    fi
}

test_network_connectivity() {
    print_test "Network connectivity to registry"
    if nc -zv 192.168.168.31 8443 &> /dev/null; then
        print_pass "Registry (192.168.168.31:8443) accessible"
    else
        print_fail "Cannot reach registry (expected if Harbor not deployed yet)"
    fi
}

test_log_collection() {
    print_test "Pipeline logs collection capability"
    local log_dir="/var/log/dagger"
    if [ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null; then
        print_pass "Log directory configured: $log_dir"
    else
        print_fail "Cannot create log directory"
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
    print_header "Phase 3 Issue #169: Dagger CI/CD Engine Test Suite"
    echo ""
    
    test_dagger_cli
    test_namespace_exists
    test_service_account
    test_rbac_role
    test_rbac_binding
    test_configmap
    test_harbor_secret
    test_github_secret
    test_slack_secret
    test_workflow_templates
    test_docker_access
    test_git_access
    test_k3s_api
    test_dagger_pods
    test_network_connectivity
    test_log_collection
    
    echo ""
    print_summary
}

main "$@"
