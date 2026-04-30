# Rollback & Emergency Procedures

**Status:** Emergency-only procedures  
**Last Updated:** April 30, 2026  
**Audience:** DevOps L2, Operations Manager  

---

## When to Trigger Rollback

### IMMEDIATE ROLLBACK (Don't Wait)
Execute rollback immediately if ANY of these occur:

```
❌ CRITICAL: API completely unresponsive (0% requests passing)
❌ CRITICAL: Database corrupted (corrupted pages in PostgreSQL logs)
❌ CRITICAL: Replication broken and cannot repair (lag > 5 minutes)
❌ CRITICAL: Data loss detected (rows missing, transactions lost)
❌ CRITICAL: Security breach detected (unauthorized access)
❌ CRITICAL: > 50% of containers in failure state
```

### ESCALATE TO L2, THEN ROLLBACK (5-minute grace period)
Proceed to rollback if unable to resolve in 5 minutes:

```
⚠️ HIGH: API error rate > 50% for > 5 minutes
⚠️ HIGH: Response time P95 > 10 seconds for > 5 minutes
⚠️ HIGH: Replication lag > 300 seconds for > 5 minutes
⚠️ HIGH: > 30% of containers in failure state
⚠️ HIGH: Database connection pool exhausted
```

---

## Quick Rollback (Under 10 minutes)

### Rollback to Last Known Good Configuration

**Prerequisites:**
- All team members notified
- L2 engineer confirmed rollback decision
- Backup of current state taken (if time permits)

**Step 1: Stop Current Deployment** (30 seconds)
```bash
ssh ubuntu@192.168.168.31

# Emergency: Stop all containers
docker-compose down
# This takes ~1-2 minutes

# Wait for completion
docker ps | grep code-server
# Expected: Empty output (all stopped)
```

**Step 2: Restore Last Known Good Version** (2-3 minutes)
```bash
# Go to code-server directory
cd /home/ubuntu/code-server

# Check git status
git status

# Revert to last stable commit (May 1 pre-deployment)
git reset --hard HEAD~1
# OR specific commit:
# git reset --hard b2305be7

# Verify revert
git log --oneline -3
```

**Step 3: Restart Services** (3-4 minutes)
```bash
# Rebuild if needed
docker-compose build --no-cache

# Start all services
docker-compose up -d

# Wait for startup (~2 minutes)
sleep 120

# Verify containers are running
docker-compose ps | grep -c Up
# Expected: ≥ 87
```

**Step 4: Verify Rollback Success** (2-3 minutes)
```bash
# Run health checks
bash final-infrastructure-validation.sh

# Expected: All checks passing, Infrastructure READY

# Test API
curl http://localhost:8000/health
# Expected: 200 OK

# Test Database
docker exec code-server-postgres psql -U postgres -c "SELECT 1;"
# Expected: (1 row) with value 1

# Test Replication (if applicable)
docker exec code-server-postgres psql -U postgres \
  -c "SELECT pg_is_in_recovery();" 
# Expected: f (false on primary)
```

**Step 5: Notify Team** (1 minute)
```bash
# Post rollback status to Slack
# Message template:
# "🔴 Rollback completed successfully. Previous version restored.
#  All health checks passing. [Time: MM:SS]
#  Root cause: [brief description]
#  Next steps: [what happens now]"
```

**Expected Total Time:** 10-15 minutes

---

## Full Disaster Recovery Rollback

### If Quick Rollback Fails or Data Needs Restoring

**Prerequisites:**
- Incident commander authorized full rollback
- All critical services notified
- Backup systems verified available
- On-call team standing by for support

**Step 1: Database Restoration from Backup** (15-30 minutes)

```bash
# SSH to primary
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server

# Find most recent backup
ls -la /backups/postgresql/
# Expected: Latest backup_YYYYMMDD_HHMMSS.dump

# Restore from backup
echo "Starting database restore from backup..."
BACKUP_FILE=$(ls -t /backups/postgresql/backup_*.dump | head -1)

# Stop current PostgreSQL
docker-compose stop postgres

# Wait for stop
sleep 30

# Restore database
docker exec code-server-postgres pg_restore \
  --clean \
  --if-exists \
  --verbose \
  --dbname=postgresql://postgres@localhost/postgres \
  "$BACKUP_FILE"

# Wait for restore to complete (may take 5-20 minutes depending on size)
# Expected output: "...restore of [backup] complete"

# Start PostgreSQL
docker-compose start postgres

# Wait for startup
sleep 30

# Verify restore succeeded
docker exec code-server-postgres psql -U postgres -c \
  "SELECT COUNT(*) as tables FROM information_schema.tables;"
# Expected: Non-zero table count
```

