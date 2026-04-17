# Runbook: Disk Space Approaching Capacity (DiskSpaceWarning)

**Alert**: `DiskSpaceWarning` (< 10% free) | `DiskSpaceCritical` (< 5% free)  
**Severity**: WARNING / CRITICAL  
**Component**: File system  
**Related Issue**: #569

## Overview

This alert fires when disk space is running critically low. Low disk can cause database failures, crashed, and service interruptions.

## Quick Response

```bash
# 1. Check disk usage
df -h /

# 2. Find largest directories
du -sh /* | sort -h | tail -10

# 3. Check Docker volumes
docker system df

# 4. Check Prometheus storage
du -sh /data/prometheus /var/lib/docker/volumes/prometheus-data

# 5. Check PostgreSQL data
du -sh /var/lib/postgresql
```

## Detailed Investigation

### Step 1: Identify Space Hog

```bash
# Find largest files (recursively)
find / -type f -size +1G -exec ls -lh {} \; | sort -k5 -h | tail -10

# Find largest directories
du -sh /* 2>/dev/null | sort -h | tail -15

# Check Docker-specific directories
du -sh /var/lib/docker/containers/* 2>/dev/null | sort -h | tail -10
du -sh /var/lib/docker/volumes/* 2>/dev/null | sort -h | tail -10

# Check application logs
find /var/log -type f -size +100M -exec ls -lh {} \;
docker-compose exec <container> du -sh /var/log/*
```

### Step 2: Common Causes

| Location | Cause | Fix |
|----------|-------|-----|
| `/var/lib/docker/containers` | Old container logs | `docker system prune -a --volumes` |
| `/data/prometheus` | Prometheus metrics storage (1-year retention) | Reduce `--storage.tsdb.retention.time` or extend volume |
| `/data/postgres` | Database too large | Vacuum: `docker-compose exec postgres vacuumdb -z` or archive old data |
| `/var/log` | Application logs not rotated | Configure logrotate or use Docker json-file logging driver |
| `/home` | User files or cache | Check `/root/.cache`, `/home/user/.cache` |
| `/tmp` | Temporary files from build/tests | `rm -rf /tmp/*` (safe on running system) |

### Step 3: Quick Cleanup

```bash
# SAFE - Remove unused Docker images/containers/volumes
docker system prune -a --volumes -f

# SAFE - Prometheus: keep last 30 days only
docker-compose down prometheus
# Edit prometheus.yml: --storage.tsdb.retention.time=30d
# Edit docker-compose.yml: retention env var
docker-compose up -d prometheus

# SAFE - PostgreSQL: Vacuum to free space
docker-compose exec postgres vacuumdb -z codeserver

# SAFE - Delete old logs from /tmp
find /tmp -type f -atime +7 -delete

# SAFE - Ollama: Clear model cache (non-critical)
docker-compose exec ollama rm -rf ~/.ollama/models/blobs
docker-compose restart ollama
```

### Step 4: Safe High-Impact Cleanup

```bash
# BEFORE: Check current size
du -sh /data/prometheus

# Option 1: Archive Prometheus to S3
tar czf prometheus-backup-$(date +%s).tar.gz /data/prometheus
# Upload to S3: aws s3 cp prometheus-backup-*.tar.gz s3://backup-bucket/

# Option 2: Reduce Prometheus retention
docker-compose stop prometheus
# Edit docker-compose.yml: change retention from 365d to 90d
docker volume prune -f  # Remove old prometheus volume if using named volumes
docker-compose up -d prometheus

# Option 3: Archive old PostgreSQL data
docker-compose exec postgres pg_dump codeserver | gzip > codeserver-backup-$(date +%Y%m%d).sql.gz
# Delete old data from application if retention policy allows
```

## Prevention

- **Alert configured**: Warning at 10% free, critical at 5%
- **Monitoring**: Track growth over time via Prometheus `node_filesystem_free_bytes`
- **Retention policies**: Set reasonable limits (30d for dev, 90d for prod, 365d for audit)
- **Automated cleanup**: Cron job to clean `/tmp` and old logs weekly
- **Volume sizing**: Start with 250GB for on-prem deployment, monitor growth trajectory

## Volume Extension (if cleanup insufficient)

```bash
# Check current partitions
lsof | grep -E "/data|/var|/home"

# SSH to host and extend LVM (if applicable)
ssh root@192.168.168.31

# If using LVM:
lvdisplay /dev/ubuntu-vg/ubuntu-lv
lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv  # Extend logical volume
resize2fs /dev/ubuntu-vg/ubuntu-lv  # Resize file system

# If using partitions:
# May require unmounting — risky on running system
# Better to migrate to larger disk or add new volume
```

## Monitoring Configuration

```yaml
# prometheus-rules-alerts-operational.yml

- alert: DiskSpaceWarning
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.10
  for: 5m
  annotations:
    summary: "Disk {{ $labels.device }} has {{ $value | humanizePercentage }} free"

- alert: DiskSpaceCritical
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.05
  for: 2m
  annotations:
    summary: "CRITICAL: Disk {{ $labels.device }} has {{ $value | humanizePercentage }} free"
```

## Grafana Dashboard

- **Panel**: Node Exporter > Filesystem > Available Space (bytes)
- **Alert**: Threshold at 5% free
- **Action**: Link to this runbook

## Escalation

If disk remains full after cleanup:
1. Extend storage (resize LVM, add new volume, migrate to larger disk)
2. Review retention policies — may need to reduce from defaults
3. Consider off-loading data (archive to cold storage, remove old backups)
4. Audit application logs — may indicate runaway process generating excessive logs

## Related Runbooks

- [Backup Recovery](backup-recovery.md) — Backup may fail with low disk
- [Container Restart Investigation](container-restart-investigation.md) — Services may OOM with low disk
