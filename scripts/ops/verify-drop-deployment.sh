#!/usr/bin/env bash
# @file        scripts/ops/verify-drop-deployment.sh
# @module      operations/deployment
# @description Post-deployment health check - verify all KC services are operational
# @owner       devops
# @status      production-ready
#
# Usage: bash verify-drop-deployment.sh
# Verifies: Replicas, NAS, PostgreSQL, Redis, Services, Ollama models, Policy engine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

VERIFY_PRIMARY_HOST="${VERIFY_PRIMARY_HOST:-${DEPLOY_HOST:-${REPLICA_1_IP:-}}}"
VERIFY_REPLICA_HOST="${VERIFY_REPLICA_HOST:-${REPLICA_2_IP:-}}"
VERIFY_NAS_HOST="${VERIFY_NAS_HOST:-${NAS_HOST:-}}"
VERIFY_LOOPBACK_HOST="${VERIFY_LOOPBACK_HOST:-127.0.0.1}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-5}"

if [[ -z "$VERIFY_PRIMARY_HOST" ]]; then
  log_error "Set VERIFY_PRIMARY_HOST, DEPLOY_HOST, or REPLICA_1_IP before running the deployment check"
  exit 1
fi

if [[ -z "$VERIFY_REPLICA_HOST" ]]; then
  log_error "Set VERIFY_REPLICA_HOST or REPLICA_2_IP before running the deployment check"
  exit 1
fi

if [[ -z "$VERIFY_NAS_HOST" ]]; then
  log_error "Set VERIFY_NAS_HOST or NAS_HOST before running the deployment check"
  exit 1
fi

# Health check counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_TOTAL=0

# ─────────────────────────────────────────────────────────────────────────────
# Health Check Functions
# ─────────────────────────────────────────────────────────────────────────────

verify_host() {
  local host=$1
  local name=$2
  
  ((CHECKS_TOTAL++))
  
  if ping -c 1 -W "$VERIFY_TIMEOUT" "$host" &> /dev/null; then
    log_info "✅ $name ($host) responding to ping"
    ((CHECKS_PASSED++))
    return 0
  else
    log_error "❌ $name ($host) not responding"
    ((CHECKS_FAILED++))
    return 1
  fi
}

verify_service() {
  local host=$1
  local port=$2
  local service=$3
  
  ((CHECKS_TOTAL++))
  
  if timeout "$VERIFY_TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
    log_info "✅ $service listening on $host:$port"
    ((CHECKS_PASSED++))
    return 0
  else
    log_error "❌ $service not responding on $host:$port"
    ((CHECKS_FAILED++))
    return 1
  fi
}

verify_http_endpoint() {
  local url=$1
  local name=$2
  
  ((CHECKS_TOTAL++))
  
  if timeout "$VERIFY_TIMEOUT" curl -sf "$url" &> /dev/null; then
    log_info "✅ $name endpoint responding"
    ((CHECKS_PASSED++))
    return 0
  else
    log_error "❌ $name endpoint not responding ($url)"
    ((CHECKS_FAILED++))
    return 1
  fi
}

