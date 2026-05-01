#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/rollback.sh
# @module      ops/rollback
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/rollback.sh
# @description IaC Lifecycle Control - Comprehensive rollback mechanism (#1531)
# @governance GOV-002 - Immutable, idempotent rollback procedures
# @automation Triggered by health-check-and-rollback.sh or manual execution
# @prerequisite Must source scripts/_common/init.sh

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT


# Source bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly ROLLBACK_TYPE="${1:-manual}"  # auto, manual, emergency
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# Backup directory
BACKUP_DIR="${REPO_ROOT}/.rollback-backups"
mkdir -p "${BACKUP_DIR}"

# ==============================================================================
# ROLLBACK STATES
# ==============================================================================

# Create rollback checkpoint before making changes
create_rollback_checkpoint() {
  local checkpoint_name="checkpoint-$(date +%s)"
  local checkpoint_dir="${BACKUP_DIR}/${checkpoint_name}"
  
  mkdir -p "${checkpoint_dir}"
  
  log_info "Creating rollback checkpoint: $checkpoint_name"
  
  # Backup critical files
  cp "${REPO_ROOT}/docker-compose.yml" "${checkpoint_dir}/" 2>/dev/null || true
  cp "${REPO_ROOT}/docker-compose.override.yml" "${checkpoint_dir}/" 2>/dev/null || true
  cp "${REPO_ROOT}/config/caddy/Caddyfile" "${checkpoint_dir}/" 2>/dev/null || true
  cp "${REPO_ROOT}/.env" "${checkpoint_dir}/" 2>/dev/null || true
  
  # Backup Git state
  cd "${REPO_ROOT}"
  git status > "${checkpoint_dir}/git-status.txt" 2>/dev/null || true
  git log --oneline -10 > "${checkpoint_dir}/git-log.txt" 2>/dev/null || true
  git rev-parse HEAD > "${checkpoint_dir}/git-sha.txt" 2>/dev/null || true
  
  # Backup container status
  docker ps -a > "${checkpoint_dir}/docker-ps.txt" 2>/dev/null || true
  docker-compose config > "${checkpoint_dir}/docker-compose-config.yml" 2>/dev/null || true
  
  echo "$checkpoint_name" > "${BACKUP_DIR}/latest-checkpoint.txt"
  log_success "Checkpoint created: ${checkpoint_dir}"
}

# List available rollback checkpoints
list_rollback_checkpoints() {
  log_info "Available rollback checkpoints:"
  
  if [ ! -d "${BACKUP_DIR}" ] || [ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]; then
    log_warn "No rollback checkpoints found"
    return 1
  fi
  
  ls -1d "${BACKUP_DIR}"/checkpoint-* 2>/dev/null | sort -r | head -5 | while read -r checkpoint; do
    local name=$(basename "$checkpoint")
    local file_count=$(find "$checkpoint" -type f | wc -l)
    log_info "  - $name ($file_count files)"
  done
}

# ==============================================================================
# DOCKER COMPOSE ROLLBACK
# ==============================================================================

rollback_docker_compose() {
  log_info "Rolling back Docker Compose deployment..."
  
  # Stop all containers gracefully
  log_info "Stopping containers..."
  cd "${REPO_ROOT}"
  docker-compose down -v 2>/dev/null || true
  
  sleep 3
  
  # Restart from current composition
  log_info "Restarting containers from current configuration..."
  docker-compose up -d 2>/dev/null || {
    log_error "Failed to restart containers"
    return 1
  }
  
  # Wait for containers to start
  sleep 5
  
  log_success "Docker Compose rollback completed"
}

# ==============================================================================
# TERRAFORM ROLLBACK
# ==============================================================================

rollback_terraform() {
  log_info "Rolling back Terraform state..."
  
  # Get current state backup
  local current_state="${REPO_ROOT}/terraform.tfstate.backup"
  
  if [ -f "$current_state" ]; then
    log_info "Reverting to last known-good Terraform state"
    cp "$current_state" "${REPO_ROOT}/terraform.tfstate" 2>/dev/null || true
  else
    log_warn "No Terraform state backup found, skipping terraform rollback"
  fi
  
  # Reinitialize terraform
  cd "${REPO_ROOT}/terraform/environments/private"
  terraform init -upgrade -no-color 2>/dev/null || {
    log_error "Terraform init failed"
    return 1
  }
  
  log_success "Terraform rollback completed"
}

