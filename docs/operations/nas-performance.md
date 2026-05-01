# NAS Performance Reference

**Status:** Reference document — benchmark when connected to NAS at 192.168.168.56  
**Issue:** #1536 — Networking, DNS & Performance  
**Governance:** GOV-002

---

## NAS Configuration

| Parameter | Value |
|-----------|-------|
| NAS Host | 192.168.168.56 (`$NAS_HOST`) |
| Protocol | CIFS/SMB (Windows Z: drive), NFS (Linux hosts) |
| Network | 10GbE (eiq-nas) |
| Mount point | `/nas/persistent/` (primary data) |

---

## Optimized Mount Options

### NFS Mount (Linux)
```bash
mount -t nfs -o \
  rsize=131072,wsize=131072,\
  noatime,nodiratime,\
  hard,intr,\
  timeo=600,retrans=3,\
  vers=4.1 \
  ${NAS_HOST}:/nas /nas
```

### /etc/fstab Entry
```
192.168.168.56:/nas /nas nfs4 rsize=131072,wsize=131072,noatime,nodiratime,hard,intr,timeo=600 0 0
```

---

## Benchmark Commands

### Network Throughput (iperf3)
```bash
# On NAS server, run iperf3 server:
iperf3 -s

# From primary host:
iperf3 -c ${NAS_HOST} -t 30 -P 4  # 4 parallel streams, 30 seconds

# Expected: ~9.8 Gbps on 10GbE
```

### Sequential I/O (fio)
```bash
# Write test
fio --name=write-test \
    --directory=/nas/hot/benchmarks \
    --rw=write \
    --bs=1M \
    --size=1G \
    --numjobs=4 \
    --runtime=30 \
    --group_reporting

# Read test
fio --name=read-test \
    --directory=/nas/hot/benchmarks \
    --rw=read \
    --bs=1M \
    --size=1G \
    --numjobs=4 \
    --runtime=30 \
    --group_reporting
```

### Random I/O (fio)
```bash
fio --name=random-rw \
    --directory=/nas/hot/benchmarks \
    --rw=randrw \
    --rwmixread=70 \
    --bs=4k \
    --size=512M \
    --numjobs=4 \
    --iodepth=32 \
    --runtime=30 \
    --group_reporting
```

---

## Health Check Script

```bash
source scripts/_common/hosts.sh
check_nas_health 100  # Alert if latency > 100ms
```

---

## NAS Failover Procedure

If primary NAS mount fails:

```bash
# 1. Check mount status
mountpoint -q /nas/persistent || echo "NAS unmounted"

# 2. Attempt remount with retry
for i in 1 2 3 4 5; do
  mount -a && break
  echo "Retry $i/5..."
  sleep $((i * 2))
done

# 3. If mount fails: services continue with local cache
# Docker services with volume mounts will queue writes until remounted
```

---

## Directory Structure

```
/nas/persistent/         # PostgreSQL data, app state (persistent across reboots)
/nas/hot/               # Docker images, build cache, fast-access data
/nas/cold/              # Backups, archives, cold storage
```

---

*GOV-002: Update this document with actual benchmark results after running fio/iperf3.*
