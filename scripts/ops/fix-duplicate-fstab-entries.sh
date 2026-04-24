#!/usr/bin/env bash
# @file        scripts/ops/fix-duplicate-fstab-entries.sh
# @module      operations/infrastructure
# @description Fix duplicate mount entries in /etc/fstab causing systemd-fstab-generator errors (P1 #1631)
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

# Detect duplicate entries in fstab
detect_duplicates() {
    local host="$1"
    
    log_info "Detecting duplicate mount entries on $host..."
    
    # Get unique mount points with count
    local duplicates
    duplicates=$(ssh "${EXEC_USER}@${host}" "grep -v '^#' /etc/fstab | awk '{print \$2}' | sort | uniq -d 2>/dev/null" || echo "")
    
    if [ -z "$duplicates" ]; then
        log_info "No duplicates found on $host"
        echo ""
        return 0
    fi
    
    log_warn "Found duplicate mount points on $host:"
    echo "$duplicates" | sed 's/^/  /'
    echo ""
    echo "$duplicates"
}

# Show all entries for a mount point
show_entries() {
    local host="$1"
    local mount_point="$2"
    
    log_info "Entries for mount point: $mount_point"
    ssh "${EXEC_USER}@${host}" "grep '$mount_point' /etc/fstab | grep -v '^#'" | nl | sed 's/^/  /'
}

# Remove duplicate entries, keeping first occurrence
remove_duplicates() {
    local host="$1"
    
    log_info "Removing duplicate entries from $host fstab..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would remove duplicates:"
        log_info "[DRY-RUN] Creating deduplicated fstab (keeping first of each mount point)"
        return 0
    fi
    
    # Create a temporary script to deduplicate fstab
    local dedup_script="awk '!seen[\$2]++' /etc/fstab > /tmp/fstab.dedup-${TIMESTAMP}"
    
    log_info "Creating deduplicated copy..."
    ssh "${EXEC_USER}@${host}" "sudo bash -c '$dedup_script'" || {
        log_error "Failed to create deduplicated fstab"
        return 1
    }
    
    # Backup original
    log_info "Backing up original fstab..."
    ssh "${EXEC_USER}@${host}" "sudo cp /etc/fstab /etc/fstab.backup-${TIMESTAMP}" || {
        log_error "Failed to backup fstab"
        return 1
    }
    
    # Replace with deduplicated version
    log_info "Replacing fstab with deduplicated version..."
    ssh "${EXEC_USER}@${host}" "sudo cp /tmp/fstab.dedup-${TIMESTAMP} /etc/fstab" || {
        log_error "Failed to replace fstab"
        # Attempt restore
        log_warn "Attempting to restore backup..."
        ssh "${EXEC_USER}@${host}" "sudo cp /etc/fstab.backup-${TIMESTAMP} /etc/fstab"
        return 1
    }
    
    # Clean up temp file
    ssh "${EXEC_USER}@${host}" "rm /tmp/fstab.dedup-${TIMESTAMP}"
    
    log_success "Duplicates removed"
}

# Reload systemd after fstab changes
reload_systemd() {
    local host="$1"
    
    log_info "Reloading systemd on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would run: sudo systemctl daemon-reload"
        return 0
    fi
    
    ssh "${EXEC_USER}@${host}" "sudo systemctl daemon-reload" || {
        log_error "Failed to reload systemd"
        return 1
    }
    
    log_success "Systemd reloaded"
}

# Check systemd-fstab-generator for errors
check_generator_errors() {
    local host="$1"
    
    log_info "Checking systemd-fstab-generator status on $host..."
    
    local errors
    errors=$(ssh "${EXEC_USER}@${host}" "sudo journalctl -u systemd-fstab-generator -n 10 2>/dev/null | grep -i 'error\|duplicate' || echo ''" || echo "")
    
    if [ -z "$errors" ]; then
        log_success "No generator errors found"
        return 0
    fi
    
    log_warn "Recent generator errors:"
    echo "$errors" | sed 's/^/  /'
}

# Verify fstab syntax
verify_syntax() {
    local host="$1"
    
    log_info "Verifying fstab syntax on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would verify fstab syntax"
        return 0
    fi
    
    ssh "${EXEC_USER}@${host}" "sudo mount -a --fake" > /dev/null 2>&1 && {
        log_success "fstab syntax is valid"
        return 0
    } || {
        log_error "fstab has syntax errors"
        return 1
    }
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Fixing duplicate fstab mount entries (P1 #1631)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Replica Host: $REPLICA_HOST"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${REPLICA_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to replica host"
    fi
    log_success "✓ Connected to replica"
    log_info ""
    
    # Check primary for duplicates
    log_info "Checking Primary ($PRIMARY_HOST)..."
    log_info "================================"
    primary_dups=$(detect_duplicates "$PRIMARY_HOST") || true
    
    if [ -n "$primary_dups" ]; then
        while IFS= read -r mount_point; do
            [ -z "$mount_point" ] && continue
            show_entries "$PRIMARY_HOST" "$mount_point"
        done <<< "$primary_dups"
        
        remove_duplicates "$PRIMARY_HOST" || return 1
        reload_systemd "$PRIMARY_HOST" || return 1
    fi
    log_info ""
    
    # Check replica for duplicates
    log_info "Checking Replica ($REPLICA_HOST)..."
    log_info "===================================="
    replica_dups=$(detect_duplicates "$REPLICA_HOST") || true
    
    if [ -n "$replica_dups" ]; then
        while IFS= read -r mount_point; do
            [ -z "$mount_point" ] && continue
            show_entries "$REPLICA_HOST" "$mount_point"
        done <<< "$replica_dups"
        
        remove_duplicates "$REPLICA_HOST" || return 1
        reload_systemd "$REPLICA_HOST" || return 1
    fi
    log_info ""
    
    # Verify results
    log_info "Verifying final state..."
    log_info ""
    
    log_info "Checking systemd-fstab-generator on primary..."
    check_generator_errors "$PRIMARY_HOST"
    log_info ""
    
    log_info "Checking systemd-fstab-generator on replica..."
    check_generator_errors "$REPLICA_HOST"
    log_info ""
    
    log_info "Verifying fstab syntax..."
    verify_syntax "$PRIMARY_HOST" || log_warn "Primary fstab syntax may have issues"
    verify_syntax "$REPLICA_HOST" || log_warn "Replica fstab syntax may have issues"
    log_info ""
    
    log_success "========================================================================"
    log_success "Duplicate fstab entry removal complete!"
    log_success "========================================================================"
    log_info ""
    log_info "Rollback (if needed):"
    log_info "  sudo cp /etc/fstab.backup-${TIMESTAMP} /etc/fstab"
    log_info "  sudo systemctl daemon-reload"
}

main "$@"
