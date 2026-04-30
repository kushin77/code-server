# DevOps Team Runbook - Hermes Agent Portal

**Date:** April 30, 2026 | **Audience:** DevOps Team | **Status:** PRODUCTION

---

## Quick Start (5 Minutes)

### Morning Startup
```bash
cd /home/akushnir/code-server

# Verify services are up
docker-compose -f docker-compose.enterprise.yml ps

# If any down: restart all
docker-compose -f docker-compose.enterprise.yml restart

# Verify health
curl -k https://kushnir.cloud/api/hermes/health

# Check no errors
docker-compose -f docker-compose.enterprise.yml logs --since 10m | grep -i error
```

### Daily Monitoring (30 seconds)
```bash
# Quick health check every 2 hours
./monitor-health.sh 10 300

# Check metrics
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}"

# Check disk
df -h /home
```

---

## Critical Procedures

### Deploy Production (30 minutes)

```bash
#!/bin/bash
set -e

echo "[1/5] Pre-deployment backup"
./backup-recovery.sh backup

echo "[2/5] Validate deployment"
./validate-deployment.sh
# Should show: ALL CHECKS PASS

echo "[3/5] Upgrade SSL certificate"
ssh akushnir@192.168.168.31 << 'EOF'
sudo certbot certonly --standalone -d kushnir.cloud --agree-tos
# Update Caddyfile with cert path
docker exec nginx-reverse-proxy nginx -s reload
EOF

echo "[4/5] Start all services"
docker-compose -f docker-compose.enterprise.yml up -d

echo "[5/5] Verify production"
sleep 30
curl -k https://kushnir.cloud/api/hermes/health
echo "[OK] Production deployment complete"
```

### Emergency: Service Down (5 minutes)

```bash
# 1. Identify issue
docker logs <service-name> | tail -50

# 2. Restart
docker-compose -f docker-compose.enterprise.yml restart <service-name>

# 3. Verify
curl -k https://kushnir.cloud/api/hermes/health

# If still down:
# 4. Rebuild
docker-compose -f docker-compose.enterprise.yml down <service-name>
docker-compose -f docker-compose.enterprise.yml up -d <service-name>

# 5. Last resort: Full restore
./backup-recovery.sh restore <backup-id>
```

### Emergency: Database Down (10 minutes)

```bash
# 1. Check status
docker ps | grep postgres

# 2. Check logs
docker logs code-server-postgres | tail -50

# 3. Restart
docker-compose -f docker-compose.enterprise.yml restart code-server-postgres

# 4. Verify connectivity
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"

# 5. If replication broken: Remediate secondary
./remediate_secondary.sh

# 6. Verify after remediation
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT * FROM pg_stat_replication;"
```

### Emergency: Disk Full (5 minutes)

```bash
# 1. Check usage
df -h /home
du -sh /* | sort -h | tail -10

# 2. Emergency cleanup
rm -rf /home/akushnir/code-server/deployment-reports/*.text
rm -rf /home/akushnir/code-server/monitoring-logs/*.log

# 3. Docker cleanup
docker system prune -a

# 4. Verify
df -h /home
# Should have >20GB free
```

### Emergency: High CPU (5 minutes)

```bash
# 1. Identify culprit
docker stats --no-stream | sort -k3 -rn | head -3

# 2. If database high:
docker exec code-server-postgres vacuumdb -U purebliss_user purebliss_db

# 3. If app high:
docker-compose -f docker-compose.enterprise.yml restart appsmith

# 4. Monitor
docker stats --no-stream

# CPU should drop to <60%
```

### Emergency: High Memory (5 minutes)

```bash
# 1. Check memory
docker stats --no-stream | sort -k4 -rn | head -3

# 2. Clear Redis cache
docker exec code-server-redis redis-cli FLUSHALL

# 3. Restart high-memory service
docker-compose -f docker-compose.enterprise.yml restart <service>

# 4. Monitor
docker stats --no-stream
# Memory should drop to <70%
```

---

## Scheduled Tasks

### Daily (09:00 UTC)
```bash
# Health check
./monitor-health.sh 30 300

# Validate deployment
./validate-deployment.sh
```

### Weekly (Friday 15:00 UTC)
```bash
# Full backup
./backup-recovery.sh backup

# Performance optimization
./optimize-performance.sh optimize

# Weekly report
./optimize-performance.sh report
```

### Monthly (1st at 09:00 UTC)
```bash
# Test recovery
./backup-recovery.sh restore <oldest-backup>
# Verify system works
curl -k https://kushnir.cloud/api/hermes/health
# Re-deploy from latest backup
./backup-recovery.sh restore <latest-backup>
```

---

## Commands Reference

```bash
# Service management
docker-compose -f docker-compose.enterprise.yml ps
docker-compose -f docker-compose.enterprise.yml up -d
docker-compose -f docker-compose.enterprise.yml down
docker-compose -f docker-compose.enterprise.yml restart
docker-compose -f docker-compose.enterprise.yml logs -f

# Service-specific logs
docker logs -f hermes-integration
docker logs -f appsmith
docker logs -f code-server-postgres
docker logs -f code-server-redis

# Health checks
curl -k https://kushnir.cloud/api/hermes/health
curl -k https://kushnir.cloud/
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"

# Resource monitoring
docker stats --no-stream
df -h /home
docker system df

# Database management
docker exec code-server-postgres pg_dump -U purebliss_user purebliss_db > backup.sql
docker exec code-server-postgres vacuumdb -U purebliss_user purebliss_db
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db

# Cache management
docker exec code-server-redis redis-cli FLUSHALL
docker exec code-server-redis redis-cli INFO

# Backup operations
./backup-recovery.sh backup
./backup-recovery.sh list
./backup-recovery.sh restore <backup-id>

# Automation
./monitor-health.sh 30 3600
./validate-deployment.sh
./optimize-performance.sh analyze
./deploy-replica.sh 192.168.168.31 192.168.168.42
```

---

## On-Call Escalation

**Response Time Targets:**
- P1 (Critical): 5 minutes
- P2 (High): 15 minutes
- P3 (Medium): 1 hour
- P4 (Low): 24 hours

**Escalation Chain:**
1. DevOps On-Call (5 min)
2. Senior DevOps (10 min if unresolved)
3. Architecture Lead (20 min if unresolved)
4. CTO (30 min if unresolved)

**Contact:** [On-call contact list]

---

## Weekly Checklist

- [ ] Monday 09:00: Week planning standup
- [ ] Daily 09:00: Health check
- [ ] Daily 12:00: Mid-day review
- [ ] Friday 15:00: Weekly backup and optimization
- [ ] Friday 17:00: Weekly report and planning

---

**This runbook is your daily reference. Bookmark it and keep it handy.**
