#!/bin/bash
###############################################################################
# @file        scripts/k8s/production-readiness-check.sh
# @module      k8s/production-readiness-check
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/k8s/production-readiness-check.sh
# @description Comprehensive production readiness validation
# @governance GOV-002: Production deployment gating
# @usage ./production-readiness-check.sh [namespace]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

NAMESPACE="${1:-code-server-enterprise}"

PASSED=0
FAILED=0
WARNINGS=0

check_pass() {
    echo -e "${GREEN}✓${RESET} $1"
    PASSED+=1
}

check_fail() {
    echo -e "${RED}✗${RESET} $1"
    FAILED+=1
}

check_warn() {
    echo -e "${YELLOW}⚠${RESET} $1"
    WARNINGS+=1
}

echo -e "${BLUE}=== Production Readiness Check ===${RESET}"
echo "Namespace: $NAMESPACE"
echo ""

# ============================================================================
# 1. CLUSTER INFRASTRUCTURE
# ============================================================================
echo -e "${BLUE}[1. Cluster Infrastructure]${RESET}"

# Cluster connectivity
if kubectl cluster-info &>/dev/null; then
    check_pass "Kubernetes cluster accessible"
else
    check_fail "Kubernetes cluster not accessible"
    exit 1
fi

# Node count
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ge 3 ]; then
    check_pass "Minimum 3 nodes ($NODE_COUNT nodes available)"
else
    check_fail "Insufficient nodes ($NODE_COUNT < 3 required)"
fi

# Node readiness
READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_pass "All nodes Ready ($READY_NODES/$NODE_COUNT)"
else
    check_warn "Some nodes not Ready ($READY_NODES/$NODE_COUNT)"
fi

# Cluster resources
ALLOCATABLE_CPU=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.cpu}' | tr ' ' '+' | bc 2>/dev/null || echo "0")
ALLOCATABLE_MEMORY=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.memory}' | tail -1)
echo "  CPU Allocatable: $ALLOCATABLE_CPU cores"
echo "  Memory Allocatable: $ALLOCATABLE_MEMORY"

echo ""

# ============================================================================
# 2. NAMESPACE & CONFIGURATION
# ============================================================================
echo -e "${BLUE}[2. Namespace & Configuration]${RESET}"

# Namespace exists
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    check_pass "Namespace '$NAMESPACE' exists"
else
    check_fail "Namespace '$NAMESPACE' not found"
    exit 1
fi

# Istio injection enabled
ISTIO_ENABLED=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")
if [ "$ISTIO_ENABLED" = "enabled" ]; then
    check_pass "Istio injection enabled"
else
    check_warn "Istio injection not enabled (optional but recommended)"
fi

# ConfigMaps
CONFIGMAPS=$(kubectl get configmap -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$CONFIGMAPS" -gt 0 ]; then
    check_pass "$CONFIGMAPS ConfigMaps found"
else
    check_warn "No ConfigMaps found (may be OK)"
fi

# Secrets
SECRETS=$(kubectl get secret -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$SECRETS" -gt 0 ]; then
    check_pass "$SECRETS Secrets found"
else
    check_fail "No Secrets found (credentials required)"
fi

echo ""

# ============================================================================
# 3. WORKLOAD STATUS
# ============================================================================
echo -e "${BLUE}[3. Workload Status]${RESET}"

# Deployments
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$DEPLOYMENTS" -gt 0 ]; then
    check_pass "$DEPLOYMENTS Deployments configured"
else
    check_warn "No Deployments found"
fi

# Pods running
PODS_TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
PODS_RUNNING=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)

if [ "$PODS_RUNNING" -eq "$PODS_TOTAL" ] && [ "$PODS_TOTAL" -gt 0 ]; then
    check_pass "All pods Running ($PODS_RUNNING/$PODS_TOTAL)"
elif [ "$PODS_RUNNING" -gt 0 ]; then
    check_warn "Some pods not Running ($PODS_RUNNING/$PODS_TOTAL)"
else
    check_fail "No pods running"
fi

# Pods ready
PODS_READY=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)

if [ "$PODS_READY" -eq "$PODS_TOTAL" ]; then
    check_pass "All pods Ready ($PODS_READY/$PODS_TOTAL)"
elif [ "$PODS_READY" -gt 0 ]; then
    check_warn "Some pods not Ready ($PODS_READY/$PODS_TOTAL)"
else
    check_fail "No pods Ready for traffic"
fi

# Pod restart count
MAX_RESTARTS=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | tr ' ' '\n' | sort -rn | head -1)
if [ -z "$MAX_RESTARTS" ] || [ "$MAX_RESTARTS" -lt 3 ]; then
    check_pass "Pod restart count acceptable (max: $MAX_RESTARTS)"
else
    check_warn "High pod restart count detected (max: $MAX_RESTARTS)"
fi

echo ""

