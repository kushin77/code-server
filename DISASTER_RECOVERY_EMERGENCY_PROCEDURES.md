# Disaster Recovery & Emergency Procedures Manual

**Date:** April 30, 2026  
**Version:** 1.0  
**Audience:** DevOps, Operations, Infrastructure teams  
**Scope:** Production incident response and recovery procedures

---

## Introduction

This manual provides step-by-step procedures for responding to critical incidents and recovering from disasters. All procedures are designed for rapid recovery with minimal downtime.

**Critical Contacts (Keep Handy):**
- DevOps Lead On-Call: [Contact]
- Operations Lead: [Contact]
- CTO: [Contact]
- Infrastructure Manager: [Contact]

---

## Severity Levels & Response Times

| Level | Definition | Response Time | Examples |
|-------|-----------|---------------|----------|
| P1 | System down, no workaround | 5 minutes | Complete service outage, data loss |
| P2 | Significant degradation | 15 minutes | 50% capacity loss, high errors |
| P3 | Minor issues | 1 hour | Single service slow, warnings only |
| P4 | Cosmetic or low-impact | 24 hours | Logging issues, minor UI bugs |

---

## Part 1: Service Recovery Procedures

### Scenario 1: API Service Down

**Problem:** `hermes-integration` container not responding

**Response Time Target:** 5 minutes

**Recovery Steps:**

```bash
# Step 1: Verify the problem (30 seconds)
curl -k https://kushnir.cloud/api/hermes/health
# Expected: Connection refused or timeout

# Step 2: Check service status (1 minute)
docker-compose -f docker-compose.enterprise.yml ps
# Look for: hermes-integration status

# Step 3: Check service logs (2 minutes)
docker logs hermes-integration | tail -50
# Look for: Error messages, startup failures

# Step 4: Restart the service (1 minute)
docker-compose -f docker-compose.enterprise.yml restart hermes-integration

# Step 5: Verify recovery (1 minute)
sleep 10
curl -k https://kushnir.cloud/api/hermes/health
# Expected: {"status": "healthy", "service": "hermes-integration"}

# Step 6: Monitor stability (3 minutes)
./monitor-health.sh 10 300
# Look for: Continuous healthy responses
```

**If Steps 1-6 fail:**

```bash
# Step 7: Check resource constraints (2 minutes)
docker stats --no-stream hermes-integration
# Check: Memory, CPU not maxed out

# Step 8: Rebuild service (3 minutes)
docker-compose -f docker-compose.enterprise.yml down hermes-integration
docker-compose -f docker-compose.enterprise.yml up -d hermes-integration

# Step 9: Verify again (2 minutes)
curl -k https://kushnir.cloud/api/hermes/health

# Step 10: If still failing - ESCALATE to DevOps Lead
# Full logs for diagnosis: docker logs hermes-integration > /tmp/api_logs.txt
```

### Scenario 2: Database Connection Lost

**Problem:** API unable to connect to PostgreSQL database

**Response Time Target:** 10 minutes

**Recovery Steps:**

```bash
# Step 1: Verify database is running (1 minute)
docker ps | grep postgres
# Expected: code-server-postgres is running

# Step 2: Check database logs (2 minutes)
docker logs code-server-postgres | tail -50
# Look for: Connection errors, startup issues

# Step 3: Test database connectivity (2 minutes)
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"
# Expected: 1 (single row output)

# Step 4: Restart database (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart code-server-postgres

# Step 5: Wait for database startup (3 minutes)
sleep 30

# Step 6: Reconnect API (1 minute)
docker-compose -f docker-compose.enterprise.yml restart hermes-integration

# Step 7: Verify connectivity (2 minutes)
curl -k https://kushnir.cloud/api/hermes/health

# Step 8: If still failing:
# Check disk space (database might not have space)
df -h /home
```

### Scenario 3: Appsmith Dashboard Unavailable

**Problem:** https://kushnir.cloud shows error or blank page

**Response Time Target:** 10 minutes

**Recovery Steps:**

