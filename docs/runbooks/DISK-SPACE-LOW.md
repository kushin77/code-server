# Alert Runbook: Disk Space Critical

**Alerts**: `DiskSpace{Warning,Critical}`  
**Severity**: WARNING (> 80% full), CRITICAL (> 93% full)  
**SLA**: WARNING (4 hours), CRITICAL (1 hour)  
**Owner**: Infrastructure/SRE Team  

---

## Problem

Root filesystem (`/`) is running low on disk space. Symptoms:
- **Warning** (80-93%): Services may run out of space soon
- **Critical** (>93%): Imminent failure, new writes may fail
- **Impact**: Prometheus can't write metrics, Docker can't layer images, applications crash when writing logs

---

## Immediate Investigation (< 2 minutes)

```bash
# Check disk usage
df -h /

# Breakdown by directory (find largest)
du -sh /* | sort -h | tail -10

# Check Docker disk usage
docker system df

# Check Prometheus retention data
du -sh /opt/prometheus-data/
ls -lh /opt/prometheus-data/ | head

# Check backup directory
du -sh /mnt/backups/

# Check log files
du -sh /var/log/
find /var/log -type f -size +100M | sort -h

# Check Docker images
docker images | awk '{print $3}' | xargs docker image inspect --format='{{.RepoTags}} {{.VirtualSize}}' | sort -k2 -h
```

---

## Quick Fixes (In Priority Order)

### 1. Clean Docker System (Usually frees 10-50GB)

```bash
# Remove unused images, containers, volumes (CAREFUL - may delete needed data)
docker system prune -a  # -a removes even unused images

# Or more selective:
docker image prune -a   # Remove unused images only
docker container prune  # Remove stopped containers
docker volume prune     # Remove unused volumes

# Verify space freed
df -h /
```

### 2. Clean Prometheus Old Data (5-20GB)

```bash
# Check retention setting
docker inspect prometheus | grep -i "retention"

# View disk usage
du -sh /opt/prometheus-data/

# If safe to reduce: Scale down retention
# Edit docker-compose.yml: --storage.tsdb.retention.time=30d (was 365d)

# OR manually delete old data
find /opt/prometheus-data -mtime +90 -delete

# Restart Prometheus
docker-compose down prometheus
docker-compose up -d prometheus

# Verify space freed
df -h /
```

### 3. Delete Old Backup Files (10-100GB+)

```bash
# Check backup directory
du -sh /mnt/backups/

# Delete backups older than 30 days
find /mnt/backups -name "*.sql.gz" -mtime +30 -delete

# OR keep only last N backups
ls -t /mnt/backups/*.sql.gz | tail -n +6 | xargs rm

# Compress if not already
gzip /mnt/backups/*.sql

# Verify space
df -h /
```

### 4. Rotate/Delete Old Logs (1-20GB)

```bash
# Check log usage
du -sh /var/log/
find /var/log -type f -size +500M

# Rotate or delete old logs
journalctl --vacuum=size=1G  # Keep only 1GB of systemd logs
journalctl --vacuum=time=7d   # Keep only 7 days of logs

# Delete Docker container logs
docker logs --tail 0 container_name > /dev/null  # Truncates logs
# OR delete all logs
find /var/lib/docker/containers -name "*-json.log" -delete

# Or manually delete old files
find /var/log -type f -mtime +30 -delete

# Verify space
df -h /
```

### 5. Clean Package Manager Cache

```bash
# APT (Debian/Ubuntu)
apt-get clean && apt-get autoclean

# Docker build cache (if needed space)
docker builder prune

# Verify space
df -h /
```

---

## Root Cause Investigation

If disk keeps filling up even after cleanup:

### Check what's consuming space

```bash
# Monitor in real-time
watch 'df -h / && echo "---" && du -sh /* | sort -h'

# Find growth rate
du -sh /opt/prometheus-data
sleep 300  # Wait 5 minutes
du -sh /opt/prometheus-data
# If growing, need to reduce Prometheus retention or increase storage

# Check for application log spam
tail -f /var/log/docker.log | grep -i "error\|warn"
tail -f /var/log/syslog | tail -50
```

### Common causes and fixes

**Cause 1: Prometheus storing too much data**
```bash
# Reduce retention time
docker-compose down prometheus
# Edit docker-compose.yml:
#   --storage.tsdb.retention.time=30d
docker-compose up -d prometheus
```

**Cause 2: Application generating huge log files**
```bash
# Find culprit
find /var/log -type f -size +100M

# Check application logs
docker logs app-container | wc -l
# If millions of lines, log level may be too verbose

# Reduce log level
docker-compose down app-container
# Edit docker-compose.yml: LOG_LEVEL=warn (not debug)
docker-compose up -d app-container
```

**Cause 3: Database growing too large**
```bash
# Check PostgreSQL data directory
du -sh /var/lib/postgresql/data/

# Check table sizes
docker exec postgres psql -U postgres -c "
  SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
  FROM pg_tables
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
  LIMIT 10;
"

# May need to archive old data or vacuum
docker exec postgres psql -U postgres -c "VACUUM ANALYZE;"
```

---

## Verification

```bash
# Check disk usage now < 80%
df -h /

# Verify applications still running
docker-compose ps

# Verify services are healthy
curl -s http://localhost:9090/-/ready
curl -s http://localhost:3000/api/health

# Alert should clear
curl -s http://localhost:9093/api/v1/alerts | \
  jq '.data[] | select(.labels.alertname | test("DiskSpace"))'
```

---

## Prevention (Long-term)

**Expand storage**:
```bash
# Add new disk to host (if available)
# Extend root filesystem or mount new volume

# Mount new volume
sudo mkdir /data
sudo mount /dev/sdb1 /data

# Move Prometheus data
sudo mv /opt/prometheus-data /data/
sudo docker-compose down prometheus
# Update docker-compose.yml to point to /data/prometheus-data
sudo docker-compose up -d prometheus
```

**Adjust retention policies**:
```bash
# Prometheus: Keep 30 days instead of 365
# Logs: Rotate daily, keep 7 days
# Backups: Keep last 10 backups, delete older

# Monitor growth rate
watch 'du -sh /opt/prometheus-data /var/log /mnt/backups'
```

**Set up automatic cleanup**:
```bash
# Cron job to clean old files daily
0 2 * * * /opt/scripts/cleanup-disk.sh

# Contents of cleanup-disk.sh:
#!/bin/bash
find /mnt/backups -name "*.sql.gz" -mtime +30 -delete
find /var/log -type f -mtime +14 -delete
docker system prune -af --filter "until=48h"
```

---

**Document**: docs/runbooks/disk-space-low.md  
**Last Updated**: 2026-04-15  
**Approved By**: Infrastructure Lead  
