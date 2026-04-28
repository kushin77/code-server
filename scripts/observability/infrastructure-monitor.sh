#!/usr/bin/env bash
# @file scripts/observability/infrastructure-monitor.sh
# @module observability/monitoring
# @description Real-time infrastructure health monitoring with alerting
# @governance GOV-003: Proactive infrastructure monitoring for uptime
# @usage infrastructure-monitor.sh [--interval 30] [--threshold 80] [--output ./metrics.json]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Monitoring failed at line $LINENO"; exit 1' ERR
trap 'cleanup_monitoring' EXIT

# Configuration
INTERVAL="${1:-30}"
THRESHOLD="${2:-80}"
OUTPUT_FILE="${3:-.}/metrics.json"
MONITOR_ID="MONITOR-$(date +%s)"
TEMP_METRICS="/tmp/metrics-${MONITOR_ID}.tmp"

cleanup_monitoring() {
  rm -f "${TEMP_METRICS}" 2>/dev/null || true
}

log_info "═══════════════════════════════════════════════════════"
log_info "INFRASTRUCTURE MONITORING"
log_info "═══════════════════════════════════════════════════════"
log_info "Monitor ID: ${MONITOR_ID}"
log_info "Interval: ${INTERVAL}s"
log_info "Threshold: ${THRESHOLD}%"
echo

# Initialize metrics JSON
init_metrics_json() {
  cat > "${TEMP_METRICS}" <<EOF
{
  "monitor_id": "${MONITOR_ID}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "interval": ${INTERVAL},
  "threshold": ${THRESHOLD},
  "cpu": {},
  "memory": {},
  "disk": {},
  "network": {},
  "processes": {},
  "containers": {},
  "alerts": []
}
EOF
}

# Monitor CPU usage
monitor_cpu() {
  log_info "Monitoring CPU usage..."
  
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  local cpu_usage_int=$(printf "%.0f" "$cpu_usage")
  
  jq ".cpu = {
    \"usage_percent\": ${cpu_usage},
    \"status\": \"$([ ${cpu_usage_int} -gt ${THRESHOLD} ] && echo 'ALERT' || echo 'OK')\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  if [ "${cpu_usage_int}" -gt "${THRESHOLD}" ]; then
    log_warn "⚠ CPU usage high: ${cpu_usage_int}%"
    jq ".alerts += [{\"type\": \"CPU\", \"severity\": \"HIGH\", \"message\": \"CPU usage ${cpu_usage_int}%\"}]" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  else
    log_success "✓ CPU usage normal: ${cpu_usage_int}%"
  fi
}

# Monitor memory usage
monitor_memory() {
  log_info "Monitoring memory usage..."
  
  local mem_total=$(free | awk 'NR==2 {print $2}')
  local mem_used=$(free | awk 'NR==2 {print $3}')
  local mem_percent=$((mem_used * 100 / mem_total))
  
  jq ".memory = {
    \"total_mb\": $((mem_total / 1024)),
    \"used_mb\": $((mem_used / 1024)),
    \"usage_percent\": ${mem_percent},
    \"status\": \"$([ ${mem_percent} -gt ${THRESHOLD} ] && echo 'ALERT' || echo 'OK')\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  if [ "${mem_percent}" -gt "${THRESHOLD}" ]; then
    log_warn "⚠ Memory usage high: ${mem_percent}%"
    jq ".alerts += [{\"type\": \"MEMORY\", \"severity\": \"HIGH\", \"message\": \"Memory usage ${mem_percent}%\"}]" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  else
    log_success "✓ Memory usage normal: ${mem_percent}%"
  fi
}

# Monitor disk usage
monitor_disk() {
  log_info "Monitoring disk usage..."
  
  local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  
  jq ".disk = {
    \"root_usage_percent\": ${disk_usage},
    \"status\": \"$([ ${disk_usage} -gt ${THRESHOLD} ] && echo 'ALERT' || echo 'OK')\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  if [ "${disk_usage}" -gt "${THRESHOLD}" ]; then
    log_warn "⚠ Disk usage high: ${disk_usage}%"
    jq ".alerts += [{\"type\": \"DISK\", \"severity\": \"HIGH\", \"message\": \"Disk usage ${disk_usage}%\"}]" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  else
    log_success "✓ Disk usage normal: ${disk_usage}%"
  fi
}