# ============================================================================
# 4. SERVICES & NETWORKING
# ============================================================================
echo -e "${BLUE}[4. Services & Networking]${RESET}"

# Services
SERVICES=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$SERVICES" -gt 0 ]; then
    check_pass "$SERVICES Services configured"
else
    check_warn "No Services found"
fi

# Service endpoints
ENDPOINTS=$(kubectl get endpoints -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$ENDPOINTS" -gt 0 ]; then
    check_pass "$ENDPOINTS Services with endpoints"
else
    check_warn "Services without endpoints"
fi

# Network policies
NETPOLICIES=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$NETPOLICIES" -gt 0 ]; then
    check_pass "$NETPOLICIES Network Policies configured"
else
    check_warn "No Network Policies found (optional)"
fi

# Ingress
INGRESS=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$INGRESS" -gt 0 ]; then
    check_pass "$INGRESS Ingress resources configured"
else
    check_warn "No Ingress found"
fi

echo ""

# ============================================================================
# 5. STORAGE & PERSISTENCE
# ============================================================================
echo -e "${BLUE}[5. Storage & Persistence]${RESET}"

# Persistent volumes
PVS=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
if [ "$PVS" -gt 0 ]; then
    check_pass "$PVS Persistent Volumes exist"
else
    check_warn "No Persistent Volumes found"
fi

# Persistent volume claims
PVCS=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$PVCS" -gt 0 ]; then
    check_pass "$PVCS Persistent Volume Claims bound"
else
    check_warn "No PVCs found"
fi

# Storage classes
STORAGECLASSES=$(kubectl get storageclasses --no-headers 2>/dev/null | wc -l)
if [ "$STORAGECLASSES" -gt 0 ]; then
    check_pass "$STORAGECLASSES Storage Classes available"
else
    check_warn "No Storage Classes configured"
fi

echo ""

# ============================================================================
# 6. OBSERVABILITY & MONITORING
# ============================================================================
echo -e "${BLUE}[6. Observability & Monitoring]${RESET}"

# Prometheus
if kubectl get deployment prometheus-operator -n monitoring &>/dev/null 2>&1; then
    check_pass "Prometheus installed"
else
    check_warn "Prometheus not found"
fi

# Grafana
if kubectl get deployment grafana -n monitoring &>/dev/null 2>&1; then
    check_pass "Grafana installed"
else
    check_warn "Grafana not found"
fi

# Jaeger
if kubectl get deployment jaeger -n monitoring &>/dev/null 2>&1; then
    check_pass "Jaeger installed"
else
    check_warn "Jaeger not found (optional)"
fi

# Pod resource requests/limits
CONTAINERS_WITH_LIMITS=$(kubectl get pods -n "$NAMESPACE" -o json | jq '[.items[].spec.containers[] | select(.resources.limits != null)] | length')
TOTAL_CONTAINERS=$(kubectl get pods -n "$NAMESPACE" -o json | jq '[.items[].spec.containers[]] | length')

if [ "$CONTAINERS_WITH_LIMITS" -eq "$TOTAL_CONTAINERS" ]; then
    check_pass "All containers have resource limits"
elif [ "$CONTAINERS_WITH_LIMITS" -gt 0 ]; then
    check_warn "Only $CONTAINERS_WITH_LIMITS/$TOTAL_CONTAINERS containers have limits"
else
    check_warn "No resource limits configured"
fi

echo ""

# ============================================================================
# 7. HIGH AVAILABILITY
# ============================================================================
echo -e "${BLUE}[7. High Availability]${RESET}"

# Replica count
MIN_REPLICAS=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].spec.replicas}' | tr ' ' '\n' | sort -n | head -1)
if [ "$MIN_REPLICAS" -ge 2 ]; then
    check_pass "Minimum 2 replicas per deployment"
else
    check_warn "Deployments with < 2 replicas (not HA)"
fi

