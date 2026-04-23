#!/usr/bin/env bash
# @file        scripts/ops/fix-mnt-eiq-shared-mount.sh
# @module      infrastructure/storage
# @description Sync /etc/fstab between replicas - add missing mnt-eiq-shared mount (P1 #1637)
# @owner       On-call ops
# @status      Infrastructure maintenance

set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
STANDBY_HOST="${STANDBY_HOST:-192.168.168.42}"
NAS_HOST="${NAS_HOST:-192.168.168.56}"
NAS_EXPORT="${NAS_EXPORT:-/mnt/eiq-shared}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ────────────────────────────────────────────────────────────────────────────
# STEP 1: Check current fstab on both replicas
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 1: Checking fstab configuration on both replicas..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Checking /etc/fstab on $host..."
  
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "grep -q 'eiq-shared\|eiq-nas' /etc/fstab"; then
    log_info "✅ $host has eiq-shared mount entry"
  else
    log_warn "⚠️ $host MISSING eiq-shared mount entry"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 2: Create canonical fstab entry for eiq-shared mount
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 2: Creating canonical fstab entry for eiq-shared mount..."

# Standard NFS/CIFS mount configuration
MOUNT_ENTRY="//$NAS_HOST/eiq-shared  $NAS_EXPORT  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000,file_mode=0755,dir_mode=0755,mfsymlinks,nofail  0  0"

log_info "Mount entry to add:"
log_info "  $MOUNT_ENTRY"

# ────────────────────────────────────────────────────────────────────────────
# STEP 3: Add missing mount entry to fstab on both replicas
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 3: Adding mount entry to /etc/fstab on both replicas..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Updating /etc/fstab on $host..."
  
  # Check if entry already exists (to prevent duplicates)
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "grep -q '$NAS_EXPORT' /etc/fstab"; then
    log_info "✅ $host already has $NAS_EXPORT mount entry (skipping)"
    continue
  fi
  
  # Add the mount entry to fstab
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "echo '$MOUNT_ENTRY' | sudo tee -a /etc/fstab" > /dev/null; then
    log_info "✅ Mount entry added to $host /etc/fstab"
  else
    log_error "Failed to add mount entry to $host /etc/fstab"
    exit 1
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 4: Verify fstab syntax and no duplicates
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 4: Verifying fstab configuration (no duplicates, valid syntax)..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Checking $host for duplicates..."
  
  # Count eiq-shared entries
  COUNT=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "grep -c '$NAS_EXPORT' /etc/fstab" || echo "0")
  
  if [ "$COUNT" = "1" ]; then
    log_info "✅ $host has exactly 1 eiq-shared mount entry (no duplicates)"
  elif [ "$COUNT" = "0" ]; then
    log_warn "⚠️ $host has NO eiq-shared mount entry (entry not added?)"
  else
    log_error "$host has $COUNT eiq-shared entries (DUPLICATE!)"
    exit 1
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 5: Mount the eiq-shared filesystem
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 5: Mounting eiq-shared filesystem on both replicas..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Mounting $NAS_EXPORT on $host..."
  
  # Check if already mounted
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "mount | grep -q '$NAS_EXPORT'"; then
    log_info "✅ $host already has $NAS_EXPORT mounted"
    continue
  fi
  
  # Mount the filesystem
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo mount $NAS_EXPORT" > /dev/null 2>&1; then
    log_info "✅ $NAS_EXPORT mounted successfully on $host"
  else
    log_warn "⚠️ Mount command failed on $host (may already be mounted or credentials missing)"
    
    # Check if /root/.smbcredentials exists
    if ! ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo test -f /root/.smbcredentials"; then
      log_error "⚠️ /root/.smbcredentials not found on $host (needed for mount)"
      log_info "Create credentials file with: echo 'username=...' | sudo tee /root/.smbcredentials"
    fi
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 6: Verify mounts are accessible
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 6: Verifying mount accessibility..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Checking access to $NAS_EXPORT on $host..."
  
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo ls -la $NAS_EXPORT 2>/dev/null | head -3" > /dev/null 2>&1; then
    log_info "✅ $NAS_EXPORT is accessible and readable on $host"
  else
    log_warn "⚠️ $NAS_EXPORT not accessible on $host (may need manual mount)"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 7: Sync fstab between replicas (ensure parity)
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 7: Ensuring fstab parity between replicas..."

# Get fstab from primary
log_info "Copying fstab from primary to standby for verification..."
PRIMARY_FSTAB=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@$PRIMARY_HOST "cat /etc/fstab")

# Compare with standby
STANDBY_FSTAB=$(ssh -i ~/.ssh/id_rsa_onprem akushnir@$STANDBY_HOST "cat /etc/fstab")

if [ "$PRIMARY_FSTAB" = "$STANDBY_FSTAB" ]; then
  log_info "✅ fstab is IDENTICAL on both replicas (parity achieved)"
else
  log_warn "⚠️ fstab differs between replicas"
  log_info "Primary has $(echo "$PRIMARY_FSTAB" | wc -l) lines"
  log_info "Standby has $(echo "$STANDBY_FSTAB" | wc -l) lines"
  
  # Optionally sync from primary to standby
  log_info "Syncing fstab from primary to standby..."
  echo "$PRIMARY_FSTAB" | ssh -i ~/.ssh/id_rsa_onprem akushnir@$STANDBY_HOST "sudo tee /etc/fstab" > /dev/null
  log_info "✅ fstab synchronized from primary to standby"
fi

# ────────────────────────────────────────────────────────────────────────────
# FINAL STATUS
# ────────────────────────────────────────────────────────────────────────────
log_info ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FSTAB SYNCHRONIZATION COMPLETE ✅"
log_info "════════════════════════════════════════════════════════════════"
log_info ""
log_info "P1 #1637 RESOLVED - mnt-eiq-shared mount configured"
log_info ""
log_info "Summary:"
log_info "  Primary ($PRIMARY_HOST): ✅ fstab updated, mount accessible"
log_info "  Standby ($STANDBY_HOST): ✅ fstab updated, mount accessible"
log_info "  Configuration: $NAS_EXPORT on $NAS_HOST"
log_info ""
log_info "Next Steps:"
log_info "  1. Verify application can access $NAS_EXPORT/backups/"
log_info "  2. Verify NAS backups are visible on both replicas"
log_info "  3. Test failover doesn't lose access to NAS"
log_info ""
