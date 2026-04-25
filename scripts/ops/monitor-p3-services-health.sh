#!/bin/bash
# @file scripts/ops/monitor-p3-services-health.sh
# @description Real-time P3 Services Health Monitoring (IaC)
# @governance GOV-002: Immutable, idempotent monitoring
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 Services #1558, #1559, #1561

set -euo pipefail

# Source P3 configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../_common/_p3-services-config.env"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# Load network configuration SSOT
source "${PROJECT_ROOT}/scripts/_common/_epic-1536-network-config.env" || {
    echo "Warning: Network configuration SSOT not found, using defaults"
}

################################################################################
# COLOR CODES
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREY='\033[0;37m'
NC='\033[0m'

################################################################################
# CONFIGURATION
################################################################################

MONITOR_INTERVAL="${MONITOR_INTERVAL:-10}"  # seconds
MAX_ITERATIONS="${MAX_ITERATIONS:-0}"       # 0 = infinite
QUIET_MODE="${QUIET_MODE:-false}"
JSON_OUTPUT="${JSON_OUTPUT:-false}"
REPORT_FILE="${REPORT_FILE:-artifacts/p3-health-$(date +'%Y%m%d-%H%M%S').json}"

# Service definitions
declare -A SERVICES=(
  [reputation]="Reputation Engine|${REPUTATION_ENGINE_URL}${REPUTATION_ENGINE_HEALTH_PATH}"
  [scheduler]="Execution Scheduler|${EXECUTION_SCHEDULER_URL}${EXECUTION_SCHEDULER_HEALTH_PATH}"
  [paperclip]="Paperclip Control Plane|${PAPERCLIP_CONTROL_PLANE_URL}${PAPERCLIP_CONTROL_PLANE_HEALTH_PATH}"
  [opa]="OPA Policy Engine|${OPA_URL}${OPA_HEALTH_PATH}"
)

################################################################################
# STATE TRACKING
################################################################################

declare -A SERVICE_STATUS
declare -A SERVICE_RESPONSE_TIME
declare -A SERVICE_LAST_CHECK
declare -A SERVICE_FAILURE_COUNT

for service in "${!SERVICES[@]}"; do
  SERVICE_STATUS[$service]="UNKNOWN"
  SERVICE_RESPONSE_TIME[$service]="0"
  SERVICE_LAST_CHECK[$service]="0"
  SERVICE_FAILURE_COUNT[$service]="0"
done

ITERATION=0
TOTAL_CHECKS=0
TOTAL_FAILURES=0
START_TIME=$(date +%s)

################################################################################
# LOGGING
################################################################################

log_info() {
  if [[ "$QUIET_MODE" == "false" ]]; then
    echo "[$(date +'%H:%M:%S')] [INFO] $*"
  fi
}

log_status() {
  local service="$1"
  local status="$2"
  local response_time="$3"
  
  if [[ "$QUIET_MODE" == "false" ]]; then
    local color
    case "$status" in
      UP)     color="$GREEN" ;;
      DOWN)   color="$RED" ;;
      SLOW)   color="$YELLOW" ;;
      *)      color="$GREY" ;;
    esac
    
    printf "  ${color}[%-8s]${NC} %-30s %6sms\n" "$status" "$service" "$response_time"
  fi
}

################################################################################
# HEALTH CHECK
################################################################################

check_service_health() {
  local service_key="$1"
  local service_info="${SERVICES[$service_key]}"
  local service_name="${service_info%%|*}"
  local health_url="${service_info##*|}"
  
  local start_time
  start_time=$(date +%s%N)
  
  local http_code
  local response
  
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "$HEALTH_CHECK_TIMEOUT" \
    "$health_url" 2>/dev/null || echo "000")
  
  local end_time
  end_time=$(date +%s%N)
  
  local response_ms=$(( (end_time - start_time) / 1000000 ))
  
  local status
  if [[ "$http_code" == "200" ]] || [[ "$http_code" == "204" ]]; then
    status="UP"
    SERVICE_FAILURE_COUNT[$service_key]=0
  else
    status="DOWN"
    ((SERVICE_FAILURE_COUNT[$service_key]++))
    ((TOTAL_FAILURES++))
  fi
  
  # Check for slow responses
  if [[ $response_ms -gt 5000 ]]; then
    status="SLOW"
  fi
  
  SERVICE_STATUS[$service_key]="$status"
  SERVICE_RESPONSE_TIME[$service_key]="$response_ms"
  SERVICE_LAST_CHECK[$service_key]=$(date +'%Y-%m-%dT%H:%M:%SZ')
  
  log_status "$service_name" "$status" "$response_ms"
  ((TOTAL_CHECKS++))
}

