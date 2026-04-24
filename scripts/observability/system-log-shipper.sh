#!/usr/bin/env bash
# @file        scripts/observability/system-log-shipper.sh
# @module      observability/log-collection
# @description Ships host and container logs from /var/log and Docker to Loki.
# @owner       platform
# @status      active
# ------------------------------------------------------------------------------
# System Log Shipper (Phase 22+)
#
# Purpose:
#   - Ship rsyslog/journalctl logs from bare metal hosts
#   - Collect Docker container stdout/stderr streams
#   - Parse kernel messages, systemd events
#   - Send to Loki with proper labeling
#   - Trigger GitHub issues on system-level errors
#
# Usage:
#   ./scripts/observability/system-log-shipper.sh --daemon
#   SSH to host: ssh akushnir@192.168.168.31
#   Run on host: docker-compose exec system-logger bash scripts/observability/system-log-shipper.sh
#
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh"

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
SHIPPER_LOG_DIR="${SHIPPER_LOG_DIR:-/var/log}"
JOURNALCTL_FOLLOW="${JOURNALCTL_FOLLOW:-false}"
DAEMON_MODE=false
BATCH_SIZE=100  # Buffer logs before sending to Loki
GITHUB_ISSUE_ON_KERNEL_ERROR=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon)
      DAEMON_MODE=true
      shift
      ;;
    --follow)
      JOURNALCTL_FOLLOW=true
      shift
      ;;
    --log-dir)
      SHIPPER_LOG_DIR="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ------------------------------------------------------------------------------
# LOG COLLECTION & LOKI SHIPPING
# ------------------------------------------------------------------------------

# Send logs batch to Loki
send_batch_to_loki() {
  local job_name="$1"
  local component="$2"
  local log_lines="$3"
  
  if [[ -z "${log_lines}" ]]; then
    return 0
  fi
  
  # Build Loki payload with multiple streams
  local streams_array="[]"
  local line_index=0
  
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" ]]; then
      continue
    fi
    
    local timestamp=$(date -u +%s%N)
    local stream_label=""
    local level="INFO"
    
    # Detect severity level from line content
    if [[ "${line}" =~ (ERROR|FATAL|panic|Panic|error|fatal) ]]; then
      level="ERROR"
    elif [[ "${line}" =~ (WARNING|WARN|Deprecat) ]]; then
      level="WARN"
    elif [[ "${line}" =~ (DEBUG|debug) ]]; then
      level="DEBUG"
    fi
    
    # Extract component from log line if possible
    if [[ "${line}" =~ ^\[[^]]*\] ]]; then
      stream_label=$(echo "${line}" | grep -oP '(?<=\[)[^\]]*(?=\])' | head -1)
    fi
    
    # Build stream entry
    local stream_json
    stream_json=$(jq -n \
      --arg job "${job_name}" \
      --arg component "${component}" \
      --arg level "${level}" \
      --arg stream "${stream_label}" \
      '{
        stream: {
          job: $job,
          component: $component,
          level: $level,
          source: $stream
        },
        values: []
      }')
    
    # Append line to stream
    stream_json=$(echo "${stream_json}" | jq \
      --arg timestamp "${timestamp}" \
      --arg message "${line}" \
      '.values += [[$timestamp, $message]]')
    
    # Add to streams array
    streams_array=$(echo "${streams_array}" | jq --argjson stream "${stream_json}" '. += [$stream]')
    
    ((line_index++))
  done <<< "${log_lines}"
  
  if [[ ${line_index} -eq 0 ]]; then
    return 0
  fi
  
  # Send to Loki
  local payload
  payload=$(jq -n --argjson streams "${streams_array}" '{streams: $streams}')
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" \
    >/dev/null 2>&1 || log_warn "Failed to send ${line_index} log lines to Loki"
}

# Collect kernel logs from journalctl
collect_kernel_logs() {
  log_info "Collecting kernel logs from journalctl..."
  
  local journalctl_args="--no-pager --output=short-iso -u kernel"
  
  if [[ "${JOURNALCTL_FOLLOW}" == "true" ]]; then
    journalctl_args="${journalctl_args} -f"
  else
    journalctl_args="${journalctl_args} --since=1h"
  fi
  
  local log_buffer=""
  local line_count=0
  
  # Use timeout to prevent hanging on follow mode
  timeout 300 journalctl ${journalctl_args} 2>/dev/null | while IFS= read -r line || [[ -n "${line}" ]]; do
    log_buffer="${log_buffer}${line}"$'\n'
    ((line_count++))
    
    # Send batch when reaching batch size
    if [[ ${line_count} -ge ${BATCH_SIZE} ]]; then
      send_batch_to_loki "systemd" "kernel" "${log_buffer}"
      log_buffer=""
      line_count=0
    fi
  done
  
  # Send remaining batch
  if [[ -n "${log_buffer}" ]]; then
    send_batch_to_loki "systemd" "kernel" "${log_buffer}"
  fi
  
  log_info "Kernel logs collection complete"
}

