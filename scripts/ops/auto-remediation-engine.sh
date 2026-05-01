#!/bin/bash
# Automated remediation engine for code-server infrastructure
# Self-healing for common operational issues
# Controlled via policies and safeguards

set -euo pipefail

trap 'log_error "Remediation failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load dependencies
source "${SCRIPT_DIR}/../lib/alert-router.sh" 2>/dev/null || true

# Configuration
REMEDIATION_CONFIG="${REMEDIATION_CONFIG:-.remediation/config.env}"
REMEDIATION_LOG="/tmp/code-server-remediation.log"
REMEDIATION_STATE="/tmp/code-server-remediation"
DRY_RUN="${DRY_RUN:-false}"
SAFE_MODE="${SAFE_MODE:-true}"

# Default remediation policies
REMEDIATE_UNHEALTHY_CONTAINERS="${REMEDIATE_UNHEALTHY_CONTAINERS:-true}"
REMEDIATE_DISK_SPACE="${REMEDIATE_DISK_SPACE:-true}"
REMEDIATE_TERRAFORM_DRIFT="${REMEDIATE_TERRAFORM_DRIFT:-false}"  # Disabled by default (risky)
MAX_AUTO_RESTARTS_PER_HOUR="${MAX_AUTO_RESTARTS_PER_HOUR:-5}"
DISK_CLEANUP_THRESHOLD="${DISK_CLEANUP_THRESHOLD:-85}"
DRIFT_REMEDIATION_THRESHOLD="${DRIFT_REMEDIATION_THRESHOLD:-10}"

# Hosts
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"

mkdir -p "$REMEDIATION_STATE"
mkdir -p "$(dirname "$REMEDIATION_LOG")"

# Initialize alert router if available
init_alerts 2>/dev/null || true

# ============================================================================
# LOGGING & TRACKING
# ============================================================================

log_remediation() {
  local action="$1"
  local status="$2"
  local message="$3"
  local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  
  echo "[$timestamp] [$action] [$status] $message" | tee -a "$REMEDIATION_LOG"
  
  if [[ "$status" == "ERROR" ]]; then
    send_alert ERROR remediation-engine "$action failed" "$message"
  fi
}

# Track remediation count to prevent infinite loops
track_remediation() {
  local container="$1"
  local host="$2"
  local state_file="${REMEDIATION_STATE}/restart-${host}-${container}"
  local current_hour=$(date +%Y%m%d%H)
  
  if [[ -f "$state_file" ]]; then
    local last_hour=$(cat "$state_file")
    if [[ "$last_hour" == "$current_hour" ]]; then
      local count=$(grep -c "$container" "${REMEDIATION_STATE}/restarts-${current_hour}" 2>/dev/null || echo 0)
      return "$count"
    fi
  fi
  
  echo "$current_hour" > "$state_file"
  return 0
}

# ============================================================================
# REMEDIATION: UNHEALTHY CONTAINERS
# ============================================================================

