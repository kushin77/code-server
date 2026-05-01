# OPERATIONAL RUNBOOK - CODE-SERVER OBSERVABILITY PLATFORM
## Production Operations Manual
**Version**: 1.0.0  
**Last Updated**: May 1, 2026  
**Audience**: Operations, DevOps, SRE Teams

---

## TABLE OF CONTENTS
1. [Daily Operations Checklist](#daily-operations-checklist)
2. [Service Management](#service-management)
3. [Monitoring & Alerting](#monitoring--alerting)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Emergency Procedures](#emergency-procedures)
6. [Backup & Recovery](#backup--recovery)
7. [Performance Tuning](#performance-tuning)
8. [Common Tasks](#common-tasks)

---

## DAILY OPERATIONS CHECKLIST

### Morning Shift (8:00 AM)
```
□ Check Grafana dashboard: http://192.168.168.31:3000
  └─ Verify all services showing green (healthy)
  └─ Review system resource usage
  └─ Check for any overnight alerts

□ Verify primary host connectivity
  └─ ssh akushnir@192.168.168.31 'docker ps'
  └─ Confirm all 51 containers running
  └─ Check container memory/CPU allocation

□ Verify replica host connectivity
  └─ ssh akushnir@192.168.168.42 'docker ps'
  └─ Confirm sync status with primary
  └─ Check replication lag (should be <1s)

□ Review database replication
  └─ SSH to primary: psql -U postgres -h localhost
  └─ Check: SELECT * FROM pg_stat_replication;
  └─ Verify state='streaming' and sync_state='async'

□ Review AlertManager: http://192.168.168.31:9093
  └─ Check for any active alerts
  └─ Review alert history from overnight
  └─ Acknowledge any critical alerts

□ Check application logs: http://192.168.168.31:3100
  └─ Review Loki for any error patterns
  └─ Search for ERROR or CRITICAL level logs
  └─ Investigate any anomalies
```

### Hourly Check (Every 2 Hours)
```
□ Quick health check (2 min)
  └─ curl http://192.168.168.31:3000/api/health
  └─ curl http://192.168.168.31:9090/-/healthy
  └─ Verify response time <100ms

□ Container status (1 min)
  └─ ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}\t{{.Status}}" | grep -i unhealthy'
  └─ Should return empty (no unhealthy containers)

□ Disk space check (1 min)
  └─ ssh akushnir@192.168.168.31 'df -h | grep -E "dev/|mount"'
  └─ Ensure all mounts >20% free space
  └─ Alert if any mount >80% full
```

### End of Shift (5:00 PM)
```
□ Review all alerts from the day
  └─ Check AlertManager for patterns
  └─ Document any recurring issues
  └─ File tickets for long-term improvements

□ Verify backup completion
  └─ Check PostgreSQL backup: /var/lib/postgresql/backups/
  └─ Verify daily backup file exists and is recent
  └─ Confirm backup size is reasonable

□ Document shift handoff
  └─ Write summary of any incidents
  └─ List any outstanding issues
  └─ Note any performance observations
  └─ Mention any configuration changes made

□ Secure handoff to next shift
  └─ Ensure all containers running
  └─ Verify no pending deployments
  └─ Leave monitoring dashboards accessible
```

---

## SERVICE MANAGEMENT

### Starting All Services
```bash
# Connect to primary host
ssh akushnir@192.168.168.31

# Change to deployment directory
cd /home/akushnir/code-server-deployment

# Start all services
docker-compose up -d

# Verify startup
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Expected: All 51 containers should transition to "Up" state within 2-3 minutes
# Most services should be "healthy" within 5-7 minutes
```

### Stopping All Services
```bash
# WARNING: This will interrupt service for all users
# Only do this during scheduled maintenance window

ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-deployment
docker-compose down

# Verify all containers stopped
docker ps

# Expected: No running containers
```

### Stopping Specific Service
```bash
# Example: Stop Grafana for maintenance
ssh akushnir@192.168.168.31

# Stop single container
docker stop code-server-grafana

# Verify it stopped
docker ps | grep grafana

# Restart when ready
docker start code-server-grafana
```

### Restarting Failed Service
```bash
# Monitor for unhealthy containers
ssh akushnir@192.168.168.31
docker ps --filter "status=unhealthy" --format "{{.Names}}"

# Restart unhealthy container
docker restart <container_name>

# Example:
docker restart code-server-prometheus

# Monitor recovery
docker ps | grep prometheus
# Watch it cycle through states: "Up (health: starting)" → "Up (health: healthy)"
```

### Viewing Service Logs
```bash
# Real-time logs from container
docker logs -f code-server-prometheus

# Last 100 lines
docker logs --tail 100 code-server-prometheus

# Logs since specific time
docker logs --since 30m code-server-prometheus

# Logs with timestamps
docker logs --timestamps code-server-prometheus
```

---

## MONITORING & ALERTING

### Grafana Dashboard (http://192.168.168.31:3000)
```
Default credentials:
  Username: admin
  Password: (configured in .env)

Key Dashboards:
1. System Overview - Host metrics, Docker resource usage
2. Application Performance - Service latency, throughput
3. Database - PostgreSQL queries, replication lag
4. Container Metrics - CPU, memory, network per container
5. Alerts Status - Current and historical alerts
```

### Prometheus Queries
```
# Check all targets healthy
up{job=~".*"}

# CPU usage by container
sum(rate(container_cpu_usage_seconds_total[5m])) by (container_label_com_docker_container_name)

# Memory usage by container
container_memory_usage_bytes / 1024 / 1024 by (container_label_com_docker_container_name)

# PostgreSQL replication lag
pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') - pg_wal_lsn_diff(pg_last_xlog_receive_lsn(), '0/0')

# Redis memory usage
redis_used_memory_bytes / 1024 / 1024

# Network I/O by interface
rate(node_network_receive_bytes_total[5m]) by (device)
```

### AlertManager Configuration (http://192.168.168.31:9093)
```
Configuration file: /etc/alertmanager/alertmanager.yml (in container)

Key Rules:
- Service Down Alert: Fires if service unreachable for >2 minutes
- High Memory Alert: Fires if any container >90% memory
- High Disk Alert: Fires if any mount >85% full
- Database Replication Alert: Fires if replication lag >10 seconds
- High Error Rate: Fires if error rate >1% for 5 minutes

Actions Taken:
- Email notifications to ops team
- Webhook to incident management
- Slack integration (if configured)
```

### Setting Up Custom Alert
```yaml
# Edit alert rules (inside prometheus container)
# File: /etc/prometheus/alerts/custom.yml

groups:
  - name: custom_alerts
    interval: 30s
    rules:
      - alert: CustomServiceDown
        expr: up{job="service_name"} == 0
        for: 5m
        annotations:
          summary: "Service Name is down"
          description: "Service Name has been unreachable for >5 minutes"
```

---

## TROUBLESHOOTING GUIDE

### Container Not Starting
```bash
# 1. Check container status
docker ps -a | grep <container_name>

# 2. View container logs
docker logs <container_name>

# 3. Check for port conflicts
docker ps --format "table {{.Names}}\t{{.Ports}}"

# 4. Check resource availability
docker stats <container_name>

# 5. Inspect container configuration
docker inspect <container_name>

# 6. Restart container
docker restart <container_name>

# 7. If still failing, rebuild image
docker-compose build --no-cache <service_name>
docker-compose up -d <service_name>
```

### High Memory Usage
```bash
# 1. Identify container using most memory
docker stats --no-stream | sort -k 4 -h -r | head -5

# 2. Check memory limit
docker inspect <container_name> | grep -i memory

# 3. View detailed memory info
docker exec <container_name> free -h

# 4. Options to resolve:
#    a) Increase container memory limit in docker-compose.yml
#    b) Restart container (clears memory leaks)
#    c) Reduce verbosity of logging
#    d) Clear application caches

# Example: Restart to clear potential memory leak
docker restart <container_name>

# Example: Increase memory in docker-compose.yml
# services:
#   service_name:
#     mem_limit: 2g  (increase from previous value)
```

### Slow Database Queries
```bash
# 1. Connect to PostgreSQL
ssh akushnir@192.168.168.31
docker exec -it code-server-postgres psql -U postgres -d code_server

# 2. Check slow query log
SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;

# 3. Check database size
SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname))
FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;

# 4. Check table statistics
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

# 5. Restart PostgreSQL if performance degraded
docker restart code-server-postgres
```

### Redis Connection Issues
```bash
# 1. Check Redis status
ssh akushnir@192.168.168.31
docker exec code-server-redis redis-cli PING

# Expected output: PONG

# 2. Check connected clients
docker exec code-server-redis redis-cli INFO clients

# 3. Check memory
docker exec code-server-redis redis-cli INFO memory

# 4. Flush unused data (if needed)
docker exec code-server-redis redis-cli FLUSHDB

# 5. Restart if needed
docker restart code-server-redis
```

### Network Connectivity Issues
```bash
# 1. Test connectivity between hosts
ssh akushnir@192.168.168.31
ping -c 3 192.168.168.42

# 2. Test service-to-service connectivity
docker exec code-server-prometheus curl -s http://192.168.168.42:9090/-/healthy

# 3. Check Docker network
docker network ls
docker network inspect services

# 4. Test DNS resolution (if using service names)
docker exec code-server-prometheus getent hosts code-server-postgres

# 5. Check firewall rules
sudo iptables -L -n | grep -E "192.168.168|443|8090"
```

### Disk Space Issues
```bash
# 1. Check disk usage
ssh akushnir@192.168.168.31
df -h

# 2. Find largest directories
du -sh /* | sort -hr | head -10

# 3. Check Docker storage
docker system df

# 4. Clean up unused images/volumes (careful!)
docker image prune -a --force  # Removes unused images
docker volume prune --force     # Removes unused volumes
docker system prune --force     # Removes images, containers, volumes

# 5. Check logs directory
du -sh /var/lib/docker/containers/*/
# Consider reducing log rotation settings
```

---

## EMERGENCY PROCEDURES

### Service Outage Response
```
STEP 1: Assess Impact (1 minute)
  □ Which service(s) are down?
  □ How many users affected?
  □ What is the business impact?

STEP 2: Immediate Triage (2 minutes)
  □ Check Grafana for health status
  □ Review recent AlertManager events
  □ Check application logs in Loki
  □ Restart affected service(s)

STEP 3: Verify Recovery (2 minutes)
  □ Monitor service health metrics
  □ Confirm users can access service
  □ Verify no cascading failures
  □ Check error rates returning to normal

STEP 4: Root Cause Analysis (ongoing)
  □ Review logs for error patterns
  □ Check resource usage (CPU, memory, disk)
  □ Review recent configuration changes
  □ Check for external dependencies (DB, cache)

STEP 5: Documentation (after recovery)
  □ Document incident timeline
  □ Record root cause
  □ Create follow-up tickets
  □ Schedule post-incident review
```

### Database Replication Failure
```
SYMPTOM: Replica host losing sync with primary

IMMEDIATE ACTION:
  1. Check replication status on primary:
     ssh akushnir@192.168.168.31
     docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"
  
  2. Check replica connection:
     ssh akushnir@192.168.168.42
     docker logs code-server-postgres | tail -50
  
  3. If replica is stuck, restart it:
     docker restart code-server-postgres

LONGER-TERM FIX:
  1. Check network connectivity:
     ssh akushnir@192.168.168.31
     ping -c 5 192.168.168.42
  
  2. If still failing, full resync:
     ssh akushnir@192.168.168.42
     docker-compose down
     docker-compose up -d code-server-postgres
     # Wait 5-10 minutes for resync
  
  3. Verify replication resumed:
     ssh akushnir@192.168.168.31
     docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Complete Cluster Failure
```
SYMPTOM: Both primary and replica hosts unreachable

RECOVERY STEPS:
  1. Check host connectivity:
     ping 192.168.168.31
     ping 192.168.168.42
  
  2. If hosts are up but services down:
     ssh akushnir@192.168.168.31
     docker ps  # If no response, Docker daemon crashed
  
  3. Restart Docker daemon (if needed):
     sudo systemctl restart docker
     # Wait 30 seconds for daemon to start
     docker ps  # Should now respond
  
  4. Restart all services:
     cd /home/akushnir/code-server-deployment
     docker-compose up -d
     # Wait 5-10 minutes for services to stabilize
  
  5. Verify data integrity:
     # Check PostgreSQL data
     docker exec code-server-postgres psql -U postgres -c "SELECT COUNT(*) FROM pg_tables;"
     
  6. Restore from backup if needed:
     /scripts/backup-restore.sh /path/to/backup
```

### Critical Memory Leak
```
SYMPTOM: Container memory usage continuously increasing, service slowing down

IMMEDIATE ACTION:
  1. Identify container with memory leak:
     docker stats --no-stream | sort -k 4 -h -r
  
  2. View container logs for errors:
     docker logs -f <container_name> | grep -i "error\|memory\|oom"
  
  3. Restart container to clear memory:
     docker restart <container_name>
  
  4. Monitor memory after restart:
     docker stats <container_name>  # Should drop to low level

LONGER-TERM FIX:
  1. Update container image to latest version
  2. Review application for memory leaks
  3. Check for unbounded caches or logs
  4. Consider reducing container memory limit to force garbage collection
  5. Implement memory alerts for early warning
```

---

## BACKUP & RECOVERY

### Database Backup Procedure
```bash
# Automatic daily backup (configured in cron)
# Manual backup when needed:

ssh akushnir@192.168.168.31

# Full database backup
docker exec code-server-postgres pg_dump -U postgres > backup_$(date +%Y%m%d_%H%M%S).sql

# Compressed backup
docker exec code-server-postgres pg_dump -U postgres | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz

# Backup specific database
docker exec code-server-postgres pg_dump -U postgres code_server > backup_code_server_$(date +%Y%m%d_%H%M%S).sql

# Verify backup integrity
pg_restore --list backup_file.sql | head -20

# List backups
ls -lh backup_*.sql*
```

### Database Restore Procedure
```bash
# WARNING: This will overwrite existing data

ssh akushnir@192.168.168.31

# Stop applications using database (optional but recommended)
docker stop code-server-control-plane code-server-api

# Restore from backup
docker exec -i code-server-postgres psql -U postgres < backup_file.sql

# Or if compressed:
gunzip -c backup_file.sql.gz | docker exec -i code-server-postgres psql -U postgres

# Verify data after restore
docker exec code-server-postgres psql -U postgres -c "SELECT COUNT(*) FROM pg_tables;"

# Restart applications
docker start code-server-control-plane code-server-api

# Verify everything working
curl http://192.168.168.31:3000/api/health
```

### Volume Backup (Persistent Data)
```bash
# Backup all volumes
ssh akushnir@192.168.168.31
docker run --rm -v services_data:/data -v $(pwd):/backup alpine tar czf /backup/volumes_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C / data

# List volume backups
ls -lh volumes_backup_*.tar.gz

# Restore volumes from backup
docker run --rm -v services_data:/data -v $(pwd):/backup alpine tar xzf /backup/volumes_backup_file.tar.gz -C /
```

---

## PERFORMANCE TUNING

### Container Resource Limits
```yaml
# Edit docker-compose.yml to optimize resource allocation

services:
  service_name:
    deploy:
      resources:
        limits:
          cpus: '2.0'      # Maximum 2 CPU cores
          memory: 2G       # Maximum 2GB memory
        reservations:
          cpus: '1.0'      # Reserve 1 CPU core
          memory: 1G       # Reserve 1GB memory
```

### PostgreSQL Performance Tuning
```bash
ssh akushnir@192.168.168.31

# Connect to PostgreSQL
docker exec -it code-server-postgres psql -U postgres

# Check current settings
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW work_mem;
SHOW maintenance_work_mem;

# Optimize for host resources
# For 16GB+ hosts:
ALTER SYSTEM SET shared_buffers = '4GB';
ALTER SYSTEM SET effective_cache_size = '12GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
SELECT pg_reload_conf();
```

### Redis Memory Optimization
```bash
ssh akushnir@192.168.168.31

# Check current memory usage
docker exec code-server-redis redis-cli INFO memory

# Set memory limit to 2GB
docker exec code-server-redis redis-cli CONFIG SET maxmemory 2gb

# Set eviction policy (remove least recently used)
docker exec code-server-redis redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Verify settings persisted (edit docker-compose.yml to make permanent)
```

### Network Optimization
```bash
ssh akushnir@192.168.168.31

# Increase TCP backlog
sudo sysctl -w net.core.somaxconn=65535

# Increase max file descriptors
sudo sysctl -w fs.file-max=2097152

# Make persistent (edit /etc/sysctl.conf)
sudo nano /etc/sysctl.conf
# Add:
# net.core.somaxconn=65535
# fs.file-max=2097152
sudo sysctl -p
```

---

## COMMON TASKS

### Adding a New Service
```bash
# 1. Define service in docker-compose.yml
# 2. Create Dockerfile (if not using public image)
# 3. Test locally
# 4. Deploy to staging
# 5. Run validation tests
# 6. Deploy to production

ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-deployment
docker-compose pull <new_service>
docker-compose up -d <new_service>
docker ps | grep <new_service>
```

### Scaling a Service
```bash
# Scale service replicas (if using Docker Swarm)
docker service scale <service_name>=3

# Or manually with docker-compose
# 1. Update docker-compose.yml to add multiple service definitions
# 2. Deploy: docker-compose up -d
# 3. Configure load balancing (Caddy)
```

### Rolling Update (Zero Downtime)
```bash
# 1. Pull new image
docker pull <image:tag>

# 2. Create new container with new image
docker-compose up -d --no-deps --scale <service_name>=2 --no-recreate <service_name>

# 3. Wait for health check
sleep 30
docker ps | grep <service_name>

# 4. Remove old container
docker ps -a | grep <service_name>
docker rm <old_container_id>
```

### Debugging Service Issues
```bash
# 1. Check logs
docker logs -f <container_name>

# 2. Execute command in container
docker exec -it <container_name> sh

# 3. Check environment variables
docker exec <container_name> env | sort

# 4. Check network connectivity
docker exec <container_name> ping <other_service>

# 5. Check open ports
docker exec <container_name> netstat -tulpn

# 6. Monitor resource usage
docker stats <container_name>
```

### Configuration Changes
```bash
# 1. Edit docker-compose.yml or .env
nano docker-compose.yml

# 2. Validate syntax
docker-compose config

# 3. Apply changes (most services support hot-reload)
docker-compose up -d

# 4. Some services require restart
docker-compose restart <service_name>

# 5. Verify changes took effect
docker exec <service_name> grep <config_key> /etc/config/file
```

---

## MAINTENANCE WINDOW PROCEDURES

### Scheduled Maintenance
```bash
# 1. Announce maintenance window (1 hour before)
#    - Notify all users
#    - Set status page to "Maintenance Scheduled"

# 2. Create backup before maintenance
docker exec code-server-postgres pg_dump -U postgres | gzip > pre_maintenance_backup.sql.gz

# 3. Stop services
docker-compose down

# 4. Perform maintenance (OS updates, config changes, etc.)

# 5. Verify system health before restart
fsck -n /dev/sda1  # Check filesystem
df -h  # Check disk space
free -h  # Check memory

# 6. Restart services
docker-compose up -d

# 7. Wait for stabilization (5-10 minutes)

# 8. Run health checks
bash scripts/ops/full-deployment-test.sh --dry-run

# 9. Announce maintenance complete
#    - Set status page to "Operational"
#    - Notify all users
#    - Document work performed
```

---

## ESCALATION CONTACTS

### Support Levels
- **Level 1**: Check Grafana dashboard, restart service
- **Level 2**: Review logs in Loki, check database
- **Level 3**: Manual intervention, emergency procedures
- **Level 4**: Major incident, engage leadership

### Emergency Contacts
- **Primary On-Call**: akushnir@192.168.168.31
- **Escalation**: Review AlertManager severity levels
- **Incident Management**: File ticket and notify team

---

## QUICK REFERENCE

### Most Common Commands
```bash
# Check all services
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# View recent errors
docker logs --since 1h | grep -i error

# Restart everything
docker-compose restart

# Check health status
curl -s http://192.168.168.31:3000/api/health

# View metrics
curl -s http://192.168.168.31:9090/api/v1/query?query=up

# SSH to replica
ssh akushnir@192.168.168.42
```

---

**Document Version**: 1.0.0  
**Last Updated**: May 1, 2026  
**Next Review**: May 15, 2026