################################################################################
# MONITORING LOOP
################################################################################

display_header() {
  if [[ "$QUIET_MODE" == "false" ]]; then
    clear || true
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  P3 Services Health Monitor                                ║"
    echo "║  Interval: ${MONITOR_INTERVAL}s | Iteration: $((ITERATION + 1))  Uptime: $(date -u -d @$(($(date +%s) - START_TIME)) +%H:%M:%S)"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Service Status:"
  fi
}

check_all_services() {
  local iteration=$1
  
  display_header
  
  for service_key in "${!SERVICES[@]}"; do
    check_service_health "$service_key"
  done
  
  # Calculate statistics
  local up_count=0
  for service in "${!SERVICE_STATUS[@]}"; do
    if [[ "${SERVICE_STATUS[$service]}" == "UP" ]]; then
      ((up_count++))
    fi
  done
  
  if [[ "$QUIET_MODE" == "false" ]]; then
    echo ""
    echo "Summary: ${up_count}/${#SERVICES[@]} services UP"
    echo "Total Checks: $TOTAL_CHECKS | Failures: $TOTAL_FAILURES"
    echo ""
    echo "Press Ctrl+C to stop monitoring..."
  fi
}

################################################################################
# REPORTING
################################################################################

generate_json_report() {
  mkdir -p artifacts
  
  cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "monitoring_duration_seconds": $(($(date +%s) - START_TIME)),
  "total_checks": $TOTAL_CHECKS,
  "total_failures": $TOTAL_FAILURES,
  "services": {
EOF

  local first=true
  for service_key in "${!SERVICES[@]}"; do
    local service_info="${SERVICES[$service_key]}"
    local service_name="${service_info%%|*}"
    
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo "," >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF
    "$service_name": {
      "status": "${SERVICE_STATUS[$service_key]}",
      "response_time_ms": ${SERVICE_RESPONSE_TIME[$service_key]},
      "failure_count": ${SERVICE_FAILURE_COUNT[$service_key]},
      "last_check": "${SERVICE_LAST_CHECK[$service_key]}"
    }
EOF
  done
  
  echo "" >> "$REPORT_FILE"
  echo "  }" >> "$REPORT_FILE"
  echo "}" >> "$REPORT_FILE"
}

################################################################################
# ALERT HANDLING
################################################################################

check_critical_failures() {
  local critical=false
  
  for service in "${!SERVICE_STATUS[@]}"; do
    if [[ "${SERVICE_STATUS[$service]}" == "DOWN" ]]; then
      if [[ ${SERVICE_FAILURE_COUNT[$service]} -ge 3 ]]; then
        critical=true
        echo -e "${RED}CRITICAL: ${service} down for 3+ checks${NC}" >&2
      fi
    fi
  done
  
  if [[ "$critical" == "true" ]]; then
    # Could trigger webhook, Slack notification, etc.
    log_info "Critical failures detected"
  fi
}

################################################################################
# MAIN LOOP
################################################################################

main() {
  log_info "Starting P3 Services Health Monitor"
  log_info "Services configured:"
  
  for service_key in "${!SERVICES[@]}"; do
    local service_info="${SERVICES[$service_key]}"
    local service_name="${service_info%%|*}"
    local url="${service_info##*|}"
    log_info "  - $service_name: $url"
  done
  
  log_info "Press Ctrl+C to stop..."
  sleep 2
  
  while true; do
    check_all_services "$ITERATION"
    check_critical_failures
    
    ((ITERATION++))
    
    # Check iteration limit
    if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
      break
    fi
    
    sleep "$MONITOR_INTERVAL"
  done
  
  # Generate final report
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    generate_json_report
    log_info "Report saved: $REPORT_FILE"
  fi
  
  # Final summary
  if [[ "$QUIET_MODE" == "false" ]]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Monitoring Complete                                       ║"
    echo "║  Total Iterations: $ITERATION"
    echo "║  Total Checks: $TOTAL_CHECKS"
    echo "║  Total Failures: $TOTAL_FAILURES"
    echo "║  Duration: $(date -u -d @$(($(date +%s) - START_TIME)) +%H:%M:%S)"
    echo "╚════════════════════════════════════════════════════════════╝"
  fi
}

# Signal handler for graceful shutdown
trap 'echo ""; log_info "Monitoring stopped"; exit 0' SIGINT SIGTERM

main "$@"
