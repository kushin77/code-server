# NAS Integration Specification for 192.168.168.31

**Purpose**: Comprehensive NAS mounting, configuration, and backup automation specifications  
**Status**: Supporting document for #142 NAS Integration  
**Target Host**: 192.168.168.31 (192.168.168.0/24 network)  
**NAS Protocols**: NFS4 (primary), NFS3 (fallback), iSCSI (optional)

---

## Quick Start: NAS Mount Decision Matrix

| Requirement | NFS4 | NFS3 | iSCSI | Notes |
|---|---|---|---|---|
| **Primary Use** | Model storage, code | Legacy systems | Block storage | |
| **Performance** | ⭐⭐⭐ (High) | ⭐⭐ (Medium) | ⭐⭐⭐⭐ (Very High) | NFS4 > NFS3; iSCSI best for I/O intensive |
| **Security** | ⭐⭐⭐ (Strong - Kerberos) | ⭐ (UID/GID only) | ⭐⭐⭐⭐ (Encryption) | NFS4 with Kerberos recommended |
| **Complexity** | Medium | Low | High | NFS3 simplest, iSCSI most complex |
| **Latency** | <5ms (typical) | <5ms (typical) | <1ms (excellent) | iSCSI lowest latency |
| **Bandwidth** | 100 MB/s+ | 100 MB/s+ | 200 MB/s+ | iSCSI typically faster |
| **Setup Time** | 20 min | 10 min | 45 min | NFS3 fastest to deploy |
| **Recommended** | ✓ Yes (default) | For legacy only | For high-I/O workloads | Choose NFS4 unless constrained |

**Recommendation for 192.168.168.31**: 
- **Primary**: NFS4 (performance + security)
- **Fallback**: NFS3 (compatibility)
- **Optional**: iSCSI (if additional block storage needed for databases)

---

## NAS Mount Points Architecture

### Proposed Mount Structure

```
/mnt/models           # Ollama models (large files, <5ms latency requirement)
├── {nfs4} ollama-models share
├── Capacity: 200GB
├── Performance: Critical path for inference
└── Backup: Hourly rsync to backup NAS

/mnt/data             # Application data (medium I/O)
├── {nfs4} data share
├── Capacity: 100GB
├── Performance: Standard (non-critical)
└── Backup: Daily tar.gz to NAS2

/mnt/backups          # Local backup staging (high I/O temporary)
├── {nfs3} backups share
├── Capacity: 300GB (staging area)
├── Performance: Temporary staging only
└── Purge: After rsync to remote

/mnt/archive          # Long-term cold storage (infrequent access)
├── {nfs4} archive share
├── Capacity: 500GB
├── Performance: Non-critical
└── Backup: Quarterly to external storage
```

---

## NAS Configuration Specifications

### NFS4 Primary Mount (Model Storage)

#### Network Specifications
```
NAS Server IP: 192.168.168.10
Export Path: /export/models
Mount Path: /mnt/models
Protocol: NFSv4.1 with Kerberos (recommended)
Network: Direct gigabit Ethernet (client-NAS)
MTU: 1500 (standard Ethernet)
```

#### Performance Requirements
```
Target Latency: <5ms (p99)
Target Throughput: 150 MB/s minimum
Target IOPS: 5,000+ random read IOPS
Availability: 99.99% (RTO <30s)
Consistency: Strong (metadata + data)
```

#### Capacity Planning
```
Ollama Model Storage:
  - llama2:70b-chat: ~40GB (primary)
  - llama2:13b-chat: ~8GB (secondary)
  - codegemma:7b: ~4GB (utility)
  - mistral:7b: ~4GB (alternative)
  - Additional models: ~50GB (growth)
  Subtotal: ~106GB (reserved 200GB for headroom)

Free Space Target: Always maintain >30% free (60GB minimum)
Capacity Alert: Trigger alert at 75% utilization
```

#### Mount Configuration (systemd)

**File**: /etc/systemd/system/mnt-models.mount

```ini
[Unit]
Description=NAS Models Storage Mount (NFSv4)
After=network-online.target
Wants=network-online.target
Documentation=man:mount.nfs(8)

[Mount]
Type=nfs4
What=192.168.168.10:/export/models
Where=/mnt/models
Options=rw,sync,hard,intr,rsize=131072,wsize=131072,timeo=600,retrans=2,sec=krb5:krb5i:krb5p
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

**Enable and Mount**:
```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-models.mount
sudo systemctl start mnt-models.mount
sudo systemctl status mnt-models.mount
```

**Verification**:
```bash
mount | grep /mnt/models
df -h /mnt/models
cat /proc/mounts | grep models
```

---

### NFS3 Fallback Mount (Compatibility)

#### Configuration (systemd)

**File**: /etc/systemd/system/mnt-backup.mount

```ini
[Unit]
Description=NAS Backup Storage Mount (NFSv3)
After=network-online.target
Wants=network-online.target
ConditionVirtualization=!container

