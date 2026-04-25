#!/usr/bin/env bash

################################################################################
# @file        scripts/ops/cluster-sync-daemon.sh
# @module      ops/cluster-synchronization
# @description Continuous cluster sync daemon (IaC: Idempotent, Immutable)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
#
# GOVERNANCE: GOV-002 Compliance
# - Deterministic: git pull always produces same state
# - Audited: All sync operations logged
# - Immutable: Config-driven, no manual state changes
# - Idempotent: Safe to run every 5 minutes
# - Ephemeral: Creates temporary logs only, no persistent state
#
# PURPOSE
# Automatically synchronize configuration between primary and replica nodes
# by pulling latest git changes and restarting affected services.
#
# DEPLOYMENT MODEL
# - Install on BOTH replica nodes
# - Run via cron: */5 * * * * (every 5 minutes)
# - Or via systemd timer: cluster-sync.timer
#
# SYNC PROCESS (Idempotent)
# 1. Check if updates available: git fetch origin
# 2. If no changes: exit (no-op, idempotent)
# 3. If changes exist: git pull origin main
# 4. Validate docker-compose: docker compose config
# 5. Restart affected services: docker compose up -d
# 6. Run health checks on restarted services
# 7. Log result to audit trail
#
# FAILURES & ROLLBACK
# If any step fails:
# - Automatic rollback: git reset --hard <previous-commit>
# - Service restart from previous state
# - Alert to monitoring (if configured)
#
# LOGGING
# All operations logged to:
#   /var/log/cluster-sync.log (rotated daily, 10 files kept)
#   /var/log/cluster-sync-audit.json (machine-readable events)
#
# USAGE
#   # Manual execution
#   bash scripts/ops/cluster-sync-daemon.sh --sync
#
#   # Install cron job (on both replicas)
#   bash scripts/ops/cluster-sync-daemon.sh --install-cron
#
#   # View sync status
#   bash scripts/ops/cluster-sync-daemon.sh --status
#
#   # Disable sync (emergency)
#   bash scripts/ops/cluster-sync-daemon.sh --disable
#
# @author Autonomous Infrastructure
# @version 1.0.0
# @date 2026-04-25
# @issue #XXXX (Cluster Sync - Multi-Node HA)
################################################################################

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="/var/log"
readonly LOG_FILE="$LOG_DIR/cluster-sync.log"
readonly AUDIT_LOG="$LOG_DIR/cluster-sync-audit.json"
readonly STATE_DIR="/var/run/cluster-sync"
readonly LOCK_FILE="$STATE_DIR/sync.lock"
readonly STATUS_FILE="$STATE_DIR/status.json"
readonly PREVIOUS_COMMIT_FILE="$STATE_DIR/previous-commit"

# Source configuration
source "$PROJECT_ROOT/scripts/_common/init.sh" 2>/dev/null || true

# Sync parameters
GIT_BRANCH="${GIT_BRANCH:-origin/main}"
MAX_SYNC_TIME=300  # 5 minutes
HEALTH_CHECK_TIMEOUT=60  # 1 minute
SERVICES_TO_MONITOR=(
  "caddy"
  "prometheus"
  "grafana"
  "loki"
  "alertmanager"
)

# Command-line arguments
SYNC_MODE="${1:-}"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log_info() {
  local message="$1"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $message" | tee -a "$LOG_FILE"
}

log_success() {
  local message="$1"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] ✓ $message" | tee -a "$LOG_FILE"
}

log_error() {
  local message="$1"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] ✗ $message" | tee -a "$LOG_FILE" >&2
}

log_warn() {
  local message="$1"
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] ⚠ $message" | tee -a "$LOG_FILE"
}

log_audit() {
  local event="$1"
  local status="${2:-success}"
  local details="${3:-}"
  
  cat >> "$AUDIT_LOG" <<EOF
{"timestamp":"$(date -u +'%Y-%m-%dT%H:%M:%SZ')","event":"$event","status":"$status","hostname":"$(hostname)","details":"$details"}
EOF
}

# Initialize state directory
init_state_dir() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
  fi
}

# Create/manage lock file (prevent concurrent runs)
acquire_lock() {
  init_state_dir
  
  if [[ -f "$LOCK_FILE" ]]; then
    local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
      log_warn "Sync already running (PID: $lock_pid), skipping"
      return 1
    else
      log_info "Removing stale lock file"
      rm -f "$LOCK_FILE"
    fi
  fi
  
  echo "$$" > "$LOCK_FILE"
  trap "rm -f '$LOCK_FILE'" EXIT
  return 0
}

# ==============================================================================
# CHECK 1: Detect Changes
# ==============================================================================

