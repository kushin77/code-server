#!/usr/bin/env bash
# @file scripts/ci/check-deployment-health.sh
# @description Post-deployment health check: verifies all Terraform-managed containers
#              are running, all HTTP endpoints respond, and all data stores are reachable.
# @usage check-deployment-health.sh [--timeout <sec>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
TIMEOUT=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

PASS=0; FAIL=0

check_http() {
  local name="$1" url="$2" expect="${3:-200}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] ${name}"; PASS=$((PASS+1)); return; fi
  local code
  code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time "${TIMEOUT}" "${url}" 2>/dev/null || echo 000)
  if [[ "${code}" == "${expect}" ]]; then
    log_info "  ✅ ${name} → HTTP ${code}"; PASS=$((PASS+1))
  else
    log_error "  ❌ ${name} → HTTP ${code} (expected ${expect})"; FAIL=$((FAIL+1))
  fi
}

check_container() {
  local name="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] container ${name}"; PASS=$((PASS+1)); return; fi
  local state
  state=$(docker inspect --format='{{.State.Status}}' "${name}" 2>/dev/null || echo missing)
  if [[ "${state}" == "running" ]]; then
    log_info "  ✅ container ${name} running"; PASS=$((PASS+1))
  else
    log_error "  ❌ container ${name} state=${state}"; FAIL=$((FAIL+1))
  fi
}

check_tcp() {
  local name="$1" host="$2" port="$3"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] TCP ${name}"; PASS=$((PASS+1)); return; fi
  if timeout 5 bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
    log_info "  ✅ TCP ${name} ${host}:${port}"; PASS=$((PASS+1))
  else
    log_error "  ❌ TCP ${name} ${host}:${port} unreachable"; FAIL=$((FAIL+1))
  fi
}

# Main
log_info "Deployment Health Check — dry-run=${DRY_RUN}"
log_info "================================================"

log_info "Containers:"
for c in code-server-caddy code-server-postgres code-server-redis \
          code-server-vault code-server-prometheus code-server-grafana; do
  check_container "${c}"
done

log_info "HTTP endpoints:"
check_http "caddy health"       "http://${PRIMARY_HOST:-localhost}:8080/health"
check_http "api status"         "http://${PRIMARY_HOST:-localhost}:8080/api/v1/status"
check_http "grafana"            "http://${PRIMARY_HOST:-localhost}:3000/api/health"
check_http "prometheus"         "http://${PRIMARY_HOST:-localhost}:9090/-/healthy"

log_info "TCP connectivity:"
check_tcp "postgres" "${PRIMARY_HOST:-localhost}" "5432"
check_tcp "redis"    "${PRIMARY_HOST:-localhost}" "6379"

log_info "================================================"
log_info "Results: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ Deployment healthy"; exit 0; } || \
  { log_error "❌ ${FAIL} health check(s) failed"; exit 1; }