# Monitor network connections
monitor_network() {
  log_info "Monitoring network connections..."
  
  local active_connections=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l || echo "0")
  local listening_ports=$(netstat -tln 2>/dev/null | grep LISTEN | wc -l || echo "0")
  
  jq ".network = {
    \"active_connections\": ${active_connections},
    \"listening_ports\": ${listening_ports},
    \"status\": \"OK\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  log_success "✓ Network connections: ${active_connections} active, ${listening_ports} listening"
}

# Monitor processes
monitor_processes() {
  log_info "Monitoring processes..."
  
  local total_processes=$(ps aux | wc -l)
  local zombie_processes=$(ps aux | grep -c "Z" || echo "0")
  
  jq ".processes = {
    \"total\": ${total_processes},
    \"zombie\": ${zombie_processes},
    \"status\": \"$([ ${zombie_processes} -gt 0 ] && echo 'WARNING' || echo 'OK')\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  if [ "${zombie_processes}" -gt 0 ]; then
    log_warn "⚠ Zombie processes detected: ${zombie_processes}"
    jq ".alerts += [{\"type\": \"PROCESSES\", \"severity\": \"MEDIUM\", \"message\": \"${zombie_processes} zombie processes\"}]" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  else
    log_success "✓ Process health normal: ${total_processes} processes"
  fi
}

# Monitor Docker containers
monitor_containers() {
  log_info "Monitoring Docker containers..."
  
  if ! command -v docker &> /dev/null; then
    log_warn "⚠ Docker not available"
    return 0
  fi
  
  local total_containers=$(docker ps -aq 2>/dev/null | wc -l || echo "0")
  local running_containers=$(docker ps -q 2>/dev/null | wc -l || echo "0")
  local unhealthy_containers=$(docker ps 2>/dev/null | grep -c "unhealthy" || echo "0")
  
  jq ".containers = {
    \"total\": ${total_containers},
    \"running\": ${running_containers},
    \"unhealthy\": ${unhealthy_containers},
    \"status\": \"$([ ${unhealthy_containers} -gt 0 ] && echo 'ALERT' || echo 'OK')\"
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  if [ "${unhealthy_containers}" -gt 0 ]; then
    log_warn "⚠ Unhealthy containers: ${unhealthy_containers}"
    jq ".alerts += [{\"type\": \"CONTAINERS\", \"severity\": \"HIGH\", \"message\": \"${unhealthy_containers} containers unhealthy\"}]" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  else
    log_success "✓ Container health: ${running_containers}/${total_containers} running"
  fi
}

# Generate summary report
generate_summary() {
  log_info "Generating summary report..."
  
  local alert_count=$(jq '.alerts | length' "${TEMP_METRICS}")
  local status="OK"
  
  if [ "${alert_count}" -gt 0 ]; then
    status="ALERTING"
  fi
  
  jq ".summary = {
    \"total_alerts\": ${alert_count},
    \"status\": \"${status}\",
    \"monitoring_complete\": true
  }" "${TEMP_METRICS}" > "${TEMP_METRICS}.new" && mv "${TEMP_METRICS}.new" "${TEMP_METRICS}"
  
  log_success "✓ Monitoring complete: ${alert_count} alerts"
}

# Save metrics
save_metrics() {
  log_info "Saving metrics to ${OUTPUT_FILE}..."
  cp "${TEMP_METRICS}" "${OUTPUT_FILE}"
  log_success "✓ Metrics saved"
}

# Main monitoring loop
main() {
  init_metrics_json
  
  monitor_cpu
  monitor_memory
  monitor_disk
  monitor_network
  monitor_processes
  monitor_containers
  
  generate_summary
  save_metrics
  
  echo
  log_info "═══════════════════════════════════════════════════════"
  
  local alerts=$(jq '.alerts | length' "${OUTPUT_FILE}")
  if [ "${alerts}" -eq 0 ]; then
    log_success "✓ All systems normal"
    exit 0
  else
    log_warn "⚠ ${alerts} alerts generated"
    exit 0
  fi
}

main