**Step 2: Redis Restoration from Snapshot** (5-10 minutes)

```bash
# Find most recent Redis backup
ls -la /backups/redis/
# Expected: Latest dump_YYYYMMDD_HHMMSS.rdb

# Stop Redis
docker-compose stop redis

# Restore RDB file
REDIS_BACKUP=$(ls -t /backups/redis/dump_*.rdb | head -1)
cp "$REDIS_BACKUP" /var/lib/redis/dump.rdb

# Fix permissions (important!)
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo chmod 644 /var/lib/redis/dump.rdb

# Start Redis
docker-compose start redis

# Wait for startup
sleep 10

# Verify restore
docker-compose exec redis redis-cli INFO server
# Expected: Redis server info response
```

**Step 3: Full Container Restart** (10-15 minutes)

```bash
# Restart all services
docker-compose restart

# Wait for all services to stabilize
sleep 120

# Verify all containers are up
docker-compose ps | grep -c Up
# Expected: ≥ 87

# Run full validation
bash final-infrastructure-validation.sh
# Expected: All checks passing
```

**Step 4: Data Validation** (10-15 minutes)

```bash
# Verify no data corruption
docker exec code-server-postgres pg_dump \
  --format=plain \
  --verbose \
  --dbname=postgresql://postgres@localhost/postgres \
  2>&1 | head -100
# Expected: Valid SQL dump output

# Verify application data integrity
docker exec api-server curl http://api-server:8000/api/v1/validate
# Expected: Validation success response

# Check for missing records
docker exec code-server-postgres psql -U postgres -c \
  "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';"
# Expected: All tables present
```

**Expected Total Time:** 45-90 minutes

---

## Partial Rollback (Single Component)

### If Only One Component Failed

#### API Server Rollback Only

```bash
# Stop API
docker-compose stop api-server

# Revert code to previous version
git reset --hard HEAD~1

# Rebuild API image
docker-compose build --no-cache api-server

# Restart API
docker-compose up -d api-server

# Verify
curl http://localhost:8000/health
sleep 10
# Expected: 200 OK
```

#### Database Rollback Only

```bash
# Full database restore from backup (see section above)
# Keep other services running

# Restart dependent services after restore
docker-compose restart api-server redis
```

#### Redis Rollback Only

```bash
# Redis snapshot restore (see section above)
docker-compose stop redis

# Restore RDB
REDIS_BACKUP=$(ls -t /backups/redis/dump_*.rdb | head -1)
cp "$REDIS_BACKUP" /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb

# Restart
docker-compose up -d redis

# Restart dependent services
docker-compose restart api-server
```

---

## Zero-Downtime Failover to Replica

### If Primary (192.168.168.31) Is Irrecoverable

**Prerequisites:**
- Replica is healthy (192.168.168.42)
- Replica has recent replication data
- Database is consistent
- DNS/VIP reconfiguration ready

**Step 1: Replica Promotion** (5 minutes)

```bash
# SSH to replica
ssh ubuntu@192.168.168.42
cd /home/ubuntu/code-server

# Promote replica to primary
docker exec code-server-postgres psql -U postgres -c \
  "SELECT pg_promote();"

# Wait for promotion to complete
sleep 30

# Verify promotion
docker exec code-server-postgres psql -U postgres -c \
  "SELECT pg_is_in_recovery();"
# Expected: f (false) - no longer in recovery
```

**Step 2: Update Configuration** (5-10 minutes)

```bash
# Update primary IP in code to use replica IP
# Edit: docker-compose.yml, config files, etc.
# Change: All references to 192.168.168.31 → 192.168.168.42

# Restart all services with new primary
docker-compose down
docker-compose up -d

# Wait for startup
sleep 120

# Verify connectivity
curl http://localhost:8000/health
# Expected: 200 OK
```

**Step 3: Recovery of Original Primary** (Later, when available)

```bash
# When original primary comes back online:
# SSH to original primary
ssh ubuntu@192.168.168.31

# Make it standby again
cd /home/ubuntu/code-server
bash orchestrate-postgresql-replication-fix.sh
# (This will set it up as replica to new primary on .42)

# Verify standby status
docker exec code-server-postgres psql -U postgres -c \
  "SELECT pg_is_in_recovery();"
# Expected: t (true) - standby mode
```

---

## Communication Template

### Rollback Announcement (Slack #incidents)

```
🔴 ROLLBACK IN PROGRESS

Incident: [Brief description]
Action: Rolling back deployment
Timeline:
  - 14:32 UTC: Issue detected
  - 14:35 UTC: Rollback initiated
  - 14:40 UTC: Services restarting
  - 14:45 UTC: Expected restoration time

Impact:
  - Current: [service/users affected]
  - Expected: Full service restoration in ~15 minutes

Previous Status: All services operational [time]
Next Update: 14:55 UTC

🔗 Incident tracking: [JIRA/GitHub issue link]
```