[Mount]
Type=nfs
What=192.168.168.10:/export/backups
Where=/mnt/backups
Options=rw,sync,hard,intr,rsize=262144,wsize=262144,timeo=600,retrans=2,vers=3
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

**Failover Strategy**:
- Monitor NFS4 connectivity
- Auto-unmount and switch to NFS3 on timeout
- Log failover events for diagnostics
- Alert on repeated failovers

---

### iSCSI Block Storage (Optional High-I/O)

#### When to Use iSCSI

**Recommended for**:
- Database indices requiring <1ms latency
- High-frequency model parameter updates
- Real-time model fine-tuning workloads
- Cache acceleration for large models

**Not recommended for**:
- Read-heavy model serving (use NFS4)
- Infrequent backups (overhead too high)
- Single-node deployments (complexity not justified)

#### iSCSI Configuration

**iSCSI Initiator Setup**:
```bash
# Install iSCSI initiator
sudo apt install -y open-iscsi

# Configure initiator name
sudo nano /etc/iscsi/initiatorname.iscsi
# Edit: InitiatorName=iqn.2026-04.local:192-168-168-31

# Discover NAS iSCSI targets
sudo iscsiadm -m discovery -t st -p 192.168.168.10:3260

# Log in to target
sudo iscsiadm -m node -T iqn.2026-04.nas:lun0 -p 192.168.168.10:3260 -l

# Verify
sudo lsblk | grep iscsi
sudo iscsiadm -m session
```

**Create LVM Volume**:
```bash
# Create LVM volume on iSCSI LUN
sudo pvcreate /dev/sdb
sudo vgcreate vg-models /dev/sdb
sudo lvcreate -L 100G -n models vg-models

# Format with ext4
sudo mkfs.ext4 /dev/vg-models/models

# Mount via systemd (/etc/systemd/system/mnt-iscsi.mount)
[Mount]
Type=ext4
What=/dev/vg-models/models
Where=/mnt/iscsi
Options=defaults,nofail
```

---

## NAS Mount Validation and Monitoring

### Pre-Mount Validation

```bash
#!/bin/bash
# Validate NAS accessibility before mounting

# 1. Check network connectivity
ping -c 3 192.168.168.10 || { echo "NAS unreachable"; exit 1; }

# 2. Check NFS service availability
rpcinfo -p 192.168.168.10 | grep nfs || { echo "NFS service down"; exit 1; }

# 3. Check export availability
showmount -e 192.168.168.10 | grep models || { echo "Model export not available"; exit 1; }

# 4. Check required packages
dpkg -l | grep -E "nfs-common|open-iscsi" || { echo "NFS client not installed"; exit 1; }

echo "✓ All pre-mount validations passed"
```

### Post-Mount Validation

```bash
#!/bin/bash
# Validate mounted NAS storage

echo "=== NAS Mount Validation ==="

# 1. Check mount active
mountpoint -q /mnt/models && echo "✓ /mnt/models mounted" || { echo "✗ /mnt/models not mounted"; exit 1; }

# 2. Check accessibility
touch /mnt/models/.validation-test && echo "✓ /mnt/models readable/writable" || { echo "✗ Permission denied"; exit 1; }

# 3. Check performance
dd if=/dev/zero of=/mnt/models/perf-test bs=1M count=100 2>&1 | \
  awk '/copied/ {gsub(/[^0-9.]/,""); print "  Write speed: " $1 " MB/s"}'

# 4. Check latency
for i in {1..5}; do
  latency=$(date +%s%N)
  ls /mnt/models > /dev/null
  latency=$(( ($(date +%s%N) - latency) / 1000000 ))
  echo "  Latency $i: ${latency}ms"
done | awk '{sum+=$3; count++} END {print "  Average: " sum/count "ms"}'

# 5. Check capacity
df -h /mnt/models | awk 'NR==2 {print "  Total: " $2 ", Used: " $3 ", Available: " $4 " (" $5 ")"}'

# 6. Check for stale mounts
timeout 5 ls /mnt/models > /dev/null || echo "  ⚠ Mount appears stale (timeout)"

echo "✓ Mount validation complete"
```

### Continuous Health Monitoring

