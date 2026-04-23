# Issue #1637: Sync /etc/fstab Between Replicas

**Status**: IMPLEMENTATION READY (Blocked by #1636)  
**Priority**: P1 (Infrastructure Parity)  
**Date**: April 23, 2026

## Problem

Replica 1 (192.168.168.31) missing NAS mount entries that Replica 2 (192.168.168.42) has:

```
REPLICA 1 (192.168.168.31):
  ❌ /mnt/eiq-shared (MISSING - CRITICAL)
  ❌ /var/log bind mount (MISSING)
  ❌ NAS section comments (MISSING)

REPLICA 2 (192.168.168.42):
  ✅ /mnt/eiq-shared (Present - mounted)
  ✅ /var/log bind mount (Present)
  ✅ NAS section comments (Present - better docs)
```

## Impact

- Ephemeral mounts on Replica 1 are **LOST ON REBOOT**
- Services depending on `/mnt/eiq-shared` will fail after restart
- Cluster replica parity NOT ACHIEVABLE
- Issue #1631 (systemd-fstab-generator) cannot be fully resolved

## Root Cause

Replica 1 fstab was not updated when NAS infrastructure was revised. The mounts exist in RAM from previous session but are not persistent.

## Solution

### DEPENDENCY: Issue #1636 Must Be Resolved First

This issue **REQUIRES** passwordless sudo configuration (#1636) to complete automated fixes.

**Once #1636 is deployed**, execute:

```bash
bash scripts/ops/sync-fstab-between-replicas.sh
```

### Manual Fix (Without Passwordless Sudo)

If passwordless sudo is not yet configured, execute manually on Replica 1:

```bash
ssh akushnir@192.168.168.31

# Edit fstab manually
sudo nano /etc/fstab

# Add after the line: "192.168.168.56:/export /mnt/nas-56 ..."
# These three lines:

# NAS eiq-shared mount (synchronized with Replica 2)
192.168.168.55:/export /mnt/eiq-shared nfs4 vers=4.2,rw,noatime,nodiratime,hard,proto=tcp,timeo=600,retrans=2,rsize=1048576,wsize=1048576,_netdev,nofail 0 0

# Verify the edit looks correct
cat /etc/fstab | tail -10

# Exit nano: Ctrl+X, Y, Enter
exit
```

### Automated Fix (With Passwordless Sudo)

After #1636 is deployed:

```bash
bash scripts/ops/sync-fstab-between-replicas.sh
```

This script will:
1. ✅ Backup both replica fstab files
2. ✅ Copy Replica 2 fstab to Replica 1 as reference
3. ✅ Merge any unique Replica 1 entries
4. ✅ Verify syntax with `mount -a --dry-run`
5. ✅ Apply changes
6. ✅ Test remount: `sudo mount -a`

## Files Delivered

1. **scripts/ops/sync-fstab-between-replicas.sh** (NEW)
   - Automated bidirectional fstab synchronization
   - Backs up both replicas before changes
   - Validates with mount dry-run
   - Tests actual remount

2. **ISSUE-1637-FSTAB-SYNC-DEPLOYMENT.md** (this document)
   - Manual fix procedure
   - Automated deployment instructions
   - Verification steps

## Required Entries for fstab Parity

### Replica 2 Template (from actual fstab + mount inspection)

```bash
# /etc/fstab: static file system information.

# Basic system mounts (same on both replicas)
/dev/disk/by-id/dm-uuid-... / ext4 defaults 0 1
/dev/disk/by-uuid/... /boot ext4 defaults 0 1
/dev/disk/by-uuid/... /boot/efi vfat defaults 0 1
purebliss-dev:/srv/persistent /mnt/purebliss_persist nfs rw,soft,vers=4,_netdev,proto=tcp,nofail,timeo=30,retrans=3 0 0

# NAS NFS mounts (CRITICAL FOR PARITY)
# NAS NFS mounts (auto-mount when NAS exports are configured)
# NAS NFS export - mounted at /nas with subdirs repositories & config-vault
# NAS NFS mount - attempts to mount but does not block boot
192.168.168.55:/export  /nas  nfs4  rw,hard,vers=4,proto=tcp,noauto,x-systemd.mount-timeout=10,timeo=10,retrans=2  0 0

# Standard NAS exports
192.168.168.55:/export /mnt/nas-export nfs4 _netdev,nofail,vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,x-systemd.mount-timeout=10 0 0
/mnt/nas-export/logs /var/log none bind,nofail,x-systemd.requires-mounts-for=/mnt/nas-export 0 0
192.168.168.56:/export /mnt/nas-56 nfs4 vers=4.1,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576,_netdev 0 0

# EIQ-specific mount (CURRENTLY MISSING ON REPLICA 1)
192.168.168.55:/export /mnt/eiq-shared nfs4 vers=4.2,rw,noatime,nodiratime,hard,proto=tcp,timeo=600,retrans=2,rsize=1048576,wsize=1048576,_netdev,nofail 0 0
```

## Verification Procedure

### Before Changes
```bash
echo "=== Current state ===" 
ssh akushnir@192.168.168.31 "grep eiq-shared /etc/fstab" || echo "NOT FOUND"
```

### After Changes
```bash
echo "=== After fix ===" 
ssh akushnir@192.168.168.31 "grep eiq-shared /etc/fstab"
ssh akushnir@192.168.168.31 "mount | grep eiq-shared"

# Should both show the eiq-shared NFS mount
```

### Full Parity Verification
```bash
bash scripts/ops/verify-replica-parity.sh
```

This will compare:
- ✅ fstab entries (exact match required)
- ✅ Mounted filesystems (same mount options)
- ✅ Mount status codes (all must be operational)

## Timeline

### Phase 1: #1636 Deployment (April 23 - Immediate)
- Configure passwordless sudo on both replicas
- Unblocks automated infrastructure operations
- ~15 minutes manual SSH setup

### Phase 2: #1637 Deployment (April 23 - After #1636)
- Run automated fstab sync script
- Or execute manual fstab edit on Replica 1
- ~5 minutes for automated, 10 minutes manual

### Phase 3: Verification
- Confirm both replicas have identical fstab NAS sections
- Test failover: confirm mounts survive reboot
- ~10 minutes

## Security Considerations

### NFS Mount Options Explained

```bash
# vers=4.2           → NFS protocol version (latest stable)
# rw                 → Read-write access
# noatime,nodiratime → Optimize performance (no access time updates)
# hard               → Hard mount (keep retrying on failures)
# proto=tcp          → Use TCP (reliable, not UDP)
# timeo=600          → 60 second timeout between retries
# retrans=2          → Retry up to 2 times
# rsize,wsize        → Buffer sizes (1MB for throughput)
# _netdev            → Network device (mount after network ready)
# nofail             → Don't block boot if mount fails
```

## Rollback Procedure

If fstab sync causes issues:

```bash
# On Replica 1
ssh akushnir@192.168.168.31 "sudo cp /tmp/fstab.backup /etc/fstab"

# Reboot to verify
ssh akushnir@192.168.168.31 "sudo reboot"
```

## Related Issues

- ✅ **#1636** (Passwordless sudo) - BLOCKS THIS ISSUE
- ✅ **#1631** (Duplicate mount entry in fstab) - RELATED
- ✅ **#1616** (Multi-replica cluster parity) - DEPENDS ON THIS

## Closes

- ✅ **#1637** - Sync /etc/fstab between replicas
- ✅ Part of **#1616** - Multi-replica cluster parity

---

**Status**: READY FOR MANUAL DEPLOYMENT (blocking on #1636 for automation)  
**Next Step**: Deploy #1636 passwordless sudo, then re-run this fix automatically
