#!/usr/bin/env bash
# @file        scripts/lib/nas-health.sh
# @module      lib/storage
# @description NAS health monitoring, alerting, and failover logic
# @governance  GOV-002: Immutable, version-controlled
# Issue #1536: Networking, DNS & Performance — NAS Health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"
source "${REPO_ROOT}/scripts/_common/_base-config.env"
source "${REPO_ROOT}/scripts/lib/nas.sh"

# ── Configuration ─────────────────────────────────────────────────────────────
# All configuration via environment variables from _base-config.env
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas}"
NAS_MAX_LATENCY_MS="${NAS_MAX_LATENCY_MS:-100}"
NAS_DISK_USAGE_ALERT_PCT="${NAS_DISK_USAGE_ALERT_PCT:-80}"

# Health check results
NAS_HEALTH_STATUS="UNKNOWN"
NAS_HEALTH_ISSUES=()

# ── Health Check Utilities ─────────────────────────────────────────────────────

# Check host reachability
nas_check_host_reachability() {
  local host="${1}"
  local max_retries=3
  local retry_count=0

  while [ ${retry_count} -lt ${max_retries} ]; do
    if ping -c 1 -W 2 "${host}" >/dev/null 2>&1; then
      log_info "NAS host (${host}) is reachable"
      return 0
    fi
    retry_count=$((retry_count + 1))
    [ ${retry_count} -lt ${max_retries} ] && sleep 2
  done

  log_error "NAS host (${host}) is NOT reachable after ${max_retries} attempts"
  NAS_HEALTH_ISSUES+=("NAS host unreachable")
  return 1
}

# Check mount status and attempt recovery
nas_check_mount_status() {
  local mount_point="${1}"
  local nas_host="${2}"

  if mountpoint -q "${mount_point}" 2>/dev/null; then
    log_info "NAS is mounted at ${mount_point}"
    return 0
  fi

  log_warn "NAS not mounted at ${mount_point}, attempting recovery..."

  # Attempt to remount with exponential backoff
  local max_retries=3
  local retry_count=0

  while [ ${retry_count} -lt ${max_retries} ]; do
    log_info "Remount attempt $((retry_count + 1))/${max_retries}..."

    # Try lazy unmount first
    umount -l "${mount_point}" >/dev/null 2>&1 || true

    # Attempt mount
    local mount_opts="rsize=131072,wsize=131072,proto=tcp,noatime,nodiratime,hard,intr"
    if mount -t nfs -o "${mount_opts}" "${nas_host}:/export/persistent/paperclip" "${mount_point}" >/dev/null 2>&1; then
      log_info "NAS remounted successfully"
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [ ${retry_count} -lt ${max_retries} ]; then
      local wait_time=$((2 ** retry_count))
      log_warn "Remount failed, retrying in ${wait_time}s..."
      sleep "${wait_time}"
    fi
  done

  log_error "Failed to remount NAS after ${max_retries} attempts"
  NAS_HEALTH_ISSUES+=("NAS mount failed")
  return 1
}

# Check mount latency
nas_check_latency() {
  local mount_point="${1}"
  local max_latency_ms="${2}"

  local start_time end_time latency_ms
  start_time=$(date +%s%N)
  stat "${mount_point}" >/dev/null 2>&1 || true
  end_time=$(date +%s%N)

  latency_ms=$(( (end_time - start_time) / 1000000 ))

  if [ ${latency_ms} -lt ${max_latency_ms} ]; then
    log_info "NAS latency OK: ${latency_ms}ms (threshold: ${max_latency_ms}ms)"
    return 0
  else
    log_error "NAS latency HIGH: ${latency_ms}ms (threshold: ${max_latency_ms}ms)"
    NAS_HEALTH_ISSUES+=("NAS latency ${latency_ms}ms")
    return 1
  fi
}

