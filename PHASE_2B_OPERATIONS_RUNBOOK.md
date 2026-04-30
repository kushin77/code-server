# Phase 2b Operations Runbook

**Version:** 1.0  
**Purpose:** Day-to-day operational procedures and troubleshooting for Phase 2b infrastructure  
**Status:** Production-ready runbook  

---

## Table of Contents

1. Quick Reference Commands
2. Daily Operations
3. Monitoring & Alerting
4. Common Troubleshooting
5. Emergency Procedures
6. Maintenance Operations
7. Incident Response
8. Performance Tuning

---

## 1. Quick Reference Commands

### 1.1 Essential Commands Cheat Sheet

```bash
# Deployment & Status
orchestrate-deployment.sh --dry-run              # Test deployment
orchestrate-deployment.sh local                  # Deploy locally
orchestrate-deployment.sh gcp                    # Deploy to GCP
full-deployment-test.sh                          # Run 6-phase validation
check-gitlab-compose-parity.sh                   # Verify PRIMARY/REPLICA parity

# Monitoring & Health
curl http://localhost:9090/api/v1/targets       # Check Prometheus targets
curl http://localhost:3000                      # Access Grafana (admin/admin)
curl http://localhost:9093                      # Access AlertManager

# Container Management
docker ps -n 20                                  # List containers
docker logs -f gitlab-main                      # Follow GitLab logs
docker exec gitlab-postgresql psql              # Connect to PostgreSQL

# System Status
ssh "root@$PRIMARY_HOST" "docker ps"            # List PRIMARY containers
ssh "root@$REPLICA_HOST" "docker ps"            # List REPLICA containers
ssh "root@$PRIMARY_HOST" "free -h"              # Check PRIMARY memory
ssh "root@$REPLICA_HOST" "free -h"              # Check REPLICA memory

# Database Operations
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c '\l'"
# List databases

ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'SELECT slot_name FROM pg_replication_slots;'"
# Check replication slots

# Redis Operations
ssh "root@$PRIMARY_HOST" "docker exec gitlab-redis redis-cli PING"
ssh "root@$PRIMARY_HOST" "docker exec gitlab-redis redis-cli INFO replication"
```

### 1.2 Environment Setup

```bash
# Load Phase 2b environment variables
source scripts/config/phase2b-env.sh

# Set deployment mode
export DEPLOYMENT_MODE="local"  # or "gcp"

# Verify environment
echo "PRIMARY_HOST: $PRIMARY_HOST"
echo "REPLICA_HOST: $REPLICA_HOST"
```

---

## 2. Daily Operations

### 2.1 Morning Health Check

**Duration:** 5 minutes  
**Frequency:** Daily before start of shift  

```bash
#!/bin/bash
set -euo pipefail

echo "=== Phase 2b Morning Health Check ==="

# 1. Check GitLab availability
echo "Checking GitLab..."
GITLAB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8101)
if [ "$GITLAB_STATUS" = "200" ]; then
  echo "✅ GitLab: OK (HTTP $GITLAB_STATUS)"
else
  echo "❌ GitLab: DOWN (HTTP $GITLAB_STATUS)"
  exit 1
fi

# 2. Check database replication
echo "Checking database replication..."
REP_SLOTS=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-postgresql psql -U postgres -t -c 'SELECT COUNT(*) FROM pg_replication_slots;' 2>&1")
if [ "$REP_SLOTS" -gt 0 ]; then
  echo "✅ Database replication: ACTIVE ($REP_SLOTS slots)"
else
  echo "❌ Database replication: INACTIVE"
  exit 1
fi

# 3. Check Redis connectivity
echo "Checking Redis..."
REDIS_PING=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-redis redis-cli PING 2>&1")
if [ "$REDIS_PING" = "PONG" ]; then
  echo "✅ Redis: PONG"
else
  echo "❌ Redis: NO PONG"
  exit 1
fi

# 4. Check container count
echo "Checking containers..."
PRIMARY_COUNT=$(ssh "root@$PRIMARY_HOST" "docker ps -q | wc -l")
REPLICA_COUNT=$(ssh "root@$REPLICA_HOST" "docker ps -q | wc -l")
echo "✅ PRIMARY: $PRIMARY_COUNT containers"
echo "✅ REPLICA: $REPLICA_COUNT containers"

if [ "$PRIMARY_COUNT" -lt 50 ] || [ "$REPLICA_COUNT" -lt 50 ]; then
  echo "⚠️  WARNING: Container count lower than expected"
fi

# 5. Check disk space
echo "Checking disk space..."
PRIMARY_DISK=$(ssh "root@$PRIMARY_HOST" "df / | awk '/\// {print \$5}' | sed 's/%//'")
REPLICA_DISK=$(ssh "root@$REPLICA_HOST" "df / | awk '/\// {print \$5}' | sed 's/%//'")

if [ "$PRIMARY_DISK" -gt 80 ]; then
  echo "⚠️  WARNING: PRIMARY disk ${PRIMARY_DISK}% (> 80%)"
else
  echo "✅ PRIMARY disk: ${PRIMARY_DISK}%"
fi

if [ "$REPLICA_DISK" -gt 80 ]; then
  echo "⚠️  WARNING: REPLICA disk ${REPLICA_DISK}% (> 80%)"
else
  echo "✅ REPLICA disk: ${REPLICA_DISK}%"
fi

echo ""
echo "✅ Morning health check complete"
```

