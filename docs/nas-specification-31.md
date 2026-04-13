# NAS Configuration Audit: 192.168.168.31

**Assessment Date**: April 13, 2026  
**Purpose**: Document NAS topology, capacity, performance, and connectivity for code-server-enterprise deployment  
**Status**: IN PROGRESS — Awaiting field assessment

---

## 1. NAS Overview

**Network-Attached Storage** provides persistent, highly-available storage for:
- **Ollama Models**: Large ML models (70B parameters = 40+ GB) cached on fast storage
- **Code-Server Workspaces**: User projects, extensions, configuration
- **Database Backups**: Incremental/full backup archives
- **Build Artifacts**: Docker images, compiled binaries

---

## 2. NAS Mount Points & Capacity

### Primary NAS (192.168.168.50)

| Mount Point | Allocation | Capacity | Status | Purpose |
|---|---|---|---|---|
| `/mnt/nas-primary` | [PENDING] | [PENDING] | [PENDING] | Primary storage pool |
| `/mnt/nas-primary/models` | 2TB | 2TB | [PENDING] | Ollama LLM models |
| `/mnt/nas-primary/workspaces` | 1TB | 1TB | [PENDING] | User code-server workspaces |
| `/mnt/nas-primary/backups` | 500GB | 500GB | [PENDING] | Regular backup archives |
| `/mnt/nas-primary/docker` | 500GB | 500GB | [PENDING] | Docker volume backups |

**Total Primary NAS**: [PENDING] GB (recommend: 4-5TB minimum)

### Backup NAS (192.168.168.51)

| Mount Point | Allocation | Capacity | Status | Purpose |
|---|---|---|---|---|
| `/mnt/nas-backup` | [PENDING] | [PENDING] | [PENDING] | Secondary backup pool |
| Sync Strategy | Incremental hourly | - | [PENDING] | Hot copy of primary |
| Failover Ready | Yes | - | [PENDING] | Can serve as primary if needed |

**Total Backup NAS**: [PENDING] GB (recommend: ≥50% of primary)

---

## 3. NAS Network Configuration

### Network Connectivity

| Parameter | Value | Notes |
|---|---|---|
| **NAS Primary IP** | 192.168.168.50 | Management/status access |
| **NAS Primary iSCSI Portal** | 192.168.168.50:3260 | iSCSI target (if applicable) |
| **NAS Primary NFS Export** | 192.168.168.50:/export/[path] | NFS export (if applicable) |
| **NAS Backup IP** | 192.168.168.51 | Secondary/failover |
| **Network Segment** | [PENDING ASSESSMENT] | Dedicated VLAN or shared subnet |
| **Network Speed** | [PENDING ASSESSMENT] | 1Gbps, 10Gbps, or other |
| **Network Latency** | [PENDING ASSESSMENT] | Measure: ping 192.168.168.50 |

### Protocol Details

#### If iSCSI-based NAS:
```
NAS Initiator (192.168.168.31)
    ↓ iSCSI Discovery (port 3260)
NAS Target (192.168.168.50:3260)
    ↓ CHAP Authentication (if configured)
iSCSI LUN (Logical Unit Number)
    ↓ Block device (/dev/sdX)
    ↓ Filesystem mount (/mnt/nas-primary)
```

**CHAP Credentials**:
- Username: [PENDING ASSESSMENT]
- Password: [SECURED IN VAULT] (not in this document)

#### If NFS-based NAS:
```
NAS Exporter (192.168.168.50)
    ↓ NFS v4 / v3 Export
192.168.168.31 NFS Client
    ↓ Mount via nfs-client
Mount point: /mnt/nas-primary
    ↓ Read/write filesystem operations
```

**NFS Export**: [PENDING ASSESSMENT]
- Example: `192.168.168.50:/export/primary /mnt/nas-primary nfs4 rw,hard,intr,timeo=600`

---

## 4. NAS Storage & Performance Specifications

### Storage Capacity

```
Primary NAS (192.168.168.50)
├── Total Capacity: [PENDING] TB
├── Used: [PENDING] GB
├── Available: [PENDING] GB
├── Usage %: [PENDING]%
└── Growth Rate: [PENDING] GB/month

Backup NAS (192.168.168.51)
├── Total Capacity: [PENDING] TB
├── Used (as backup): [PENDING] GB
├── Available: [PENDING] GB
├── Usage %: [PENDING]%
└── Sync Lag: [PENDING] (should be <1 hour)
```

### Performance Characteristics

#### Sequential I/O (Throughput)

| Metric | Target | Baseline | Status |
|---|---|---|---|
| **Read Throughput** | >500 MB/s | [PENDING] | [PENDING] |
| **Write Throughput** | >500 MB/s | [PENDING] | [PENDING] |
| **Measurement Tool** | dd / fio / iperf3 | - | [PENDING] |

#### Random I/O (IOPS)

