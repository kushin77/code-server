#!/usr/bin/env bash
# @file        scripts/ci/validate-stage-2-readiness.sh
# @module      ci/deployment-validation
# @description Validates all infrastructure prerequisites for Collab-9 Stage 2 production canary
# @owner       collab-9-deployment-team
# @status      ready-for-execution

set -euo pipefail

source "$SCRIPT_DIR/_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

REPLICA_1_HOST="${REPLICA_1_HOST:-192.168.168.31}"
REPLICA_2_HOST="${REPLICA_2_HOST:-192.168.168.42}"
REPLICA_1_USER="${REPLICA_1_USER:-akushnir}"
REPLICA_2_USER="${REPLICA_2_USER:-akushnir}"

REQUIRED_SERVICES=38
MIN_MEMORY_MB=1024
HEALTH_CHECK_URL="https://ide.kushnir.cloud/"

VALIDATION_PASSED=0
VALIDATION_FAILED=0

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function check_ssh_access() {
  local host=$1
  local user=$2
  local name=$3
  
  log_info "Checking SSH access to $name ($user@$host)..."
  
  if ssh -o ConnectTimeout=5 "$user@$host" "exit 0" 2>/dev/null; then
    log_info "✅ SSH access verified: $user@$host"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_error "❌ SSH access FAILED to $user@$host"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_git_status() {
  local host=$1
  local user=$2
  local name=$3
  
  log_info "Checking git status on $name..."
  
  local git_status
  git_status=$(ssh "$user@$host" "cd code-server-enterprise && git status" 2>&1)
  
  if [[ "$git_status" == *"On branch main"* ]] && [[ "$git_status" != *"Changes not staged"* ]]; then
    log_info "✅ Git status clean on $name"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  Git status: $(echo "$git_status" | head -3)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_docker_services() {
  local host=$1
  local user=$2
  local name=$3
  
  log_info "Checking docker services on $name..."
  
  local running_count
  running_count=$(ssh "$user@$host" "cd code-server-enterprise && docker-compose ps 2>&1 | grep -c 'Up ' || echo 0")
  
  if (( running_count >= REQUIRED_SERVICES )); then
    log_info "✅ Docker services running on $name: $running_count/$REQUIRED_SERVICES"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_error "❌ Docker services on $name: $running_count/$REQUIRED_SERVICES (INSUFFICIENT)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_http_connectivity() {
  local url=$1
  
  log_info "Checking HTTP connectivity: $url"
  
  if curl -s -m 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -qE "200|302|401"; then
    log_info "✅ HTTP connectivity verified: $url"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_error "❌ HTTP connectivity FAILED: $url"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_prometheus() {
  local host=$1
  
  log_info "Checking Prometheus API..."
  
  if curl -s "http://$host:9090/api/v1/targets" 2>/dev/null | grep -q "prometheus"; then
    log_info "✅ Prometheus API responding"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  Prometheus API not responding (metrics collection may be delayed)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_grafana() {
  local host=$1
  
  log_info "Checking Grafana..."
  
  if curl -s -o /dev/null -w "%{http_code}" "http://$host:3000/api/health" 2>/dev/null | grep -q "200"; then
    log_info "✅ Grafana API responding"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  Grafana not responding (dashboards may not be available)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_loki() {
  local host=$1
  
  log_info "Checking Loki (log aggregation)..."
  
  if curl -s "http://$host:3100/loki/api/v1/label" 2>/dev/null | grep -q "values"; then
    log_info "✅ Loki API responding"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  Loki not responding (log aggregation delayed)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_jaeger() {
  local host=$1
  
  log_info "Checking Jaeger (distributed tracing)..."
  
  if curl -s -o /dev/null -w "%{http_code}" "http://$host:16686/api/services" 2>/dev/null | grep -q "200"; then
    log_info "✅ Jaeger API responding"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  Jaeger not responding (trace collection delayed)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_alertmanager() {
  local host=$1
  local user=$2
  
  log_info "Checking AlertManager..."
  
  local alert_status
  alert_status=$(ssh "$user@$host" "docker logs alertmanager 2>&1 | grep -i 'loaded\|listening' | tail -1" 2>/dev/null || echo "")
  
  if [[ "$alert_status" == *"listening"* ]]; then
    log_info "✅ AlertManager running"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_warn "⚠️  AlertManager status unclear (alerts may have latency)"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function run_baseline_test() {
  local host=$1
  local user=$2
  
  log_info "Running baseline performance test on $user@$host..."
  log_info "(This may take 30-60 seconds...)"
  
  local test_result
  test_result=$(ssh "$user@$host" "cd code-server-enterprise && timeout 120 node COLLAB-9-BASELINE-LOAD-TEST.js 2>&1 | tail -20" 2>/dev/null || echo "FAILED")
  
  if [[ "$test_result" == *"SLO MET"* ]]; then
    log_info "✅ Baseline performance test PASSED"
    ((VALIDATION_PASSED++))
    return 0
  else
    log_error "❌ Baseline performance test FAILED or TIMEOUT"
    log_error "Result: $test_result"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

function check_deployment_script() {
  log_info "Checking deployment scripts exist..."
  
  local scripts_exist=0
  
  if [[ -f "scripts/ops/deploy-collab-9-production-canary.sh" ]]; then
    log_info "✅ Production canary deployment script found"
    ((scripts_exist++))
  fi
  
  if [[ -f "docs/ops/COLLAB-9-STAGE-2-OPS-RUNBOOK.md" ]]; then
    log_info "✅ Operations runbook found"
    ((scripts_exist++))
  fi
  
  if (( scripts_exist >= 2 )); then
    ((VALIDATION_PASSED++))
    return 0
  else
    log_error "❌ Deployment scripts incomplete"
    ((VALIDATION_FAILED++))
    return 1
  fi
}

# ============================================================================
# MAIN VALIDATION FLOW
# ============================================================================

function main() {
  log_info "=========================================="
  log_info "Collab-9 Stage 2 Readiness Validation"
  log_info "=========================================="
  log_info "Timestamp: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  log_info ""
  
  # Phase 1: SSH and Git
  log_info "--- PHASE 1: SSH & Git Status ---"
  check_ssh_access "$REPLICA_1_HOST" "$REPLICA_1_USER" "Replica 1"
  check_ssh_access "$REPLICA_2_HOST" "$REPLICA_2_USER" "Replica 2"
  check_git_status "$REPLICA_1_HOST" "$REPLICA_1_USER" "Replica 1"
  check_git_status "$REPLICA_2_HOST" "$REPLICA_2_USER" "Replica 2"
  
  log_info ""
  
  # Phase 2: Docker Services
  log_info "--- PHASE 2: Docker Services ---"
  check_docker_services "$REPLICA_1_HOST" "$REPLICA_1_USER" "Replica 1"
  check_docker_services "$REPLICA_2_HOST" "$REPLICA_2_USER" "Replica 2"
  
  log_info ""
  
  # Phase 3: HTTP Connectivity
  log_info "--- PHASE 3: HTTP Connectivity ---"
  check_http_connectivity "$HEALTH_CHECK_URL"
  
  log_info ""
  
  # Phase 4: Observability Services
  log_info "--- PHASE 4: Observability Services ---"
  check_prometheus "$REPLICA_1_HOST"
  check_grafana "$REPLICA_1_HOST"
  check_loki "$REPLICA_1_HOST"
  check_jaeger "$REPLICA_1_HOST"
  check_alertmanager "$REPLICA_1_HOST" "$REPLICA_1_USER"
  
  log_info ""
  
  # Phase 5: Performance & Deployment
  log_info "--- PHASE 5: Performance & Deployment Scripts ---"
  run_baseline_test "$REPLICA_1_HOST" "$REPLICA_1_USER"
  check_deployment_script
  
  log_info ""
  
  # Phase 6: Summary
  log_info "=========================================="
  log_info "VALIDATION SUMMARY"
  log_info "=========================================="
  log_info "✅ Passed: $VALIDATION_PASSED"
  log_info "❌ Failed: $VALIDATION_FAILED"
  
  if (( VALIDATION_FAILED == 0 )); then
    log_info ""
    log_info "🚀 RESULT: ALL CHECKS PASSED"
    log_info "✅ Infrastructure is READY for Stage 2 deployment"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Review Stage 2 ops runbook: docs/ops/COLLAB-9-STAGE-2-OPS-RUNBOOK.md"
    log_info "2. Execute deployment at scheduled time: April 26, 09:00 UTC"
    log_info "3. Monitor metrics during 48-hour canary window"
    log_info "4. Make go/no-go decisions at checkpoint 1 (12h) and checkpoint 2 (24h)"
    
    return 0
  else
    log_fatal "❌ RESULT: VALIDATION FAILED"
    log_fatal "$VALIDATION_FAILED check(s) failed. Fix issues before proceeding with deployment."
  fi
}

main "$@"
