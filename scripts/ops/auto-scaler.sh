#!/usr/bin/env bash
# @file scripts/ops/auto-scaler.sh
# @description Horizontal auto-scaler for code-server workers and API containers.
#              Reads CPU/memory metrics from cAdvisor, scales Terraform-managed
#              replicas within min/max bounds.
# @usage auto-scaler.sh [--service <name>] [--dry-run] [--once]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
RUN_ONCE=false
TARGET_SERVICE="code-server-worker"
CADVISOR_URL="${CADVISOR_URL:-http://localhost:8081}"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9090}"

# Scaling thresholds
CPU_SCALE_UP_PCT=75
CPU_SCALE_DOWN_PCT=25
MIN_REPLICAS=1
MAX_REPLICAS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --once)     RUN_ONCE=true; shift ;;
    --service)  TARGET_SERVICE="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

get_current_replicas() {
  local service="$1"
  # Count running containers matching the service name
  docker ps --filter "name=code-server-${service}" --format '{{.Names}}' 2>/dev/null | wc -l
}

get_avg_cpu_pct() {
  local service="$1"
  # Query Prometheus for avg CPU across all replicas of this container name
  local query="100 - (avg(rate(container_cpu_usage_seconds_total{name=~\"code-server-${service}.*\"}[2m])) * 100)"
  local result
  result=$(curl -sf --max-time 5 \
    "${PROM_URL}/api/v1/query?query=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${query}'))")" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1])" 2>/dev/null)
  echo "${result:-50}"  # default 50% if unavailable
}

scale_service() {
  local service="$1"
  local target_replicas="$2"
  log_info "  Scaling ${service} to ${target_replicas} replica(s)..."
  run_or_dry terraform -chdir="${REPO_ROOT}/terraform/environments/private" \
    apply -auto-approve \
    -var="${service}_replicas=${target_replicas}" \
    -target="module.code_server_primary.docker_container.${service}"
}

check_and_scale() {
  local service="${TARGET_SERVICE}"
  local current
  current=$(get_current_replicas "${service}")
  local cpu_pct
  cpu_pct=$(get_avg_cpu_pct "${service}")

  log_info "Service: ${service} | Replicas: ${current} | CPU: ${cpu_pct}%"

  local new_replicas="${current}"

  if (( $(echo "${cpu_pct} > ${CPU_SCALE_UP_PCT}" | bc -l 2>/dev/null || echo 0) )); then
    new_replicas=$(( current < MAX_REPLICAS ? current + 1 : MAX_REPLICAS ))
    log_info "  ⬆️  CPU ${cpu_pct}% > ${CPU_SCALE_UP_PCT}% — scaling UP to ${new_replicas}"
  elif (( $(echo "${cpu_pct} < ${CPU_SCALE_DOWN_PCT}" | bc -l 2>/dev/null || echo 0) )); then
    new_replicas=$(( current > MIN_REPLICAS ? current - 1 : MIN_REPLICAS ))
    log_info "  ⬇️  CPU ${cpu_pct}% < ${CPU_SCALE_DOWN_PCT}% — scaling DOWN to ${new_replicas}"
  else
    log_info "  ✅ CPU within bounds — no scaling needed"
    return 0
  fi

  if [[ "${new_replicas}" != "${current}" ]]; then
    scale_service "${service}" "${new_replicas}"
  fi
}

# Main
log_info "Auto-Scaler — service=${TARGET_SERVICE} dry-run=${DRY_RUN}"
log_info "================================================"

if [[ "${RUN_ONCE}" == "true" ]]; then
  check_and_scale
else
  while true; do
    check_and_scale
    sleep 30
  done
fi

log_info "================================================"
log_info "Auto-scaler complete"
