#!/usr/bin/env bash
# @file        scripts/ops/fix-replica-1-permissions.sh
# @module      ops/replica-sync
# @description Fix file permission issues on Replica 1 to enable git operations and deployments
# @owner       infrastructure
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICA_HOST="${REPLICA_1_HOST:-192.168.168.31}"
# Note: DEPLOY_USER, DEPLOY_DIR, SSH_OPTS are set as readonly by config.sh (via init.sh)
# We use them directly without reassigning
DRY_RUN="${DRY_RUN:-0}"

log_info "Replica 1 Permission Remediation"
log_info "Host: $REPLICA_HOST"
log_info "User: $DEPLOY_USER"
log_info "Deploy dir: $DEPLOY_DIR"
log_info "Dry run: $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"

# Verify SSH access
verify_ssh_access() {
  if ! ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${REPLICA_HOST}" true 2>/dev/null; then
    log_fatal "SSH access failed to ${DEPLOY_USER}@${REPLICA_HOST}"
  fi
  log_info "SSH access verified"
}

# Fix ownership recursively
fix_ownership() {
  local remote_cmd="sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} ~/${DEPLOY_DIR}/"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh ${SSH_OPTS[*]} ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Fixing file ownership on $REPLICA_HOST..."
  if ! ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Failed to fix ownership. Ensure sudo is configured for $DEPLOY_USER without password prompt."
    return 1
  fi
  log_info "File ownership fixed"
}

# Clean git state
clean_git_state() {
  local remote_cmd="cd ~/${DEPLOY_DIR} && git clean -fdx && git reset --hard origin/main"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh $SSH_OPTS ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Cleaning git state on $REPLICA_HOST..."
  if ! ssh $SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Git cleanup failed"
    return 1
  fi
  log_info "Git state cleaned"
}

# Pull latest and redeploy
redeploy() {
  local remote_cmd="cd ~/${DEPLOY_DIR} && git pull --ff-only origin main && docker compose pull && docker compose up -d"
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh $SSH_OPTS ${DEPLOY_USER}@${REPLICA_HOST} '$remote_cmd'"
    return 0
  fi
  
  log_info "Redeploying on $REPLICA_HOST..."
  if ! ssh $SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "$remote_cmd"; then
    log_error "Redeployment failed"
    return 1
  fi
  log_info "Redeployment completed"
}

# Verify git status
verify_git_status() {
  log_info "Verifying git status on $REPLICA_HOST..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] Skipping verification in dry-run mode"
    return 0
  fi
  
  local commit_sha=$(ssh $SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "cd ~/${DEPLOY_DIR} && git rev-parse --short HEAD")
  log_info "Replica 1 commit: $commit_sha"
  
  local main_sha=$(ssh $SSH_OPTS "${DEPLOY_USER}@${REPLICA_HOST}" "cd ~/${DEPLOY_DIR} && git rev-parse --short origin/main")
  log_info "Main branch commit: $main_sha"
  
  if [[ "$commit_sha" == "$main_sha" ]]; then
    log_info "✓ Replica 1 is synced with main"
    return 0
  else
    log_warn "Replica 1 may not be fully synced (local: $commit_sha, main: $main_sha)"
    return 1
  fi
}

# Main execution
verify_ssh_access
fix_ownership || exit 1
clean_git_state || exit 1
redeploy || exit 1
verify_git_status

log_info "Replica 1 remediation completed successfully"
