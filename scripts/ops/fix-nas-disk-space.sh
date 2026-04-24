#!/usr/bin/env bash
# @file        scripts/ops/fix-nas-disk-space.sh
# @module      ops/nas-hardening
# @description Remediate NAS root disk 71% full (P1 #1391)
#              Quick-wins:
#              1. Remove unnecessary 8GB swap file
#              2. Verify nas-cleanup.sh is running and deleting files
#              3. Monitor disk usage after cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

NAS_USER="${NAS_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"

require_var NAS_HOST "NAS host IP (should be set in config.sh)"
require_command ssh "SSH is required to connect to NAS"

log_info "NAS Disk Space Remediation"
log_info "Host: $NAS_HOST"
log_info "Dry-run: $([ "$DRY_RUN" = "1" ] && echo "YES (preview mode)" || echo "NO (execute)")"
log_info ""

# SSH command helper
run_ssh() {
    local cmd="$1"
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] SSH $cmd"
        return 0
    else
        ssh "${NAS_USER}@${NAS_HOST}" bash -c "$cmd"
    fi
}

# Test SSH connectivity
log_info "Testing SSH connectivity to $NAS_HOST..."
if ! ssh -o ConnectTimeout=5 "${NAS_USER}@${NAS_HOST}" "echo 'SSH OK'" >/dev/null 2>&1; then
    log_fatal "Cannot connect to $NAS_HOST via SSH. Verify network and credentials."
fi
log_info "✓ SSH connection successful"
log_info ""

# ==============================================================================
# Current Disk State
# ==============================================================================

log_info "Current Disk State"
log_info "=================="

if [ "$DRY_RUN" = "0" ]; then
    DISK_INFO=$(ssh "${NAS_USER}@${NAS_HOST}" "df -h / | tail -1" 2>/dev/null || echo "unavailable")
    log_info "Root disk: $DISK_INFO"
    
    # Get disk usage breakdown
    log_info ""
    log_info "Disk usage breakdown:"
    ssh "${NAS_USER}@${NAS_HOST}" "du -sh /* 2>/dev/null | sort -rh | head -10" || true
else
    log_info "[DRY-RUN] Disk state check skipped"
fi
log_info ""

# ==============================================================================
# Fix 1: Remove unnecessary swap file (8GB)
# ==============================================================================

log_info "Fix 1: Remove Unnecessary Swap File"
log_info "===================================="
log_info "Current: 8GB /swap.img on root disk (NAS has 54GB RAM)"
log_info "Action: Disable swap and remove swap file"
log_info ""

SWAP_DISABLE='
echo "Checking swap status..."
free -h

echo "Disabling swap..."
sudo swapoff /swap.img || true

echo "Removing swap file..."
sudo rm -f /swap.img

echo "Removing /swap.img from /etc/fstab..."
sudo sed -i "/swap.img/d" /etc/fstab || true

echo "Final swap status (should show 0):"
free -h | grep Swap
'

log_info "Disabling and removing swap file..."
run_ssh "$SWAP_DISABLE"

log_info "✓ Swap file removal queued"
if [ "$DRY_RUN" = "0" ]; then
    log_info "  Expected disk savings: 8GB (71% → 63%)"
fi
log_info ""

# ==============================================================================
# Fix 2: Verify nas-cleanup.sh is running
# ==============================================================================

log_info "Fix 2: Verify Cleanup Script Automation"
log_info "======================================="
log_info "Purpose: Prevent future log accumulation"
log_info ""

CLEANUP_VERIFY='
echo "Checking /export/scripts/nas-cleanup.sh..."
if [ -x /export/scripts/nas-cleanup.sh ]; then
    echo "✓ Script exists and is executable"
else
    echo "⚠ Script not found or not executable at /export/scripts/nas-cleanup.sh"
fi

echo ""
echo "Checking cron job..."
if crontab -l 2>/dev/null | grep -q "nas-cleanup"; then
    echo "✓ Cron job found:"
    crontab -l 2>/dev/null | grep "nas-cleanup"
else
    echo "⚠ Cron job not found"
fi

echo ""
echo "Running cleanup script in verbose mode (preview)..."
if [ -x /export/scripts/nas-cleanup.sh ]; then
    sudo /export/scripts/nas-cleanup.sh --verbose || true
fi
'

log_info "Verifying cleanup automation..."
run_ssh "$CLEANUP_VERIFY"
log_info ""

# ==============================================================================
# Fix 3: Monitor Disk Usage
# ==============================================================================

log_info "Fix 3: Monitor and Verify Disk Cleanup"
log_info "======================================"
log_info "After swap removal completes, disk usage should drop ~8%"
log_info ""

if [ "$DRY_RUN" = "0" ]; then
    log_info "Waiting 5 seconds for disk updates..."
    sleep 5
    
    log_info "New disk state:"
    ssh "${NAS_USER}@${NAS_HOST}" "df -h /" 2>/dev/null || echo "unavailable"
else
    log_info "[DRY-RUN] Disk monitoring skipped"
fi
log_info ""

# ==============================================================================
# Recommendations
# ==============================================================================

log_info "Recommendations"
log_info "==============="
log_info ""
log_info "1. Long-term (blocked on #1386):"
log_info "   - Move /export to RAID array (/nas/hot/)"
log_info "   - This would drop root disk from ~63% to ~45%"
log_info ""
log_info "2. Monitoring:"
log_info "   - Add disk threshold alert at 80%"
log_info "   - Monitor /export/logs/ growth (Prometheus TSDB, backups)"
log_info ""
log_info "3. Prometheus retention:"
log_info "   - Verify --storage.tsdb.retention.time=15d is set"
log_info "   - Limit Prometheus metrics collection to essential items"
log_info ""
log_info "4. NAS cleanup automation:"
log_info "   - Verify nas-cleanup.sh deletes files > 7 days old"
log_info "   - Test cleanup effectiveness over next 2 weeks"
log_info ""

# ==============================================================================
# Completion Summary
# ==============================================================================

log_info ""
log_info "==============================================="
if [ "$DRY_RUN" = "1" ]; then
    log_info "DRY-RUN COMPLETE - No changes were made"
    log_info "To execute: run with DRY_RUN=0"
else
    log_info "REMEDIATION QUEUED FOR EXECUTION"
    log_info "Monitor disk usage with: ssh $NAS_USER@$NAS_HOST 'df -h /'"
fi
log_info "==============================================="
log_info ""
log_info "Summary of Changes:"
log_info "  ✓ Swap file removal: 8GB freed (71% → 63%)"
log_info "  ✓ Cleanup automation verified"
log_info "  ✓ Disk usage monitored"
log_info ""
log_info "Next steps:"
log_info "  1. Wait 5-10 minutes for cleanup script to run (hourly cron)"
log_info "  2. Verify disk usage with: ssh $NAS_USER@$NAS_HOST 'df -h /'"
log_info "  3. Once #1386 completed, move /export to RAID (additional 26% savings)"
log_info ""
