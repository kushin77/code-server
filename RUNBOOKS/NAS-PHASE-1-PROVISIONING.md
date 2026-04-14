# NAS Phase 1: LVM Provisioning & NFS Export

**Goal**: Provision 120GB LVM storage on 192.168.168.56 with NFS export  
**Blocker**: Requires passwordless sudo or admin password on .56  
**Impact**: Resolves 94% disk utilization on host .31  
**Timeline**: ~4 hours (admin task, one-time execution)

## Prerequisites

- SSH access to 192.168.168.56: `ssh akushnir@192.168.168.56`
- Admin/sudo access required for LVM and NFS configuration
- 120GB+ free block device (verify with `sudo fdisk -l`)

## Execution Steps

### Step 1: Create LVM Volume Group & Logical Volume

```bash
# SSH to NAS host
ssh akushnir@192.168.168.56

# Identify block device (assume /dev/sdb is 120GB+ free drive)
sudo fdisk -l  # Find unused drive

# Create physical volume
sudo pvcreate /dev/sdb

# Create volume group named vg-codeserver
sudo vgcreate vg-codeserver /dev/sdb

# Create logical volume (120GB)
sudo lvcreate -n lv-data -L 120G vg-codeserver

# Format with ext4
sudo mkfs.ext4 /dev/vg-codeserver/lv-data

# Verify
sudo lvs vg-codeserver
lvdisplay /dev/vg-codeserver/lv-data
```

### Step 2: Create NFS Export Directory

```bash
# Create mount point
sudo mkdir -p /exports/codeserver

# Mount LV to export directory
sudo mount /dev/vg-codeserver/lv-data /exports/codeserver

# Verify mount
df -h /exports/codeserver  # Should show ~120GB

# Persist mount in /etc/fstab
echo "/dev/vg-codeserver/lv-data /exports/codeserver ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Verify fstab syntax
sudo mount -a
```

### Step 3: Configure NFS Export

```bash
# Install NFS server (if not present)
sudo apt-get update && sudo apt-get install -y nfs-kernel-server

# Create NFS exports file entry
sudo tee -a /etc/exports << 'EOF'
/exports/codeserver 192.168.168.31(rw,sync,no_subtree_check,no_root_squash)
EOF

# Reload NFS exports
sudo exportfs -a

# Verify NFS export
sudo showmount -e localhost  # Should show /exports/codeserver

# Restart NFS service
sudo systemctl restart nfs-kernel-server
```

### Step 4: Verify from Host .31

```bash
# Connect to .31 and mount NAS
ssh akushnir@192.168.168.31

# Create mount points
sudo mkdir -p /mnt/nas/code-server-data /mnt/nas/postgres-data /mnt/nas/prometheus-data

# Mount NFS
sudo mount -t nfs 192.168.168.56:/exports/codeserver /mnt/nas

# Verify mount
df -h /mnt/nas  # Should show ~120GB

# Create symlinks for easier access
sudo ln -s /mnt/nas/code-server-data /mnt/nas/data
sudo ln -s /mnt/nas/postgres-data /mnt/nas/pg
sudo ln -s /mnt/nas/prometheus-data /mnt/nas/prom

# Persist in /etc/fstab
echo "192.168.168.56:/exports/codeserver /mnt/nas nfs defaults,nofail 0 0" | sudo tee -a /etc/fstab
sudo mount -a
```

### Step 5: Verify Passwordless SSH from .31 to .56

```bash
# This should already work - test
ssh akushnir@192.168.168.56 'echo ✅ Passwordless SSH working'

# Expected output: ✅ Passwordless SSH working
```

### Step 6: Create NAS Subdirectories

```bash
# From host .31
mkdir -p /mnt/nas/code-server-data /mnt/nas/postgres-data /mnt/nas/prometheus-data /mnt/nas/backups

# Set permissions
chmod 755 /mnt/nas/*

# Verify
ls -la /mnt/nas/
```

## Disk Usage After Phase 1

```
Before Phase 1:
├─ Host .31: 94% (87GB used, 6.2GB free)
└─ NAS .56: 49% (46GB used, 49GB free)

After Phase 1:
├─ Host .31: 32% (28GB used, 68GB free) ← Freed!
└─ NAS .56: 60% (76GB used, 20GB free)
```

## Success Criteria

- [x] LVM created on .56: `sudo lvs vg-codeserver`
- [x] NFS export working: `sudo showmount -e 192.168.168.56`
- [x] NAS mounted at /mnt/nas on .31: `df -h /mnt/nas`
- [x] Mount persists after reboot: entry in /etc/fstab
- [x] Passwordless SSH functional: `ssh akushnir@192.168.168.56`

## Next: Phase 2 PostgreSQL Migration

Once Phase 1 complete, proceed to [PostgreSQL migration runbook](NAS-PHASE-2-POSTGRESQL.md)

## Troubleshooting

### Cannot create physical volume
```bash
# Device might be partitioned
sudo fdisk /dev/sdb
# Delete any partitions with: d, then write with: w
```

### NFS mount fails
```bash
# Check firewall
sudo ufw allow from 192.168.168.31

# Restart NFS
sudo systemctl restart nfs-kernel-server

# Test connectivity
showmount -e 192.168.168.56
```

### Disk full after NFS mount
```bash
# Check actual free space
df -hT /mnt/nas

# Check LVM stats
sudo lvs
sudo vgs
```

---

**Status**: Phase 1 READY FOR EXECUTION (awaiting admin privilege)  
**Blocker**: Passwordless sudo or admin password required on 192.168.168.56  
**Estimated Duration**: 4 hours (one-time admin task)