```bash
# Step 1: Check if Appsmith container is running (1 minute)
docker ps | grep appsmith

# Step 2: Check Appsmith logs (2 minutes)
docker logs appsmith | tail -100
# Look for: Startup errors, database connection issues

# Step 3: Verify port 8084 is accessible (2 minutes)
curl -i -k http://localhost:8084/
# Expected: HTTP response (may redirect)

# Step 4: Restart Appsmith (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart appsmith

# Step 5: Wait for startup (2 minutes)
sleep 60

# Step 6: Test access (1 minute)
curl -i -k https://kushnir.cloud/

# Step 7: If still failing - check database
# Appsmith depends on PostgreSQL
docker logs code-server-postgres | tail -50
```

### Scenario 4: High CPU Usage

**Problem:** Server CPU > 85%, services sluggish

**Response Time Target:** 15 minutes

**Recovery Steps:**

```bash
# Step 1: Identify high CPU process (1 minute)
docker stats --no-stream --format "{{.Container}}\t{{.CPUPerc}}" | sort -k2 -rn

# Step 2: Check logs of high CPU container (2 minutes)
docker logs <high-cpu-container> | tail -50
# Look for: Runaway processes, infinite loops

# Step 3: If database is high CPU (3 minutes)
docker exec code-server-postgres pg_stat_statements
# Look for: Slow queries

# Step 4: Optimize queries (5 minutes)
docker exec code-server-postgres vacuumdb -U purebliss_user purebliss_db
docker exec code-server-postgres analyzedb -U purebliss_user purebliss_db

# Step 5: Restart affected service (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart <service>

# Step 6: Verify CPU normalized (2 minutes)
docker stats --no-stream
# Check: CPU now < 60%

# Step 7: Run optimization if needed
./optimize-performance.sh optimize
```

### Scenario 5: High Memory Usage

**Problem:** Memory > 90%, services getting killed

**Response Time Target:** 10 minutes

**Recovery Steps:**

```bash
# Step 1: Check memory usage (1 minute)
docker stats --no-stream --format "{{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Step 2: Identify memory hog (1 minute)
docker stats --no-stream | sort -k4 -rn | head -5

# Step 3: Clear cache (2 minutes)
docker exec code-server-redis redis-cli FLUSHALL
# Or: docker exec code-server-redis redis-cli MEMORY PURGE

# Step 4: Restart high-memory service (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart <service>

# Step 5: Monitor memory (2 minutes)
docker stats --no-stream
# Check: Memory now < 70%

# Step 6: If memory issue persists:
# Check for memory leaks
docker logs <service> | grep -i "memory\|gc\|leak"

# Step 7: Long-term: Plan service optimization or resource upgrade
```

---

## Part 2: Data Recovery Procedures

### Scenario 6: Database Corruption

**Problem:** Database unable to start or data appears corrupted

**Response Time Target:** 30 minutes

**Recovery Steps:**

```bash
# PRIORITY 1: DO NOT RESTART DATABASE MULTIPLE TIMES
# Each restart attempt may cause more corruption

# Step 1: Create immediate backup (2 minutes)
docker exec code-server-postgres pg_dump -U purebliss_user purebliss_db > /tmp/backup_corrupted.sql 2>&1 || true

# Step 2: Check database integrity (5 minutes)
docker exec code-server-postgres pg_check | tee /tmp/db_check.log

# Step 3: Attempt emergency repair (5 minutes)
docker-compose -f docker-compose.enterprise.yml stop code-server-postgres

# Check if repair is possible (create fresh database)
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres

sleep 30

# Step 4: Test basic connectivity (2 minutes)
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT count(*) FROM information_schema.tables;"

# Step 5: If database recovered
# Verify data integrity
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "PRAGMA integrity_check;"

# Step 6: If database still broken - RESTORE FROM BACKUP
./backup-recovery.sh restore <most-recent-backup>

# Step 7: After restore - verify
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"
```

### Scenario 7: Lost Data / Accidental Deletion

**Problem:** Critical data was deleted accidentally

**Response Time Target:** 15 minutes

**Recovery Steps:**

