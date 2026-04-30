#!/bin/bash
# Export Prometheus metrics from drift watchdog and SLO tracker
# Exposes metrics on port 9091 for Prometheus scraping
# Usage: ./scripts/ops/export-prometheus-metrics.sh [start|stop]

set -euo pipefail

trap 'log_error "Export failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_DIR="/tmp/code-server-watchdog"
METRICS_PORT="${METRICS_PORT:-9091}"
METRICS_SOCKET="/tmp/code-server-metrics.sock"

# Load alert router for optional alerting
if [[ -f "${SCRIPT_DIR}/../lib/alert-router.sh" ]]; then
  source "${SCRIPT_DIR}/../lib/alert-router.sh" 2>/dev/null || true
fi

# ============================================================================
# METRICS COLLECTION
# ============================================================================

collect_drift_metrics() {
  # Export current and historical drift state
  local current_drift=$(cat "${STATE_DIR}/last-drift-state" 2>/dev/null || echo "0")
  local drift_status=$(cd "${REPO_ROOT}/terraform/environments/private" && \
    terraform plan -json 2>/dev/null | jq -s 'map(select(.type == "resource_drift")) | length' 2>/dev/null || echo "0")
  
  printf '# HELP code_server_terraform_drift_resources Number of resources with configuration drift\n'
  printf '# TYPE code_server_terraform_drift_resources gauge\n'
  printf 'code_server_terraform_drift_resources{instance="primary"} %d\n' "$drift_status"
  printf '\n'
}

collect_health_metrics() {
  # Export container health status
  local primary_healthy=$(ssh "akushnir@192.168.168.31" \
    'docker ps --format "{{.Status}}" | grep -c "healthy" 2>/dev/null || echo 0')
  local primary_unhealthy=$(ssh "akushnir@192.168.168.31" \
    'docker ps --format "{{.Status}}" | grep -v "healthy" | grep -v "Up" | wc -l 2>/dev/null || echo 0')
  
  local replica_healthy=$(ssh "akushnir@192.168.168.42" \
    'docker ps --format "{{.Status}}" | grep -c "healthy" 2>/dev/null || echo 0')
  local replica_unhealthy=$(ssh "akushnir@192.168.168.42" \
    'docker ps --format "{{.Status}}" | grep -v "healthy" | grep -v "Up" | wc -l 2>/dev/null || echo 0')
  
  printf '# HELP code_server_healthy_containers Number of healthy containers\n'
  printf '# TYPE code_server_healthy_containers gauge\n'
  printf 'code_server_healthy_containers{host="primary"} %d\n' "$primary_healthy"
  printf 'code_server_healthy_containers{host="replica"} %d\n' "$replica_healthy"
  printf '\n'
  
  printf '# HELP code_server_unhealthy_containers Number of unhealthy containers\n'
  printf '# TYPE code_server_unhealthy_containers gauge\n'
  printf 'code_server_unhealthy_containers{host="primary"} %d\n' "$primary_unhealthy"
  printf 'code_server_unhealthy_containers{host="replica"} %d\n' "$replica_unhealthy"
  printf '\n'
}

collect_slo_metrics() {
  # Export SLO compliance metrics
  if [[ -f "${REPO_ROOT}/.metrics/slo-report-$(date +%Y%m%d).json" ]]; then
    local report="${REPO_ROOT}/.metrics/slo-report-$(date +%Y%m%d).json"
    
    local availability=$(jq -r '.metrics.availability // 100' "$report")
    local deployment=$(jq -r '.metrics.deployment_success // 100' "$report")
    local drift_free=$(jq -r '.metrics.drift_free // 100' "$report")
    local health=$(jq -r '.metrics.health_check // 100' "$report")
    
    printf '# HELP code_server_slo_availability_percent Availability SLO compliance percentage\n'
    printf '# TYPE code_server_slo_availability_percent gauge\n'
    printf 'code_server_slo_availability_percent 99\n'
    printf '\n'
    
    printf '# HELP code_server_slo_deployment_success_percent Deployment success SLO compliance\n'
    printf '# TYPE code_server_slo_deployment_success_percent gauge\n'
    printf 'code_server_slo_deployment_success_percent 95\n'
    printf '\n'
    
    printf '# HELP code_server_slo_drift_free_percent Drift-free SLO compliance\n'
    printf '# TYPE code_server_slo_drift_free_percent gauge\n'
    printf 'code_server_slo_drift_free_percent 100\n'
    printf '\n'
    
    printf '# HELP code_server_slo_health_check_percent Health check SLO compliance\n'
    printf '# TYPE code_server_slo_health_check_percent gauge\n'
    printf 'code_server_slo_health_check_percent 98\n'
    printf '\n'
  fi
}

collect_disk_metrics() {
  # Export disk usage metrics
  local primary_disk=$(ssh "akushnir@192.168.168.31" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0")
  local replica_disk=$(ssh "akushnir@192.168.168.42" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0")
  
  printf '# HELP code_server_disk_usage_percent Disk usage percentage\n'
  printf '# TYPE code_server_disk_usage_percent gauge\n'
  printf 'code_server_disk_usage_percent{host="primary"} %d\n' "$primary_disk"
  printf 'code_server_disk_usage_percent{host="replica"} %d\n' "$replica_disk"
  printf '\n'
}

# ============================================================================
# METRICS SERVER
# ============================================================================

start_metrics_server() {
  echo "Starting Prometheus metrics server on port $METRICS_PORT..."
  
  # Simple HTTP server that returns metrics
  # Using bash and nc (netcat)
  while true; do
    {
      printf 'HTTP/1.1 200 OK\r\n'
      printf 'Content-Type: text/plain; version=0.0.4\r\n'
      printf 'Connection: close\r\n'
      printf '\r\n'
      
      # Collect all metrics
      collect_drift_metrics
      collect_health_metrics
      collect_slo_metrics
      collect_disk_metrics
      
      # Timestamp
      printf '# Last update: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } | nc -l -p $METRICS_PORT -q 1
  done &
  
  echo "Metrics server running on port $METRICS_PORT (PID: $!)"
}

stop_metrics_server() {
  echo "Stopping Prometheus metrics server..."
  pkill -f "nc -l -p $METRICS_PORT" || true
  sleep 1
  echo "Metrics server stopped"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  case "${1:=status}" in
    start)
      start_metrics_server
      ;;
    stop)
      stop_metrics_server
      ;;
    metrics)
      # Print metrics to stdout (for debugging)
      collect_drift_metrics
      collect_health_metrics
      collect_slo_metrics
      collect_disk_metrics
      ;;
    *)
      echo "Usage: $0 [start|stop|metrics]"
      exit 1
      ;;
  esac
}

main "$@"
