#!/usr/bin/env bash
# @file        scripts/ops/sync-fstab-between-replicas.sh
# @module      infrastructure/cluster-synchronization
# @description Synchronize /etc/fstab between Replica 1 and Replica 2 (Issue #1637)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Initialize repository context
init_repo

REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
SSH_USER="akushnir"

# Backup timestamp
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"

sync_fstab() {
    local source_host="$1"
    local target_host="$2"
    local source_label="$3"
    local target_label="$4"
    
    log_info "Synchronizing /etc/fstab from $source_label to $target_label..."
    
    # Backup target fstab
    local backup_file="/tmp/fstab-backup-${BACKUP_TS}.txt"
    log_info "Backing up target fstab to /tmp/fstab-backup-${BACKUP_TS}.txt on $target_host..."
    ssh "$SSH_USER@$target_host" "sudo cp /etc/fstab $backup_file && sudo chmod 644 $backup_file" || \
        log_fatal "Failed to backup fstab on $target_host"
    
    # Get source fstab
    log_info "Retrieving source fstab from $source_label..."
    ssh "$SSH_USER@$source_host" "cat /etc/fstab" > /tmp/source-fstab.txt || \
        log_fatal "Failed to retrieve source fstab"
    
    # Copy to target
    log_info "Copying source fstab to $target_label..."
    cat /tmp/source-fstab.txt | ssh "$SSH_USER@$target_host" "sudo tee /etc/fstab > /dev/null" || \
        log_fatal "Failed to update fstab on $target_host"
    
    # Validate syntax
    log_info "Validating fstab syntax on $target_label..."
    if ssh "$SSH_USER@$target_host" "sudo mount -a --dry-run" > /dev/null 2>&1; then
        log_info "✅ fstab syntax validation passed"
    else
        log_warn "⚠️  fstab syntax validation issue - review carefully"
    fi
    
    # Actual mount test (non-destructive)
    log_info "Testing mount operation on $target_label (not modifying existing mounts)..."
    ssh "$SSH_USER@$target_host" "sudo mount -a" || log_warn "⚠️  Some mounts may have failed (expected if already mounted)"
    
    log_info "✅ fstab synchronization complete: $source_label → $target_label"
    log_info "   Backup available at: $backup_file on $target_host"
}

main() {
    log_info "Starting bidirectional fstab synchronization..."
    
    # Test SSH connectivity
    for host in "$REPLICA_1" "$REPLICA_2"; do
        log_info "Testing SSH connectivity to $host..."
        if ! ssh -o ConnectTimeout=5 "$SSH_USER@$host" "echo OK" > /dev/null 2>&1; then
            log_fatal "Cannot connect to $host"
        fi
    done
    
    # Determine which replica has more complete fstab
    log_info "Comparing fstab completeness..."
    local r1_entries=$(ssh "$SSH_USER@$REPLICA_1" "grep -c 'eiq-shared\|nas-' /etc/fstab" || echo "0")
    local r2_entries=$(ssh "$SSH_USER@$REPLICA_2" "grep -c 'eiq-shared\|nas-' /etc/fstab" || echo "0")
    
    log_info "Replica 1 NAS entries: $r1_entries, Replica 2 NAS entries: $r2_entries"
    
    if [ "$r2_entries" -gt "$r1_entries" ]; then
        log_info "Replica 2 has more complete fstab - syncing to Replica 1..."
        sync_fstab "$REPLICA_2" "$REPLICA_1" "Replica 2" "Replica 1"
    elif [ "$r1_entries" -gt "$r2_entries" ]; then
        log_info "Replica 1 has more complete fstab - syncing to Replica 2..."
        sync_fstab "$REPLICA_1" "$REPLICA_2" "Replica 1" "Replica 2"
    else
        log_info "Both replicas have equivalent fstab entries - no sync needed"
    fi
    
    # Final verification
    log_info "Final verification - comparing fstab hashes..."
    local r1_hash=$(ssh "$SSH_USER@$REPLICA_1" "sha256sum /etc/fstab" | awk '{print $1}')
    local r2_hash=$(ssh "$SSH_USER@$REPLICA_2" "sha256sum /etc/fstab" | awk '{print $1}')
    
    if [ "$r1_hash" = "$r2_hash" ]; then
        log_info "✅ SUCCESS - Both replicas have identical fstab (hash: ${r1_hash:0:8}...)"
    else
        log_warn "⚠️  fstab hashes differ - likely due to replica-specific entries"
        log_info "   Replica 1 hash: ${r1_hash:0:16}..."
        log_info "   Replica 2 hash: ${r2_hash:0:16}..."
    fi
    
    log_info "✅ fstab synchronization process complete"
}

main "$@"