```bash
# Step 1: STOP all services immediately (30 seconds)
# Prevent further changes
docker-compose -f docker-compose.enterprise.yml down

# Step 2: Locate most recent backup (2 minutes)
./backup-recovery.sh list
# Choose: Most recent backup before deletion

# Step 3: Restore from backup (5 minutes)
./backup-recovery.sh restore <backup-id>
# This will:
# - Stop all services
# - Restore database from backup
# - Restore volume data
# - Restart services

# Step 4: Verify restoration (3 minutes)
curl -k https://kushnir.cloud/api/hermes/health
# Expected: Healthy response

# Step 5: Verify data (3 minutes)
# Manually verify the restored data looks correct
# Check: Database records, file contents

# Step 6: Notify team (1 minute)
# Data restored from backup: [timestamp]
# Lost data: [describe what was lost]
# Recovery time: [measure]
```

### Scenario 8: Disk Full

**Problem:** Disk space 100%, services unable to write

**Response Time Target:** 20 minutes

**Recovery Steps:**

```bash
# Step 1: Check what's using disk (2 minutes)
du -sh /* | sort -h | tail -10
# Find largest directories

# Step 2: Check Docker (2 minutes)
docker system df
# This shows Docker disk usage

# Step 3: Emergency cleanup (5 minutes)
# Remove old logs
rm -rf /home/akushnir/code-server/deployment-reports/*.text

# Remove old backups (keep most recent 2)
ls -lt backups/ | tail -n +3 | awk '{print $NF}' | xargs rm -rf

# Archive old monitoring data
tar -czf monitoring_archive_$(date +%Y%m%d).tar.gz monitoring-logs/
rm -rf monitoring-logs/*.log

# Step 4: Clean Docker (3 minutes)
docker system prune -a  # Warning: removes unused images
docker volume prune      # Remove unused volumes

# Step 5: Verify free space (1 minute)
df -h /home

# Step 6: Restart services if needed (2 minutes)
docker-compose -f docker-compose.enterprise.yml up -d

# Step 7: Long-term action: Plan storage expansion
```

---

## Part 3: Network & External Connectivity Recovery

### Scenario 9: DNS Resolution Broken

**Problem:** kushnir.cloud does not resolve

**Response Time Target:** 10 minutes

**Recovery Steps:**

```bash
# Step 1: Test DNS from server (1 minute)
nslookup kushnir.cloud
# Should return: 173.77.179.148

# Step 2: If not resolving:
# Check /etc/resolv.conf
cat /etc/resolv.conf
# Should have nameserver entries (8.8.8.8, 1.1.1.1, etc.)

# Step 3: Restart networking (1 minute)
sudo systemctl restart systemd-resolved

# Step 4: Test again (1 minute)
nslookup kushnir.cloud

# Step 5: If still not working:
# Update /etc/resolv.conf manually
sudo nano /etc/resolv.conf
# Add: nameserver 8.8.8.8
# Add: nameserver 1.1.1.1

# Step 6: Test external resolution (2 minutes)
curl -i https://kushnir.cloud/

# Step 7: If DNS provider issue:
# Contact domain registrar
# Verify DNS records pointing to: 173.77.179.148
```

### Scenario 10: TLS Certificate Expired

**Problem:** Browser shows SSL certificate error, connections refused

**Response Time Target:** 30 minutes

**Recovery Steps:**

```bash
# Step 1: Check certificate expiration (1 minute)
echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "notAfter"
# Shows: notAfter=Dec 30 12:00:00 2024 GMT (if expired)

# Step 2: If not yet expired but close (7 days):
# Renew early to prevent issues
sudo certbot renew --force-renewal

# Step 3: If expired - EMERGENCY RENEWAL (10 minutes)
sudo certbot certonly --standalone -d kushnir.cloud --agree-tos

# Step 4: Update nginx config (5 minutes)
sudo nano /home/akushnir/code-server/nginx.conf
# Update certificate paths to new location

# Step 5: Restart nginx (1 minute)
docker exec nginx-reverse-proxy nginx -s reload

# Step 6: Verify certificate (2 minutes)
echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "notAfter"

# Step 7: If still broken:
# Use temporary self-signed cert as emergency measure
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/server.key -out /tmp/server.crt

# Update nginx to use /tmp/server.key and /tmp/server.crt
# Restart nginx
# Users will see browser warning but can access the system
```

### Scenario 11: Port 443 Blocked / Not Responding

**Problem:** External users cannot reach https://kushnir.cloud

