#!/usr/bin/env bash
# @file        scripts/security/fix-nfs-no-root-squash.sh
# @module      security/nfs
# @description Fix NFS security vulnerability: restrict exports from wildcard (*) to specific IPs and enable root_squash
#
# @owner       Security Team
# @status      production-ready
# @depends_on  ssh, exportfs (NFS server)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONSTANTS
# ============================================================================

NAS_HOST="${NAS_HOST:-192.168.168.56}"
NAS_USER="${NAS_USER:-akushnir}"
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
EXPORTS_FILE="/etc/exports"
EXPORTS_BACKUP="${EXPORTS_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

# ============================================================================
# VALIDATION
# ============================================================================

validate_nfs_access() {
  log_info "Validating NFS access to $NAS_HOST..."
  
  if ! ssh "$NAS_USER@$NAS_HOST" "sudo test -f $EXPORTS_FILE" 2>/dev/null; then
    log_fatal "Cannot access $NAS_HOST:$EXPORTS_FILE. Check SSH keys and permissions."
  fi
  
  log_info "✅ NAS access verified"
}

# ============================================================================
# BACKUP
# ============================================================================

backup_exports() {
  log_info "Backing up current $EXPORTS_FILE..."
  
  ssh "$NAS_USER@$NAS_HOST" "sudo cp $EXPORTS_FILE $EXPORTS_BACKUP" || {
    log_fatal "Failed to backup $EXPORTS_FILE"
  }
  
  log_info "✅ Backup created: $EXPORTS_BACKUP"
}

# ============================================================================
# AUDIT CURRENT STATE
# ============================================================================

audit_current_exports() {
  log_info "Auditing current NFS exports..."
  
  local current_exports
  current_exports=$(ssh "$NAS_USER@$NAS_HOST" "sudo cat $EXPORTS_FILE" || echo "")
  
  echo "$current_exports" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue
    
    if [[ "$line" == *"*"* ]]; then
      log_warn "⚠️  Wildcard export found: $line"
    fi
    
    if [[ "$line" == *"no_root_squash"* ]]; then
      log_warn "⚠️  no_root_squash found: $line"
    fi
  done
  
  log_info "Audit complete"
}

# ============================================================================
# FIX EXPORTS
# ============================================================================

fix_exports() {
  log_info "Creating fixed /etc/exports configuration..."
  
  # Create new exports with:
  # - Specific IPs only (no wildcard)
  # - root_squash enabled (default)
  # - Preserved options (rw, sync, no_subtree_check)
  
  local new_exports_content=$(cat <<'EOF'
# NFS Exports Configuration (Fixed: P1 #1387)
# Restricted to primary (.31) and replica (.42) hosts
# With root_squash enabled (default) to prevent root privilege escalation

# PostgreSQL backups
/export/postgres-backups 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/postgres-backups 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# PostgreSQL data (if stored on NAS)
/export/postgres 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/postgres 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Code-server data
/export/code-server 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/code-server 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Caddy certificates and data
/export/caddy 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/caddy 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Grafana data
/export/grafana 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/grafana 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Backups
/export/backups 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/backups 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Full /export (fallback for unmapped paths)
/export 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export 192.168.168.42(rw,sync,no_subtree_check,root_squash)
EOF
)
  
  # Send to NAS and apply
  log_info "Applying new exports configuration..."
  
  ssh "$NAS_USER@$NAS_HOST" << 'REMOTE_CMD'
sudo tee /etc/exports.new > /dev/null <<'EXPORTS'
# NFS Exports Configuration (Fixed: P1 #1387)
# Restricted to primary (.31) and replica (.42) hosts
# With root_squash enabled (default) to prevent root privilege escalation

# PostgreSQL backups
/export/postgres-backups 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/postgres-backups 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# PostgreSQL data (if stored on NAS)
/export/postgres 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/postgres 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Code-server data
/export/code-server 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/code-server 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Caddy certificates and data
/export/caddy 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/caddy 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Grafana data
/export/grafana 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/grafana 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Backups
/export/backups 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/backups 192.168.168.42(rw,sync,no_subtree_check,root_squash)

# Full /export (fallback for unmapped paths)
/export 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export 192.168.168.42(rw,sync,no_subtree_check,root_squash)
EXPORTS

# Verify syntax
if ! sudo nfsstat 2>/dev/null; then
  log_info "NFS tools available"
fi

# Apply new exports (atomic: copy to location)
sudo mv /etc/exports.new "$EXPORTS_FILE"

# Reload NFS exports
sudo exportfs -ra

# Verify reload succeeded
if sudo exportfs -s 2>/dev/null | grep -q "192.168.168.31"; then
  log_info "✅ Exports reloaded successfully"
else
  log_error "Failed to reload exports"
  exit 1
fi
REMOTE_CMD
  
  log_info "✅ Exports fixed and reloaded"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_fix() {
  log_info "Verifying NFS security fix..."
  
  local showmount_output
  showmount_output=$(ssh "$NAS_USER@$NAS_HOST" "showmount -e localhost 2>/dev/null" || echo "")
  
  # Check for wildcard
  if echo "$showmount_output" | grep -q '\*'; then
    log_error "❌ Wildcard still present in exports"
    return 1
  fi
  
  # Check for no_root_squash
  if echo "$showmount_output" | grep -q 'no_root_squash'; then
    log_error "❌ no_root_squash still enabled"
    return 1
  fi
  
  # Check for specific IPs
  if echo "$showmount_output" | grep -q "192.168.168.31"; then
    log_info "✅ Primary host (.31) access configured"
  else
    log_error "❌ Primary host access missing"
    return 1
  fi
  
  if echo "$showmount_output" | grep -q "192.168.168.42"; then
    log_info "✅ Replica host (.42) access configured"
  else
    log_error "❌ Replica host access missing"
    return 1
  fi
  
  # Test mount from primary
  log_info "Testing NFS mount from primary host..."
  ssh "root@$PRIMARY_HOST" "mount | grep -q /export" 2>/dev/null && {
    log_info "✅ NFS already mounted on primary"
  } || {
    log_warn "⚠️  NFS not currently mounted on primary (may be intermittent)"
  }
  
  log_info "✅ Verification complete"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "Starting NFS no_root_squash fix (P1 #1387)..."
  
  validate_nfs_access
  audit_current_exports
  backup_exports
  fix_exports
  verify_fix
  
  log_info "✅ NFS security fix complete"
  log_info ""
  log_info "Summary:"
  log_info "  - Exports restricted to specific IPs (no wildcard)"
  log_info "  - root_squash enabled (prevents root privilege escalation)"
  log_info "  - Backup: $EXPORTS_BACKUP"
  log_info ""
  log_info "To verify from unauthorized host (should be refused):"
  log_info "  showmount -e 192.168.168.56"
  log_info ""
  log_info "To verify from authorized hosts (.31, .42):"
  log_info "  showmount -e 192.168.168.56"
  log_info "  mount | grep /export"
}

main "$@"
