#!/bin/bash
# @file scripts/ops/sla-metrics-collector.sh
# @module infrastructure/monitoring
# @description P3-1531 Phase 5: Collect SLA metrics and availability verification
# @governance GOV-002: All deployments monitored for uptime, latency, error rates
# @usage sla-metrics-collector.sh [--duration HOURS] [--interval SECONDS]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

METRICS_FILE="${REPO_ROOT}/artifacts/sla-metrics.json"

mkdir -p "$(dirname "${METRICS_FILE}")"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

collect_availability_metrics() {
  log_info "Collecting availability metrics..."
  
  local health_endpoint="${HEALTH_CHECK_ENDPOINT:-${API_HEALTH_ENDPOINT}}"
  local total_checks=0
  local successful_checks=0
  local failed_checks=0
  
  for i in {1..10}; do
    total_checks=$((total_checks + 1))
    
    if curl -sf "${health_endpoint}" > /dev/null 2>&1; then
      successful_checks=$((successful_checks + 1))
    else
      failed_checks=$((failed_checks + 1))
    fi
    
    [[ ${i} -lt 10 ]] && sleep 5
  done
  
  local availability=$(echo "scale=2; ${successful_checks} * 100 / ${total_checks}" | bc)
  echo "${availability}"
}

collect_latency_metrics() {
  log_info "Collecting latency metrics..."
  
  local health_endpoint="${HEALTH_CHECK_ENDPOINT:-${API_HEALTH_ENDPOINT}}"
  local total_time=0
  local num_requests=5
  
  for i in {1..${num_requests}}; do
    local response_time=$(curl -s -w '%{time_total}' -o /dev/null "${health_endpoint}" 2>/dev/null || echo "0")
    total_time=$(echo "${total_time} + ${response_time}" | bc)
    [[ ${i} -lt ${num_requests} ]] && sleep 2
  done
  
  local avg_latency=$(echo "scale=3; ${total_time} / ${num_requests}" | bc)
  echo "${avg_latency}"
}

collect_error_rate() {
  log_info "Collecting error rate metrics..."
  
  local health_endpoint="${HEALTH_CHECK_ENDPOINT:-${API_HEALTH_ENDPOINT}}"
  local total_requests=20
  local error_count=0
  
  for i in {1..${total_requests}}; do
    local http_code=$(curl -s -o /dev/null -w '%{http_code}' "${health_endpoint}" 2>/dev/null || echo "000")
    
    if [[ "${http_code}" != "200" ]]; then
      error_count=$((error_count + 1))
    fi
    
    [[ ${i} -lt ${total_requests} ]] && sleep 1
  done
  
  local error_rate=$(echo "scale=2; ${error_count} * 100 / ${total_requests}" | bc)
  echo "${error_rate}"
}

generate_sla_report() {
  local availability="$1"
  local latency="$2"
  local error_rate="$3"
  
  # SLA Targets: 99.5% availability, <200ms latency, <1% error rate
  local availability_pass=$(echo "${availability} >= 99.5" | bc)
  local latency_pass=$(echo "${latency} < 0.200" | bc)
  local error_pass=$(echo "${error_rate} <= 1" | bc)
  
  local overall_sla="PASS"
  [[ ${availability_pass} -eq 0 ]] && overall_sla="FAIL"
  [[ ${latency_pass} -eq 0 ]] && overall_sla="FAIL"
  [[ ${error_pass} -eq 0 ]] && overall_sla="FAIL"
  
  cat > "${METRICS_FILE}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "sla_status": "${overall_sla}",
  "metrics": {
    "availability_percent": ${availability},
    "availability_target": 99.5,
    "availability_pass": $([ ${availability_pass} -eq 1 ] && echo true || echo false),
    "latency_seconds": ${latency},
    "latency_target": 0.2,
    "latency_pass": $([ ${latency_pass} -eq 1 ] && echo true || echo false),
    "error_rate_percent": ${error_rate},
    "error_rate_target": 1.0,
    "error_rate_pass": $([ ${error_pass} -eq 1 ] && echo true || echo false)
  }
}
EOF
  
  log_success "SLA metrics report saved to ${METRICS_FILE}"
  
  if [[ "${overall_sla}" == "PASS" ]]; then
    log_success "SLA VERIFICATION PASSED (Availability: ${availability}%, Latency: ${latency}s, Errors: ${error_rate}%)"
    return 0
  else
    log_error "SLA VERIFICATION FAILED - Targets not met"
    return 1
  fi
}

main() {
  log_info "SLA Metrics Collection Started"
  
  local availability=$(collect_availability_metrics)
  local latency=$(collect_latency_metrics)
  local error_rate=$(collect_error_rate)
  
  log_info "Collected metrics: Availability=${availability}%, Latency=${latency}s, Errors=${error_rate}%"
  
  generate_sla_report "${availability}" "${latency}" "${error_rate}"
}

main "$@"