```bash
#!/bin/bash
# Monitor NAS mount health every 60 seconds

MOUNT_POINT="/mnt/models"
CHECK_INTERVAL=60
ALERT_THRESHOLD=3  # Failed checks before alert

consecutive_failures=0

while true; do
  # Check mount status
  if mountpoint -q "$MOUNT_POINT"; then
    # Check responsiveness
    if timeout 5 ls "$MOUNT_POINT" > /dev/null 2>&1; then
      consecutive_failures=0
    else
      consecutive_failures=$((consecutive_failures + 1))
      echo "$(date): Mount check $consecutive_failures failed"
      
      if [[ $consecutive_failures -ge $ALERT_THRESHOLD ]]; then
        echo "$(date): ALERT: NAS mount appears unresponsive"
        # Trigger alert (email, slack, pagerduty, etc.)
      fi
    fi
  else
    consecutive_failures=$((consecutive_failures + 1))
    echo "$(date): ALERT: $MOUNT_POINT is not mounted"
  fi
  
  sleep "$CHECK_INTERVAL"
done
```

---

## Backup Automation Procedures

### Hourly Model Backup (to Secondary NAS)

**File**: /etc/systemd/system/nas-model-backup.timer

```ini
[Unit]
Description=NAS Model Backup Timer
Requires=nas-model-backup.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min

[Install]
WantedBy=timers.target
```

**File**: /etc/systemd/system/nas-model-backup.service

```ini
[Unit]
Description=NAS Model Backup Service
After=mnt-models.mount

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-models.sh
StandardOutput=journal
StandardError=journal
```

**Backup Script**: /usr/local/bin/backup-models.sh

```bash
#!/bin/bash
# Hourly backup of Ollama models to secondary NAS

set -e

BACKUP_LOG="/var/log/nas-backup.log"
MODELS_SOURCE="/mnt/models"
BACKUP_DEST="192.168.168.11:/export/backups/models"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Function to log with timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$BACKUP_LOG"
}

log "Starting hourly model backup..."

# Check source mount
if ! mountpoint -q "$MODELS_SOURCE"; then
  log "ERROR: $MODELS_SOURCE not mounted"
  exit 1
fi

# Perform rsync backup
log "Backing up $MODELS_SOURCE to $BACKUP_DEST"
rsync -avz --delete --timeout=300 "$MODELS_SOURCE/" "$BACKUP_DEST/" || {
  log "ERROR: rsync failed"
  exit 1
}

log "Backup completed successfully"

# Cleanup old backups (keep last 24 hourly backups)
find /mnt/backups -name "models-backup-*" -mtime +1 -delete 2>/dev/null || true

log "Backup cleanup complete"
```

**Enable Backup**:
```bash
sudo systemctl daemon-reload
sudo systemctl enable nas-model-backup.timer
sudo systemctl start nas-model-backup.timer
sudo systemctl status nas-model-backup.timer
```

### Daily Full Backup (to Archive NAS)

**File**: /usr/local/bin/backup-full.sh

```bash
#!/bin/bash
# Daily tar backup of all data to archive NAS

BACKUP_LOG="/var/log/backup-full.log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/mnt/backups/full-backup-${TIMESTAMP}.tar.gz"
ARCHIVE_DEST="192.168.168.12:/export/archive"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$BACKUP_LOG"
}

log "Starting daily full backup..."

# Create tar backup
tar --exclude='/mnt/backups/*' \
    --exclude='/mnt/*/*.lock' \
    --exclude='/tmp/*' \
    -czf "$BACKUP_FILE" \
    /mnt/models \
    /mnt/data || {
  log "ERROR: tar backup failed"
  exit 1
}

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"

# Copy to archive NAS
scp "$BACKUP_FILE" "$ARCHIVE_DEST/" || {
  log "ERROR: Archive copy failed"
  exit 1
}

log "Daily backup archived successfully"

# Keep last 7 days of backups locally
find /mnt/backups -name "full-backup-*.tar.gz" -mtime +7 -delete || true
```

**Restore Procedures**:
```bash
# List available backups
ls -lh /mnt/backups/full-backup-*.tar.gz

# Restore specific backup
tar -xzf /mnt/backups/full-backup-YYYYMMDD-HHMMSS.tar.gz -C /

# Verify restoration
ls -la /mnt/models
```

---

## NAS Disaster Recovery (RTO/RPO)

### Recovery Time Objective (RTO): <30 seconds

**Procedure**:
1. **Detect failure** (5s): Health monitor detects mount timeout
2. **Trigger failover** (5s): Switch from primary to secondary NAS
3. **Remount** (15s): systemd remounts from backup
4. **Resume service** (5s): Ollama resumes inference

**Implementation**:
```bash
# In /etc/systemd/system/mnt-models.mount
OnFailure=mnt-models-failover.service

# Failover script
systemctl start mnt-models-failover
# → Unmount primary
# → Mount secondary
# → Restart Ollama
```

### Recovery Point Objective (RPO): <1 hour

**Backup Schedule**:
- **Hourly rsync**: Ollama models (most critical)
- **Daily tar**: Full data backup
- **Weekly verification**: Restore test to validate backups