### 2.2 Status Dashboard Monitoring

**Duration:** Ongoing (view every 2 hours)  
**Tools:** Grafana, Prometheus  

```bash
# Access dashboards
echo "Grafana: http://localhost:3000"
echo "  - Username: admin"
echo "  - Password: admin"
echo ""
echo "Prometheus: http://localhost:9090"
echo "  - Query interface for raw metrics"
```

**Dashboards to monitor:**
1. **Cluster Health Dashboard**
   - Overall cluster status
   - Container counts (PRIMARY/REPLICA)
   - Replication lag
   - Parity gate status

2. **Performance Metrics Dashboard**
   - CPU usage (PRIMARY/REPLICA)
   - Memory usage (PRIMARY/REPLICA)
   - Disk I/O
   - Network bandwidth

3. **Database Health Dashboard**
   - Connection count
   - Query performance
   - Replication status
   - Backup status

### 2.3 Log Review

**Duration:** 10 minutes  
**Frequency:** Every 4 hours  

```bash
# Check for errors in container logs
echo "Checking GitLab logs for errors..."
ssh "root@$PRIMARY_HOST" "docker logs -n 100 gitlab-main 2>&1 | grep -i error | tail -10"

# Check GitLab-specific logs
echo "Checking GitLab-specific error logs..."
ssh "root@$PRIMARY_HOST" "docker exec gitlab-main tail -20 /var/log/gitlab/gitlab-rails/production.log | grep -i error"

# Check database logs
echo "Checking database logs..."
ssh "root@$PRIMARY_HOST" "docker logs gitlab-postgresql 2>&1 | grep -i error | tail -10"

# Check system logs
echo "Checking system logs..."
ssh "root@$PRIMARY_HOST" "tail -20 /var/log/syslog | grep -i error"
```

---

## 3. Monitoring & Alerting

### 3.1 Alert Response Procedures

**Alert:** `PrimaryHostHighCPU`  
**Threshold:** CPU > 80%  
**Action:**
```bash
# 1. Check running processes
ssh "root@$PRIMARY_HOST" "top -bn1 | head -20"

# 2. Check container resource usage
ssh "root@$PRIMARY_HOST" "docker stats --no-stream"

# 3. Identify heavy processes
ssh "root@$PRIMARY_HOST" "ps aux --sort=-pcpu | head -10"

# 4. Check GitLab jobs queue
# This might indicate backlog of CI jobs causing CPU spike

# 5. If sustained, consider:
# - Scale up instance size (GCP)
# - Reduce background worker threads
# - Investigate job queue backlog
```

**Alert:** `DatabaseReplicationLag`  
**Threshold:** Lag > 30 seconds  
**Action:**
```bash
# 1. Check replication status
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c '\x' -c 'SELECT * FROM pg_stat_replication;'"

# 2. Check network connectivity
ssh "root@$PRIMARY_HOST" "ping -c5 $REPLICA_HOST"

# 3. Check REPLICA database status
ssh "root@$REPLICA_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'SELECT now();'"

# 4. If lag persists:
# - Check network bandwidth: iftop, mtr
# - Increase WAL level (temporary)
# - Scale up instance (GCP)

# 5. Force checkpoint on PRIMARY
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'CHECKPOINT;'"
```

