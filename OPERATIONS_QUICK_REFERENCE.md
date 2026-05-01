# OPERATIONS QUICK REFERENCE - PRODUCTION CHEAT SHEET
## 1-Page Command Reference for Operations Team
**Last Updated**: May 1, 2026

---

## CRITICAL CONTACT INFO

| Role | Host | Method |
|------|------|--------|
| Primary System | 192.168.168.31 | ssh akushnir@192.168.168.31 |
| Replica System | 192.168.168.42 | ssh akushnir@192.168.168.42 |
| Grafana Dashboard | http://192.168.168.31:3000 | Web browser |
| Prometheus | http://192.168.168.31:9090 | Web browser |
| AlertManager | http://192.168.168.31:9093 | Web browser |
| Loki Logs | http://192.168.168.31:3100 | Web browser |

---

## HEALTH CHECK (30 SECONDS)

```bash
# Quick 5-command health check
ssh akushnir@192.168.168.31

# 1. Container status (should show 51 running)
docker ps | wc -l

# 2. Unhealthy services (should be empty)
docker ps --filter "status=unhealthy" --format "{{.Names}}"

# 3. API health
curl -s http://localhost:3000/api/health | grep -q '"ok":true' && echo "✓ OK" || echo "✗ FAIL"

# 4. Database replication
docker exec code-server-postgres psql -U postgres -c "SELECT state FROM pg_stat_replication LIMIT 1;" | tail -1

# 5. Disk usage (should show >20% free)
df -h /mnt/data | tail -1
```

---

## MOST COMMON ISSUES & FIXES

| Issue | Quick Fix | Details |
|-------|-----------|---------|
| Service Down | `docker restart <name>` | Most restart within 30 seconds |
| Can't reach Grafana | `curl http://192.168.168.31:3000` | Check if port 3000 is open |
| High Memory | `docker stats --no-stream \| sort -k4 -h -r` | Identify and restart if needed |
| DB Replication Lag | `docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"` | Check "state" is "streaming" |
| Disk Full | `df -h && du -sh /*` | Find and remove large files |
| Network Issue | `ping 192.168.168.42` | Check host connectivity first |

---

## START/STOP EVERYTHING

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-deployment

# START all services
docker-compose up -d
# Wait 5-10 minutes for stability

# STOP all services (⚠️ affects users)
docker-compose down

# RESTART all services
docker-compose restart

# PULL latest images and restart
docker-compose pull && docker-compose up -d
```

---

## VIEW LOGS

```bash
ssh akushnir@192.168.168.31

# Real-time log from container
docker logs -f code-server-prometheus

# Last 50 lines with timestamps
docker logs --tail 50 --timestamps code-server-<service>

# Logs from last hour
docker logs --since 1h code-server-<service>

# All error logs
docker logs code-server-<service> 2>&1 | grep -i error

# Logs in Loki (web UI)
http://192.168.168.31:3100  (query: {container_name="code-server-*"})
```

---

## RESTART SPECIFIC SERVICE

```bash
ssh akushnir@192.168.168.31

# Find service name
docker ps | grep <keyword>

# Restart it
docker restart <full_container_name>

# Example: Restart Prometheus
docker restart code-server-prometheus

# Watch it restart
docker ps | grep prometheus
# Should cycle: Up (unhealthy) → Up (health: starting) → Up (health: healthy)
```

---

## DATABASE BACKUP/RESTORE

```bash
ssh akushnir@192.168.168.31

# BACKUP database
docker exec code-server-postgres pg_dump -U postgres | gzip > db_backup_$(date +%Y%m%d_%H%M%S).sql.gz

# List backups
ls -lh db_backup_*.sql.gz

# RESTORE from backup (⚠️ overwrites existing data)
gunzip -c db_backup_2026-05-01_120000.sql.gz | \
  docker exec -i code-server-postgres psql -U postgres
```

---

## PERFORMANCE CHECK

```bash
ssh akushnir@192.168.168.31

# Memory usage (sort by highest)
docker stats --no-stream | sort -k4 -h -r | head -10

# CPU usage (sort by highest)
docker stats --no-stream | sort -k3 -h -r | head -10

# Disk usage
df -h

# Network traffic
docker stats --no-stream | grep -E "NET I/O|code-server"

# Database size
docker exec code-server-postgres psql -U postgres -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) \
   FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```

---

## REPLICATION CHECK

```bash
ssh akushnir@192.168.168.31

# Check primary → replica replication status
docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Expected output: Should show 1 row with state='streaming'

# If replication is lagging (lag > 1 second):
# 1. Check replica is running: ssh akushnir@192.168.168.42 docker ps | grep postgres
# 2. Check network: ping 192.168.168.42
# 3. Restart replica PostgreSQL: docker restart code-server-postgres (on replica)
```

---

## NETWORK TESTING

```bash
ssh akushnir@192.168.168.31

# Ping replica host
ping -c 3 192.168.168.42

# Test service connectivity between hosts
docker exec code-server-prometheus curl -s http://192.168.168.42:9090/-/healthy

# Check Docker network
docker network inspect services

# Test DNS (if using service names)
docker exec code-server-prometheus getent hosts code-server-postgres
```

---

## EMERGENCY PROCEDURES

### Service Won't Start
```bash
# 1. Check logs
docker logs <container_name> | tail -50

# 2. Check if port is in use
docker ps --format "{{.Names}}\t{{.Ports}}" | grep <port>

# 3. Increase resource limit in docker-compose.yml
# 4. Rebuild image: docker-compose build --no-cache <service>
# 5. Restart: docker-compose up -d <service>
```

### Container Using All Memory
```bash
# 1. Identify it
docker stats --no-stream | sort -k4 -h -r