| Metric | Target | Baseline | Status |
|---|---|---|---|
| **Read IOPS (4KB)** | >20,000 | [PENDING] | [PENDING] |
| **Write IOPS (4KB)** | >20,000 | [PENDING] | [PENDING] |
| **Mixed (50/50 R/W)** | >30,000 | [PENDING] | [PENDING] |
| **Measurement Tool** | fio / sysbench | - | [PENDING] |

#### Latency

| Metric | Target | Baseline | Status |
|---|---|---|---|
| **Read Latency (p50)** | <2ms | [PENDING] | [PENDING] |
| **Read Latency (p99)** | <50ms | [PENDING] | [PENDING] |
| **Write Latency (p50)** | <2ms | [PENDING] | [PENDING] |
| **Write Latency (p99)** | <50ms | [PENDING] | [PENDING] |
| **Mount Latency** | <5s | [PENDING] | [PENDING] |

---

## 5. NAS Redundancy & RAID Configuration

### RAID Level (Primary NAS)

| Parameter | Value | Notes |
|---|---|---|
| **RAID Type** | [PENDING ASSESSMENT] | RAID 5/6/10, ZFS, etc |
| **Disk Count** | [PENDING ASSESSMENT] | Number of physical drives |
| **Disk Size** | [PENDING ASSESSMENT] | Per-disk capacity |
| **Failure Tolerance** | [PENDING ASSESSMENT] | How many disk failures tolerated |
| **Rebuild Time (on failure)** | [PENDING ASSESSMENT] | Hours to rebuild destroyed drive |
| **Hot Spare Drives** | [PENDING ASSESSMENT] | Reserved for auto-rebuild |

### Data Protection

| Feature | Enabled | Details |
|---|---|---|
| **Snapshots** | [PENDING] | Point-in-time copies (if available) |
| **Replication** | [PENDING] | Real-time sync to backup? |
| **Checksumming** | [PENDING] | Data integrity via checksums? |
| **SMART Monitoring** | [PENDING] | Disk health alerts? |

---

## 6. NAS Backup & Recovery

### Backup Strategy

```
Backup Schedule:
├── Hourly Incremental
│   ├── Source: /mnt/nas-primary (rsync delta)
│   ├── Destination: /mnt/nas-backup
│   └── Retention: 24 backups (past 24 hours)
├── Daily Full
│   ├── Time: 02:00 UTC daily
│   ├── Source: /mnt/nas-primary
│   ├── Destination: /mnt/nas-backup/daily-$(date)
│   └── Retention: 30 days
└── Weekly Off-Site
    ├── Time: Sunday 04:00 UTC
    ├── Source: /mnt/nas-backup/daily-latest
    ├── Destination: Cloud storage / Archive
    └── Retention: 90 days rolling
```

### Recovery Procedures

#### 1. Single File Recovery
```bash
# From latest backup
rsync -av /mnt/nas-backup/latest/models/llama2-70b.bin \
         /mnt/nas-primary/models/

# Verify checksum
sha256sum /mnt/nas-primary/models/llama2-70b.bin
```

#### 2. Full NAS Primary Rebuild (RTO: <30 minutes)
```bash
# Emergency failover to backup NAS
# 1. Mark backup as primary
# 2. Update mount points in docker-compose
# 3. Restart containers
# 4. Verify data integrity
```

#### 3. Cold Restore from Archive (RTO: 4-24 hours)
```bash
# Restore from cloud/tape archive
# 1. Download archive to temporary storage
# 2. Verify file integrity (checksums)
# 3. Mount and validate
# 4. Failover containers if needed
```

### RTO/RPO Targets

| Scenario | RTO (Recovery Time) | RPO (Recovery Point) | Notes |
|---|---|---|---|
| **Single file loss** | <5 min | <1 hour | Restore from hourly backup |
| **NAS Primary failure** | <30 min | <15 min | Failover to backup NAS |
| **Backup NAS failure** | <5 min | <1 hour | Continue on primary (higher risk) |
| **Complete data center loss** | 4-24 hours | <1 week | Restore from off-site archive |

---

## 7. NAS Health Monitoring & Alerts

### Key Metrics to Monitor

```
Capacity Monitoring:
├── Primary NAS Usage: Alert if >80% full
├── Backup NAS Sync Lag: Alert if >1 hour behind
├── Growth Rate: Trend analysis for capacity planning
└── Free Space Threshold: Alert if <500GB free

Performance Monitoring:
├── Read/Write IOPS: Track vs. baseline
├── Latency (p99): Alert if >100ms consistently
├── Replication Lag (if applicable): <30 seconds
└── Network Bandwidth: Monitor for congestion

Reliability Monitoring:
├── Disk Health (SMART status)
├── RAID Status: Alert if degraded
├── Snapshot Success Rate: Should be 100%
├── Backup Job Success: Alert on failures
└── Network Connectivity: Ping/health probe
```

### Prometheus Metrics (for #144 Monitoring & Observability)