verify_ssh_command() {
  local host=$1
  local user=$2
  local command=$3
  local name=$4
  
  ((CHECKS_TOTAL++))
  
  if ssh -o ConnectTimeout="$VERIFY_TIMEOUT" "$user@$host" "$command" &> /dev/null; then
    log_info "✅ $name verified on $host"
    ((CHECKS_PASSED++))
    return 0
  else
    log_error "❌ $name check failed on $host"
    ((CHECKS_FAILED++))
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Verification Sequence
# ─────────────────────────────────────────────────────────────────────────────

log_info "Starting Kushnir.cloud Drop Deployment Health Check..."
log_info "Primary: $VERIFY_PRIMARY_HOST | Replica: $VERIFY_REPLICA_HOST | NAS: $VERIFY_NAS_HOST"
log_info ""

# Phase 1: Network Connectivity
log_info "────────────────────────────────────────────"
log_info "Phase 1: Network Connectivity"
log_info "────────────────────────────────────────────"

verify_host "$VERIFY_PRIMARY_HOST" "Primary replica"
verify_host "$VERIFY_REPLICA_HOST" "Replica host"
verify_host "$VERIFY_NAS_HOST" "NAS server"

log_info ""

# Phase 2: Port Availability
log_info "────────────────────────────────────────────"
log_info "Phase 2: Service Port Availability"
log_info "────────────────────────────────────────────"

# Primary host services
verify_service "$VERIFY_PRIMARY_HOST" 443 "HTTPS (Caddy)"
verify_service "$VERIFY_PRIMARY_HOST" 80 "HTTP (Caddy redirect)"
verify_service "$VERIFY_PRIMARY_HOST" 5432 "PostgreSQL"
verify_service "$VERIFY_PRIMARY_HOST" 6379 "Redis"
verify_service "$VERIFY_PRIMARY_HOST" 11434 "Ollama API"
verify_service "$VERIFY_PRIMARY_HOST" 3250 "Prompt Gateway"
verify_service "$VERIFY_PRIMARY_HOST" 8181 "OPA Policy Engine"
verify_service "$VERIFY_PRIMARY_HOST" 9090 "Prometheus"
verify_service "$VERIFY_PRIMARY_HOST" 3000 "Grafana"
verify_service "$VERIFY_PRIMARY_HOST" 3100 "Loki"

# Replica host services
verify_service "$VERIFY_REPLICA_HOST" 5432 "PostgreSQL (replica)"
verify_service "$VERIFY_REPLICA_HOST" 6379 "Redis (replica)"

log_info ""

# Phase 3: Health Endpoints
log_info "────────────────────────────────────────────"
log_info "Phase 3: Service Health Endpoints"
log_info "────────────────────────────────────────────"

verify_http_endpoint "https://$VERIFY_PRIMARY_HOST/health" "Code-Server"
verify_http_endpoint "http://$VERIFY_PRIMARY_HOST:11434/api/tags" "Ollama models"
verify_http_endpoint "http://$VERIFY_PRIMARY_HOST:3250/health" "Prompt Gateway"
verify_http_endpoint "http://$VERIFY_PRIMARY_HOST:8181/health" "OPA"
verify_http_endpoint "http://$VERIFY_PRIMARY_HOST:9090/-/healthy" "Prometheus"

log_info ""

# Phase 4: Database Replication
log_info "────────────────────────────────────────────"
log_info "Phase 4: PostgreSQL Streaming Replication"
log_info "────────────────────────────────────────────"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "docker compose exec -T postgres psql -U postgres -c 'SELECT COUNT(*) FROM pg_stat_replication;' | grep -q 1" \
  "PostgreSQL replication active"

log_info ""

# Phase 5: Cache Failover
log_info "────────────────────────────────────────────"
log_info "Phase 5: Redis Sentinel Configuration"
log_info "────────────────────────────────────────────"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "docker compose exec -T redis redis-cli sentinel masters | grep -q mymaster" \
  "Redis Sentinel active"

log_info ""

# Phase 6: Model Availability
log_info "────────────────────────────────────────────"
log_info "Phase 6: Ollama Model Availability"
log_info "────────────────────────────────────────────"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "curl -s http://${VERIFY_LOOPBACK_HOST}:11434/api/tags | grep -q 'llama3:8b'" \
  "llama3:8b model loaded"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "curl -s http://${VERIFY_LOOPBACK_HOST}:11434/api/tags | grep -q 'mistral'" \
  "mistral model loaded"

log_info ""

# Phase 7: Policy Engine
log_info "────────────────────────────────────────────"
log_info "Phase 7: OPA Policy Engine"
log_info "────────────────────────────────────────────"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "curl -s http://${VERIFY_LOOPBACK_HOST}:8181/v1/policies | grep -q 'policy'" \
  "OPA policies loaded"

log_info ""

# Phase 8: Observability
log_info "────────────────────────────────────────────"
log_info "Phase 8: Observability Stack"
log_info "────────────────────────────────────────────"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "docker compose ps | grep prometheus | grep -q 'Up'" \
  "Prometheus running"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "docker compose ps | grep grafana | grep -q 'Up'" \
  "Grafana running"

verify_ssh_command "$VERIFY_PRIMARY_HOST" "root" \
  "docker compose ps | grep loki | grep -q 'Up'" \
  "Loki running"

log_info ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary Report
# ─────────────────────────────────────────────────────────────────────────────

log_info "════════════════════════════════════════════════════════════════"
log_info "Deployment Health Check Complete"
log_info "════════════════════════════════════════════════════════════════"
log_info ""

SUCCESS_RATE=$(( CHECKS_PASSED * 100 / CHECKS_TOTAL ))

cat << EOF

╔════════════════════════════════════════════════════════════════════════╗
║        Kushnir.cloud Deployment Verification Report                  ║
╠════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  Checks Passed:  $CHECKS_PASSED / $CHECKS_TOTAL ($SUCCESS_RATE%)
║  Checks Failed:  $CHECKS_FAILED
║                                                                        ║
║  Primary Host:   $VERIFY_PRIMARY_HOST
║  Replica Host:   $VERIFY_REPLICA_HOST
║  NAS Server:     $VERIFY_NAS_HOST
║                                                                        ║

EOF

if [ $CHECKS_FAILED -eq 0 ]; then
  cat << EOF
║  Status:         🎉 ALL SYSTEMS OPERATIONAL 🎉
║                                                                        ║
║  Your Kushnir.cloud deployment is ready for use!                      ║
║                                                                        ║
║  Next Steps:                                                           ║
║  1. Access IDE: https://ide.kushnir.cloud                             ║
║  2. View Metrics: https://prometheus.kushnir.cloud                    ║
║  3. Configure Grafana: https://grafana.kushnir.cloud                  ║
║  4. Check Logs: https://loki.kushnir.cloud                            ║
║  5. Policy Rules: curl http://$VERIFY_PRIMARY_HOST:8181/v1/policies       ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

EOF
  exit 0
else
  cat << EOF
║  Status:         ⚠️  ISSUES DETECTED - Review Above ⚠️
║                                                                        ║
║  Troubleshooting:                                                      ║
║  1. Check service logs: docker compose logs <service>                 ║
║  2. Verify network connectivity between hosts                         ║
║  3. Check resource availability (CPU, memory, disk)                   ║
║  4. Review Terraform apply output for errors                          ║
║  5. Consult troubleshooting guide in terraform/drop-package/README.md ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

EOF
  exit 1
fi