remediate_unhealthy_containers() {
  [[ "$REMEDIATE_UNHEALTHY_CONTAINERS" != "true" ]] && return 0
  
  echo "Checking for unhealthy containers on primary host..."
  
  local unhealthy_containers
  unhealthy_containers=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'docker ps --format "{{.Names}} {{.Status}}" | grep -v "healthy" | grep -v "Up" | awk "{print \$1}"' 2>/dev/null || echo ""
  )
  
  if [[ -z "$unhealthy_containers" ]]; then
    echo "✓ No unhealthy containers found on primary"
    return 0
  fi
  
  while read -r container; do
    [[ -z "$container" ]] && continue
    
    log_remediation "RESTART_CONTAINER" "ATTEMPT" "Container: $container (primary)"
    
    # Check restart count
    local restart_count
    restart_count=$(track_remediation "$container" "primary")
    
    if (( restart_count >= MAX_AUTO_RESTARTS_PER_HOUR )); then
      log_remediation "RESTART_CONTAINER" "SKIPPED" "Max restarts/hour reached for $container"
      send_alert WARNING remediation-engine "Max restarts reached" "Container $container exceeded $MAX_AUTO_RESTARTS_PER_HOUR restarts/hour"
      continue
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_remediation "RESTART_CONTAINER" "DRY_RUN" "Would restart: $container"
    else
      if ssh "akushnir@${PRIMARY_HOST}" "docker restart $container" 2>/dev/null; then
        log_remediation "RESTART_CONTAINER" "SUCCESS" "Restarted: $container"
        send_alert INFO remediation-engine "Container restarted" "Auto-restarted unhealthy container: $container"
        echo "$container" >> "${REMEDIATION_STATE}/restarts-$(date +%Y%m%d%H)"
      else
        log_remediation "RESTART_CONTAINER" "ERROR" "Failed to restart: $container"
        send_alert ERROR remediation-engine "Container restart failed" "Could not restart: $container"
      fi
    fi
  done <<< "$unhealthy_containers"
  
  # Check replica host
  echo "Checking for unhealthy containers on replica host..."
  
  local replica_unhealthy
  replica_unhealthy=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'docker ps --format "{{.Names}} {{.Status}}" | grep -v "healthy" | grep -v "Up" | awk "{print \$1}"' 2>/dev/null || echo ""
  )
  
  if [[ -z "$replica_unhealthy" ]]; then
    echo "✓ No unhealthy containers found on replica"
    return 0
  fi
  
  while read -r container; do
    [[ -z "$container" ]] && continue
    
    log_remediation "RESTART_CONTAINER" "ATTEMPT" "Container: $container (replica)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_remediation "RESTART_CONTAINER" "DRY_RUN" "Would restart: $container (replica)"
    else
      if ssh "akushnir@${REPLICA_HOST}" "docker restart $container" 2>/dev/null; then
        log_remediation "RESTART_CONTAINER" "SUCCESS" "Restarted: $container (replica)"
        send_alert INFO remediation-engine "Container restarted on replica" "Auto-restarted: $container"
      else
        log_remediation "RESTART_CONTAINER" "ERROR" "Failed to restart: $container (replica)"
        send_alert ERROR remediation-engine "Replica container restart failed" "Could not restart: $container"
      fi
    fi
  done <<< "$replica_unhealthy"
}

# ============================================================================
# REMEDIATION: DISK SPACE
# ============================================================================

remediate_disk_space() {
  [[ "$REMEDIATE_DISK_SPACE" != "true" ]] && return 0
  
  echo "Checking disk space on primary host..."
  
  local primary_usage
  primary_usage=$(
    ssh "akushnir@${PRIMARY_HOST}" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0"
  )
  
  if (( primary_usage >= DISK_CLEANUP_THRESHOLD )); then
    log_remediation "DISK_CLEANUP" "ATTEMPT" "Primary disk usage: ${primary_usage}%"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_remediation "DISK_CLEANUP" "DRY_RUN" "Would clean up Docker artifacts"
    else
      # Clean up Docker artifacts (stopped containers, dangling images, old logs)
      if ssh "akushnir@${PRIMARY_HOST}" \
        'docker system prune -af --volumes 2>/dev/null; docker image prune -af 2>/dev/null' \
        2>/dev/null; then
        
        local new_usage
        new_usage=$(
          ssh "akushnir@${PRIMARY_HOST}" \
          'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "$primary_usage"
        )
        
        log_remediation "DISK_CLEANUP" "SUCCESS" "Primary disk: ${primary_usage}% → ${new_usage}%"
        send_alert INFO remediation-engine "Disk space cleaned" "Primary: ${primary_usage}% → ${new_usage}%"
      else
        log_remediation "DISK_CLEANUP" "ERROR" "Failed to clean primary disk"
        send_alert ERROR remediation-engine "Disk cleanup failed" "Could not clean up Docker artifacts on primary"
      fi
    fi
  else
    echo "✓ Primary disk usage OK: ${primary_usage}%"
  fi
  
  echo "Checking disk space on replica host..."
  
  local replica_usage
  replica_usage=$(
    ssh "akushnir@${REPLICA_HOST}" \
    'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "0"
  )
  
  if (( replica_usage >= DISK_CLEANUP_THRESHOLD )); then
    log_remediation "DISK_CLEANUP" "ATTEMPT" "Replica disk usage: ${replica_usage}%"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_remediation "DISK_CLEANUP" "DRY_RUN" "Would clean up Docker artifacts on replica"
    else
      if ssh "akushnir@${REPLICA_HOST}" \
        'docker system prune -af --volumes 2>/dev/null; docker image prune -af 2>/dev/null' \
        2>/dev/null; then
        
        local new_replica_usage
        new_replica_usage=$(
          ssh "akushnir@${REPLICA_HOST}" \
          'df /home | tail -1 | awk "{print \$5}" | sed "s/%//"' 2>/dev/null || echo "$replica_usage"
        )
        
        log_remediation "DISK_CLEANUP" "SUCCESS" "Replica disk: ${replica_usage}% → ${new_replica_usage}%"
        send_alert INFO remediation-engine "Replica disk cleaned" "Replica: ${replica_usage}% → ${new_replica_usage}%"
      else
        log_remediation "DISK_CLEANUP" "ERROR" "Failed to clean replica disk"
        send_alert ERROR remediation-engine "Replica disk cleanup failed" "Could not clean Docker artifacts"
      fi
    fi
  else
    echo "✓ Replica disk usage OK: ${replica_usage}%"
  fi
}