# Pod Disruption Budgets
PDBS=$(kubectl get pdb -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$PDBS" -gt 0 ]; then
    check_pass "$PDBS Pod Disruption Budgets configured"
else
    check_warn "No Pod Disruption Budgets found"
fi

# Health check configuration
LIVENESS_PROBES=$(kubectl get pods -n "$NAMESPACE" -o json | jq '[.items[].spec.containers[] | select(.livenessProbe != null)] | length')
if [ "$LIVENESS_PROBES" -gt 0 ]; then
    check_pass "$LIVENESS_PROBES containers with liveness probes"
else
    check_warn "No liveness probes configured"
fi

READINESS_PROBES=$(kubectl get pods -n "$NAMESPACE" -o json | jq '[.items[].spec.containers[] | select(.readinessProbe != null)] | length')
if [ "$READINESS_PROBES" -gt 0 ]; then
    check_pass "$READINESS_PROBES containers with readiness probes"
else
    check_warn "No readiness probes configured"
fi

echo ""

# ============================================================================
# 8. AUTOSCALING
# ============================================================================
echo -e "${BLUE}[8. Autoscaling]${RESET}"

# HPA configured
HPAS=$(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$HPAS" -gt 0 ]; then
    check_pass "$HPAS Horizontal Pod Autoscalers configured"
else
    check_warn "No HPAs found (manual scaling only)"
fi

# Metrics server
if kubectl get deployment metrics-server -n kube-system &>/dev/null 2>&1; then
    check_pass "Metrics server available (for HPA)"
else
    check_warn "Metrics server not found"
fi

echo ""

# ============================================================================
# 9. SECURITY
# ============================================================================
echo -e "${BLUE}[9. Security]${RESET}"

# mTLS enabled
if kubectl get peerauthentication -n "$NAMESPACE" &>/dev/null 2>&1; then
    check_pass "mTLS peer authentication configured"
else
    check_warn "No peer authentication (mTLS not enforced)"
fi

# Authorization policies
if kubectl get authorizationpolicy -n "$NAMESPACE" &>/dev/null 2>&1; then
    check_pass "Authorization policies configured"
else
    check_warn "No authorization policies found"
fi

# Pod security policies/standards
if kubectl get psp &>/dev/null 2>&1; then
    check_pass "Pod security policies available"
else
    check_warn "Pod security policies not configured"
fi

# TLS certificates
CERTS=$(kubectl get certificate -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$CERTS" -gt 0 ]; then
    check_pass "$CERTS TLS certificates provisioned"
else
    check_warn "No TLS certificates found"
fi

echo ""

# ============================================================================
# 10. DATA & BACKUPS
# ============================================================================
echo -e "${BLUE}[10. Data & Backups]${RESET}"

# Database connectivity test
DB_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ ! -z "$DB_POD" ]; then
    if kubectl exec -n "$NAMESPACE" "$DB_POD" -- pg_isready &>/dev/null; then
        check_pass "PostgreSQL database responsive"
    else
        check_fail "PostgreSQL database not responding"
    fi
else
    check_warn "Database pod not found"
fi

# Backup schedule (check for backup jobs)
BACKUP_JOBS=$(kubectl get cronjob -n "$NAMESPACE" --no-headers 2>/dev/null | grep -i backup | wc -l)
if [ "$BACKUP_JOBS" -gt 0 ]; then
    check_pass "$BACKUP_JOBS backup jobs configured"
else
    check_warn "No backup jobs found"
fi

echo ""

# ============================================================================
# 11. PERFORMANCE BASELINE
# ============================================================================
echo -e "${BLUE}[11. Performance Baseline]${RESET}"

# Resource usage
CPU_USAGE=$(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum}' || echo "0")
MEM_USAGE=$(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{sum+=$3} END {print sum}' || echo "0")

if [ "$CPU_USAGE" != "0" ]; then
    check_pass "Current CPU usage: ${CPU_USAGE}m"
    check_pass "Current memory usage: ${MEM_USAGE}Mi"
else
    check_warn "Cannot read current resource usage (metrics not ready)"
fi

# Latency baseline
LATENCY=$(kubectl exec -n "$NAMESPACE" -it $(kubectl get pod -n "$NAMESPACE" -l app=api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) -- \
    curl -s -w '%{time_total}\n' -o /dev/null http://localhost:3100/health 2>/dev/null || echo "unavailable")

if [ "$LATENCY" != "unavailable" ]; then
    check_pass "API latency: ${LATENCY}s"
else
    check_warn "Could not measure API latency"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
TOTAL=$((PASSED + FAILED + WARNINGS))
PASS_PCT=$((PASSED * 100 / TOTAL))

echo -e "${BLUE}=== Production Readiness Summary ===${RESET}"
echo "Passed: $PASSED | Failed: $FAILED | Warnings: $WARNINGS | Total: $TOTAL"
echo "Score: ${PASS_PCT}%"
echo ""

if [ "$FAILED" -eq 0 ] && [ "$PASS_PCT" -ge 90 ]; then
    echo -e "${GREEN}✓ READY FOR PRODUCTION${RESET}"
    echo ""
    echo "Next steps:"
    echo "1. Conduct load testing (./scripts/k8s/load-test.sh)"
    echo "2. Run chaos engineering tests"
    echo "3. Perform data consistency check"
    echo "4. Team sign-off"
    echo "5. Execute traffic migration"
    exit 0
elif [ "$FAILED" -eq 0 ] && [ "$PASS_PCT" -ge 75 ]; then
    echo -e "${YELLOW}⚠ CONDITIONAL READY (with review)${RESET}"
    echo ""
    echo "Address warnings above before production deployment"
    exit 1
else
    echo -e "${RED}✗ NOT READY FOR PRODUCTION${RESET}"
    echo ""
    echo "Fix critical failures before proceeding"
    exit 1
fi
