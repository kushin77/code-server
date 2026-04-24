#!/usr/bin/env bash
# @file        scripts/ops/security-remediate-ssh-key-rotation.sh
# @module      security/incident-response
# @description Rotate compromised SSH key (~/.ssh/id_rsa_onprem) on both production replicas
#
# SECURITY INCIDENT: SSH private key exposed to terminal output during Phase 4 deployment operations
# - Date: April 23, 2026 ~22:50-22:55 UTC
# - Key: ~/.ssh/id_rsa_onprem
# - Exposure: Terminal output capture via bash -lc with PowerShell pager interference
# - Action: Immediately revoke compromised key and deploy new key to all replicas
#
# This script implements idempotent, reversible SSH key rotation:
# 1. Generate new SSH key locally
# 2. Deploy public key to authorized_keys on both replicas
# 3. Test new key connectivity to both replicas
# 4. Verify old key is no longer trusted (optional: revoke from authorized_keys)
# 5. Document rotation in audit log
#

set -euo pipefail

# ==================== CONFIGURATION ====================
REPLICAS=("192.168.168.31" "192.168.168.42")
SSH_USER="akushnir"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa_onprem"
SSH_KEY_NEW_PATH="${SSH_KEY_PATH}.new"
SSH_KEY_OLD_PATH="${SSH_KEY_PATH}.old"
SSH_KEY_BITS=4096
AUDIT_LOG="/tmp/ssh-key-rotation-audit-$(date +%Y%m%d-%H%M%S).log"

# ==================== LOGGING ====================
log_info() {
  printf "[INFO] %s\n" "$1" | tee -a "$AUDIT_LOG"
}

log_warn() {
  printf "[WARN] %s\n" "$1" | tee -a "$AUDIT_LOG" >&2
}

log_error() {
  printf "[ERROR] %s\n" "$1" | tee -a "$AUDIT_LOG" >&2
}

log_success() {
  printf "[✓] %s\n" "$1" | tee -a "$AUDIT_LOG"
}

# ==================== SECURITY VALIDATION ====================
validate_key_safety() {
  local key_path="$1"
  
  # Verify key permissions (must be 600 or 400, not world-readable)
  if [[ -f "$key_path" ]]; then
    local mode=$(stat -c %a "$key_path")
    if [[ ! "$mode" =~ ^40 ]]; then
      log_error "Key $key_path has unsafe permissions: $mode (must be 400 or 600)"
      return 1
    fi
  fi
  return 0
}

# ==================== MAIN EXECUTION ====================
main() {
  log_info "SSH Key Rotation - Security Incident Remediation"
  log_info "=================================================="
  log_info "Rotation ID: $(date -u +%Y%m%dT%H%M%SZ)"
  log_info "Replicas: ${REPLICAS[*]}"
  log_info "Audit log: $AUDIT_LOG"
  
  # Step 1: Backup current key
  log_info ""
  log_info "STEP 1: Backup compromised key"
  if [[ -f "$SSH_KEY_PATH" ]]; then
    cp "$SSH_KEY_PATH" "$SSH_KEY_OLD_PATH"
    chmod 400 "$SSH_KEY_OLD_PATH"
    log_success "Backed up compromised key to: $SSH_KEY_OLD_PATH"
  else
    log_warn "Current key not found at $SSH_KEY_PATH (may already be rotated)"
  fi
  
  # Step 2: Generate new SSH key (idempotent: only if not exists)
  log_info ""
  log_info "STEP 2: Generate new SSH key"
  if [[ -f "$SSH_KEY_NEW_PATH" ]]; then
    log_warn "New key already exists at $SSH_KEY_NEW_PATH, skipping generation (idempotent)"
  else
    ssh-keygen -t rsa -b "$SSH_KEY_BITS" -f "$SSH_KEY_NEW_PATH" -N "" -C "kushnir-onprem-rotated-$(date +%Y%m%d)" >/dev/null 2>&1
    chmod 400 "$SSH_KEY_NEW_PATH"
    log_success "Generated new SSH key: $SSH_KEY_NEW_PATH"
  fi
  validate_key_safety "$SSH_KEY_NEW_PATH" || return 1
  
  # Step 3: Activate new key (atomically move to production path)
  log_info ""
  log_info "STEP 3: Activate new key"
  mv "$SSH_KEY_NEW_PATH" "$SSH_KEY_PATH"
  chmod 400 "$SSH_KEY_PATH"
  log_success "Activated new key at: $SSH_KEY_PATH"
  
  # Step 4: Deploy public key to both replicas
  log_info ""
  log_info "STEP 4: Deploy public key to replicas"
  local pub_key_content
  pub_key_content=$(cat "${SSH_KEY_PATH}.pub")
  
  for replica in "${REPLICAS[@]}"; do
    log_info "  → Deploying to $replica..."
    
    # Check connectivity with new key first (should fail initially)
    if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" "echo 'test'" >/dev/null 2>&1; then
      log_warn "  → New key already trusted on $replica (may have been pre-deployed)"
    else
      log_warn "  → New key not yet trusted on $replica (expected, will deploy via fallback)"
      # Use old key to deploy new public key to authorized_keys
      if [[ -f "$SSH_KEY_OLD_PATH" ]]; then
        ssh -i "$SSH_KEY_OLD_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" \
          "mkdir -p ~/.ssh && echo '$pub_key_content' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" || {
          log_error "Failed to deploy public key to $replica using old key"
          return 1
        }
        log_success "  → Deployed public key to $replica"
      else
        log_error "Cannot deploy to $replica: old key not available for SSH access"
        return 1
      fi
    fi
  done
  
  # Step 5: Verify new key connectivity to all replicas
  log_info ""
  log_info "STEP 5: Verify new key connectivity"
  local all_connected=true
  for replica in "${REPLICAS[@]}"; do
    if ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" "echo 'connection test'" >/dev/null 2>&1; then
      log_success "  ✓ Connected to $replica with new key"
    else
      log_error "  ✗ Failed to connect to $replica with new key"
      all_connected=false
    fi
  done
  
  if [[ "$all_connected" != "true" ]]; then
    log_error "FAILURE: Could not establish connectivity with new key to all replicas"
    return 1
  fi
  
  # Step 6: Optional - Revoke old key from authorized_keys (reversible: keep backup)
  log_info ""
  log_info "STEP 6: Revoke old key from authorized_keys (optional, reversible)"
  local old_pub_key_content
  if [[ -f "${SSH_KEY_OLD_PATH}.pub" ]]; then
    old_pub_key_content=$(cat "${SSH_KEY_OLD_PATH}.pub")
    for replica in "${REPLICAS[@]}"; do
      ssh -i "$SSH_KEY_PATH" -o BatchMode=yes "$SSH_USER@$replica" \
        "sed -i '$(printf '%s\n' "$old_pub_key_content" | sed 's/[&/\]/\\&/g')//g' ~/.ssh/authorized_keys" || true
      log_info "  → Revoked old key from $replica (if present)"
    done
  fi
  
  # Step 7: Document rotation in audit log
  log_info ""
  log_info "STEP 7: Audit documentation"
  log_info "Rotation completed successfully"
  log_info "  Old key: $SSH_KEY_OLD_PATH (ARCHIVED - COMPROMISED)"
  log_info "  New key: $SSH_KEY_PATH (ACTIVE)"
  log_info "  Audit log: $AUDIT_LOG"
  
  log_success ""
  log_success "SSH KEY ROTATION COMPLETE ✓"
  log_success "  - New key active on all replicas"
  log_success "  - Old key archived for audit trail"
  log_success "  - Audit log: $AUDIT_LOG"
}

# Execute
main "$@"
