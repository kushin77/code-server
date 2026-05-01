#!/bin/bash
#
# Drift monitoring watchdog for code-server deployment
# Runs periodically to detect configuration drift and health degradation
# Suitable for: cron job or systemd timer
#

set -euo pipefail

trap 'log_alert "ERROR" "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/environments/private"
STATE_DIR="/tmp/code-server-watchdog"
ALERT_LOG="${STATE_DIR}/alerts.log"
LAST_DRIFT_STATE="${STATE_DIR}/last-drift-state"
LAST_HEALTH_STATE="${STATE_DIR}/last-health-state"

# Load alert router
source "${SCRIPT_DIR}/../lib/alert-router.sh" || {
  echo "ERROR: Failed to load alert router module"
  exit 1
}

# Ensure state directory exists
mkdir -p "${STATE_DIR}"
mkdir -p "$(dirname "$ALERT_HISTORY")"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
ALERT_THRESHOLD_DRIFT_INCREASE="${ALERT_THRESHOLD_DRIFT_INCREASE:-5}"
ALERT_THRESHOLD_HEALTH="${ALERT_THRESHOLD_HEALTH:-1}"
ALERT_THRESHOLD_PARITY="${ALERT_THRESHOLD_PARITY:-2}"
ALERT_THRESHOLD_DISK="${ALERT_THRESHOLD_DISK:-80}"

log_alert() {
  local severity="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  echo "[${timestamp}] ${severity}: ${message}" >> "${ALERT_LOG}"
  echo "[${timestamp}] ${severity}: ${message}" >&2
  
  # Send via alert router if enabled
  local level="$severity"
  [[ "$severity" == "WARNING" ]] && level="WARNING"
  [[ "$severity" == "ERROR" ]] && level="ERROR"
  [[ "$severity" == "INFO" ]] && level="INFO"
  
  # Only send non-info alerts via router
  if [[ "$level" != "INFO" ]]; then
    send_alert "$level" "drift-watchdog" "$severity" "$message"
  fi
}

# Check 1: Terraform drift detection
check_terraform_drift() {
  local current_drift
  local previous_drift
  
  echo "Checking Terraform drift..."
  
  # Run drift detection - count resource_drift events, not lines
  current_drift=$(
    cd "${TF_DIR}" && \
    terraform plan -json 2>/dev/null | \
    jq -s '[.[] | select(.type == "resource_drift")] | length' 2>/dev/null || echo "0"
  )
  current_drift=$(echo "$current_drift" | tr -d ' \n')
  
  # Load previous state
  if [[ -f "${LAST_DRIFT_STATE}" ]]; then
    previous_drift=$(cat "${LAST_DRIFT_STATE}" | tr -d ' \n')
  else
    previous_drift=0
  fi
  
  # Save current state
  echo "${current_drift}" > "${LAST_DRIFT_STATE}"
  
  # Check if drift increased significantly
  local drift_increase=$((current_drift - previous_drift))
  
  if (( drift_increase > ALERT_THRESHOLD_DRIFT_INCREASE )); then
    log_alert "WARNING" "Terraform drift increased significantly: +${drift_increase} resources (${previous_drift} → ${current_drift})"
    return 1
  fi
  
  if (( drift_increase < -2 )); then
    log_alert "INFO" "Terraform drift improved: ${drift_increase} resources (${previous_drift} → ${current_drift})"
  fi
  
  echo "  Drift check: OK (${current_drift} resources, change: ${drift_increase:+${drift_increase}})"
  return 0
}

# Check 2: Container health status
check_container_health() {
  echo "Checking container health..."
  
  local unhealthy_count=0
  local unhealthy_containers=()
  
  # Check primary host
  local primary_unhealthy
  primary_unhealthy=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'docker ps --format "{{.Names}} {{.Status}}" | grep -v "healthy" | grep -v "Up"' 2>/dev/null | \
    wc -l || echo "0"
  )
  
  unhealthy_count=$((unhealthy_count + primary_unhealthy))
  
  # Check replica host
  local replica_unhealthy
  replica_unhealthy=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'docker ps --format "{{.Names}} {{.Status}}" | grep -v "healthy" | grep -v "Up"' 2>/dev/null | \
    wc -l || echo "0"
  )
  
  unhealthy_count=$((unhealthy_count + replica_unhealthy))
  
  # Save state
  echo "${unhealthy_count}" > "${LAST_HEALTH_STATE}"
  
  # Check if unhealthy containers exceed threshold
  if (( unhealthy_count > ALERT_THRESHOLD_HEALTH )); then
    log_alert "WARNING" "Unhealthy containers detected: ${unhealthy_count}"
    return 1
  fi
  
  echo "  Health check: OK (${unhealthy_count} unhealthy)"
  return 0
}

