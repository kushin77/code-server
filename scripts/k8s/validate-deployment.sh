#!/bin/bash
###############################################################################
# @file        scripts/k8s/validate-deployment.sh
# @module      k8s/validate-deployment
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/k8s/validate-deployment.sh
# @description Validates Kubernetes deployment with comprehensive health checks
# @governance GOV-002: Deployment validation
# @usage ./validate-deployment.sh [namespace]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

NAMESPACE="${1:-code-server-enterprise}"
PASSED=0
WARNINGS=0

check_pass() { echo -e "${GREEN}✓${NC} $1"; PASSED+=1; }
check_fail() { echo -e "${RED}✗${NC} $1"; FAILED+=1; }
check_warn() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS+=1; }

echo -e "${BLUE}=== Kubernetes Deployment Validation ===${NC}"
echo "Namespace: $NAMESPACE"
echo ""

# 1. Namespace checks
echo -e "${BLUE}[1] Namespace Checks${NC}"
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    check_pass "Namespace exists"
else
    check_fail "Namespace not found"
    exit 1
fi

# 2. Pod checks
echo -e "${BLUE}[2] Pod Status${NC}"
PODS=$(kubectl get pods -n "$NAMESPACE" -o json)
TOTAL=$(echo "$PODS" | jq '.items | length')
RUNNING=$(echo "$PODS" | jq '[.items[] | select(.status.phase=="Running")] | length')

if [ "$RUNNING" -eq "$TOTAL" ]; then
    check_pass "All $TOTAL pods running"
else
    check_warn "$RUNNING/$TOTAL pods running"
fi

# 3. Deployment status
echo -e "${BLUE}[3] Deployment Status${NC}"
DEPLOYS=$(kubectl get deployment -n "$NAMESPACE" -o json)
DEPLOY_COUNT=$(echo "$DEPLOYS" | jq '.items | length')

if [ "$DEPLOY_COUNT" -gt 0 ]; then
    check_pass "Found $DEPLOY_COUNT deployments"
    NOT_READY=$(echo "$DEPLOYS" | jq '[.items[] | select(.status.readyReplicas != .spec.replicas)] | length')
    if [ "$NOT_READY" -eq 0 ]; then
        check_pass "All deployments ready"
    else
        check_warn "$NOT_READY deployments not ready"
    fi
fi

# 4. Service checks
echo -e "${BLUE}[4] Services${NC}"
SVCS=$(kubectl get svc -n "$NAMESPACE" -o json)
SVC_COUNT=$(echo "$SVCS" | jq '.items | length')
[ "$SVC_COUNT" -gt 0 ] && check_pass "Found $SVC_COUNT services" || check_warn "No services"

# 5. Istio resources
echo -e "${BLUE}[5] Istio Resources${NC}"
VS=$(kubectl get virtualservice -n "$NAMESPACE" 2>/dev/null | wc -l)
[ "$VS" -gt 1 ] && check_pass "VirtualServices configured" || check_warn "No VirtualServices"

# 6. HPA status
echo -e "${BLUE}[6] Autoscaling${NC}"
HPAS=$(kubectl get hpa -n "$NAMESPACE" 2>/dev/null | wc -l)
[ "$HPAS" -gt 1 ] && check_pass "HPAs configured" || check_warn "No HPAs"

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

[ "$FAILED" -eq 0 ] && echo -e "${GREEN}✓ PASSED${NC}" && exit 0 || (echo -e "${RED}✗ FAILED${NC}" && exit 1)