# Collect Docker container logs
collect_docker_logs() {
  log_info "Collecting Docker container logs..."
  
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available, skipping container logs"
    return 1
  fi
  
  # Get list of running containers
  local containers
  containers=$(docker ps --format "{{.Names}}" 2>/dev/null || echo "")
  
  if [[ -z "${containers}" ]]; then
    log_info "No running containers found"
    return 0
  fi
  
  # Collect logs from each container
  while IFS= read -r container || [[ -n "${container}" ]]; do
    local log_buffer=""
    local line_count=0
    
    log_debug "Collecting logs from container: ${container}"
    
    # Get logs from container
    docker logs --timestamps=true --tail=1000 "${container}" 2>&1 | while IFS= read -r line || [[ -n "${line}" ]]; do
      log_buffer="${log_buffer}${line}"$'\n'
      ((line_count++))
      
      # Send batch
      if [[ ${line_count} -ge ${BATCH_SIZE} ]]; then
        send_batch_to_loki "docker" "${container}" "${log_buffer}"
        log_buffer=""
        line_count=0
      fi
    done
    
    # Send remaining
    if [[ -n "${log_buffer}" ]]; then
      send_batch_to_loki "docker" "${container}" "${log_buffer}"
    fi
  done <<< "${containers}"
  
  log_info "Docker container logs collection complete"
}

# Collect system logs from /var/log
collect_system_logs() {
  log_info "Collecting system logs from ${SHIPPER_LOG_DIR}..."
  
  if [[ ! -d "${SHIPPER_LOG_DIR}" ]]; then
    log_warn "Log directory not found: ${SHIPPER_LOG_DIR}"
    return 1
  fi
  
  # Collect common system logs
  local log_files=(
    "${SHIPPER_LOG_DIR}/syslog"
    "${SHIPPER_LOG_DIR}/auth.log"
    "${SHIPPER_LOG_DIR}/kern.log"
    "${SHIPPER_LOG_DIR}/docker.log"
    "${SHIPPER_LOG_DIR}/dmesg"
  )
  
  for log_file in "${log_files[@]}"; do
    if [[ ! -f "${log_file}" ]]; then
      continue
    fi
    
    log_debug "Processing log file: ${log_file}"
    
    local filename=$(basename "${log_file}")
    local log_buffer=""
    local line_count=0
    
    # Read last 1000 lines from each log file
    tail -n 1000 "${log_file}" 2>/dev/null | while IFS= read -r line || [[ -n "${line}" ]]; do
      log_buffer="${log_buffer}${line}"$'\n'
      ((line_count++))
      
      # Send batch
      if [[ ${line_count} -ge ${BATCH_SIZE} ]]; then
        send_batch_to_loki "syslog" "${filename}" "${log_buffer}"
        log_buffer=""
        line_count=0
      fi
    done
    
    # Send remaining
    if [[ -n "${log_buffer}" ]]; then
      send_batch_to_loki "syslog" "${filename}" "${log_buffer}"
    fi
  done
  
  log_info "System logs collection complete"
}

# Create GitHub issue for kernel panic or critical error
create_issue_on_kernel_error() {
  local error_type="$1"
  local error_message="$2"
  
  if [[ "${GITHUB_ISSUE_ON_KERNEL_ERROR}" != "true" ]]; then
    return 0
  fi
  
  log_info "Creating GitHub issue for kernel error: ${error_type}"
  
  source "${PROJECT_ROOT}/scripts/_common/issue-create-unified.sh" 2>/dev/null || {
    log_warn "Issue creation script not available"
    return 1
  }
  
  copilot_create_issue \
    --title "P0 CRITICAL: Kernel ${error_type} Detected" \
    --body "## Kernel Error Report

**Error Type**: ${error_type}
**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Host**: $(hostname)

### Error Details
\`\`\`
${error_message}
\`\`\`

### Investigation Steps
1. Check kernel logs: \`journalctl -xe\`
2. Verify system resource usage
3. Check hardware health
4. Review recent package updates

### Action Items
- [ ] Investigate root cause
- [ ] Implement fix or workaround
- [ ] Monitor for recurrence
- [ ] Schedule incident review

---
*Auto-generated by System Log Shipper*" \
    --priority P0 \
    --type infrastructure
}

# ------------------------------------------------------------------------------
# MAIN ENTRY POINT
# ------------------------------------------------------------------------------

main() {
  log_info "System Log Shipper starting..."
  log_info "  Loki Endpoint: ${LOKI_ENDPOINT}"
  log_info "  Log Directory: ${SHIPPER_LOG_DIR}"
  
  # Collect logs in order
  collect_kernel_logs || true
  collect_docker_logs || true
  collect_system_logs || true
  
  log_info "System log collection complete"
}

main "$@"