# Check 3: Container count parity
check_container_parity() {
  echo "Checking container count parity..."
  
  local primary_count
  local replica_count
  
  primary_count=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'docker ps -q | wc -l' 2>/dev/null || echo "0"
  )
  
  replica_count=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'docker ps -q | wc -l' 2>/dev/null || echo "0"
  )
  
  local diff=$((primary_count - replica_count))
  
  if (( diff < 0 )); then
    diff=$((diff * -1))
  fi
  
  # Allow small differences (configurable via ALERT_THRESHOLD_PARITY)
  if (( diff > ALERT_THRESHOLD_PARITY )); then
    log_alert "WARNING" "Container count mismatch: primary=${primary_count}, replica=${replica_count}"
    return 1
  fi
  
  echo "  Parity check: OK (primary=${primary_count}, replica=${replica_count})"
  return 0
}

# Check 4: Disk space availability
check_disk_space() {
  echo "Checking disk space..."
  
  local threshold_percent="${ALERT_THRESHOLD_DISK}"
  local primary_usage
  local replica_usage
  
  primary_usage=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0"
  )
  
  replica_usage=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0"
  )
  
  if (( primary_usage > threshold_percent )); then
    log_alert "WARNING" "High disk usage on primary: ${primary_usage}%"
    return 1
  fi
  
  if (( replica_usage > threshold_percent )); then
    log_alert "WARNING" "High disk usage on replica: ${replica_usage}%"
    return 1
  fi
  
  echo "  Disk space: OK (primary=${primary_usage}%, replica=${replica_usage}%)"
  return 0
}

# Check 5: Keepalived VRRP status
check_keepalived_status() {
  echo "Checking Keepalived VRRP..."
  
  # Check if keepalived containers are running
  local primary_keepalived
  local replica_keepalived
  
  primary_keepalived=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'docker ps | grep keepalived | wc -l' 2>/dev/null || echo "0"
  )
  
  replica_keepalived=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'docker ps | grep keepalived | wc -l' 2>/dev/null || echo "0"
  )
  
  if (( primary_keepalived == 0 )); then
    log_alert "ERROR" "Keepalived not running on primary"
    return 1
  fi
  
  if (( replica_keepalived == 0 )); then
    log_alert "ERROR" "Keepalived not running on replica"
    return 1
  fi
  
  echo "  VRRP status: OK"
  return 0
}

# Main execution
main() {
  local checks_passed=0
  local checks_failed=0
  
  echo "============================================"
  echo "Drift Monitoring Watchdog"
  echo "============================================"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  
  # Run all checks
  check_terraform_drift && ((checks_passed++)) || ((checks_failed++))
  check_container_health && ((checks_passed++)) || ((checks_failed++))
  check_container_parity && ((checks_passed++)) || ((checks_failed++))
  check_disk_space && ((checks_passed++)) || ((checks_failed++))
  check_keepalived_status && ((checks_passed++)) || ((checks_failed++))
  
  echo ""
  echo "============================================"
  echo "Watchdog Summary"
  echo "============================================"
  echo "Checks passed: ${checks_passed}"
  echo "Checks failed: ${checks_failed}"
  
  if [[ -f "${ALERT_LOG}" ]] && (( checks_failed > 0 )); then
    echo ""
    echo "Recent alerts (last 10):"
    tail -10 "${ALERT_LOG}"
  fi
  
  # Return appropriate exit code
  if (( checks_failed > 0 )); then
    return 1
  else
    echo "All checks passed ✓"
    return 0
  fi
}

main "$@"