**Alert:** `ContainerRestart`  
**Threshold:** Any container restarted unexpectedly  
**Action:**
```bash
# 1. Identify restarted container
ssh "root@$PRIMARY_HOST" "docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -i restart"

# 2. Check container logs
CONTAINER_NAME="name-of-restarted-container"
ssh "root@$PRIMARY_HOST" "docker logs -n 200 $CONTAINER_NAME | tail -50"

# 3. Check restart policy
ssh "root@$PRIMARY_HOST" "docker inspect $CONTAINER_NAME --format '{{json .RestartPolicy}}'"

# 4. Restart if needed
ssh "root@$PRIMARY_HOST" "docker restart $CONTAINER_NAME"

# 5. Monitor for further restarts
```

### 3.2 Prometheus Maintenance

**Daily backup of Prometheus data:**
```bash
# Backup Prometheus database
ssh "root@$PRIMARY_HOST" bash << 'EOF'
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
docker exec prometheus tar -czf /tmp/prometheus-backup-$TIMESTAMP.tar.gz /prometheus/data
docker cp prometheus:/tmp/prometheus-backup-$TIMESTAMP.tar.gz /backups/prometheus/
echo "Prometheus backed up: prometheus-backup-$TIMESTAMP.tar.gz"
EOF
```

---

## 4. Common Troubleshooting

### 4.1 GitLab Unresponsive

**Issue:** GitLab web interface not responding  

```bash
# Step 1: Check if container is running
ssh "root@$PRIMARY_HOST" "docker ps | grep -i gitlab"

# Step 2: Check container logs
ssh "root@$PRIMARY_HOST" "docker logs -n 50 gitlab-main | tail -30"

# Step 3: Check port binding
ssh "root@$PRIMARY_HOST" "netstat -tlnp | grep 8101"

# Step 4: Restart GitLab (if safe)
ssh "root@$PRIMARY_HOST" "docker restart gitlab-main"

# Step 5: Wait for startup (can take 30-60 seconds)
sleep 30
curl -s http://localhost:8101/health_check || echo "Still loading..."

# Step 6: If still down, check system resources
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
echo "Memory: $(free -h | awk '/^Mem:/ {print $2, "total,", $3, "used"}')"
echo "Disk: $(df -h / | awk '/\// {print $2, "total,", $3, "used"}')"
SCRIPT

# Step 7: Check PostgreSQL connection
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'SELECT 1;'"
```

### 4.2 Database Replication Lag Spike

**Issue:** Replication lag suddenly increases  

```bash
# Step 1: Verify replicas connected
ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'SELECT client_addr, state FROM pg_stat_replication;'"

# Step 2: Check network connectivity
ssh "root@$PRIMARY_HOST" "mtr -r -c 100 $REPLICA_HOST | tail -5"

# Step 3: Check REPLICA database size
ssh "root@$REPLICA_HOST" "docker exec gitlab-postgresql psql -U postgres -c 'SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database;'"

# Step 4: Check WAL production rate
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
docker exec gitlab-postgresql psql -U postgres -c 'SELECT NOW() AS time, pg_wal_lsn_diff(pg_current_wal_lsn(), 0) / 1024.0 / 1024.0 AS size_mb;'
SCRIPT

# Step 5: Reduce write load (if possible)
# - Pause CI/CD pipelines
# - Pause backup jobs
# - Reduce API requests

# Step 6: Monitor recovery
# Check lag every 30 seconds for 5 minutes
for i in {1..10}; do
  ssh "root@$PRIMARY_HOST" "docker exec gitlab-postgresql psql -U postgres -t -c 'SELECT replay_lag FROM pg_stat_replication;'" || echo "Error"
  sleep 30
done
```

### 4.3 Parity Gate Failure

**Issue:** PRIMARY and REPLICA configurations diverged  

