#!/usr/bin/env bash
# @file        scripts/ops/sync-fstab-replicas.sh
# @module      operations/infrastructure
# @description Sync /etc/fstab NAS mount entries between replicas (P1 #1637)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Backup fstab on a host
backup_fstab() {
    local host="$1"
    local backup_file="/etc/fstab.backup-${TIMESTAMP}"
    
    log_info "Backing up fstab on $host to $backup_file"
    ssh "${EXEC_USER}@${host}" "sudo cp /etc/fstab $backup_file" || {
        log_error "Failed to backup fstab on $host"
        return 1
    }
    log_success "Backup created: $backup_file"
}

# Get NAS mount entries from fstab
get_nas_mounts() {
    local host="$1"
    
    log_debug "Retrieving NAS mount entries from $host"
    ssh "${EXEC_USER}@${host}" "grep -E '(192.168.168.56|mnt-|nas|eiq-shared)' /etc/fstab 2>/dev/null || true"
}

# Add missing NAS entries to fstab
add_nas_entries() {
    local host="$1"
    local entries="$2"
    
    if [ -z "$entries" ]; then
        log_warn "No NAS entries to add"
        return 0
    fi
    
    log_info "Adding NAS entries to $host fstab..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would add these entries to $host:/etc/fstab:"
        echo "$entries" | sed 's/^/  [DRY-RUN] /'
        return 0
    fi
    
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        
        mount_point=$(echo "$entry" | awk '{print $NF}')
        
        if ssh "${EXEC_USER}@${host}" "grep -q '$mount_point' /etc/fstab 2>/dev/null"; then
            log_debug "Entry already exists: $mount_point"
        else
            log_info "Adding entry: $mount_point"
            ssh "${EXEC_USER}@${host}" "echo '$entry' | sudo tee -a /etc/fstab > /dev/null"
        fi
    done <<< "$entries"
    
    log_success "NAS entries added"
}

# Reload systemd mounts
reload_mounts() {
    local host="$1"
    
    log_info "Reloading systemd mount units on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would run: sudo systemctl daemon-reload"
        return 0
    fi
    
    ssh "${EXEC_USER}@${host}" "sudo systemctl daemon-reload" || {
        log_error "Failed to reload systemd on $host"
        return 1
    }
    
    log_success "Systemd reloaded"
}

# Verify mount points
verify_mounts() {
    local host="$1"
    
    log_info "Verifying mounts on $host..."
    
    local mounts_output
    mounts_output=$(ssh "${EXEC_USER}@${host}" "mount | grep -E '(mnt-|nas|eiq)' | wc -l" 2>/dev/null || echo "0")
    
    if [ "$mounts_output" -gt 0 ]; then
        log_success "Found $mounts_output active mounts on $host"
    else
        log_warn "No active NAS mounts found on $host (may need reboot or manual mount)"
    fi
    
    log_info "Current NAS entries in $host fstab:"
    ssh "${EXEC_USER}@${host}" "grep -E '(192.168.168.56|mnt-|nas|eiq-shared)' /etc/fstab 2>/dev/null || echo 'No NAS entries found'" | sed 's/^/  /'
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Syncing /etc/fstab NAS mount entries between replicas (P1 #1637)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host (source): $PRIMARY_HOST"
    log_info "  Replica Host (target): $REPLICA_HOST"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity to both replicas..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo 'Connected' > /dev/null" 2>/dev/null; then
        log_fatal "Cannot connect to primary host ($PRIMARY_HOST)"
    fi
    log_success "✓ Connected to primary host"
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${REPLICA_HOST}" "echo 'Connected' > /dev/null" 2>/dev/null; then
        log_fatal "Cannot connect to replica host ($REPLICA_HOST)"
    fi
    log_success "✓ Connected to replica host"
    log_info ""
    
    log_info "Retrieving NAS mount entries from primary ($PRIMARY_HOST)..."
    primary_nas_entries=$(get_nas_mounts "$PRIMARY_HOST") || {
        log_error "Failed to get NAS entries from primary"
        return 1
    }
    
    if [ -z "$primary_nas_entries" ]; then
        log_warn "No NAS entries found in primary fstab - using default"
        primary_nas_entries="192.168.168.56:/export /mnt/eiq-shared nfs4 rw,sync,hard,intr 0 0"
    fi
    
    log_info "NAS entries on primary ($PRIMARY_HOST):"
    echo "$primary_nas_entries" | sed 's/^/  /'
    log_info ""
    
    log_info "Creating backups..."
    backup_fstab "$PRIMARY_HOST" || return 1
    backup_fstab "$REPLICA_HOST" || return 1
    log_info ""
    
    log_info "Synchronizing fstab entries to replica ($REPLICA_HOST)..."
    add_nas_entries "$REPLICA_HOST" "$primary_nas_entries" || return 1
    log_info ""
    
    log_info "Reloading systemd mount units..."
    reload_mounts "$PRIMARY_HOST" || log_warn "Could not reload systemd on primary"
    reload_mounts "$REPLICA_HOST" || log_warn "Could not reload systemd on replica"
    log_info ""
    
    log_info "Verifying final state..."
    log_info ""
    
    log_info "Primary ($PRIMARY_HOST) mounts:"
    verify_mounts "$PRIMARY_HOST"
    log_info ""
    
    log_info "Replica ($REPLICA_HOST) mounts:"
    verify_mounts "$REPLICA_HOST"
    log_info ""
    
    log_success "========================================================================"
    log_success "fstab synchronization complete!"
    log_success "========================================================================"
}

main "$@"
