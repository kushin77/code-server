#!/bin/bash
# scripts/phase-11/health-check.sh
# Comprehensive health checks for Phase 11 HA deployment

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-code-server-ha}"
WATCH="${WATCH:-false}"
INTERVAL="${INTERVAL:-10}"

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

# Logging
log_pass() {
  echo -e "${GREEN}[✓]${NC} $*"
  ((CHECKS_PASSED++))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $*"
  ((CHECKS_FAILED++))
}

log_info() {
  echo -e "${YELLOW}[*]${NC} $*"
}

# Health checks
check_namespace() {
  log_info "Checking namespace..."
  
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_pass "Namespace exists"
  else
    log_fail "Namespace $NAMESPACE not found"
    return 1
  fi
}

check_pods() {
  log_info "Checking pod status..."
  
  local total=$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | wc -l)
  local running=$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | grep "Running" | wc -l)
  
  echo "  Total pods: $total"
  echo "  Running: $running"
  
  if [ "$running" -ge 10 ]; then
    log_pass "Pod count OK"
  else
    log_fail "Not all pods running ($running/$total)"
  fi
  
  # Check for failed pods
  local failed=$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null | grep -E "Failed|CrashLoop" | wc -l)
  if [ "$failed" -eq 0 ]; then
    log_pass "No failed pods"
  else
    log_fail "$failed pods in failed state"
    kubectl -n "$NAMESPACE" get pods | grep -E "Failed|CrashLoop"
  fi
}

check_postgresql() {
  log_info "Checking PostgreSQL..."
  
  # Check primary
  local primary=$(kubectl -n "$NAMESPACE" get pod -l app=postgres,role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$primary" ]; then
    log_fail "PostgreSQL primary not found"
    return 1
  fi
  
  if kubectl -n "$NAMESPACE" exec "$primary" -- pg_isready -U postgres &>/dev/null; then
    log_pass "PostgreSQL primary is ready"
  else
    log_fail "PostgreSQL primary is not ready"
    return 1
  fi
  
  # Check replication
  local replicas=$(kubectl -n "$NAMESPACE" exec "$primary" -- psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ' || echo "0")
  if [ "$replicas" -ge 2 ]; then
    log_pass "PostgreSQL replication OK ($replicas replicas)"
  else
    log_fail "PostgreSQL replication not healthy ($replicas replicas)"
  fi
  
  # Check replication lag
  local lag=$(kubectl -n "$NAMESPACE" exec "$primary" -- psql -U postgres -t -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_wal_receive_time())) FROM pg_stat_replication LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "999")
  if (( $(echo "$lag < 1" | bc -l 2>/dev/null || echo 0) )); then
    log_pass "Replication lag OK (${lag}s)"
  else
    log_fail "Replication lag too high (${lag}s)"
  fi
}

check_redis() {
  log_info "Checking Redis..."
  
  # Check cluster
  local redis_node=$(kubectl -n "$NAMESPACE" get pod -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$redis_node" ]; then
    log_fail "Redis nodes not found"
    return 1
  fi
  
  local cluster_nodes=$(kubectl -n "$NAMESPACE" exec "$redis_node" -- redis-cli cluster nodes 2>/dev/null | wc -l || echo "0")
  if [ "$cluster_nodes" -ge 6 ]; then
    log_pass "Redis cluster nodes OK ($cluster_nodes nodes)"
  else
    log_fail "Redis cluster incomplete ($cluster_nodes/6 nodes)"
  fi
  
  local cluster_state=$(kubectl -n "$NAMESPACE" exec "$redis_node" -- redis-cli cluster info 2>/dev/null | grep "cluster_state" || echo "cluster_state:fail")
  if echo "$cluster_state" | grep -q "ok"; then
    log_pass "Redis cluster state OK"
  else
    log_fail "Redis cluster state: $(echo $cluster_state | cut -d: -f2)"
  fi
}

check_code_server() {
  log_info "Checking code-server instances..."
  
  local count=$(kubectl -n "$NAMESPACE" get pods -l app=code-server --no-headers 2>/dev/null | grep "Running" | wc -l)
  if [ "$count" -ge 3 ]; then
    log_pass "code-server instances running ($count)"
  else
    log_fail "Not all code-server instances running ($count/3)"
  fi
  
  # Check readiness probes
  local ready=$(kubectl -n "$NAMESPACE" get pods -l app=code-server -o jsonpath='{.items[*].status.containerStatuses[?(@.readinessProbes.httpGet)].ready}' | tr ' ' '\n' | grep "true" | wc -l)
  if [ "$ready" -ge 3 ]; then
    log_pass "code-server instances ready ($ready)"
  else
    log_fail "code-server instances not all ready ($ready/3)"
  fi
}

check_monitoring() {
  log_info "Checking monitoring stack..."
  
  # Check Prometheus
  local prom=$(kubectl -n "$NAMESPACE" get pod -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$prom" ] && kubectl -n "$NAMESPACE" get pod "$prom" -o jsonpath='{.status.phase}' | grep -q "Running"; then
    log_pass "Prometheus is running"
  else
    log_fail "Prometheus is not running"
  fi
  
  # Check Jaeger
  local jaeger=$(kubectl -n "$NAMESPACE" get pod -l app=jaeger -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$jaeger" ] && kubectl -n "$NAMESPACE" get pod "$jaeger" -o jsonpath='{.status.phase}' | grep -q "Running"; then
    log_pass "Jaeger is running"
  else
    log_fail "Jaeger is not running"
  fi
}

check_storage() {
  log_info "Checking storage..."
  
  local pvcs=$(kubectl -n "$NAMESPACE" get pvc --no-headers 2>/dev/null | wc -l)
  if [ "$pvcs" -gt 0 ]; then
    log_pass "PVC count: $pvcs"
    
    local bound=$(kubectl -n "$NAMESPACE" get pvc --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    if [ "$bound" = "$pvcs" ]; then
      log_pass "All PVCs are bound"
    else
      log_fail "Not all PVCs bound ($bound/$pvcs)"
    fi
  else
    log_fail "No PVCs found"
  fi
}

check_network_policies() {
  log_info "Checking network policies..."
  
  local netpol=$(kubectl -n "$NAMESPACE" get networkpolicies --no-headers 2>/dev/null | wc -l)
  if [ "$netpol" -gt 0 ]; then
    log_pass "Network policies enabled ($netpol policies)"
  else
    log_warn "No network policies found"
  fi
}

print_summary() {
  log_info "========================================="
  log_info "Health Check Summary"
  log_info "========================================="
  echo "Checks Passed: $CHECKS_PASSED"
  echo "Checks Failed: $CHECKS_FAILED"
  
  if [ "$CHECKS_FAILED" -eq 0 ]; then
    log_pass "All health checks passed!"
    return 0
  else
    log_fail "Some health checks failed"
    return 1
  fi
}

run_health_checks() {
  echo ""
  echo "Running health checks for namespace: $NAMESPACE"
  echo ""
  
  check_namespace || return 1
  check_pods
  check_postgresql
  check_redis
  check_code_server
  check_monitoring
  check_storage
  check_network_policies
  
  echo ""
  print_summary
}

# Main loop
while true; do
  CHECKS_PASSED=0
  CHECKS_FAILED=0
  
  run_health_checks || true
  
  if [ "$WATCH" = "false" ]; then
    break
  fi
  
  echo ""
  echo "Sleeping for ${INTERVAL}s (use Ctrl+C to stop)..."
  sleep "$INTERVAL"
done