```bash
# Step 1: Run parity check
bash scripts/ops/check-gitlab-compose-parity.sh

# Step 2: Identify differences
diff <(ssh "root@$PRIMARY_HOST" "md5sum docker-compose.enterprise.yml") \
     <(ssh "root@$REPLICA_HOST" "md5sum docker-compose.enterprise.yml")

# Step 3: Re-sync configuration
# Option A: Restore from git
ssh "root@$REPLICA_HOST" bash << 'SCRIPT'
cd /root/code-server
git fetch origin main
git checkout origin/main -- docker-compose.enterprise.yml
SCRIPT

# Option B: Copy from PRIMARY
ssh "root@$PRIMARY_HOST" "scp docker-compose.enterprise.yml root@$REPLICA_HOST:/root/code-server/"

# Step 4: Re-validate
bash scripts/ops/check-gitlab-compose-parity.sh
```

### 4.4 Disk Space Warning

**Issue:** Disk usage approaching capacity  

```bash
# Step 1: Check disk usage
ssh "root@$PRIMARY_HOST" "du -sh /data/* | sort -h | tail -10"

# Step 2: Identify large directories
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
echo "Database size:"
docker exec gitlab-postgresql du -sh /var/lib/postgresql/data | tail -1
echo "Repository size:"
docker exec gitlab-main du -sh /var/opt/gitlab/git-data | tail -1
echo "Artifacts size:"
docker exec gitlab-main du -sh /var/opt/gitlab/gitlab-rails/shared/artifacts | tail -1
SCRIPT

# Step 3: Clean up old artifacts (if safe)
ssh "root@$PRIMARY_HOST" "docker exec gitlab-main gitlab-rake gitlab:cleanup:admin_verify"

# Step 4: Expand disk (GCP)
# This requires snapshot → resize → reboot

# Step 5: Archive old data
# Consider moving old projects/CI artifacts to cold storage
```

### 4.5 Certificate Expiration Warning

**Issue:** SSL/TLS certificate about to expire  

```bash
# Step 1: Check certificate expiration
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
echo "GitLab cert expiration:"
docker exec gitlab-main openssl x509 -in /etc/gitlab/ssl/gitlab.crt -noout -enddate 2>/dev/null || echo "Internal cert"
SCRIPT

# Step 2: If self-signed, renew
# Option A: Using docker-compose
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
cd /root/code-server
# Remove old cert
rm -f docker-compose.enterprise.yml.backup
docker-compose down
# Regenerate cert in docker-compose.yml
# Redeploy
./scripts/ops/orchestrate-deployment.sh --dry-run
SCRIPT

# Option B: Renew Let's Encrypt
# If using real cert, run renewal script
ssh "root@$PRIMARY_HOST" "certbot renew --force-renewal"
```

---

## 5. Emergency Procedures

### 5.1 Failover to Replica

**Use only if PRIMARY is completely down**

```bash
#!/bin/bash
set -euo pipefail

echo "⚠️  FAILOVER PROCEDURE - USE ONLY IF PRIMARY IS DOWN"
read -p "Are you sure? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  exit 1
fi

REPLICA_HOST="${REPLICA_HOST:-}"
if [ -z "$REPLICA_HOST" ]; then
  echo "❌ REPLICA_HOST not set"
  exit 1
fi

echo "Starting failover to REPLICA..."

# Step 1: Promote REPLICA
echo "Step 1: Promoting REPLICA database..."
ssh "root@$REPLICA_HOST" bash << 'SCRIPT'
docker exec gitlab-postgresql pg_ctl promote -D /var/lib/postgresql/data
SCRIPT

# Step 2: Update VIP (if using)
echo "Step 2: Updating VIP to point to REPLICA..."
# This depends on your VIP setup (Keepalived, etc.)

# Step 3: Update DNS (if using)
echo "Step 3: Update DNS records to point to REPLICA"
echo "Manual step: Update DNS A record for gitlab.example.com to $REPLICA_HOST"

# Step 4: Verify REPLICA is now PRIMARY
echo "Step 4: Verifying REPLICA..."
sleep 30
ssh "root@$REPLICA_HOST" "curl -s http://localhost:8101/health_check"

# Step 5: Notify team
echo ""
echo "✅ Failover complete"
echo "⚠️  REMEMBER:"
echo "  1. Check data integrity"
echo "  2. Notify users"
echo "  3. Plan recovery of original PRIMARY"
echo "  4. Test recovery procedure"
```