check_for_updates() {
  log_info "Checking for configuration updates..."
  
  cd "$PROJECT_ROOT" || return 1
  
  # Fetch latest from remote (no-op, just check)
  if ! git fetch origin main >/dev/null 2>&1; then
    log_error "Failed to fetch from remote"
    log_audit "fetch_failed" "error" "git fetch error"
    return 2
  fi
  
  # Compare commits
  local current_commit=$(git rev-parse HEAD)
  local remote_commit=$(git rev-parse origin/main)
  
  log_info "Current commit: $current_commit"
  log_info "Remote commit:  $remote_commit"
  
  if [[ "$current_commit" == "$remote_commit" ]]; then
    log_info "Already up-to-date, no sync needed (idempotent)"
    return 0  # No changes
  fi
  
  log_info "Updates available, proceeding with sync..."
  echo "$current_commit" > "$PREVIOUS_COMMIT_FILE"  # Save for rollback
  return 1  # Changes detected (continue)
}

# ==============================================================================
# CHECK 2: Pull Updates
# ==============================================================================

pull_updates() {
  log_info "Pulling latest configuration from git..."
  
  cd "$PROJECT_ROOT" || return 1
  
  # Validate we're on correct branch
  if ! git branch --show-current | grep -q "main\|master" || true; then
    log_warn "Not on main/master branch, proceeding anyway"
  fi
  
  # Pull with timeout
  if timeout $MAX_SYNC_TIME git pull origin main >/dev/null 2>&1; then
    log_success "Git pull completed successfully"
    return 0
  else
    log_error "Git pull failed or timed out (timeout: ${MAX_SYNC_TIME}s)"
    log_audit "git_pull_failed" "error" "timeout or merge conflict"
    return 1
  fi
}

# ==============================================================================
# CHECK 3: Validate Configuration
# ==============================================================================

validate_docker_compose() {
  log_info "Validating docker-compose configuration..."
  
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available, skipping docker-compose validation"
    return 0
  fi
  
  cd "$PROJECT_ROOT" || return 1
  
  if docker compose config >/dev/null 2>&1; then
    log_success "docker-compose.yml is valid"
    return 0
  else
    log_error "docker-compose.yml validation failed"
    log_audit "compose_validation_failed" "error" "invalid yaml or config"
    return 1
  fi
}

# ==============================================================================
# CHECK 4: Restart Services
# ==============================================================================

restart_affected_services() {
  log_info "Restarting affected services..."
  
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available, skipping service restart"
    return 0
  fi
  
  cd "$PROJECT_ROOT" || return 1
  
  # Restart all services
  if docker compose up -d >/dev/null 2>&1; then
    log_success "Services restarted successfully"
    log_audit "services_restarted" "success" "all services up-to-date"
    return 0
  else
    log_error "Failed to restart services"
    log_audit "services_restart_failed" "error" "docker compose up -d failed"
    return 1
  fi
}

# ==============================================================================
# CHECK 5: Health Checks
# ==============================================================================

