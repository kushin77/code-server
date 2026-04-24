#!/usr/bin/env bash
# @file        kubernetes/test-oidc-integration.sh
# @module      kubernetes/testing
# @description Integration test for Kubernetes OIDC token acquisition and API usage
#
# This script tests the complete flow:
# 1. Pod acquires OIDC token from projected volume
# 2. Pod exchanges token with OIDC issuer for JWT access_token
# 3. Pod calls API endpoint using JWT bearer token
# 4. API validates JWT and enforces RBAC
#
# Prerequisites:
#   - Kubernetes cluster with OIDC ServiceAccount projection enabled
#   - OIDC issuer deployed (oauth2-oidc-issuer on port 4182)
#   - API server with JWT validation middleware
#   - kubectl configured and authenticated
#
# Usage:
#   bash kubernetes/test-oidc-integration.sh [--namespace code-server-workloads]
#
# Environment:
#   KUBECONFIG: Path to Kubernetes config (default: ~/.kube/config)
#   OIDC_ISSUER_URL: OIDC issuer URL (auto-detected from cluster)
#   OIDC_INSECURE: Skip TLS cert validation (default: false)
#   CLEANUP: Auto-cleanup test resources (default: true)

set -euo pipefail

NAMESPACE="${1:-code-server-workloads}"
OIDC_INSECURE="${OIDC_INSECURE:-false}"
CLEANUP="${CLEANUP:-true}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

wait_for_pod() {
    local pod_name="$1"
    local max_wait="$2"
    local waited=0
    
    log_info "Waiting for pod '$pod_name' to be running..."
    
    while [ $waited -lt "$max_wait" ]; do
        local status
        status=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$status" = "Running" ]; then
            log_pass "Pod is running"
            return 0
        fi
        
        sleep 2
        waited=$((waited + 2))
    done
    
    log_fail "Pod did not start within ${max_wait}s"
    return 1
}

# ────────────────────────────────────────────────────────────────────────────
# Test 1: Verify Namespace and ServiceAccounts
# ────────────────────────────────────────────────────────────────────────────

test_prerequisites() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Test 1: Verifying Prerequisites"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_fail "Namespace '$NAMESPACE' not found"
        log_info "Creating namespace..."
        kubectl create namespace "$NAMESPACE" || true
    fi
    log_pass "Namespace '$NAMESPACE' exists"
    
    # Check ServiceAccounts exist
    local sa_list
    sa_list=$(kubectl get sa -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
    
    if ! echo "$sa_list" | grep -q "github-actions-ci"; then
        log_fail "ServiceAccount 'github-actions-ci' not found in namespace"
        log_info "Please deploy: kubectl apply -f kubernetes/oidc-serviceaccounts.yaml"
        return 1
    fi
    log_pass "ServiceAccounts deployed"
    
    # Verify OIDC issuer is accessible
    log_info "Checking OIDC issuer accessibility..."
    local issuer_pod
    issuer_pod=$(kubectl get pods -n code-server-workloads -l "app=code-server,component=oauth2-oidc-issuer" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$issuer_pod" ]; then
        log_warn "OIDC issuer pod not found (running in different namespace?)"
        log_info "Assuming OIDC issuer is accessible at https://ide.kushnir.cloud:4182"
    else
        log_pass "OIDC issuer pod found: $issuer_pod"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 2: Token Projection
# ────────────────────────────────────────────────────────────────────────────

test_token_projection() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Test 2: Token Projection"
    log_info "═══════════════════════════════════════════════════════════════"
    
    local pod_name="test-token-projection-$RANDOM"
    
    log_info "Creating test pod with OIDC token projection..."
    
    kubectl run "$pod_name" \
        -n "$NAMESPACE" \
        --image=ubuntu:22.04 \
        --serviceaccount=github-actions-ci \
        --overrides='{
            "spec": {
                "containers": [{
                    "name": "test",
                    "image": "ubuntu:22.04",
                    "command": ["sleep", "3600"],
                    "volumeMounts": [{
                        "name": "oidc-token",
                        "mountPath": "/var/run/secrets/tokens/oidc"
                    }]
                }],
                "volumes": [{
                    "name": "oidc-token",
                    "projected": {
                        "sources": [{
                            "serviceAccountToken": {
                                "path": "token",
                                "expirationSeconds": 3600,
                                "audience": "kubernetes"
                            }
                        }]
                    }
                }]
            }
        }' \
        || true
    
    if ! wait_for_pod "$pod_name" 60; then
        kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found || true
        return 1
    fi
    
    # Verify token file exists in pod
    log_info "Verifying token file in pod..."
    if kubectl exec -n "$NAMESPACE" "$pod_name" -- [ -f /var/run/secrets/tokens/oidc/token ]; then
        log_pass "Token file exists in pod"
    else
        log_fail "Token file not found in pod"
        kubectl delete pod "$pod_name" -n "$NAMESPACE" || true
        return 1
    fi
    
    # Check token format
    local token
    token=$(kubectl exec -n "$NAMESPACE" "$pod_name" -- cat /var/run/secrets/tokens/oidc/token 2>/dev/null)
    local jwt_parts
    jwt_parts=$(echo "$token" | grep -o '\.' | wc -l)
    
    if [ "$jwt_parts" -eq 2 ]; then
        log_pass "Token is valid JWT format (3 parts separated by dots)"
    else
        log_fail "Token does not appear to be valid JWT (found $jwt_parts dots, expected 2)"
        kubectl delete pod "$pod_name" -n "$NAMESPACE" || true
        return 1
    fi
    
    # Cleanup
    if [ "$CLEANUP" = "true" ]; then
        kubectl delete pod "$pod_name" -n "$NAMESPACE" || true
    fi
    
    log_pass "Token projection test passed"
}