### 5.2 Rollback Deployment

**Revert to previous deployment if critical issue found**

```bash
#!/bin/bash
set -euo pipefail

echo "⚠️  ROLLBACK PROCEDURE"
echo ""
echo "Recent deployments:"
git log --oneline -10

read -p "Enter commit to rollback to: " COMMIT
read -p "Are you sure you want to rollback to $COMMIT? (yes/no) " -r

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  exit 1
fi

echo "Rolling back to $COMMIT..."

# Step 1: Backup current state
BACKUP_TAG="rollback-backup-$(date +%Y%m%d-%H%M%S)"
git tag "$BACKUP_TAG"
echo "Backup tag created: $BACKUP_TAG"

# Step 2: Checkout previous commit
git checkout "$COMMIT"

# Step 3: Redeploy
./scripts/ops/orchestrate-deployment.sh --dry-run
read -p "Apply changes? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  git checkout main
  echo "Rollback cancelled"
  exit 0
fi

./scripts/ops/orchestrate-deployment.sh

# Step 4: Verify
sleep 30
curl -s http://localhost:8101/health_check

echo "✅ Rollback complete"
echo "💾 Previous state saved as tag: $BACKUP_TAG"
```

### 5.3 Emergency Database Recovery

**Restore from backup if data corruption suspected**

```bash
#!/bin/bash
set -euo pipefail

echo "⚠️  DATABASE RECOVERY - LAST RESORT ONLY"
read -p "This will restore to previous backup. Continue? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  exit 1
fi

PRIMARY_HOST="${PRIMARY_HOST:-}"
BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
  echo "Available backups:"
  ssh "root@$PRIMARY_HOST" "ls -lah /backups/postgres/ | head -10"
  read -p "Enter backup filename: " BACKUP_FILE
fi

echo "Starting database recovery from: $BACKUP_FILE"

# Stop GitLab
ssh "root@$PRIMARY_HOST" "docker-compose down"

# Restore database
ssh "root@$PRIMARY_HOST" bash << EOF
cd /root/code-server
docker run --rm \\
  -v /data/postgresql:/var/lib/postgresql/data \\
  postgres:13 \\
  pg_restore -U postgres -d gitlabdb < /backups/postgres/$BACKUP_FILE
EOF

# Start GitLab
ssh "root@$PRIMARY_HOST" "docker-compose up -d"

# Verify
sleep 60
curl -s http://localhost:8101/health_check

echo "✅ Database recovery complete"
```

---

## 6. Maintenance Operations

### 6.1 Scheduled Backup

**Run daily (typically 2 AM)**

```bash
#!/bin/bash

BACKUP_DIR="/backups/daily-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

echo "Starting scheduled backup..."

# Backup PostgreSQL
ssh "root@$PRIMARY_HOST" bash << EOF
docker exec gitlab-postgresql pg_dump -U postgres gitlabdb | gzip > $BACKUP_DIR/gitlabdb-$(date +%Y%m%d-%H%M%S).sql.gz
echo "Database backup complete"
EOF

# Backup configuration
ssh "root@$PRIMARY_HOST" bash << EOF
tar -czf $BACKUP_DIR/config-$(date +%Y%m%d-%H%M%S).tar.gz docker-compose.enterprise.yml scripts/ 2>/dev/null || true
echo "Configuration backup complete"
EOF

# Backup Prometheus
ssh "root@$PRIMARY_HOST" bash << EOF
docker exec prometheus tar -czf /tmp/prom-$(date +%Y%m%d-%H%M%S).tar.gz /prometheus/data
docker cp prometheus:/tmp/prom-$(date +%Y%m%d-%H%M%S).tar.gz $BACKUP_DIR/
EOF

echo "✅ Backup complete: $BACKUP_DIR"

# Clean up old backups (keep 30 days)
ssh "root@$PRIMARY_HOST" "find /backups -type d -name 'daily-*' -mtime +30 -exec rm -rf {} \;"
```

### 6.2 Certificate Renewal

**Monthly (if using real certificates)**

```bash
#!/bin/bash

echo "Renewing certificates..."

ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
# If using Let's Encrypt
certbot renew --force-renewal

# Reload GitLab
docker exec gitlab-main gitlab-ctl reconfigure
docker restart gitlab-main
SCRIPT

echo "✅ Certificates renewed"
```