```yaml
# Example Prometheus scrape config for NAS
- job_name: 'nas-primary'
  static_configs:
    - targets: ['192.168.168.50:9100']  # node-exporter
  
- job_name: 'nas-backup'
  static_configs:
    - targets: ['192.168.168.51:9100']

# Alert rules:
- alert: NASCapacityHigh
  expr: node_filesystem_avail_percent{mountpoint=~"/mnt/nas.*"} < 20
  for: 5m
  annotations:
    summary: "NAS low available space"

- alert: NASLatencyHigh
  expr: histogram_quantile(0.99, nfs_read_latency_ms) > 100
  for: 10m
  annotations:
    summary: "NAS read latency degraded"
```

---

## 8. NAS Connectivity Testing

### Pre-Deployment Validation

Run these tests to confirm NAS is ready for deployment:

```bash
#!/bin/bash
# NAS Connectivity Validation (run from 192.168.168.31)

echo "=== NAS Connectivity Tests ==="

# 1. Network ping
echo "1. NAS Primary Ping:"
ping -c 4 192.168.168.50 || echo "FAIL: Cannot reach 192.168.168.50"

echo ""
echo "2. NAS Backup Ping:"
ping -c 4 192.168.168.51 || echo "FAIL: Cannot reach 192.168.168.51"

# 2. iSCSI/NFS discovery (if applicable)
echo ""
echo "3. iSCSI Discovery (if iSCSI NAS):"
iscsiadm -m discovery -t sendtargets -p 192.168.168.50:3260 || echo "INFO: iscsiadm not available"

# 3. NFS mount test
echo ""
echo "4. NFS Mount Test:"
showmount -e 192.168.168.50 || echo "INFO: showmount not available"

# 4. Existing mount check
echo ""
echo "5. Current Mounts:"
mount | grep /mnt/nas

# 5. Capacity check
echo ""
echo "6. NAS Capacity:"
df -h /mnt/nas-primary /mnt/nas-backup 2>/dev/null || echo "Mounts not available"

# 6. Write permission test
echo ""
echo "7. NAS Write Permission Test:"
if [ -w "/mnt/nas-primary" ]; then
    touch /mnt/nas-primary/.connectivity-test-$(date +%s)
    echo "✓ Write test passed"
else
    echo "✗ Write test failed - NAS may not be writable"
fi

# 7. Latency baseline
echo ""
echo "8. NAS Latency Baseline (1GB sequential read):"
time dd if=/mnt/nas-primary/[large-file] of=/dev/null bs=1M count=1000
```

---

## 9. NAS Documentation & Operations

### Mount Point Management

**Systemd Mount Unit** (preferred over fstab for better error handling):

```ini
# /etc/systemd/system/mnt-nas\x2dprimary.mount
[Unit]
Description=NAS Primary Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=192.168.168.50:/export/primary
Where=/mnt/nas-primary
Type=nfs4
Options=rw,hard,intr,timeo=600,retrans=2,_netdev
TimeoutSec=120

[Install]
WantedBy=multi-user.target
```

### Mount Troubleshooting

| Issue | Symptom | Resolution |
|---|---|---|
| **Mount failed** | `mount: /mnt/nas-primary: mount(2) system call failed` | Check NAS IP, firewall, NFS export rules |
| **Timeout** | Operations hang indefinitely | Check network, NAS responsiveness, `soft` vs `hard` options |
| **Permission denied** | `ls: /mnt/nas-primary: Permission denied` | Check NFS export permissions, uid/gid mapping |
| **Stale NFS file** | `Stale NFS file handle` | Check NAS stability, consider remount cycle |

---

## 10. NAS Readiness Checklist

Before proceeding to #140 IaC Development:

- [ ] **Connectivity**: SSH to 192.168.168.31 and ping both NAS addresses
- [ ] **Mount Status**: Verify `/mnt/nas-primary` and `/mnt/nas-backup` visible and mounted
- [ ] **Capacity**: Confirm >3TB total storage available
- [ ] **Write Access**: Test write file to `/mnt/nas-primary`
- [ ] **Latency**: Measure and document NAS latency baseline
- [ ] **Redundancy**: Confirm RAID/replication strategy
- [ ] **Backup**: Verify backup sync to secondary NAS is operational
- [ ] **Network**: Confirm no firewall blocks iSCSI (3260) or NFS (2049, 111)
- [ ] **Documentation**: Update this document with actual measurements

---

## 11. Next Steps

1. **Execute connectivity tests** (above script)
2. **Document actual values** in this document
3. **Update latency baseline** in Network Topology document
4. **Confirm backup strategy** is suitable for deployment SLA
5. **Close #139** (Infrastructure Assessment) once all fields populated
6. **Proceed to #140** (IaC Development with NAS integration)

---

**Document Status**: IN PROGRESS  
**Related Issue**: #139 (Infrastructure Assessment), #142 (NAS Integration)  
**Owner**: GitHub Copilot (Automated Assessment)  
**Last Updated**: April 13, 2026  

