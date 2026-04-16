# ELITE Production Runbooks — Incident Response & Operations

**Version**: 1.0 | **Last Updated**: 2026-04-15 | **Owner**: akushnir@kushin77

---

## Critical Alerts & Response

### 🔴 CRITICAL: Container Crash (Any Service)

**Detection**: Docker health check fails 3x, container exits

**Immediate Response**:
```bash
ssh akushnir@192.168.168.31 "cd /home/akushnir/code-server-enterprise"

# 1. Identify crashed service
docker-compose ps | grep -i 'exit\|restarting'

# 2. View error logs
docker logs SERVICE_NAME --tail=50

# 3. Is it a memory/CPU issue?
docker stats SERVICE_NAME

# 4. Check disk space
df -h /var/snap/docker

# 5. If OOM: increase memory limit in docker-compose.yml
nano docker-compose.yml  # Increase limit
docker-compose up -d SERVICE_NAME

# 6. If disk full: cleanup volumes
docker volume prune -f
docker builder prune -a --force-all

# 7. If still failing: restart Docker daemon
sudo systemctl restart docker
docker-compose up -d --remove-orphans
```

**SLA**: Detect within 2 min, resolve within 5 min

---

### 🟠 URGENT: Service Unhealthy (Health Check Failing)

**Detection**: Dashboard shows 🟡 unhealthy status, but container still running

**Diagnosis**:
```bash
# 1. Check health check output
docker inspect SERVICE_NAME --format='{{range .State.Health.Log}}Exit={{.ExitCode}}: {{.Output|truncate 100}}{{end}}'

# 2. Test service endpoint directly
curl -v http://SERVICE_NAME:PORT/HEALTH_CHECK_PATH

# 3. Check logs for errors
docker logs SERVICE_NAME --tail=20 --follow
```

**Remediation by Service**:

#### Prometheus Unhealthy
```bash
# Most common: config file issue
docker exec prometheus prometheus --config.file=/etc/prometheus/prometheus.yml --check-config

# If error: fix prometheus.yml
docker-compose restart prometheus

# If still failing: check disk space in /prometheus
docker exec prometheus du -sh /prometheus
```

#### AlertManager Unhealthy
```bash
# Issue: bad alertmanager.yml syntax
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Fix file
docker-compose restart alertmanager
```

#### Ollama Unhealthy
```bash
# Check if GPU is available
nvidia-smi

# Check CUDA detection
docker logs ollama 2>&1 | grep -i 'cuda\|gpu\|nvidia'

# If no GPU: verify LD_LIBRARY_PATH
docker exec ollama echo $LD_LIBRARY_PATH

# Try model list
docker exec ollama ollama list
```

#### Code-Server Unhealthy
```bash
# Check if port 8080 is listening
docker exec code-server curl -sf http://localhost:8080/healthz || echo "DEAD"

# Check logs
docker logs code-server --tail=20

# Restart
docker-compose restart code-server
```

#### Postgres/Redis Unhealthy
```bash
# Test connection
docker exec postgres pg_isready -U codeserver
docker exec redis redis-cli -a $(grep REDIS_PASSWORD .env | cut -d= -f2) PING

# If failing: check logs
docker logs postgres
docker logs redis
```

**SLA**: Detect within 1 min, investigate within 5 min, resolve within 15 min

---

### 🟡 HIGH: High CPU/Memory Usage

**Detection**: 
```bash
watch 'docker stats --no-stream | sort -k4 -hr | head -5'
```

**Response**:
```bash
# 1. Identify resource hog
docker stats --no-stream | grep SERVICE_NAME

# 2. If >80% memory: check for memory leaks
# Code-server: restart
docker-compose restart code-server

# Prometheus: check for runaway queries
docker exec prometheus -c 'curl -s http://localhost:9090/api/v1/query_range?query=up&start=...'

# Ollama: check model size
docker exec ollama du -sh /root/.ollama/models

# 3. If >90% CPU: check if stuck in loop
docker logs SERVICE_NAME --tail=50

# 4. Scale horizontally (if resource limit allows)
# - Run ollama on separate host
# - Run prometheus on separate host
# - Use Redis cluster instead of single instance
```

**Threshold & SLA**:
- >90% memory: Alert immediately, resolve <30 min
- >80% CPU: Alert, investigate <5 min
- Sustained >70% CPU: Scale out

---

### 🟡 HIGH: Disk Space Low

**Detection**: NAS or local volume >80% full

**Response**:
```bash
# 1. Check usage
df -h | grep -E '/mnt/nas-56|/var/snap/docker'
docker volume ls --format "{{.Name}}" | xargs -I {} sh -c 'echo {} && docker volume inspect {} | grep Mountpoint'

# 2. Identify large files
du -sh /mnt/nas-56/* /var/snap/docker/common/var-lib-docker/volumes/*/

# 3. If Prometheus TSDB too large:
# Option A: Increase retention size in docker-compose.yml (not recommended)
# Option B: Run compaction (careful!)
# docker exec prometheus promtool tsdb compact /prometheus

# 4. If Ollama models too large:
# Remove unused models
docker exec ollama sh -c 'ollama rm llama2:7b-chat'  # Or copy to archive

# 5. If PostgreSQL backup directory full:
# Archive old backups
cd /mnt/nas-56/backups/postgres
tar czf archive-2026-04-15.tar.gz dump-2026-04-*.sql.gz
rm dump-2026-04-*.sql.gz

# 6. Cleanup Docker
docker volume prune -f
docker builder prune -a --force-all
```