### Post-Rollback Summary

```
✅ ROLLBACK COMPLETE

Timeline:
  - Issue Detected: [time]
  - Rollback Started: [time]
  - Rollback Completed: [time]
  - Total Duration: [XX minutes]

What Happened:
  [Description of root cause]

What We Did:
  [Steps taken in rollback]

Current Status:
  - API: Operational ✅
  - Database: Operational ✅
  - Monitoring: Operational ✅
  - User Impact: None

Next Steps:
  1. Root cause analysis (1-2 hours)
  2. Detailed findings report
  3. Deployment retry with fixes (tomorrow/later)

Thank you for your patience!
```

---

## Prevention: Lessons from Rollbacks

### Post-Rollback Analysis Template

```markdown
## Rollback Post-Mortem

**Date:** [Date]
**Incident:** [Title]
**Severity:** [Critical/High/Medium]

### Timeline
- 14:32 - Issue detected
- 14:35 - Rollback started
- 14:45 - Rollback complete

### Root Cause
[What went wrong and why]

### Detection
[How was it detected? Could it have been caught earlier?]

### Prevention for Next Time
- [ ] Pre-deployment validation check X
- [ ] Monitoring alert for condition Y
- [ ] Better testing of scenario Z
- [ ] Documentation update for procedure W

### Metrics
- Incident Detection: [X minutes]
- Incident Response: [X minutes]
- Rollback Execution: [X minutes]
- Service Restoration: [X minutes]

### Owner Follow-ups
- DevOps: [Action items]
- QA: [Action items]
- Management: [Action items]
```

---

## Quick Reference: Rollback Commands

```bash
# Emergency stop all services
docker-compose down --volumes

# Force remove all containers
docker container prune -f

# Revert to previous commit
git reset --hard HEAD~1

# Restore database from backup
docker exec code-server-postgres pg_restore \
  --clean --if-exists --verbose \
  --dbname=postgresql://postgres@localhost/postgres \
  /backups/postgresql/backup_*.dump

# Restore Redis
cp /backups/redis/dump_*.rdb /var/lib/redis/dump.rdb

# Full service restart
docker-compose up -d

# Quick health check
curl http://localhost:8000/health

# Full validation
bash final-infrastructure-validation.sh
```

---

## Escalation Decision Tree

```
START: Issue detected

Is API completely unresponsive?
├─ YES → IMMEDIATE ROLLBACK (see Quick Rollback section)
└─ NO → GO TO STEP 2

Is database unreachable or corrupted?
├─ YES → IMMEDIATE ROLLBACK
└─ NO → GO TO STEP 3

Can the issue be fixed in < 5 minutes?
├─ YES → Attempt fix while monitoring closely
│         If not resolved in 5 min → ESCALATE TO L2
└─ NO → GO TO STEP 4

Escalate to L2 engineer
├─ Can L2 fix issue in < 10 minutes?
│   ├─ YES → Continue troubleshooting
│   └─ NO → GO TO STEP 5
└─ L2 Decision: Proceed with rollback?
    ├─ YES → Execute Quick Rollback
    └─ NO → Continue troubleshooting, escalate to manager

Final Decision: Manager confirms rollback or incident mode?
├─ Rollback: Execute appropriate rollback procedure
└─ Incident Mode: Stand up incident response, 24-hour monitoring
```

---

## Contacts for Rollback Authorization

| Role | Name | Slack | Phone | Email |
|------|------|-------|-------|-------|
| DevOps L2 | [Name] | @[slack] | [Phone] | [Email] |
| Operations Manager | [Name] | @[slack] | [Phone] | [Email] |
| VP Engineering | [Name] | @[slack] | [Phone] | [Email] |

---

## Success Criteria After Rollback

### Immediate (30 minutes)
- ✅ All containers running (≥ 87)
- ✅ API responding (200 OK)
- ✅ Database accessible
- ✅ Monitoring operational

### 1 Hour
- ✅ Uptime: 99%+
- ✅ Error rate: < 1%
- ✅ No critical alerts
- ✅ Replication active (< 5s lag)

### 24 Hours
- ✅ Uptime: 99.9%+
- ✅ Error rate: < 0.1%
- ✅ All systems stable
- ✅ Root cause identified

---

**REMEMBER:** Rollback is a last resort. Use only when:
1. Issue cannot be fixed in time
2. User impact is severe
3. Data integrity is at risk
4. Service is significantly degraded

For most issues: Try to fix forward first!