**Response Time Target:** 15 minutes

**Recovery Steps:**

```bash
# Step 1: Test locally (1 minute)
curl -i https://localhost/
# Expected: HTTP response (may be 301 redirect)

# Step 2: Test on port 8080 (1 minute)
curl -i http://localhost:8080/
# Expected: HTTP response from Appsmith

# Step 3: If local works but external doesn't:
# Check firewall rules on server
sudo iptables -L -n | grep 443
# Should show: ACCEPT rules for port 443

# Step 4: Check if nginx is listening (1 minute)
netstat -tlnp | grep 443
# Should show: nginx listening on 443

# Step 5: If not listening:
docker ps | grep nginx
# If not running: restart it

# Step 6: Restart nginx (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart nginx-reverse-proxy

# Step 7: Test external access (2 minutes)
# From external machine:
curl -i https://kushnir.cloud/

# Step 8: If firewall blocking:
# Check with infrastructure team
# May need to add firewall rule: allow 173.77.179.148 port 443
```

---

## Part 4: Complete System Failure & Recovery

### Scenario 12: Primary Host Complete Failure

**Problem:** Primary server 192.168.168.31 down, unresponsive

**Response Time Target:** 30 minutes to failover

**Recovery Steps:**

```bash
# Step 1: Verify primary is truly down (2 minutes)
ping 192.168.168.31
# No response = server down

ssh akushnir@192.168.168.31 'echo test'
# Connection refused = server down

# Step 2: FAILOVER TO SECONDARY (5 minutes)
# Secondary host 192.168.168.42 should already have standby copy

# Step 3: Update DNS to point to secondary (5 minutes)
# Option A: Update DNS provider
#   Change: kushnir.cloud A record → 192.168.168.42
# Option B: Temporary direct IP access
#   Users access: https://192.168.168.42 directly (browser warning)

# Step 4: Verify secondary is operational (5 minutes)
ssh akushnir@192.168.168.42
docker-compose -f docker-compose.enterprise.yml ps
# Should show: 51 containers running from standby

# Step 5: Promote secondary to primary (5 minutes)
# Stop replication on secondary
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db \
  -c "SELECT pg_promote();"

# Step 6: Restart services on secondary (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart

# Step 7: Verify secondary is now operational (3 minutes)
curl -k https://192.168.168.42/api/hermes/health

# Step 8: Once primary is recovered:
# Reconfigure as secondary and point DNS back to primary
# See: "Recovering Primary Server" procedures
```

### Scenario 13: Recovering Primary Server After Complete Failure

**Problem:** Primary server is now recovered and back online

**Response Time Target:** 30 minutes to restore primary + 15 minutes sync

**Recovery Steps:**

```bash
# Step 1: Verify primary is operational (2 minutes)
ping 192.168.168.31
# Should respond

# Step 2: SSH to primary and check status (2 minutes)
ssh akushnir@192.168.168.31
docker-compose -f docker-compose.enterprise.yml ps
# May show stopped containers

# Step 3: Start services on primary (2 minutes)
docker-compose -f docker-compose.enterprise.yml up -d

# Step 4: Wait for startup (2 minutes)
sleep 120

# Step 5: Check database on primary (2 minutes)
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT 1;"

# Step 6: Setup replication from secondary to primary (10 minutes)
# On primary:
docker exec code-server-postgres sudo -u postgres pg_basebackup \
  -h 192.168.168.42 -U replica_user -D /var/lib/postgresql/data \
  -Fp -Xs -P -R

# Step 7: Restart primary database (2 minutes)
docker-compose -f docker-compose.enterprise.yml restart code-server-postgres

# Step 8: Verify replication (5 minutes)
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db \
  -c "SELECT * FROM pg_stat_replication;"

# Step 9: Failback to primary (5 minutes)
# Update DNS: kushnir.cloud → 192.168.168.31
# Restart secondary: docker-compose restart on secondary

# Step 10: Verify primary is primary (3 minutes)
curl -k https://kushnir.cloud/api/hermes/health
# Should return healthy response
```

---

## Part 5: Manual Backup Restore

### Scenario 14: Manual Full System Restore

**Problem:** Need to restore entire system from backup

**Response Time Target:** 30 minutes

