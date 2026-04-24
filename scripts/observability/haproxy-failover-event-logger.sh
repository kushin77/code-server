#!/usr/bin/env bash
# @file        scripts/observability/haproxy-failover-event-logger.sh
# @module      observability/failover
# @description Monitors HAProxy stats and logs failover events to Loki and GitHub issues.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# HAProxy Failover Event Logger (Phase 22+)
#
# Purpose:
#   - Monitor HAProxy stats API for backend state changes
#   - Detect failovers (primary down → replica up)
#   - Log events with full context to Loki
#   - Create/update GitHub issues for failover events
#   - Track failover duration and success metrics
#
# Usage:
#   ./scripts/observability/haproxy-failover-event-logger.sh --daemon
#   ./scripts/observability/haproxy-failover-event-logger.sh --interval 10
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || { echo "FATAL: Cannot source init.sh"; exit 1; }

# Configuration
HAPROXY_STATS_URL="${HAPROXY_STATS_URL:-http://localhost:8404/haproxy-stats;csv}"
HAPROXY_USER="${HAPROXY_USER:-admin}"
HAPROXY_PASS="${HAPROXY_PASS:-${HAPROXY_PASSWORD:-}}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
STATE_FILE="${PROJECT_ROOT}/.failover-state"
DAEMON_MODE=false
CHECK_INTERVAL=30  # seconds
GITHUB_ISSUE_ON_FAILOVER=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon)
      DAEMON_MODE=true
      shift
      ;;
    --interval)
      CHECK_INTERVAL="$2"
      shift 2
      ;;
    --haproxy-url)
      HAPROXY_STATS_URL="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${HAPROXY_PASS}" ]]; then
  log_fatal "HAPROXY_PASS or HAPROXY_PASSWORD environment variable required"
fi

mkdir -p "$(dirname "${STATE_FILE}")"

# ════════════════════════════════════════════════════════════════════════════════════════════
# HAPROXY STATS MONITORING
# ════════════════════════════════════════════════════════════════════════════════════════════

# Fetch HAProxy CSV stats
fetch_haproxy_stats() {
  curl -u "${HAPROXY_USER}:${HAPROXY_PASS}" -s "${HAPROXY_STATS_URL}" 2>/dev/null || echo ""
}

# Extract backend status from HAProxy stats
get_backend_status() {
  local stats="$1"
  local backend_name="$2"
  
  echo "${stats}" | grep "^${backend_name}," | awk -F',' '{print $18}' | head -1
}

# Get primary backend status
get_primary_status() {
  local stats="$1"
  get_backend_status "${stats}" "code_server_backend,primary"
}

# Get replica backend status
get_replica_status() {
  local stats="$1"
  get_backend_status "${stats}" "code_server_backend,replica"
}

# Send event to Loki
send_failover_event_to_loki() {
  local event_type="$1"
  local primary_status="$2"
  local replica_status="$3"
  local duration_ms="${4:-0}"
  local timestamp="${5:-$(date -u +%s%N)}"
  
  local message
  message=$(cat <<EOF
[FAILOVER] ${event_type}: primary=${primary_status}, replica=${replica_status}, duration=${duration_ms}ms
EOF
  )
  
  local payload
  payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg message "${message}" \
    --arg event_type "${event_type}" \
    --arg primary_status "${primary_status}" \
    --arg replica_status "${replica_status}" \
    '{
      streams: [{
        stream: {
          job: "haproxy",
          component: "failover",
          event_type: $event_type,
          primary_status: $primary_status,
          replica_status: $replica_status
        },
        values: [[
          $timestamp,
          $message
        ]]
      }]
    }')
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" \
    >/dev/null 2>&1 || log_warn "Failed to send failover event to Loki"
}

# Detect failover transition
detect_failover_transition() {
  local prev_primary_status="$1"
  local prev_replica_status="$2"
  local curr_primary_status="$3"
  local curr_replica_status="$4"
  
  # Failover triggered: primary DOWN, replica UP
  if [[ "${prev_primary_status}" == "UP" ]] && [[ "${curr_primary_status}" != "UP" ]] && \
     [[ "${curr_replica_status}" == "UP" ]]; then
    echo "triggered"
    return 0
  fi
  
  # Failback: primary recovered, back to primary active
  if [[ "${prev_primary_status}" != "UP" ]] && [[ "${curr_primary_status}" == "UP" ]] && \
     [[ "${prev_replica_status}" == "UP" ]] && [[ "${curr_replica_status}" == "UP" ]]; then
    echo "recovered"
    return 0
  fi
  
  echo "none"
  return 0
}

# Get or initialize previous state
get_previous_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  else
    echo "UP UP"  # Default: both healthy
  fi
}

# Save current state
save_current_state() {
  local primary_status="$1"
  local replica_status="$2"
  local failover_start_time="${3:-}"
  
  cat > "${STATE_FILE}" <<EOF
${primary_status} ${replica_status}
${failover_start_time}
EOF
}

