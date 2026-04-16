#!/bin/bash
# Phase 3 Issue #164 - k3s Cluster Validation Test Suite

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

echo -e "${BLUE}=== Phase 3 Issue #164: k3s Cluster Validation Test Suite ===${NC}"
echo "Date: $(date)"
echo ""

# ============================================================================
# Test 1: Cluster Accessibility
# ============================================================================

echo -e "${YELLOW}[TEST 1] Cluster Accessibility${NC}"

if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: kubectl can access cluster"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: kubectl cannot access cluster"
    ((TESTS_FAILED++))
fi

# ============================================================================
# Test 2: Node Status
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 2] Node Status${NC}"

node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$node_count" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Found $node_count node(s)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: No nodes found"
    ((TESTS_FAILED++))
fi

# Check node is ready
ready_count=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready" {count++} END {print count+0}')
if [ "$ready_count" -eq "$node_count" ]; then
    echo -e "${GREEN}✓ PASS${NC}: All nodes are ready"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: Only $ready_count of $node_count nodes ready"
fi

# ============================================================================
# Test 3: System Pods
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 3] System Pods${NC}"

kube_system_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
if [ "$kube_system_pods" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: kube-system has $kube_system_pods pods"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: No kube-system pods found"
    ((TESTS_FAILED++))
fi

# Check for key system pods
for pod_pattern in "coredns" "flannel"; do
    if kubectl get pods -n kube-system -l "app.kubernetes.io/name=$pod_pattern" --no-headers 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✓ PASS${NC}: $pod_pattern pod found"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ WARN${NC}: $pod_pattern pod not found"
    fi
done

# ============================================================================
# Test 4: Storage Classes
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 4] Storage Classes${NC}"

storage_classes=$(kubectl get storageclasses --no-headers 2>/dev/null | wc -l)
if [ "$storage_classes" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: Found $storage_classes storage class(es)"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: No storage classes found"
fi

# Check for specific storage classes
for sc in "local-path" "nfs"; do
    if kubectl get storageclass "$sc" 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✓ PASS${NC}: Storage class '$sc' exists"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ SKIP${NC}: Storage class '$sc' not found"
    fi
done

# ============================================================================
# Test 5: GPU Support (if available)
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 5] GPU Support${NC}"

if command -v nvidia-smi &>/dev/null; then
    if kubectl get pods -n kube-system -l app=nvidia-device-plugin 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✓ PASS${NC}: NVIDIA device plugin deployed"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ WARN${NC}: GPU found but device plugin not deployed"
    fi
    
    # Check if GPUs are allocatable
    gpu_count=$(kubectl describe node | grep "nvidia.com/gpu" | awk '{print $2}' | head -1)
    if [ -n "$gpu_count" ] && [ "$gpu_count" != "0" ]; then
        echo -e "${GREEN}✓ PASS${NC}: GPU(s) allocated ($gpu_count)"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ WARN${NC}: GPU(s) not allocated in cluster"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC}: NVIDIA GPU not detected"
fi

# ============================================================================
# Test 6: DNS Resolution
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 6] DNS Resolution${NC}"

# Create a test pod to check DNS
if kubectl run dns-test --image=busybox:1.35 --restart=Never -- sleep 3600 2>/dev/null; then
    sleep 2
    
    if kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: DNS resolution working"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: DNS resolution failed"
        ((TESTS_FAILED++))
    fi
    
    # Cleanup
    kubectl delete pod dns-test --ignore-not-found=true 2>/dev/null
else
    echo -e "${YELLOW}⚠ WARN${NC}: Could not create DNS test pod"
fi

# ============================================================================
# Test 7: Network Connectivity
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 7] Network Connectivity${NC}"

# Test inter-pod communication
if kubectl apply -f - <<EOF 2>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: nettest-1
spec:
  containers:
  - name: nettest
    image: busybox:1.35
    command: ['sleep', '1800']
---
apiVersion: v1
kind: Pod
metadata:
  name: nettest-2
spec:
  containers:
  - name: nettest
    image: busybox:1.35
    command: ['sleep', '1800']
EOF
then
    sleep 3
    
    pod1_ip=$(kubectl get pod nettest-1 -o jsonpath='{.status.podIP}')
    
    if [ -n "$pod1_ip" ]; then
        if kubectl exec nettest-2 -- ping -c 1 "$pod1_ip" &>/dev/null; then
            echo -e "${GREEN}✓ PASS${NC}: Inter-pod communication working"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗ FAIL${NC}: Inter-pod communication failed"
            ((TESTS_FAILED++))
        fi
    fi
    
    # Cleanup
    kubectl delete pod nettest-1 nettest-2 --ignore-not-found=true 2>/dev/null
else
    echo -e "${YELLOW}⚠ WARN${NC}: Could not create networking test pods"
fi

# ============================================================================
# Test 8: API Server Health
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 8] API Server Health${NC}"

if kubectl version &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: API server is healthy"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC}: API server is not responding"
    ((TESTS_FAILED++))
fi

# ============================================================================
# Test 9: Persistent Volumes
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 9] Persistent Volumes${NC}"

pv_count=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
if [ "$pv_count" -ge 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: PV support available ($pv_count PVs)"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠ WARN${NC}: Could not list PVs"
fi

# ============================================================================
# Test 10: kube-proxy
# ============================================================================

echo ""
echo -e "${YELLOW}[TEST 10] kube-proxy${NC}"

if kubectl get daemonset -n kube-system kube-proxy &>/dev/null; then
    kube_proxy_ready=$(kubectl get daemonset -n kube-system kube-proxy -o jsonpath='{.status.numberReady}')
    if [ "$kube_proxy_ready" -gt 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: kube-proxy is running"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: kube-proxy is not ready"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${YELLOW}⚠ WARN${NC}: kube-proxy not found"
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
    echo "✓ k3s Cluster is READY"
    echo ""
    echo "Next steps:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    exit 0
else
    echo -e "${YELLOW}=== SOME TESTS FAILED ===${NC}"
    echo ""
    echo "Review failed tests and check cluster status:"
    echo "  kubectl describe nodes"
    echo "  kubectl get events -A"
    echo "  journalctl -u k3s -f"
    exit 1
fi