**Procedure:**

```bash
# Step 1: List available backups (1 minute)
./backup-recovery.sh list

# Step 2: Choose backup to restore (1 minute)
# Newest backup is usually best
# Unless you need to restore to specific point in time

# Step 3: Stop all services (1 minute)
docker-compose -f docker-compose.enterprise.yml down

# Step 4: Restore from backup (10 minutes)
./backup-recovery.sh restore backup_20260430_000000
# This will restore:
# - Database
# - Volumes
# - Configurations

# Step 5: Start services (2 minutes)
docker-compose -f docker-compose.enterprise.yml up -d

# Step 6: Wait for startup (3 minutes)
sleep 180

# Step 7: Verify all services healthy (5 minutes)
docker-compose -f docker-compose.enterprise.yml ps
# Expected: All 5 services "Up (healthy)"

# Step 8: Verify data (3 minutes)
curl -k https://kushnir.cloud/api/hermes/health

# Step 9: Verify database
docker exec code-server-postgres psql -U purebliss_user -d purebliss_db -c "SELECT COUNT(*) FROM information_schema.tables;"
```

---

## Communication During Incidents

### External Communications

**Twitter/Status Page:**
- At T+5 min: "We're investigating an issue affecting service. Updates every 15 minutes."
- At T+15 min: "Root cause identified. Working on fix."
- At T+25 min: "Service restored. Verifying stability."
- At T+30 min: "Service fully operational. Incident report to follow."

**Customer Email (if applicable):**
- Subject: "Service Incident - [Timestamp] - [Resolution Status]"
- Include: What happened, how long it lasted, what was affected, what we're doing

### Internal Communications

**Slack:**
- Create incident channel: #incident-2024-04-30
- Post updates every 5 minutes during crisis
- Post resolution update
- Post post-mortem link

**Email to Leadership:**
- Incident summary: What, when, duration
- Impact: Services affected, users impacted
- Root cause: Why it happened
- Resolution: What we did to fix it
- Prevention: What we'll do to prevent recurrence

---

## Post-Incident Activities

### Immediate (Within 1 hour):

1. **Verify Stability:** Run full monitoring for 1 hour
2. **Notify Stakeholders:** Send update email
3. **Document:** Log incident in tracking system
4. **Backup:** Create backup immediately after incident

### Follow-up (Within 24 hours):

1. **Root Cause Analysis:** Determine why incident occurred
2. **Timeline:** Document exact sequence of events
3. **Impact Assessment:** Quantify impact (downtime, affected users)
4. **Remediation Plan:** How to prevent similar incidents
5. **Post-Mortem:** Share learnings with team

### Prevention (Within 1 week):

1. **Implement Fixes:** Apply remediation items
2. **Test Fixes:** Verify incidents won't recur
3. **Documentation Update:** Update procedures based on learnings
4. **Team Training:** Brief team on incident and lessons learned

---

## Quick Reference Commands

```bash
# Check all services
docker-compose -f docker-compose.enterprise.yml ps

# View specific service logs
docker logs <service-name> | tail -50

# Restart specific service
docker-compose -f docker-compose.enterprise.yml restart <service-name>

# Restart all services
docker-compose -f docker-compose.enterprise.yml restart

# Check resource usage
docker stats --no-stream

# Create backup
./backup-recovery.sh backup

# Restore from backup
./backup-recovery.sh restore <backup-id>

# Monitor health
./monitor-health.sh 10 300

# Validate deployment
./validate-deployment.sh

# Optimize performance
./optimize-performance.sh optimize

# SSH to secondary
ssh akushnir@192.168.168.42

# Emergency stop all services
docker-compose -f docker-compose.enterprise.yml down
```

---

## Prevention Checklist

- [ ] Daily backups automated and verified
- [ ] Monitoring active 24/7
- [ ] Alert escalation procedures documented
- [ ] Team trained on incident response
- [ ] Disaster recovery tested monthly
- [ ] Capacity planning reviewed quarterly
- [ ] Security hardening up to date
- [ ] HA/replica failover tested
- [ ] Communication procedures established
- [ ] Post-mortem procedures in place

---

**This manual ensures rapid incident response and minimal service disruption. All team members should be familiar with these procedures.**