# ============================================================================
# REMEDIATION: TERRAFORM DRIFT (RISKY - DISABLED BY DEFAULT)
# ============================================================================

remediate_terraform_drift() {
  [[ "$REMEDIATE_TERRAFORM_DRIFT" != "true" ]] && return 0
  [[ "$SAFE_MODE" == "true" ]] && {
    log_remediation "DRIFT_REMEDIATION" "BLOCKED" "Disabled in SAFE_MODE"
    return 0
  }
  
  echo "Checking Terraform drift..."
  
  local drift_count
  drift_count=$(
    cd "${REPO_ROOT}/terraform/environments/private" && \
    terraform plan -json 2>/dev/null | \
    jq -s 'map(select(.type == "resource_drift")) | length' 2>/dev/null || echo "0"
  )
  drift_count=$(echo "$drift_count" | tr -d ' \n')
  
  if (( drift_count >= DRIFT_REMEDIATION_THRESHOLD )); then
    log_remediation "DRIFT_REMEDIATION" "BLOCKED" "Drift exceeds ${DRIFT_REMEDIATION_THRESHOLD} resources ($drift_count > threshold)"
    send_alert ERROR remediation-engine "Drift remediation blocked" "Drift count $drift_count exceeds threshold $DRIFT_REMEDIATION_THRESHOLD"
    return 1
  fi
  
  if (( drift_count > 0 )); then
    log_remediation "DRIFT_REMEDIATION" "ATTEMPT" "Drift detected: $drift_count resources"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_remediation "DRIFT_REMEDIATION" "DRY_RUN" "Would apply Terraform (drift: $drift_count)"
    else
      cd "${REPO_ROOT}/terraform/environments/private"
      
      if terraform apply -auto-approve 2>&1 | tee -a "$REMEDIATION_LOG"; then
        log_remediation "DRIFT_REMEDIATION" "SUCCESS" "Applied Terraform - drift resolved"
        send_alert INFO remediation-engine "Terraform drift remediated" "Auto-applied Terraform, drift resolved"
      else
        log_remediation "DRIFT_REMEDIATION" "ERROR" "Terraform apply failed"
        send_alert ERROR remediation-engine "Terraform remediation failed" "Auto-remediation attempt failed"
        return 1
      fi
    fi
  else
    echo "✓ No drift detected"
  fi
}

# ============================================================================
# MAIN REMEDIATION LOOP
# ============================================================================

main() {
  echo "============================================"
  echo "Automated Remediation Engine"
  echo "============================================"
  echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "DRY_RUN: $DRY_RUN"
  echo "SAFE_MODE: $SAFE_MODE"
  echo ""
  
  # Load config if available
  [[ -f "$REMEDIATION_CONFIG" ]] && source "$REMEDIATION_CONFIG"
  
  local remediations_attempted=0
  local remediations_success=0
  
  # Run all remediation checks
  remediate_unhealthy_containers && remediations_success+=1 || true
  remediations_attempted+=1
  
  remediate_disk_space && remediations_success+=1 || true
  remediations_attempted+=1
  
  remediate_terraform_drift && remediations_success+=1 || true
  remediations_attempted+=1
  
  echo ""
  echo "============================================"
  echo "Remediation Summary"
  echo "============================================"
  echo "Checks run: $remediations_attempted"
  echo "Successful: $remediations_success"
  echo "Log: $REMEDIATION_LOG"
  
  if (( remediations_success == remediations_attempted )); then
    echo "Status: ✓ All checks passed"
    return 0
  else
    echo "Status: ⚠ Some checks failed or blocked"
    return 1
  fi
}

main "$@"