# 2. Restart to clear leak
docker restart <container_name>

# 3. Monitor recovery
watch 'docker stats --no-stream | grep <container_name>'
```

### Database Connection Issues
```bash
# 1. Check if PostgreSQL is running
docker ps | grep postgres

# 2. Check logs
docker logs code-server-postgres | tail -50

# 3. Test connection
docker exec code-server-postgres psql -U postgres -c "SELECT 1;"

# 4. If stuck, restart
docker restart code-server-postgres
```

### Can't Reach Primary Host
```bash
# 1. From local machine
ping 192.168.168.31

# 2. Check SSH
ssh akushnir@192.168.168.31 "echo alive"

# 3. Check Docker daemon
ssh akushnir@192.168.168.31 "docker ps"

# 4. If Docker is down, restart it
ssh akushnir@192.168.168.31 "sudo systemctl restart docker"
```

---

## MONITORING DASHBOARDS

### Default Access
- **Username**: admin
- **Password**: (see .env file)

### Key Metrics to Watch
```
Grafana Dashboard:
  - System Load: Should be <2x CPU cores
  - Memory Usage: Should be <80% of total
  - Disk I/O: Should be normal (<10% busy)
  - Network: Should be <50% of available bandwidth
  - Container Health: Should be mostly green (healthy)

Prometheus Queries (useful):
  - up{job="prometheus"}  # Are all targets up?
  - rate(errors_total[5m])  # Error rate
  - container_memory_usage_bytes / 1024 / 1024  # Memory in MB
  - rate(container_cpu_usage_seconds_total[5m])  # CPU usage
```

---

## ALERTING

### Alert Severity Levels
```
CRITICAL (Immediate Action Required)
  - Service completely down (0 healthy replicas)
  - Database replication failed (>60s lag)
  - Disk usage >95%
  - Memory pressure detected
  → Action: Acknowledge in AlertManager, start incident

WARNING (Investigation Needed)
  - Service degraded (1/2 replicas down)
  - Database replication slow (>10s lag)
  - Disk usage >85%
  - Error rate elevated (>1%)
  → Action: Check logs, monitor, resolve within 1 hour

INFO (For Awareness)
  - Scheduled maintenance running
  - Backup completed
  - Configuration change made
  → Action: Log and document
```

### Acknowledge Alert
```
1. Go to AlertManager: http://192.168.168.31:9093
2. Find alert in list
3. Click "Silence" button
4. Set duration (default: 5 minutes)
5. Add comment (reason for silencing)
6. Click "Silence" to confirm
```

---

## FILES & LOCATIONS

| Item | Location | Type |
|------|----------|------|
| Docker Compose | /home/akushnir/code-server-deployment/ | Directory |
| Config Files | .env (in deployment dir) | Text file |
| Logs | docker logs <container> | Command |
| Backups | /home/akushnir/code-server-deployment/backups/ | Directory |
| SSH Key | ~/.ssh/id_rsa | File |
| Documentation | /home/akushnir/code-server/ (repo root) | Directory |

---

## USEFUL BASH ALIASES

Add to ~/.bashrc for faster operations:

```bash
alias prod="ssh akushnir@192.168.168.31"
alias rep="ssh akushnir@192.168.168.42"
alias stats="docker stats --no-stream"
alias unhealthy="docker ps --filter 'status=unhealthy' --format 'table {{.Names}}\t{{.Status}}'"
alias logs="docker logs -f"
alias deploy="cd /home/akushnir/code-server-deployment && docker-compose"
alias health="curl -s http://192.168.168.31:3000/api/health"
```

Then use:
```bash
prod  # Connect to primary
rep   # Connect to replica
stats  # Show container stats
unhealthy  # Show unhealthy containers
logs code-server-prometheus  # View logs
deploy up -d  # Start services
health  # Check API health
```

---

## ESCALATION PATH

**Level 1 (You)**: Check Grafana, restart service, check logs  
**Level 2 (Supervisor)**: Database issues, network problems, major service failures  
**Level 3 (Lead)**: Infrastructure changes, emergency procedures, security issues  
**Level 4 (Management)**: Customer-facing outages, major data loss, policy decisions

---

## FREQUENTLY USED QUERIES

```bash
# Total containers running
docker ps -q | wc -l

# Count healthy containers
docker ps --filter "status=running" --format "{{.Status}}" | grep -i healthy | wc -l

# List all services and their status
docker ps --format "table {{.Names}}\t{{.Status}}"

# Show container uptime
docker inspect --format='{{.State.StartedAt}}' <container>

# Find container by port
docker ps --filter "expose=<port>"

# Show environment variables in container
docker exec <container> env | sort

# Check process list in container
docker top <container>

# Get container IP address
docker inspect --format='{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container>
```

---

## QUICK REFERENCE - Common Container Names

```
Code Server:           code-server-ide
PostgreSQL:            code-server-postgres
Redis:                 code-server-redis
Prometheus:            code-server-prometheus
Grafana:               code-server-grafana
Loki:                  code-server-loki
Tempo:                 code-server-tempo
AlertManager:          code-server-alertmanager
GitLab:                code-server-gitlab
Vault:                 code-server-vault
Caddy:                 code-server-caddy
Keepalived:            code-server-keepalived
Redpanda:              code-server-redpanda-*
Control Plane:         code-server-control-plane
OTEL Collector:        code-server-otel-collector
Appsmith:              code-server-appsmith
```

---

**Remember**: When in doubt, check Grafana first! 📊  
**Restart** solves 80% of problems.  
**Backups** are your friend.  
**Document** everything for the next person!

---