### 6.3 System Updates

**Quarterly or as needed**

```bash
#!/bin/bash
set -euo pipefail

echo "⚠️  SYSTEM UPDATE PROCEDURE"
echo "This will update system packages on both hosts"
read -p "Continue? (yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  exit 1
fi

# Update PRIMARY
echo "Updating PRIMARY..."
ssh "root@$PRIMARY_HOST" bash << 'SCRIPT'
apt-get update
apt-get upgrade -y
apt-get autoremove -y
SCRIPT

# Verify PRIMARY
sleep 30
curl -s http://localhost:8101/health_check

# Update REPLICA
echo "Updating REPLICA..."
ssh "root@$REPLICA_HOST" bash << 'SCRIPT'
apt-get update
apt-get upgrade -y
apt-get autoremove -y
SCRIPT

# Verify REPLICA
sleep 30
ssh "root@$REPLICA_HOST" "curl -s http://localhost:8101/health_check || true"

echo "✅ System updates complete"
```

---

## 7. Incident Response

### 7.1 Incident Response Checklist

**Upon discovery of critical issue:**

- [ ] Declare incident in Slack #incident-response
- [ ] Assemble response team (on-call engineer, manager, SME)
- [ ] Create war room (Zoom/Teams link)
- [ ] Document timeline
- [ ] Assign roles (incident commander, scribe, SME)
- [ ] Begin initial diagnostics
- [ ] Notify affected users
- [ ] Begin status page updates

### 7.2 Runbook for Major Outage

```
T+0: Incident detected
  - Alert fires, on-call engineer notified
  - Incident declared in #incident-response

T+5: Initial response
  - Response team assembles in war room
  - Scribe begins logging all actions
  - Initial diagnostics started

T+15: Triage
  - Determine scope of impact
  - Identify affected services
  - Check for data corruption

T+30: Recovery attempt
  - Execute recovery procedure
  - Continue monitoring

T+60: Escalation (if not resolved)
  - Escalate to senior team
  - Consider failover/rollback
  - Update status page more frequently

Post-incident: RCA & Improvement
  - Schedule RCA meeting (within 24 hours)
  - Document lessons learned
  - Create tickets for improvements
  - Update runbooks
```

### 7.3 Communication Template

```
# Incident Update

**Time:** [timestamp]
**Status:** [Investigating / Working On Fix / Resolved]
**Impact:** [X users affected / [Percentage]% system down]
**Current Action:** [What we're doing]
**ETA to resolution:** [Time estimate]

For updates follow: [Slack channel / Status page URL]
```

---

## 8. Performance Tuning

### 8.1 Monitor Performance Trends

```bash
# Check CPU trend over last 24 hours
curl 'http://localhost:9090/api/v1/query_range?query=rate(cpu[1m])&start=UNIX_TS_24H_AGO&end=now&step=5m'

# Check memory trend
curl 'http://localhost:9090/api/v1/query_range?query=memory_usage&start=UNIX_TS_24H_AGO&end=now&step=5m'

# Check replication lag trend
curl 'http://localhost:9090/api/v1/query_range?query=replication_lag_seconds&start=UNIX_TS_24H_AGO&end=now&step=5m'
```

### 8.2 Optimization Actions

**If CPU > 70% sustained:**
- Check CI/CD job queue
- Consider increasing Puma workers
- Check slow queries (database logs)
- Consider scaling (GCP)

**If memory > 85% sustained:**
- Check container memory limits
- Review Redis memory usage
- Check for memory leaks (GitHub update logs)
- Restart containers (graceful)
- Consider scaling (GCP)

**If disk > 80% used:**
- Archive old projects/CI artifacts
- Clean up temporary files
- Expand disk (GCP only)
- Implement retention policies

---

## Contact Information

**On-Call Engineer:** [Name, Phone, Slack]  
**DevOps Lead:** [Name, Phone, Slack]  
**Operations Manager:** [Name, Phone, Email]  
**Emergency Escalation:** [Process]  

---

**Version:** 1.0  
**Status:** Production-ready  
**Created:** April 30, 2026  
**Last Updated:** [To be filled]