# Check disk usage
nas_check_disk_usage() {
  local mount_point="${1}"
  local alert_threshold_pct="${2}"

  local usage_pct
  usage_pct=$(df "${mount_point}" 2>/dev/null | awk 'NR==2 {print int($5)}' || echo "0")

  if [ ${usage_pct} -lt ${alert_threshold_pct} ]; then
    log_info "NAS disk usage OK: ${usage_pct}%"
    return 0
  else
    log_error "NAS disk usage HIGH: ${usage_pct}% (threshold: ${alert_threshold_pct}%)"
    NAS_HEALTH_ISSUES+=("NAS disk ${usage_pct}% full")
    return 1
  fi
}

# ── Comprehensive Health Check ─────────────────────────────────────────────────

nas_comprehensive_health_check() {
  local nas_host="${1:-${NAS_HOST}}"
  local mount_point="${2:-${NAS_MOUNT_POINT}}"
  local max_latency_ms="${3:-${NAS_MAX_LATENCY_MS}}"
  local disk_alert_pct="${4:-${NAS_DISK_USAGE_ALERT_PCT}}"

  log_info "=== NAS Comprehensive Health Check ==="

  # Reset issues
  NAS_HEALTH_ISSUES=()
  NAS_HEALTH_STATUS="HEALTHY"

  # Check 1: Host reachability
  if ! nas_check_host_reachability "${nas_host}"; then
    NAS_HEALTH_STATUS="CRITICAL"
    return 1
  fi

  # Check 2: Mount status
  if ! nas_check_mount_status "${mount_point}" "${nas_host}"; then
    NAS_HEALTH_STATUS="CRITICAL"
    return 1
  fi

  # Check 3: Latency
  if ! nas_check_latency "${mount_point}" "${max_latency_ms}"; then
    NAS_HEALTH_STATUS="DEGRADED"
  fi

  # Check 4: Disk usage
  if ! nas_check_disk_usage "${mount_point}" "${disk_alert_pct}"; then
    NAS_HEALTH_STATUS="WARNING"
  fi

  # Report status
  if [ ${#NAS_HEALTH_ISSUES[@]} -gt 0 ]; then
    log_warn "NAS Health Status: ${NAS_HEALTH_STATUS}"
    log_warn "Issues detected:"
    for issue in "${NAS_HEALTH_ISSUES[@]}"; do
      log_warn "  - ${issue}"
    done
    return 1
  else
    log_info "NAS Health Status: ${NAS_HEALTH_STATUS}"
    return 0
  fi
}

# ── Alerting ───────────────────────────────────────────────────────────────────

# Send alert to monitoring system (Prometheus, Alertmanager)
nas_send_alert() {
  local severity="${1}"  # CRITICAL, WARNING, INFO
  local message="${2}"

  # Log to syslog
  logger -t nas-health -p "user.${severity,,}" "${message}"

  # If alerting webhook is configured, send HTTP POST
  if [ -n "${NAS_ALERT_WEBHOOK:-}" ]; then
    local payload
    payload=$(jq -n \
      --arg severity "${severity}" \
      --arg message "${message}" \
      --arg host "$(hostname)" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{severity: $severity, message: $message, host: $host, timestamp: $timestamp}')

    curl -X POST \
      -H "Content-Type: application/json" \
      -d "${payload}" \
      "${NAS_ALERT_WEBHOOK}" \
      >/dev/null 2>&1 || log_warn "Failed to send alert webhook"
  fi
}

# ── Continuous Monitoring (for cron/systemd timer) ──────────────────────────────

nas_monitor_continuous() {
  local check_interval="${1:-300}"  # Default 5 minutes

  log_info "Starting continuous NAS monitoring (interval: ${check_interval}s)"

  while true; do
    if ! nas_comprehensive_health_check; then
      nas_send_alert "ERROR" "NAS health check failed: ${NAS_HEALTH_ISSUES[*]}"
    fi

    sleep "${check_interval}"
  done
}

# ── Export Functions ───────────────────────────────────────────────────────────

export -f nas_check_host_reachability
export -f nas_check_mount_status
export -f nas_check_latency
export -f nas_check_disk_usage
export -f nas_comprehensive_health_check
export -f nas_send_alert
export -f nas_monitor_continuous
