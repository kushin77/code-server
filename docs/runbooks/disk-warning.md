# Runbook: Disk Space Warning & Critical

**Alerts**:
- `DiskSpaceWarning` (80-93% full, MEDIUM)
- `DiskSpaceCritical` (> 93% full, CRITICAL)

**Time to Resolution**: < 1 hour (Warning), < 15 minutes (Critical)  
**Recovery Time Target**: < 30 minutes  
**Service Impact**: File writes will start failing when disk is full

---

## Symptoms

- Alert: "Disk usage {{ value }}% on {{ instance }}"
- `df -h /` shows filesystem > 80% full
- Docker commands slow (can't write layers)
- Prometheus data collection slowing down
- Backup failures ("disk full" in logs)

---

## Root Causes

1. **Log files accumulated** - Docker/application logs filled disk (/var/log)
2. **Prometheus retention too long** - Metrics data (365 days) = 50GB+
3. **Old Docker images cached** - Unused images waste space
4. **Backup files not rotated** - Old backups (>30 days) still on disk
5. **Container layer growth** - Stopped containers take space
6. **Temporary files not cleaned** - /tmp, /var/tmp full

---

## Immediate Diagnosis

### Step 1: Check Disk Usage

```bash
ssh akushnir@primary.prod.internal

# Quick overview
df -h /

# Expected: / filesystem with usage %
# Critical if > 93% used

# Detailed breakdown by directory
du -sh /* | sort -rh | head -20

# Example:
# 45G  /var
# 20G  /opt
# 15G  /home
# 10G  /usr
```

### Step 2: Identify Largest Directories

```bash
# Find what's taking space
du -sh /var/*
du -sh /var/lib/*
du -sh /opt/*
du -sh /home/*

# Most common culprits:
du -sh /var/log  # Application logs
du -sh /var/lib/docker  # Docker images/containers
du -sh /opt/prometheus-data  # Prometheus metrics
du -sh /backups  # Backup files
```

### Step 3: Check Individual Service Usage

```bash
# Docker images and layers
docker images
docker system df  # Total usage by images, containers, volumes

# Container storage
docker ps -a --format "table {{.Names}}\t{{.Size}}"

# Named volumes
docker volume ls -v
```

---

## Troubleshooting & Recovery

### Symptom: `/var/log` is 20+ GB

```bash
# List log files by size
ls -laSh /var/log/ | head -20

# Rotate/clean Docker logs
# For Ubuntu/Debian:
sudo logrotate -f /etc/logrotate.conf

# For each container, manually clean old logs (if log-driver is json-file):
docker inspect --format='{{.LogPath}}' <container_name>
sudo truncate -s 0 <logpath>

# Or restart docker daemon (clears all logs in some configs)
sudo systemctl restart docker
```

### Symptom: Prometheus taking 50GB+ (in /opt/prometheus-data or docker volume)

```bash
# Check Prometheus retention setting
grep "storage.tsdb.retention" docker-compose.yml
# or
docker exec prometheus promtool query instant 'up'  # Should work

# Option 1: Reduce retention (cleaner, persistent)
# Edit docker-compose.yml:
# services:
#   prometheus:
#     command:
#       - '--storage.tsdb.retention.time=30d'  # Reduce from 365d to 30d

docker-compose restart prometheus
# Wait 10 minutes for cleanup to complete

# Option 2: Emergency cleanup (temporary, logs will rebuild)
# Connect to Prometheus volume
docker exec prometheus rm -rf /prometheus/*
docker-compose restart prometheus
# Prometheus restarts empty and begins collecting again
```

### Symptom: Docker images/layers taking 30GB+

```bash
# Clean up unused images and containers
docker system prune -a --volumes
# WARNING: This removes ALL stopped containers and unused images

# More conservative approach:
docker image prune -a --filter "until=720h"  # Remove images unused in 30 days
docker container prune --filter "until=720h"  # Remove stopped containers from 30+ days ago
docker volume prune

# Check freed space
docker system df
df -h /
```

### Symptom: Backup files (30+ GB in /backups)

```bash
# Check backup retention policy
ls -laSh /backups/ | head -10

# Delete backups older than 30 days
find /backups -type f -mtime +30 -delete

# Or keep only last N backups
cd /backups
ls -1t | tail -n +6 | xargs -r rm

# Check freed space
du -sh /backups
df -h /
```

### Symptom: Container layers/storage drivers filling disk

```bash
# Stop docker service (cautiously!)
sudo systemctl stop docker

# Clean docker storage directory
sudo du -sh /var/lib/docker/
sudo rm -rf /var/lib/docker/overlay2/l/*
# WARNING: Removes dangling overlays

# Restart
sudo systemctl start docker
docker ps  # Verify containers restart
```

---

## Critical Action (> 93% Disk Full)

If disk is critically full (> 95%), container writes will fail immediately:

```bash
# 1. IMMEDIATE: Delete oldest/largest non-critical files
du -sh /var/log/* | sort -rh | head -5
sudo rm -rf /var/log/old_app/*.log  # Delete old app logs

du -sh /backups/* | sort -rh
rm -f /backups/*_old.tar.gz  # Delete old backups

# 2. Check freed space
df -h /

# 3. If still critical, restart services to reset temp files
docker-compose restart prometheus

# 4. Alert on-call: If can't free 10%+ space, may need emergency maintenance window
```

---

## Prevention

### 1. Set Appropriate Retention Policies

```yaml
# docker-compose.yml — Set up log rotation
services:
  postgres:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
        
  prometheus:
    command:
      - '--storage.tsdb.retention.time=30d'  # Not 365d
```

### 2. Automate Log Cleanup

```bash
# Add to crontab
0 2 * * * find /var/log -name "*.log" -mtime +30 -delete
0 3 * * 0 docker system prune -a -f --filter "until=720h"
0 4 * * * find /backups -type f -mtime +30 -delete
```

### 3. Monitor Disk Growth Trend

```bash
# Create Prometheus metric to track disk usage over time
# In node_exporter or via custom script:
echo "disk_usage_percent{mount='/'} $(df / | tail -1 | awk '{print $5}')" | \
  curl --data-binary @- http://localhost:9091/metrics/job/disk_monitor
```

### 4. Set Alert Thresholds Appropriately

```yaml
# In alerts.yaml:
- alert: DiskSpaceWarning
  expr: 'disk_usage_percent > 80'
  for: 5m
  
- alert: DiskSpaceCritical
  expr: 'disk_usage_percent > 93'
  for: 2m
```

---

## Related Alerts

- `BackupFailed` - Often preceded by disk space issues
- `PrometheusHighMemory` - Memory and disk issues can occur together
- `HostCPUUsageHigh` - Disk I/O saturation affects CPU usage

---

*Last Updated: April 18, 2026*  
*On-Call Contact: @infrastructure-team*