# Create GitHub issue for failover event
create_issue_on_failover() {
  local event_type="$1"
  local primary_status="$2"
  local replica_status="$3"
  local duration_ms="${4:-0}"
  
  if [[ "${GITHUB_ISSUE_ON_FAILOVER}" != "true" ]]; then
    return 0
  fi
  
  log_info "Creating GitHub issue for failover event: ${event_type}"
  
  source "${PROJECT_ROOT}/scripts/_common/issue-create-unified.sh" 2>/dev/null || {
    log_warn "Issue creation script not available, skipping GitHub issue creation"
    return 1
  }
  
  local title
  case "${event_type}" in
    "triggered")
      title="🚨 INCIDENT: Automatic Failover Triggered"
      ;;
    "recovered")
      title="✅ Failover Recovered: Primary Restored"
      ;;
    *)
      title="⚠️ Failover Event: ${event_type}"
      ;;
  esac
  
  local body
  body=$(cat <<EOF
## Failover Event Report

**Event Type**: ${event_type}
**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Primary Status**: ${primary_status}
**Replica Status**: ${replica_status}
**Duration**: ${duration_ms}ms

### Details
- **Primary Host**: ${PRIMARY_HOST}
- **Replica Host**: ${REPLICA_HOST}
- **Failover Detection**: Automatic HAProxy health check
- **Service Impact**: Minimal (HAProxy redirected traffic automatically)

### Investigation Steps
1. Check HAProxy stats: \`curl -u admin:admin123 http://localhost:8404/haproxy-stats\`
2. Review service logs: \`docker-compose logs\`
3. Verify network connectivity between hosts
4. Check certificate expiry and TLS issues

### Action Items
- [ ] Investigate root cause of primary failure
- [ ] Implement preventive measures
- [ ] Update runbooks if operational impact detected
- [ ] Schedule post-mortem if critical

### Metrics
- **RTO**: ${duration_ms}ms
- **Health Check Interval**: 10s
- **Failover Threshold**: 3 consecutive failures

---
*Auto-generated by HAProxy Failover Event Logger*
*If this is a false alarm or expected maintenance, close this issue and reference the incident*
EOF
  )
  
  copilot_create_issue \
    --title "${title}" \
    --body "${body}" \
    --priority P1 \
    --type infrastructure \
    --check-duplicates
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN MONITORING LOOP
# ════════════════════════════════════════════════════════════════════════════════════════════

check_failover_state() {
  log_debug "Checking HAProxy failover state..."
  
  # Fetch current HAProxy stats
  local stats
  stats=$(fetch_haproxy_stats)
  
  if [[ -z "${stats}" ]]; then
    log_warn "Failed to fetch HAProxy stats"
    return 1
  fi
  
  # Get current status
  local curr_primary_status
  local curr_replica_status
  curr_primary_status=$(get_primary_status "${stats}")
  curr_replica_status=$(get_replica_status "${stats}")
  
  log_debug "Current state: primary=${curr_primary_status}, replica=${curr_replica_status}"
  
  # Get previous state
  local prev_state
  prev_state=$(get_previous_state)
  local prev_primary_status=$(echo "${prev_state}" | awk '{print $1}')
  local prev_replica_status=$(echo "${prev_state}" | awk '{print $2}')
  
  # Detect transition
  local transition
  transition=$(detect_failover_transition "${prev_primary_status}" "${prev_replica_status}" \
                                          "${curr_primary_status}" "${curr_replica_status}")
  
  if [[ "${transition}" != "none" ]]; then
    log_warn "Failover ${transition} detected!"
    
    # Calculate duration if we have failover start time
    local duration_ms=0
    local failover_start_time=$(echo "${prev_state}" | awk 'NR==2 {print $1}' || echo "")
    if [[ -n "${failover_start_time}" ]]; then
      local current_time=$(date +%s%N)
      duration_ms=$(( (current_time - failover_start_time) / 1000000 ))
    fi
    
    # Send event to Loki
    send_failover_event_to_loki "${transition}" "${curr_primary_status}" "${curr_replica_status}" "${duration_ms}"
    
    # Create GitHub issue
    create_issue_on_failover "${transition}" "${curr_primary_status}" "${curr_replica_status}" "${duration_ms}"
  fi
  
  # Save current state for next iteration
  if [[ "${transition}" == "triggered" ]]; then
    save_current_state "${curr_primary_status}" "${curr_replica_status}" "$(date +%s%N)"
  else
    save_current_state "${curr_primary_status}" "${curr_replica_status}"
  fi
  
  return 0
}

# Daemon mode: continuous monitoring
run_daemon() {
  log_info "Starting HAProxy failover monitoring daemon (interval: ${CHECK_INTERVAL}s)"
  
  while true; do
    check_failover_state || true
    sleep "${CHECK_INTERVAL}"
  done
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "HAProxy Failover Event Logger starting..."
  log_info "  HAProxy URL: ${HAPROXY_STATS_URL}"
  log_info "  Primary: ${PRIMARY_HOST}"
  log_info "  Replica: ${REPLICA_HOST}"
  
  if [[ "${DAEMON_MODE}" == "true" ]]; then
    run_daemon
  else
    check_failover_state
    log_info "Failover check complete. Use --daemon flag to run continuously"
  fi
}

main "$@"