**SLA**: Alert at 80%, resolve to <60% within 1 hour

---

### 🟡 HIGH: Network Unreachable (NAS Mount Offline)

**Detection**: NAS volumes fail to mount on container restart

**Response**:
```bash
# 1. Test NAS connectivity
ping -c 3 192.168.168.56

# 2. Check NFS mount on host
mount | grep nfs
showmount -e 192.168.168.56

# 3. If NAS offline: wait 5 min (may be rebooting)
sleep 300 && mount -a

# 4. If NAS is online but not responding:
# Issue: firewall or NFS service down on NAS
# Contact NAS admin or SSH to NAS:
# sudo systemctl restart nfs-server
# sudo systemctl status nfs-server

# 5. If volumes still unmountable: recreate Docker volumes
docker-compose down --timeout 30
docker volume rm code-server-enterprise_nas-* || true
docker-compose up -d --remove-orphans

# 6. Verify NAS volumes mounted
docker volume ls --filter name=nas
docker inspect code-server-enterprise_nas-ollama
```

**Workaround if NAS permanently offline**:
```bash
# Switch to local volumes (WARNING: data loss if container deleted)
docker-compose.yml: Change nas-* volumes to `driver: local`
# Data loss risk — only for maintenance windows
```

**SLA**: Detect within 1 min, verify NAS status <3 min, resolve/failover <10 min

---

## Common Troubleshooting

### Service Won't Start

```bash
# 1. Check docker-compose.yml syntax
docker-compose config

# 2. Check if port is already in use
netstat -tlnp | grep -E '8080|9090|3000|11434'

# 3. Check if image exists
docker image ls | grep SERVICE_NAME

# 4. Pull latest image
docker-compose pull SERVICE_NAME

# 5. Try starting individual service
docker-compose up -d SERVICE_NAME

# 6. If still fails: remove and recreate
docker-compose down SERVICE_NAME
docker-compose up -d SERVICE_NAME
```

### Can't Connect to Service

```bash
# 1. Check if service is running
docker ps | grep SERVICE_NAME

# 2. Check if port is listening
docker exec SERVICE_NAME ss -tlnp | grep LISTEN

# 3. Test from host
curl http://CONTAINER_IP:PORT/ENDPOINT

# 4. Check firewall
sudo iptables -L -n | grep DOCKER

# 5. Check docker network
docker network inspect enterprise

# 6. Check DNS resolution (from another container)
docker exec postgres ping -c 1 SERVICE_NAME
```

### Data Loss / Corruption

```bash
# 1. Stop all services
docker-compose stop

# 2. Backup current volumes
tar czf backup-$(date +%s).tar.gz /var/snap/docker/common/var-lib-docker/volumes/ /mnt/nas-56/

# 3. Attempt recovery from NAS backup
ls /mnt/nas-56/backups/postgres/*.sql.gz | sort | tail -1  # Latest backup

# 4. Restore PostgreSQL
docker-compose up -d postgres
docker exec postgres psql -U codeserver -d postgres -c "DROP DATABASE codeserver;"
zcat /mnt/nas-56/backups/postgres/dump-LATEST.sql.gz | docker exec postgres psql -U codeserver

# 5. Verify recovery
docker-compose up -d

# 6. Run integrity checks
docker logs postgres
docker logs code-server
```

---

## Planned Maintenance

### Weekly Backup

```bash
# Run every Sunday 02:00 UTC
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# 1. Backup PostgreSQL
docker exec postgres pg_dump -U codeserver codeserver | gzip > /mnt/nas-56/backups/postgres/dump-$BACKUP_DATE.sql.gz

# 2. Backup Grafana
docker exec grafana tar czf - /var/lib/grafana | gzip > /mnt/nas-56/backups/grafana-$BACKUP_DATE.tar.gz

# 3. Backup configs
cp docker-compose.yml /mnt/nas-56/backups/docker-compose-$BACKUP_DATE.yml
cp prometheus.yml /mnt/nas-56/backups/prometheus-$BACKUP_DATE.yml
cp Caddyfile /mnt/nas-56/backups/Caddyfile-$BACKUP_DATE

# 4. Cleanup old backups (keep last 8 weeks)
find /mnt/nas-56/backups -name "dump-*.sql.gz" -mtime +56 -delete
find /mnt/nas-56/backups -name "grafana-*.tar.gz" -mtime +56 -delete

echo "✅ Backup complete: $BACKUP_DATE"
```

### Monthly Cleanup

