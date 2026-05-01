# ElevatedIQ Code Server - Master Operations Runbook

**Version**: 2.0  
**Last Updated**: April 30, 2026  
**Scope**: Production operations for code-server-enterprise platform  
**Audience**: DevOps, Infrastructure, Operations teams

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Platform Architecture](#platform-architecture)
3. [Daily Operations](#daily-operations)
4. [Configuration Management](#configuration-management)
5. [Deployment Procedures](#deployment-procedures)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Incident Response](#incident-response)
8. [Backup & Recovery](#backup--recovery)
9. [Scaling & Performance](#scaling--performance)
10. [Troubleshooting](#troubleshooting)
11. [Emergency Procedures](#emergency-procedures)

---

## Quick Start

### Check System Status
```bash
# Connect to primary node
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && docker compose ps'

# Check all services running
docker compose ps | grep -E "Up|Exited"

# Quick health check
docker compose exec code-server-postgres pg_isready -h localhost
docker compose exec code-server-redis redis-cli ping
docker compose exec code-server-qdrant curl http://localhost:6333/health
```

### View Recent Logs
```bash
# Last 50 lines from all services
docker compose logs --tail=50

# Follow logs in real-time
docker compose logs -f

# Specific service logs
docker compose logs -f code-server-postgres
docker compose logs -f code-server-redis
```

### Load Configuration
```bash
# Always load in this order
source .env.base
[ -f .env.infrastructure ] && source .env.infrastructure
[ -f .env.deployment ] && source .env.deployment  
[ -f .env.cluster ] && source .env.cluster
[ -f .env.production ] && source .env.production

echo "Configuration loaded: APEX_DOMAIN=$APEX_DOMAIN, DB_HOST=$DATABASE_HOST"
```

---

## Platform Architecture

### Deployment Model

**Primary Node (192.168.168.31)**
- Master PostgreSQL database
- Redis primary
- Core services: scheduler, memory-engine, reputation-engine
- Ollama LLM (CPU-only or GPU if available)
- All application microservices

**Replica Node (192.168.168.42)**
- Standby PostgreSQL (read-only replication)
- Redis replica
- Ollama with GPU support (if hardware available)
- Load-balanced services
- Failover candidate

**Shared Infrastructure**
- Cluster VIP: 192.168.168.250 (load balancer endpoint)
- NAS: 192.168.168.56 (backup storage)

### Service Categories

**Core Infrastructure**
- PostgreSQL: Transactional data, schema 15.x
- Redis: Session cache, Pub/Sub, 6GB max memory
- Redpanda: Event streaming (Kafka-compatible)
- Qdrant: Vector database for embeddings

**Observability**
- Prometheus: Metrics collection (30-day retention)
- Grafana: Dashboards (3000)
- Loki: Log aggregation (30-day retention)
- Alertmanager: Alert routing (9093)
- Tempo: Distributed tracing (4317)

**Application Services**
- Control Plane (8000): API gateway and coordination
- Execution Scheduler (8001): Task orchestration
- Memory Engine (8003): LLM context management
- Reputation Engine (8002): Service trust scoring
- Paperclip (8007): Document processing

**AI/ML Stack**
- Ollama (11434): LLM inference (CPU or GPU)
- OPAL (8181): Policy authorization engine

---

## Daily Operations

### Morning Checklist

**1. System Health (9:00 AM)**
```bash
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && \
  docker compose ps && \
  echo "---" && \
  docker compose logs --tail=20 | tail -10'
```

**2. Database Replication Status**
```bash
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && \
  docker compose exec code-server-postgres psql -U postgres -c \
    "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"'
```

**3. Storage Health**
```bash
# Check NAS connectivity
ssh akushnir@192.168.168.31 'df -h /mnt/nas | tail -1'

# Check volume usage
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && \
  docker volume ls | grep code-server'
```

**4. Metrics Baseline**
```bash
# Check Prometheus data ingestion
curl http://192.168.168.31:9090/api/v1/query?query=up

# Check Grafana dashboard
open https://192.168.168.31:3000
# Login: admin / <GRAFANA_ADMIN_PASSWORD>
```

### Weekly Tasks

**Monday - Dependency Updates Review**
```bash
# Check for Dependabot PRs
gh pr list --label dependencies --limit 10

# Review recent updates
git log --oneline --grep="chore(deps)" --since="1 week ago"
```

**Wednesday - Configuration Validation**
```bash
# Validate environment configuration
source .env.base && source .env.infrastructure && \
source .env.deployment && source .env.cluster && \
source .env.production

# Check for drift
grep -r "hardcoded" docker-compose.yml scripts/ || echo "✅ No hardcoded values"
```

**Friday - Backup Verification**
```bash
# Verify daily backups exist
ls -lh /mnt/nas/backups/daily/ | tail -5

# Check backup integrity
du -sh /mnt/nas/backups/daily/*/postgres-* | tail -3
```

### Monthly Tasks

**First Friday - Disaster Recovery Drill**
```bash
# Schedule test failover
./scripts/dr/test-failover-simulation.sh --dry-run

# Review failover procedures
cat docs/DEPLOYMENT_PROCEDURES.md | grep -A 20 "Emergency Failover"
```

**Mid-Month - Performance Baseline**
```bash
# Run load test
./scripts/ops/run-load-test.sh --duration=300 --concurrency=50

# Review Prometheus metrics
curl http://192.168.168.31:9090/api/v1/query_range \
  -d 'query=http_request_duration_seconds_bucket' \
  -d 'start=2026-04-15T00:00:00Z' \
  -d 'end=2026-04-30T23:59:59Z' \
  -d 'step=1h'
```

---

## Configuration Management

### Environment Configuration Hierarchy

**Load Order** (highest to lowest priority):
```
1. External environment variables (CI/CD secrets, system env)
2. .env.production (production secrets)
3. .env.cluster (cluster-specific settings)
4. .env.deployment (deployment mode overrides)
5. .env.infrastructure (infrastructure URLs)
6. .env.base (canonical defaults)
```

### Modifying Configuration

**To change a value for all environments:**
```bash
# Edit .env.base (ONLY for canonical defaults)
vim .env.base

# Add comment explaining change
# Example:
# DATABASE_POOL_SIZE=${DATABASE_POOL_SIZE:-20}  # Updated 2026-04-30, issue #3284

# Reload and test
source .env.base
echo $DATABASE_POOL_SIZE  # Verify change
```

**To change a value for production only:**
```bash
# Edit .env.production (NOT in git, use secrets manager)
# If not available locally:
gcloud secrets versions access latest --secret="code-server-env-production" > .env.production
# Edit the file
vim .env.production
# Update in secrets manager
gcloud secrets versions add code-server-env-production --data-file=.env.production
```

**To change infrastructure settings:**
```bash
# Edit .env.infrastructure
vim .env.infrastructure

# Must specify: API_HOST, API_PORT, PRIMARY_HOST, REPLICA_HOST
grep "^API\|^PRIMARY\|^REPLICA" .env.infrastructure

# Test
docker compose config --quiet  # Validate docker-compose.yml
```

### Configuration Validation

```bash
# Verify all environment variables loaded
set -a
source .env.base
source .env.infrastructure 2>/dev/null || true
source .env.deployment 2>/dev/null || true
source .env.cluster 2>/dev/null || true
source .env.production 2>/dev/null || true
set +a

# Check critical variables exist
for var in DATABASE_HOST DATABASE_PORT REDIS_HOST REDIS_PORT APEX_DOMAIN; do
  if [ -z "${!var}" ]; then
    echo "❌ MISSING: $var"
  else
    echo "✅ $var=${!var}"
  fi
done

# Validate docker-compose.yml
docker compose config --quiet && echo "✅ docker-compose.yml valid"
```

---

## Deployment Procedures

### Standard Deployment (No Changes)
```bash
# 1. SSH to primary
ssh akushnir@192.168.168.31

# 2. Navigate to code-server
cd ~/code-server-enterprise

# 3. Load configuration
source .env.base
source .env.infrastructure
source .env.cluster
source .env.production

# 4. Verify current state
docker compose ps

# 5. No changes - services running as-is
echo "✅ Deployment verified"
```

### Rolling Deployment (With Updates)

```bash
# 1. Update code on primary
ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise && git pull'

# 2. Validate before applying
docker compose config --quiet

# 3. Stop services gracefully (primary)
docker compose down

# 4. Wait for replica to catch up (check replication lag)
# ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && \
#   docker compose exec -T code-server-postgres \
#   psql -U postgres -c "SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(), replay_lsn);"'

# 5. Start services with new configuration
docker compose up -d

# 6. Verify services healthy
sleep 30
docker compose ps
docker compose logs --tail=20 | grep -E "ERROR|WARNING"

# 7. Update replica (same steps)
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && git pull && \
  docker compose down && docker compose up -d'
```

### Emergency Rollback
```bash
# 1. Identify last known good commit
git log --oneline -5 | head -3

# 2. Revert to known good state
git revert HEAD --no-edit  # Creates new commit

# 3. Redeploy
docker compose down
docker compose up -d

# 4. Monitor
docker compose logs -f
```

---

## Monitoring & Alerting

### Prometheus Queries

**Service Availability**
```
up{job="docker"}  # Should be 1 for all services
```

**Request Latency**
```
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Error Rate**
```
rate(http_requests_total{status=~"5.."}[5m])
```

**Database Connections**
```
pg_stat_activity_count
```

**Redis Memory**
```
redis_memory_used_bytes / redis_memory_max_bytes
```

### Setting Up Alerts

**Example Alert in prometheus.yml**
```yaml
groups:
  - name: service_health
    interval: 30s
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} service down"
          
      - alert: HighErrorRate
        expr: rate(errors_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
```

### Manual Checks

```bash
# Check each service endpoint
for service in postgres redis redpanda qdrant prometheus grafana; do
  echo "Checking $service..."
  docker compose exec -T $service curl http://localhost:XXXX/health || echo "Failed"
done
```

---

## Incident Response

### Common Incidents & Fixes

**Database Connection Pool Exhausted**
```bash
# 1. Identify long-running queries
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT pid, usename, query, query_start FROM pg_stat_activity WHERE state != 'idle';"

# 2. Check current pool size
echo $DATABASE_POOL_SIZE

# 3. Increase if needed
# Edit .env.base and increase DATABASE_POOL_SIZE
# Then: docker compose restart code-server-control-plane

# 4. Monitor improvement
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT current_setting('max_connections');"
```

**Redis Memory Pressure**
```bash
# 1. Check memory usage
docker compose exec code-server-redis redis-cli INFO memory

# 2. Identify large keys
docker compose exec code-server-redis redis-cli --bigkeys

# 3. Flush non-critical data
docker compose exec code-server-redis redis-cli FLUSHDB ASYNC

# 4. Increase max memory if needed
# Edit .env.base: REDIS_MAX_MEMORY=8gb
# Then: docker compose restart code-server-redis
```

**High Disk Usage**
```bash
# 1. Check disk usage
df -h /

# 2. Identify largest services
docker system df

# 3. Clean unused containers/images
docker system prune -a

# 4. Check logs
du -sh /var/lib/docker/containers/*/logs

# 5. Truncate large logs
docker compose logs --tail=0 > /dev/null
```

---

## Backup & Recovery

### Automated Backups

**Frequency**: Daily at 02:00 UTC

**Backup Components**:
- PostgreSQL full dump
- Redis snapshot
- Qdrant snapshots
- Docker volumes

**Location**: `/mnt/nas/backups/daily/`

### Manual Backup

```bash
# 1. Database backup
docker compose exec code-server-postgres pg_dump -U postgres \
  -F c > backup_$(date +%Y%m%d).dump

# 2. Move to NAS
mv backup_*.dump /mnt/nas/backups/manual/

# 3. Verify
ls -lh /mnt/nas/backups/manual/backup_*.dump
```

### Recovery Procedure

**Database Recovery**
```bash
# 1. Stop services
docker compose down

# 2. Restore database
docker compose exec code-server-postgres pg_restore -U postgres \
  -d code_server /backups/backup_YYYYMMDD.dump

# 3. Restart services
docker compose up -d

# 4. Verify
docker compose logs code-server-postgres | tail -20
```

---

## Scaling & Performance

### Horizontal Scaling

**Add Replica Node**
```bash
# 1. Provision new host
terraform apply -target=aws_instance.replica_2

# 2. Configure replication
./scripts/ops/setup-replica-replication.sh --primary=192.168.168.31 \
  --replica=192.168.168.43

# 3. Add to load balancer
./scripts/ops/add-replica-to-cluster.sh --replica=192.168.168.43

# 4. Verify
curl http://192.168.168.250/health  # VIP endpoint
```

### Resource Tuning

**CPU Allocation**
```bash
# Current settings (from docker-compose.yml)
# Limits: 4 CPU per service
# Reservations: 2 CPU per service

# To increase for high-load services:
docker update --cpus 8 code-server-control-plane

# Monitor
docker stats code-server-control-plane
```

**Memory Allocation**
```bash
# Current settings
# PostgreSQL: 8GB limit, 4GB reserved
# Redis: 8GB limit, 4GB reserved

# Update if needed
docker update --memory 16g code-server-postgres

# Verify
docker inspect code-server-postgres | grep -A 5 Memory
```

---

## Troubleshooting

### Service Won't Start

```bash
# 1. Check logs
docker compose logs <service-name>

# 2. Validate configuration
docker compose config --quiet

# 3. Check image exists
docker image ls | grep <service-name>

# 4. Verify ports not in use
netstat -tulpn | grep LISTEN

# 5. Rebuild image if needed
docker compose build --no-cache <service-name>
```

### Connectivity Issues

```bash
# 1. Check DNS resolution
docker run --rm busybox nslookup code-server-postgres

# 2. Verify network
docker network ls | grep code-server
docker network inspect <network-name>

# 3. Test service connectivity
docker compose exec <service1> curl http://<service2>:PORT/health
```

### Performance Degradation

```bash
# 1. Check resource usage
docker stats

# 2. Check slow queries (PostgreSQL)
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT query, calls, mean_exec_time FROM pg_stat_statements \
   ORDER BY mean_exec_time DESC LIMIT 10;"

# 3. Check connection count
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT count(*) FROM pg_stat_activity;"

# 4. Review recent changes
git log --oneline -10
```

---

## Emergency Procedures

### Total System Failure Recovery

**Step 1: Assess Damage**
```bash
ssh akushnir@192.168.168.31 'docker compose ps -a'
# Note which services are down
```

**Step 2: Database Recovery**
```bash
# Use most recent backup
ls -lt /mnt/nas/backups/daily/postgres-* | head -1

# Stop all services
docker compose down

# Restore from backup
docker compose exec code-server-postgres pg_restore -U postgres \
  -C < /mnt/nas/backups/daily/postgres-latest.dump

# Verify
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT version();"
```

**Step 3: Service Recovery**
```bash
# Restart all services
docker compose up -d

# Verify each service
docker compose ps

# Check logs for errors
docker compose logs --tail=50 | grep ERROR

# Monitor startup
watch -n 2 'docker compose ps'
```

**Step 4: Health Verification**
```bash
# Wait 2 minutes for services to stabilize
sleep 120

# Run health checks
./scripts/ops/health-check-service.sh

# Verify database replication
docker compose exec code-server-postgres psql -U postgres -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# Check application logs
docker compose logs --since=5m | grep -i error
```

### Failover to Replica

**Planned Failover**
```bash
# 1. Prepare replica to be primary
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && \
  docker compose exec code-server-postgres pg_ctl promote'

# 2. Update VIP to point to replica
./scripts/ops/update-vip-endpoint.sh --new-primary=192.168.168.42

# 3. Verify
curl http://192.168.168.250/health  # Should return OK

# 4. Resume operations
echo "✅ Failover complete"
```

**Unplanned Failover** (Primary node down)
```bash
# 1. Force replica promotion
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && \
  docker compose exec code-server-postgres pg_ctl promote -D /var/lib/postgresql/data'

# 2. Restart all services on replica
ssh akushnir@192.168.168.42 'cd ~/code-server-enterprise && \
  docker compose restart'

# 3. Update VIP
./scripts/ops/update-vip-endpoint.sh --new-primary=192.168.168.42

# 4. Investigate original failure
ssh akushnir@192.168.168.31 'docker compose logs | tail -100 > /tmp/failure.log'
```

---

## Contact & Escalation

| Severity | Contact | Response Time |
|----------|---------|----------------|
| **Critical** (System Down) | On-call Engineer | 5 minutes |
| **High** (Service Degraded) | Engineering Lead | 15 minutes |
| **Medium** (Performance Issue) | DevOps Team | 1 hour |
| **Low** (Enhancement) | Backlog | Next sprint |

**On-Call**: [Phone/Email]  
**Escalation**: [Manager Contact]  
**War Room**: [Zoom/Slack Link]

---

## Appendix: Quick Commands Reference

```bash
# View all running services
docker compose ps

# View service logs (last 50 lines)
docker compose logs --tail=50 <service>

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Restart a specific service
docker compose restart <service>

# Execute command in service container
docker compose exec <service> <command>

# View network
docker network ls
docker network inspect <network>

# Backup database
docker compose exec code-server-postgres pg_dump -U postgres -d code_server > backup.sql

# View resource usage
docker stats

# Check configuration validity
docker compose config --quiet

# Update to latest code
git pull && docker compose up -d

# View recent changes
git log --oneline -10
```

---

**Document Version**: 2.0  
**Last Reviewed**: April 30, 2026  
**Next Review**: May 30, 2026  
**Status**: ✅ Production Ready

For updates or corrections, please submit a PR or contact the DevOps team.
