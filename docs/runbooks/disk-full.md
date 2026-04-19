# Runbook: Disk Space Critical

**Alert**: DiskSpaceRunningOut  
**Severity**: WARNING  
**SLA**: Resolve within 30 minutes  
**Owner**: Infrastructure Team  

## Symptoms

- Alert: "Disk space running low"
- Free disk space < 10% for > 10 minutes
- Disk at risk of filling up completely
- Write operations may start failing soon

## Root Causes

1. Large log files accumulated
2. Old backups not cleaned up
3. Docker containers consuming disk (overlayfs)
4. Application data growth (database, cache)
5. Temporary files not deleted (transcodes, uploads)

## Diagnosis

```bash
# Check disk usage by filesystem
df -h

# Find largest directories
du -sh /data/* | sort -rh | head -10

# Check docker usage
docker system df

# Find old files
find /data -mtime +30 -type f | head -20
```

## Remediation

### Step 1: Identify Problem Area (5 min)
```bash
# Breakdown by major directories
du -sh /data/* /var/lib/docker/* | sort -rh
```

**Largest directories**:
- Docker layers: `/var/lib/docker/overlay2/`
- Logs: `/var/log/`, `/data/logs/`
- Database: `/var/lib/postgresql/`, `/data/postgres/`
- Backups: `/mnt/nas-56/backups/`

### Step 2: Clean Old Logs (10 min)
```bash
# Compress and archive old logs (> 30 days)
find /var/log -name "*.log" -mtime +30 -exec gzip {} \;
find /data/logs -name "*.log" -mtime +30 -exec gzip {} \;

# Remove very old logs (> 90 days)
find /var/log -name "*.log.gz" -mtime +90 -delete

# Check recovery
df -h
```

### Step 3: Clean Docker Images (5 min)
```bash
# Remove dangling images
docker image prune -f

# Remove unused volumes
docker volume prune -f

# Check recovery
df -h
docker system df
```

### Step 4: Cleanup Temporary Files (5 min)
```bash
# Remove application temp files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Check PostgreSQL WAL archive
du -sh /var/lib/postgresql/pg_wal/

# Clean old WAL files
docker exec postgres pg_archivecleanup /var/lib/postgresql/pg_wal
```

### Step 5: Archive Old Backups (10 min)
```bash
# If local backups taking space, move to NAS
find /data/backups -mtime +7 -exec \
  rsync -av {} /mnt/nas-56/backups/archive/ \;
```

## Prevention

- [ ] Configure log rotation (logrotate)
- [ ] Set Docker image prune schedule (weekly)
- [ ] Monitor disk usage trending (graph in Prometheus)
- [ ] Set alert at 50% full (give time to respond)
- [ ] Implement automatic cleanup scripts
- [ ] Plan capacity: current 98GB, growth rate

## Disk Utilization Targets

- Healthy: 0-50% full (plenty of headroom)
- Degraded: 50-80% full (investigate growth)
- Alert: 80-90% full (immediate action needed)
- Critical: > 90% full (emergency action)

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Infrastructure Team