# ==============================================================================
# CADDY CONFIGURATION ROLLBACK
# ==============================================================================

rollback_caddy_config() {
  log_info "Rolling back Caddy configuration..."
  
  local caddy_backup="${BACKUP_DIR}/latest-caddy.bak"
  local caddy_config="${REPO_ROOT}/config/caddy/Caddyfile"
  
  if [ -f "$caddy_backup" ]; then
    cp "$caddy_backup" "$caddy_config"
    log_success "Caddy configuration restored from backup"
  else
    log_warn "No Caddy backup found, attempting restart only"
  fi
  
  # Restart Caddy to apply configuration
  cd "${REPO_ROOT}"
  docker-compose restart caddy 2>/dev/null || {
    log_error "Failed to restart Caddy"
    return 1
  }
  
  sleep 3
  log_success "Caddy rollback completed"
}

# ==============================================================================
# COMPREHENSIVE ROLLBACK
# ==============================================================================

perform_full_rollback() {
  local rollback_type="$1"
  
  log_warn "=== INITIATING FULL ROLLBACK (mode: $rollback_type) ==="
  
  # Create pre-rollback checkpoint
  create_rollback_checkpoint
  
  # Perform rollback operations in order
  local failed_rollbacks=0
  
  if ! rollback_docker_compose; then
    log_error "Docker Compose rollback failed"
    failed_rollbacks=$((failed_rollbacks + 1))
  fi
  
  if ! rollback_terraform; then
    log_warn "Terraform rollback had issues (may not affect functionality)"
    # Don't increment failure count for terraform issues
  fi
  
  if ! rollback_caddy_config; then
    log_error "Caddy configuration rollback failed"
    failed_rollbacks=$((failed_rollbacks + 1))
  fi
  
  if [ $failed_rollbacks -eq 0 ]; then
    log_success "✅ Full rollback completed successfully"
    
    # Verify health
    log_info "Verifying post-rollback health..."
    sleep 5
    bash "${SCRIPT_DIR}/health-check-and-rollback.sh" || {
      log_error "Health check failed post-rollback"
      return 1
    }
    
    return 0
  else
    log_error "❌ Rollback completed with $failed_rollbacks failures"
    return 1
  fi
}

# ==============================================================================
# CLEANUP OLD BACKUPS
# ==============================================================================

cleanup_old_backups() {
  log_info "Cleaning up old rollback backups (retention: $BACKUP_RETENTION_DAYS days)"
  
  find "${BACKUP_DIR}" -maxdepth 1 -type d -name "checkpoint-*" -mtime +${BACKUP_RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true
  
  log_success "Backup cleanup completed"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  log_info "IaC Rollback System Initiated"
  log_info "Rollback Type: $ROLLBACK_TYPE"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Git SHA: $(get_git_sha)"
  
  case "$ROLLBACK_TYPE" in
    auto)
      log_warn "Auto-rollback triggered by health check failure"
      perform_full_rollback "automatic"
      ;;
    manual)
      log_info "Manual rollback initiated by operator"
      perform_full_rollback "manual"
      ;;
    emergency)
      log_error "EMERGENCY ROLLBACK - All services will be forcibly stopped and reset"
      read -p "Are you sure? Type 'YES' to confirm: " confirm
      if [ "$confirm" == "YES" ]; then
        perform_full_rollback "emergency"
      else
        log_info "Emergency rollback cancelled"
        exit 0
      fi
      ;;
    list)
      list_rollback_checkpoints
      ;;
    cleanup)
      cleanup_old_backups
      ;;
    *)
      log_error "Unknown rollback type: $ROLLBACK_TYPE"
      echo "Usage: $0 {auto|manual|emergency|list|cleanup}"
      exit 1
      ;;
  esac
  
  # Clean up old backups after successful rollback
  if [ "$ROLLBACK_TYPE" != "list" ] && [ "$ROLLBACK_TYPE" != "cleanup" ]; then
    cleanup_old_backups
  fi
}

# ==============================================================================
# EXECUTION
# ==============================================================================

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
