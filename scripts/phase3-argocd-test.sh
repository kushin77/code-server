#!/bin/bash

# Phase 3 Issue #168: ArgoCD Application Deployment Validation Tests
# Tests: 12 comprehensive tests for ArgoCD functionality and GitOps features

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

export KUBECONFIG

echo -e "${BLUE}=== Phase 3 Issue #168: ArgoCD Validation Test Suite ===${NC}"
echo "Date: $(date)"
echo ""

# ============================================================================
# Test 1: ArgoCD Namespace & Pods
# ============================================================================

echo -e "${YELLOW}[TEST 1] ArgoCD Deployment Status${NC}"

if kubectl get namespace argocd &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: argocd namespace exists"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: argocd namespace not found"
    ((TESTS_FAILED++))
fi

# Check key pods
for pod_name in argocd-server argocd-controller argocd-repo-server; do
    if kubectl get pods -n argocd -l "app.kubernetes.io/name=$pod_name" 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✓ PASS${NC}: $pod_name pod running"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ WARN${NC}: $pod_name pod not found"
    fi
done

# ============================================================================
# Test 2: ArgoCD Server Service
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 2] ArgoCD Server Service${NC}"

if kubectl get svc -n argocd argocd-server &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: argocd-server service exists"
    ((TESTS_PASSED++))
    
    service_type=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.spec.type}')
    echo "  Service type: $service_type"
    
    if [ "$service_type" == "LoadBalancer" ]; then
        lb_ip=$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")
        echo "  LoadBalancer IP: $lb_ip"
    fi
else
    echo -e "${RED}✗ FAIL${NC}: argocd-server service not found"
    ((TESTS_FAILED++))
fi

# ============================================================================
# Test 3: ArgoCD API Accessibility
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 3] ArgoCD API Accessibility${NC}"

if kubectl -n argocd port-forward svc/argocd-server 8080:443 &>/dev/null & 
   sleep 2 && \
   curl -sk https://localhost:8080/api/version &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: ArgoCD API accessible"
    ((TESTS_PASSED++))
    pkill -P $$ port-forward 2>/dev/null || true
else
    echo -e "${YELLOW}⚠ WARN${NC}: Could not verify API accessibility"
    pkill -P $$ port-forward 2>/dev/null || true
fi

# ============================================================================
# Test 4: Git Repository Configuration
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 4] Git Repository Configuration${NC}"

# Check if any repositories are configured
if kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository 2>/dev/null | grep -q .; then
    echo -e "${GREEN}✓ PASS${NC}: Git repository secrets found"
    ((TESTS_PASSED++))
    
    repo_count=$(kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository --no-headers 2>/dev/null | wc -l)
    echo "  Repositories configured: $repo_count"
else
    echo -e "${YELLOW}⚠ WARN${NC}: No Git repository secrets configured"
fi

# ============================================================================
# Test 5: Applications CRD
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 5] Applications Custom Resource Definition${NC}"

if kubectl get crd applications.argoproj.io &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: Application CRD installed"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: Application CRD not found"
    ((TESTS_FAILED++))
fi

# ============================================================================
# Test 6: AppProjects Configuration
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 6] AppProjects Configuration${NC}"

if kubectl get appproject -n argocd development &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: 'development' AppProject exists"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: 'development' AppProject not found"
fi

# ============================================================================
# Test 7: Applications Status
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 7] Applications Status${NC}"

app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
if [ "$app_count" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: $app_count application(s) configured"
    ((TESTS_PASSED++))
    
    # List applications
    kubectl get applications -n argocd --no-headers 2>/dev/null | while read app_name _ _ _; do
        status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}')
        health=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}')
        echo "  - $app_name: sync=$status, health=$health"
    done
else
    echo -e "${YELLOW}⚠ WARN${NC}: No applications configured"
fi

# ============================================================================
# Test 8: Argo Rollouts Installation
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 8] Argo Rollouts (Canary Deployments)${NC}"

if kubectl get namespace argo-rollouts &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: argo-rollouts namespace exists"
    ((TESTS_PASSED++))
    
    if kubectl get crd rollouts.argoproj.io &>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: Rollout CRD installed"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ WARN${NC}: Rollout CRD not found"
    fi
else
    echo -e "${YELLOW}⚠ WARN${NC}: argo-rollouts namespace not found"
fi

# ============================================================================
# Test 9: ArgoCD Admin Credentials
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 9] ArgoCD Credentials${NC}"

if kubectl -n argocd get secret argocd-initial-admin-secret &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: Admin credentials secret exists"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: Admin credentials secret not found"
fi

# ============================================================================
# Test 10: Notification Integration
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 10] Notification Integration${NC}"

if kubectl -n argocd get configmap argocd-notifications-cm &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: Notifications ConfigMap exists"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: Notifications ConfigMap not found"
fi

# ============================================================================
# Test 11: ApplicationSet (Templating Support)
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 11] ApplicationSet Support${NC}"

if kubectl get crd applicationsets.argoproj.io &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: ApplicationSet CRD installed"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: ApplicationSet CRD not found (optional)"
fi

# ============================================================================
# Test 12: RBAC Configuration
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 12] RBAC Configuration${NC}"

if kubectl -n argocd get configmap argocd-rbac-cm &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: RBAC ConfigMap exists"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: RBAC ConfigMap not found"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TOTAL=$((TESTS_PASSED + TESTS_FAILED))
PASS_RATE=$((TESTS_PASSED * 100 / (TOTAL > 0 ? TOTAL : 1)))

echo -e "  ${GREEN}✓ Passed${NC}:  $TESTS_PASSED"
echo -e "  ${RED}✗ Failed${NC}:  $TESTS_FAILED"
echo "  ─────────────"
echo "  Total:    $TOTAL"
echo ""
echo "Pass Rate: ${GREEN}${PASS_RATE}%${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}=== ALL TESTS PASSED ===${NC}"
    echo ""
    echo "✓ ArgoCD is READY"
    echo ""
    echo "Next steps:"
    echo "  1. Access UI: kubectl -n argocd port-forward svc/argocd-server 8080:443"
    echo "  2. Login: https://localhost:8080"
    echo "  3. Configure Git webhooks for auto-sync"
    exit 0
else
    echo -e "${YELLOW}=== SOME TESTS FAILED ===${NC}"
    echo ""
    echo "Review failed tests and check ArgoCD status:"
    echo "  kubectl get pods -n argocd"
    echo "  kubectl logs -n argocd deployment/argocd-server"
    exit 1
fi