**Maximum Data Loss**: ~1 hour of new models added to Ollama

---

## Storage Capacity Planning

### Current Capacity Allocation

| Mount | Total | Used | Available | Threshold | Notes |
|-------|-------|------|-----------|-----------|-------|
| /mnt/models | 200GB | ~50GB | 150GB | 150GB (75%) | Ollama models |
| /mnt/data | 100GB | ~30GB | 70GB | 75GB (75%) | Application data |
| /mnt/backups | 300GB | ~100GB | 200GB | 225GB (75%) | Staging area |
| /mnt/archive | 500GB | ~200GB | 300GB | 375GB (75%) | Cold storage |
| **Total** | **1.1TB** | **~380GB** | **~720GB** | | |

### Growth Projections (12 months)

| Scenario | 3M Growth | 6M Growth | 12M Growth | Action |
|----------|-----------|-----------|------------|--------|
| **Conservative** (+10%/month) | 15GB | 30GB | 60GB | No action needed |
| **Moderate** (+20%/month) | 30GB | 60GB | 120GB | Upgrade at 6M |
| **Aggressive** (+30%/month) | 45GB | 90GB | 180GB | Upgrade at 3M |

**Recommended Expansion**: Upgrade to 2TB NAS at 6-month mark

---

## Troubleshooting NAS Mount Issues

### Issue 1: NAS Unreachable (Mount Timeout)

```bash
# Step 1: Check network connectivity
ping -c 3 192.168.168.10

# Step 2: Check NFS service
rpcinfo -p 192.168.168.10

# Step 3: Check firewall
sudo ufw status | grep 2049
sudo ufw allow from 192.168.168.10 to any port 2049

# Step 4: Verify mount options
sudo mount -v -t nfs4 -o timeo=600,retrans=2 192.168.168.10:/export/models /mnt/models

# Step 5: Force unmount and remount
sudo umount -l /mnt/models
sudo systemctl restart mnt-models.mount
```

### Issue 2: Stale NFS Handle

```bash
# Symptom: "Stale NFS file handle" errors

# Solution 1: Remount
sudo umount -l /mnt/models
sudo mount -t nfs4 192.168.168.10:/export/models /mnt/models

# Solution 2: Increase RTO thresholds
sudo vi /etc/default/nfs-client
# Add: STATDARGS="-t 10"

# Solution 3: Check NAS export permissions
showmount -e 192.168.168.10 | grep models
```

### Issue 3: Slow Performance

```bash
# Step 1: Measure baseline latency
nfsstat -cn | grep latency

# Step 2: Check network saturation
iftop -n | grep 192.168.168.10

# Step 3: Check NAS load
# (Connect to NAS and run: nfsstat, iostat)

# Step 4: Optimize mount options
# Current (conservative): rsize=131072,wsize=131072
# Optimized (high performance): rsize=262144,wsize=262144

# Step 5: Check for retransmissions
nfsstat -cn | grep retrans
```

---

## Storage Benchmarking

### Baseline Performance Tests

```bash
#!/bin/bash
# Measure NAS performance baseline

echo "=== NAS Performance Benchmark ==="

MOUNT="/mnt/models"
TEST_FILE="$MOUNT/benchmark-test.bin"
TEST_SIZE_MB=100

echo ""
echo "→ Sequential Write Speed:"
dd if=/dev/zero of="$TEST_FILE" bs=1M count="$TEST_SIZE_MB" 2>&1 | \
  awk '/copied/ {print "  " $7 " MB/s"}'

echo ""
echo "→ Sequential Read Speed:"
dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | \
  awk '/copied/ {print "  " $7 " MB/s"}'

echo ""
echo "→ Random IOPS (4KB blocks):"
fio --testfile="$TEST_FILE" --rw=randread --bs=4k --iodepth=16 --numjobs=4 --time_based --runtime=10s 2>&1 | \
  grep "IOPS=" | head -1

echo ""
echo "→ Latency (p99):"
# Use timestamped stat calls to measure latency
for i in {1..100}; do
  start=$(date +%s%N)
  stat "$MOUNT" > /dev/null
  end=$(date +%s%N)
  echo "$(( (end - start) / 1000000 ))"
done | sort -n | tail -1 | awk '{print "  " $1 " ms"}'

rm -f "$TEST_FILE"
echo ""
echo "✓ Benchmark complete"
```

**Expected Results**:
- Sequential write: 100-150 MB/s
- Sequential read: 150-200 MB/s
- Random IOPS: 5,000+ IOPS
- Latency p99: <5 ms

---

**Document Status**: Specification complete  
**Related Issues**: #140 (IaC), #141 (GPU), #142 (NAS integration)  
**Last Updated**: April 13, 2026