```bash
# First Monday of each month, 03:00 UTC

# 1. Prune unused Docker resources
docker container prune -f
docker image prune -f -a --filter "until=720h"
docker volume prune -f
docker network prune -f
docker builder prune --all --force-all

# 2. Rotate logs
for svc in postgres redis prometheus grafana ollama; do
  docker logs $svc > /mnt/nas-56/backups/logs-$svc-$(date +%Y%m%d).log 2>&1
done

# 3. Check disk usage
echo "Disk usage before cleanup:" && du -sh /mnt/nas-56/* && df -h /mnt/nas-56
```

### Quarterly Security Update

```bash
# Q1/Q2/Q3/Q4: First Monday of quarter, maintenance window

# 1. Update base images
docker-compose pull

# 2. Check for CVEs
docker scan python:3.12 || echo "Scan tool not available"
git dependency-check .

# 3. Update .env secrets (rotate passwords)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env

# 4. Deploy with new images
docker-compose up -d --force-recreate

# 5. Verify all services healthy
docker-compose ps

echo "✅ Security update complete"
```

---

## Disaster Recovery

### Complete System Failure (All Containers Dead)

```bash
# 1. SSH to host
ssh akushnir@192.168.168.31

# 2. Check Docker daemon
sudo systemctl restart docker
sudo systemctl status docker

# 3. Verify NAS mount
mount | grep nfs
ping 192.168.168.56

# 4. Pull latest code
cd /home/akushnir/code-server-enterprise
git fetch origin
git reset --hard origin/feat/elite-rebuild-gpu-nas-vpn

# 5. Rebuild stack from scratch
docker-compose down -v  # WARNING: deletes LOCAL volumes (not NAS)
docker-compose pull
docker-compose up -d --remove-orphans

# 6. Restore PostgreSQL (if local volume lost)
docker-compose up -d postgres
zcat /mnt/nas-56/backups/postgres/dump-LATEST.sql.gz | docker exec postgres psql -U codeserver

# 7. Restart remaining services
docker-compose up -d

# 8. Monitor health
watch -n 2 'docker-compose ps'
```

### NAS Permanently Unavailable (Failover to Local SSD)

```bash
# WARNING: This incurs data loss for models and large files!

# 1. Modify docker-compose.yml
# Change all nas-* volumes to: driver: local
sed -i 's/driver: local.*type: nfs4/driver: local/g' docker-compose.yml

# 2. Migrate critical data from NAS (if still accessible)
# tar czf /var/snap/docker/common/var-lib-docker/volumes/code-server-enterprise_nas-ollama/_data/backup.tar.gz /mnt/nas-56/ollama/

# 3. Redeploy
docker-compose down
docker-compose up -d --remove-orphans

# 4. Restore from backup if partial recovery possible
# This is a degraded mode — NAS should be restored ASAP
```

### PostgreSQL Corruption (Unrecoverable)

```bash
# 1. Stop postgres
docker-compose stop postgres

# 2. Delete corrupted volume
docker volume rm code-server-enterprise_postgres-data

# 3. Create fresh volume
docker-compose up -d postgres

# 4. Restore from latest backup
docker exec postgres psql -U codeserver -d postgres -c "CREATE DATABASE codeserver;"
zcat /mnt/nas-56/backups/postgres/dump-LATEST.sql.gz | docker exec postgres psql -U codeserver codeserver

# 5. Verify
docker-compose logs postgres | tail -10
curl http://localhost:8080  # Should be accessible again after boot
```

---

## Monitoring & Alerting Rules

### Key Metrics

| Metric | Query | Threshold | Action |
|--------|-------|-----------|--------|
| Service Down | `up{job="SERVICE"} == 0` | Immediate | Page on-call |
| High Memory | `container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9` | 90% for 5min | Alert, scale if possible |
| High CPU | `rate(container_cpu_usage_seconds_total[5m]) > 0.8` | 80% sustained | Investigate, consider scaling |
| Disk Full | `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1` | 10% remaining | Alert, cleanup |
| NAS Mount | Custom probe | Fail once | Alert to verify connectivity |
| Prometheus Errors | `increase(prometheus_tsdb_failures_total[5m]) > 0` | Any increase | Page on-call |

### Create Alerts in Prometheus

Add to `alert-rules.yml`:

```yaml
groups:
  - name: Elite Alerts
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        annotations:
          summary: "{{ $labels.job }} is down"

      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
        for: 5m
        annotations:
          summary: "High memory on {{ $labels.name }}: {{ humanizePercentage $value }}"

      - alert: DiskFull
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
        annotations:
          summary: "Disk {{ $labels.device }} is {{ humanizePercentage (1 - $value) }} full"
```

---

## On-Call Schedule & Escalation

**On-Call**: akushnir (slack: @akushnir, phone: TBD)  
**Escalation**: 15 min no response → Page engineering lead

**Contact**:
- Slack: #incidents
- Phone: (add phone number)
- Email: akushnir@domain.com

**Response Times**:
- P0 (service down): 5 min
- P1 (degraded): 15 min
- P2 (workaround available): 1 hour

---

**Last Tested**: Not yet (created 2026-04-15)  
**Next Test**: 2026-05-15 (monthly disaster recovery drill)