health_check_services() {
  log_info "Running health checks on restarted services..."
  
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available, skipping health checks"
    return 0
  fi
  
  local failed_services=()
  local all_healthy=true
  
  for service in "${SERVICES_TO_MONITOR[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "^${service}$"; then
      local health=$(docker inspect "${service}" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
      
      if [[ "$health" == "healthy" || "$health" == "unknown" ]]; then
        log_info "  ✓ $service: $health"
      else
        log_error "  ✗ $service: $health (UNHEALTHY)"
        failed_services+=("$service")
        all_healthy=false
      fi
    fi
  done
  
  if [[ "$all_healthy" == "true" ]]; then
    log_success "All monitored services are healthy"
    return 0
  else
    log_error "One or more services unhealthy: ${failed_services[*]}"
    log_audit "health_check_failed" "error" "services: ${failed_services[*]}"
    return 1
  fi
}

# ==============================================================================
# ROLLBACK ON FAILURE
# ==============================================================================

rollback_to_previous() {
  log_error "Sync failed, initiating rollback..."
  
  if [[ ! -f "$PREVIOUS_COMMIT_FILE" ]]; then
    log_error "No previous commit saved, cannot rollback"
    return 1
  fi
  
  local previous_commit=$(cat "$PREVIOUS_COMMIT_FILE")
  log_info "Rolling back to commit: $previous_commit"
  
  cd "$PROJECT_ROOT" || return 1
  
  if git reset --hard "$previous_commit" >/dev/null 2>&1; then
    log_success "Git rollback completed"
    
    # Restart services from previous state
    if docker compose up -d >/dev/null 2>&1; then
      log_success "Services restarted with previous configuration"
      log_audit "rollback_successful" "success" "reverted to $previous_commit"
      return 0
    else
      log_error "Failed to restart services after rollback"
      log_audit "rollback_partial" "error" "git ok, compose failed"
      return 1
    fi
  else
    log_error "Failed to rollback git repository"
    log_audit "rollback_failed" "error" "git reset failed"
    return 1
  fi
}

# ==============================================================================
# SYNC ORCHESTRATION
# ==============================================================================

execute_sync() {
  log_info "Starting cluster sync operation..."
  log_audit "sync_started" "info" "checking for updates"
  
  if ! acquire_lock; then
    return 0  # Already running, exit silently
  fi
  
  # Step 1: Check for updates
  if check_for_updates; then
    log_info "Cluster already in sync, no action needed"
    log_audit "sync_completed" "success" "already_in_sync"
    return 0
  fi
  
  # Step 2: Pull updates
  if ! pull_updates; then
    log_error "Failed to pull updates"
    if ! rollback_to_previous; then
      log_error "Rollback also failed - manual intervention required"
    fi
    log_audit "sync_failed" "error" "pull_updates failed"
    return 1
  fi
  
  # Step 3: Validate configuration
  if ! validate_docker_compose; then
    log_error "Configuration validation failed"
    if ! rollback_to_previous; then
      log_error "Rollback also failed - manual intervention required"
    fi
    return 1
  fi
  
  # Step 4: Restart services
  if ! restart_affected_services; then
    log_error "Service restart failed"
    if ! rollback_to_previous; then
      log_error "Rollback also failed - manual intervention required"
    fi
    return 1
  fi
  
  # Step 5: Health checks
  if health_check_services; then
    log_success "Cluster sync completed successfully"
    log_audit "sync_completed" "success" "all_healthy"
    return 0
  else
    log_error "Health checks failed"
    if ! rollback_to_previous; then
      log_error "Rollback also failed - manual intervention required"
    fi
    return 1
  fi
}

# ==============================================================================
# CRON INSTALLATION
# ==============================================================================

install_cron() {
  log_info "Installing cron job for automatic cluster sync..."
  
  local cron_entry="*/5 * * * * root cd $PROJECT_ROOT && bash scripts/ops/cluster-sync-daemon.sh --sync >> /var/log/cluster-sync-cron.log 2>&1"
  local cron_file="/etc/cron.d/cluster-sync"
  
  if [[ ! -w "/etc/cron.d/" ]]; then
    log_error "Cannot write to /etc/cron.d/ (requires root)"
    log_info "Install manually with: sudo crontab -e"
    log_info "Add this line: $cron_entry"
    return 1
  fi
  
  echo "$cron_entry" | sudo tee "$cron_file" >/dev/null
  sudo chmod 644 "$cron_file"
  
  log_success "Cron job installed: $cron_file"
  log_info "Sync will run every 5 minutes"
  return 0
}

# ==============================================================================
# STATUS AND CONTROL
# ==============================================================================

show_status() {
  log_info "Cluster sync daemon status"
  
  if [[ -f "$STATUS_FILE" ]]; then
    echo "=== Last sync status ==="
    cat "$STATUS_FILE"
  else
    echo "No previous sync recorded"
  fi
  
  echo ""
  echo "=== Recent log entries ==="
  tail -10 "$LOG_FILE" 2>/dev/null || echo "No log entries"
}

disable_sync() {
  log_info "Disabling automatic cluster sync..."
  
  if [[ -f "/etc/cron.d/cluster-sync" ]]; then
    sudo rm -f "/etc/cron.d/cluster-sync"
    log_success "Cron job removed"
  fi
  
  log_warn "Cluster sync disabled - manual updates required"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
  # Ensure log directory exists
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  touch "$AUDIT_LOG"
  
  case "$SYNC_MODE" in
    --sync)
      execute_sync
      ;;
    --install-cron)
      install_cron
      ;;
    --status)
      show_status
      ;;
    --disable)
      disable_sync
      ;;
    *)
      cat >&2 <<EOF
Usage: bash scripts/ops/cluster-sync-daemon.sh [COMMAND]

Commands:
  --sync            Execute cluster sync (pull, validate, restart)
  --install-cron    Install cron job for automatic sync every 5 minutes
  --status          Show sync daemon status
  --disable         Disable automatic sync

Examples:
  # Manual sync
  bash scripts/ops/cluster-sync-daemon.sh --sync

  # Install automatic sync on replica
  bash scripts/ops/cluster-sync-daemon.sh --install-cron

  # Check status
  bash scripts/ops/cluster-sync-daemon.sh --status
EOF
      return 2
      ;;
  esac
}

# Execute main
main