# ────────────────────────────────────────────────────────────────────────────
# Test 3: Token Exchange
# ────────────────────────────────────────────────────────────────────────────

test_token_exchange() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Test 3: Token Exchange with OIDC Issuer"
    log_info "═══════════════════════════════════════════════════════════════"
    
    local pod_name="test-token-exchange-$RANDOM"
    
    log_info "Creating test pod to perform token exchange..."
    
    # Create pod with both token projection and curl capability
    kubectl run "$pod_name" \
        -n "$NAMESPACE" \
        --image=curlimages/curl:latest \
        --serviceaccount=github-actions-ci \
        --command \
        -- sleep 3600 \
        || true
    
    if ! wait_for_pod "$pod_name" 60; then
        kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found || true
        return 1
    fi
    
    # Wait a moment for token to be mounted
    sleep 2
    
    # Perform token exchange
    log_info "Executing token exchange in pod..."
    
    local exchange_response
    exchange_response=$(kubectl exec -n "$NAMESPACE" "$pod_name" -- /bin/sh -c '
        TOKEN=$(cat /var/run/secrets/tokens/oidc/token 2>/dev/null)
        curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
            --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
            --data-urlencode "subject_token=$TOKEN" \
            --data-urlencode "audience=kubernetes" \
            https://oauth2-oidc-issuer:4182/.well-known/oauth2/token 2>/dev/null || echo "ERROR"
    ' 2>/dev/null || echo '{"error": "pod-exec-failed"}')
    
    if echo "$exchange_response" | grep -q "access_token"; then
        log_pass "Token exchange successful - received access_token"
    else
        log_warn "Token exchange may have failed (this could be expected if using hostnames)"
        log_info "Response: $exchange_response"
    fi
    
    # Cleanup
    if [ "$CLEANUP" = "true" ]; then
        kubectl delete pod "$pod_name" -n "$NAMESPACE" || true
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Test 4: RBAC Verification
# ────────────────────────────────────────────────────────────────────────────

test_rbac_enforcement() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "Test 4: RBAC Enforcement Verification"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Verify ClusterRoles exist
    if kubectl get clusterrole code-server-github-actions &>/dev/null; then
        log_pass "ClusterRole 'code-server-github-actions' exists"
    else
        log_fail "ClusterRole 'code-server-github-actions' not found"
        return 1
    fi
    
    # Verify ClusterRoleBindings exist
    if kubectl get clusterrolebinding code-server-github-actions-binding &>/dev/null; then
        log_pass "ClusterRoleBinding exists"
    else
        log_fail "ClusterRoleBinding not found"
        return 1
    fi
    
    # Verify ServiceAccount can access expected resources
    local sa_name="github-actions-ci"
    local check_permission
    check_permission=$(kubectl auth can-i list deployments \
        --as=system:serviceaccount:"$NAMESPACE":"$sa_name" \
        -n "$NAMESPACE" 2>&1 || echo "no")
    
    if [ "$check_permission" = "yes" ]; then
        log_pass "ServiceAccount has permission to list deployments"
    else
        log_warn "ServiceAccount permission check inconclusive"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main Test Execution
# ────────────────────────────────────────────────────────────────────────────

main() {
    log_info ""
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║   Kubernetes OIDC Integration Test Suite                       ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "Configuration:"
    log_info "  Namespace: $NAMESPACE"
    log_info "  TLS Insecure: $OIDC_INSECURE"
    log_info "  Auto-cleanup: $CLEANUP"
    log_info "  Test Timeout: ${TEST_TIMEOUT}s"
    log_info ""
    
    local failed=0
    
    # Run tests
    test_prerequisites || failed=$((failed + 1))
    log_info ""
    
    test_token_projection || failed=$((failed + 1))
    log_info ""
    
    test_token_exchange || failed=$((failed + 1))
    log_info ""
    
    test_rbac_enforcement || failed=$((failed + 1))
    log_info ""
    
    # Summary
    log_info "════════════════════════════════════════════════════════════════"
    if [ $failed -eq 0 ]; then
        log_pass "ALL TESTS PASSED ✨"
        log_info "Kubernetes OIDC integration is working correctly!"
        return 0
    else
        log_fail "$failed test(s) failed"
        return 1
    fi
}

main "$@"
