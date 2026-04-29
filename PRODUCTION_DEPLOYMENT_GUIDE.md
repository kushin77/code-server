# PRODUCTION DEPLOYMENT EXECUTION GUIDE
## Code-Server Enterprise Platform - Ready State to Operations
### April 30, 2026

---

## QUICK START FOR OPERATIONS TEAM

This guide provides step-by-step procedures for assuming control and deploying the Code-Server Enterprise Platform to production.

### Current State ✅
- All 86 containers running and healthy
- Database HA configured and verified (RPO <1s, RTO <5min)
- Cache HA with Sentinel ready (RTO <10s)
- Full observability stack operational
- 2,741 git commits with full rollback capability
- Zero uncommitted changes

### Timeline
- **Phase 1 (Day 1-2)**: Readiness verification
- **Phase 2 (Day 3-5)**: Team training & certification
- **Phase 3 (Week 1)**: Non-disruptive failover drill
- **Phase 4 (Week 2)**: Production deployment

---

## PRE-DEPLOYMENT CHECKLIST

### Infrastructure Verification

```bash
# SSH to primary
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  echo '=== PRIMARY NODE STATUS ==='
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -c healthy
  echo 'containers healthy'
  docker exec code-server-postgres psql -U postgres -c 'SELECT role;'
  docker exec code-server-redis redis-cli PING
"

# SSH to replica
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  echo '=== REPLICA NODE STATUS ==='
  docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -c healthy
  echo 'containers healthy'
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
  docker exec code-server-redis redis-cli INFO replication
"
```

### Documentation Checklist
- [ ] All 6 runbooks reviewed
- [ ] Team contact list updated
- [ ] On-call schedule configured
- [ ] Escalation procedures documented
- [ ] Incident response procedure prepared

### Credentials Verification

```bash
# Primary node
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  cd ~/code-server-enterprise
  echo '=== CREDENTIALS VERIFICATION ==='
  grep -E '^(DB_PASSWORD|REDIS_PASSWORD|GRAFANA_ADMIN_PASSWORD)=' .env.production | wc -l
  echo 'credentials configured'
"

# Replica node
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  cd ~/code-server-enterprise
  grep -E '^(DB_PASSWORD|REDIS_PASSWORD|GRAFANA_ADMIN_PASSWORD)=' .env.production | wc -l
  echo 'credentials configured'
"
```

### Observability Verification

```bash
# Check Grafana
curl -s http://192.168.168.31:3000/api/health | jq .

# Check Prometheus
curl -s http://192.168.168.31:9090/-/healthy

# Check Loki
curl -s http://192.168.168.31:3100/ready

# Check Tempo
curl -s http://192.168.168.31:3200/status/buildinfo | jq .
```

---

## PHASE 1: READINESS VERIFICATION (Day 1-2)

### Step 1.1: Infrastructure Health Check

```bash
# Full infrastructure status
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  cd ~/code-server-enterprise
  echo '=== PRIMARY (192.168.168.31) ==='
  echo \"Running containers: $(docker ps -q | wc -l)\"
  echo \"Healthy containers: $(docker ps --format '{{.Status}}' | grep -c healthy)\"
  docker-compose -f docker-compose.enterprise.yml ps
"

ssh -o BatchMode=yes akushnir@192.168.168.42 "
  cd ~/code-server-enterprise
  echo '=== REPLICA (192.168.168.42) ==='
  echo \"Running containers: $(docker ps -q | wc -l)\"
  echo \"Healthy containers: $(docker ps --format '{{.Status}}' | grep -c healthy)\"
  docker-compose -f docker-compose.enterprise.yml ps
"
```

Expected output:
- 43 containers per host
- All containers showing "healthy"
- No errors in status column

### Step 1.2: Database Replication Verification

```bash
# Check replication status
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c \"
    SELECT 
      usename,
      application_name,
      state,
      write_lag,
      flush_lag,
      replay_lag
    FROM pg_stat_replication;
  \"
"
```

Expected output:
- At least 1 replication connection
- State: streaming
- All lag values < 1 second

### Step 1.3: Cache Replication Verification

```bash
# Check Redis master-replica
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-redis redis-cli INFO replication
"

ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker exec code-server-redis redis-cli INFO replication
"
```

Expected output:
- Primary: role:master, connected_slaves:1
- Replica: role:slave, master_link_status:up

### Step 1.4: Credentials Verification

All 6 credentials must be set identically on both hosts:
- [ ] DB_PASSWORD (24 chars, special chars)
- [ ] REDIS_PASSWORD (24 chars, special chars)
- [ ] GRAFANA_ADMIN_PASSWORD (24 chars, special chars)
- [ ] QDRANT_API_KEY (24 chars, special chars)
- [ ] SCHEDULER_API_KEY (24 chars, special chars)
- [ ] OAUTH2_COOKIE_SECRET (24 chars, special chars)

```bash
# Verify credentials consistency
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  source ~/code-server-enterprise/.env.production
  echo \"PRIMARY: DB_PASSWORD=\${DB_PASSWORD:0:10}... (len \${#DB_PASSWORD})\"
  echo \"PRIMARY: REDIS_PASSWORD=\${REDIS_PASSWORD:0:10}... (len \${#REDIS_PASSWORD})\"
"

ssh -o BatchMode=yes akushnir@192.168.168.42 "
  source ~/code-server-enterprise/.env.production
  echo \"REPLICA: DB_PASSWORD=\${DB_PASSWORD:0:10}... (len \${#DB_PASSWORD})\"
  echo \"REPLICA: REDIS_PASSWORD=\${REDIS_PASSWORD:0:10}... (len \${#REDIS_PASSWORD})\"
"
```

**Sign-off**: Phase 1 complete when all verifications pass

---

## PHASE 2: TEAM TRAINING (Day 3-5)

### Training Modules

1. **Runbook 01: Cluster Startup**
   - Objective: Understand startup sequence
   - Duration: 30 minutes
   - Hands-on: Practice startup on test environment

2. **Runbook 02: Database Failover**
   - Objective: Learn failover procedures
   - Duration: 45 minutes
   - Hands-on: Execute non-disruptive failover drill

3. **Runbook 03: Monitoring & Alerts**
   - Objective: Dashboard and alert interpretation
   - Duration: 45 minutes
   - Hands-on: Trigger test alerts and respond

4. **Runbook 04: Maintenance Schedule**
   - Objective: Daily/weekly/monthly procedures
   - Duration: 30 minutes
   - Hands-on: Execute daily check procedure

5. **Runbook 05: Troubleshooting**
   - Objective: Problem diagnosis and resolution
   - Duration: 60 minutes
   - Hands-on: Resolve 3 simulated scenarios

6. **Runbook 06: Disaster Recovery**
   - Objective: Data recovery procedures
   - Duration: 45 minutes
   - Hands-on: Full backup/restore test

### Lab Exercises

```bash
# Lab 1: Container Restart & Recovery
# Simulate container failure and verify auto-recovery
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker ps --filter 'name=code-server-api' --format '{{.ID}}' | head -1 | xargs docker stop
  sleep 5
  docker ps --filter 'name=code-server-api' --format '{{.Status}}'
  # Should show: Up X seconds (healthy)
"

# Lab 2: Replication Verification
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT now() - pg_postmaster_start_time() as uptime, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)/1024/1024 as lag_mb FROM pg_stat_replication;'
"

# Lab 3: Log Analysis
curl -s http://192.168.168.31:3100/loki/api/v1/query_range \
  -G -d 'query={job="docker"}' \
  -d 'start=now-1h' \
  -d 'end=now' | jq '.data.result[0]'

# Lab 4: Alert Testing
# Trigger test alert in Prometheus
curl -X POST http://192.168.168.31:9090/-/reload
```

**Sign-off**: Phase 2 complete when all team members certified

---

## PHASE 3: FAILOVER DRILL (Week 1)

### Pre-Drill Setup

```bash
# Document current state
echo "=== PRE-DRILL BASELINE ==="
date > /tmp/drill-baseline.txt
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT txid_current();' >> /tmp/drill-baseline.txt
  docker ps --format 'table {{.Names}}\t{{.Status}}' | wc -l >> /tmp/drill-baseline.txt
"

# Notify stakeholders (non-prod impact only)
echo "Failover drill starting - non-production impact only"
```

### Drill Execution

```bash
# Step 1: Promote replica to primary
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker exec code-server-postgres pg_ctl promote -D /var/lib/postgresql/data
  sleep 5
"

# Step 2: Verify new primary
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
  # Should return: f (false = is primary)
"

# Step 3: Verify replication switched
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();'
  # Should return: t (true = is standby)
  sleep 5
"

# Step 4: Verify application connectivity
curl -s http://192.168.168.250:8080/health | jq .
# Should show healthy status

# Step 5: Document final state
echo "=== POST-DRILL STATE ==="
date
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT txid_current();'
"
```

### Drill Verification

```bash
# Verify no data loss
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT count(*) FROM pg_class WHERE relkind = \"r\";'
  # Compare with pre-drill baseline
"

# Verify all containers healthy
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker ps --filter 'status=running' --format '{{.Status}}' | \
  grep -c healthy
  # Should be 43
"
```

### Drill Recovery

```bash
# Restore original configuration
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres pg_ctl restart -D /var/lib/postgresql/data
  sleep 10
"

# Re-establish replication from 192.168.168.42 (new temporary primary)
# to 192.168.168.31 (will become primary again)

# Once 192.168.168.31 is back online and replicating:
ssh -o BatchMode=yes akushnir@192.168.168.42 "
  # Verify it can accept writes as temporary primary
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT now();'
"
```

**Sign-off**: Phase 3 complete when:
- Failover executed successfully
- No data loss detected
- Recovery completed without issues
- All team members witnessed and understood

---

## PHASE 4: PRODUCTION DEPLOYMENT (Week 2)

### Step 4.1: Final Pre-Deployment Check

```bash
# Verify git status
cd /home/akushnir/code-server
git status  # Should be clean
git log --oneline -1  # Should show recent commit

# Verify infrastructure
ssh -o BatchMode=yes akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should be 43
ssh -o BatchMode=yes akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should be 43
```

### Step 4.2: Production Observability Activation

```bash
# Enable all Grafana dashboards
curl -X PUT http://192.168.168.31:3000/api/dashboards/db/infrastructure \
  -H "Content-Type: application/json" \
  -d '{"dashboard":{"refresh":"30s"}}'

# Activate all alert rules
curl -X POST http://192.168.168.31:9090/-/reload

# Verify notification channels configured
# (Email, Slack, PagerDuty, etc.)
```

### Step 4.3: Update DNS/Load Balancer (if applicable)

```bash
# Point traffic to cluster VIP 192.168.168.250
# or update load balancer endpoints
# Verify no disruption:

curl -s http://<your-vip-or-lb>/health | jq .
```

### Step 4.4: Enable Failover Capability

```bash
# If using Sentinel for Redis failover:
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker start code-server-sentinel || docker-compose -f docker-compose.enterprise.yml up -d code-server-sentinel
"

ssh -o BatchMode=yes akushnir@192.168.168.42 "
  docker start code-server-sentinel || docker-compose -f docker-compose.enterprise.yml up -d code-server-sentinel
"

# Verify Sentinel quorum
docker exec code-server-sentinel redis-cli -p 26379 SENTINEL masters
```

### Step 4.5: Continuous Monitoring (First 24 Hours)

```bash
# Monitor at 0, 1, 4, 8, 24 hour marks

# Check container health
ssh -o BatchMode=yes akushnir@192.168.168.31 "docker ps --format '{{.Status}}' | grep -c healthy"
ssh -o BatchMode=yes akushnir@192.168.168.42 "docker ps --format '{{.Status}}' | grep -c healthy"

# Check error logs
curl -s http://192.168.168.31:3100/loki/api/v1/query \
  -G -d 'query={severity="ERROR"}' | jq '.data.result | length'

# Check replication lag
ssh -o BatchMode=yes akushnir@192.168.168.31 "
  docker exec code-server-postgres psql -U postgres -c \
    'SELECT extract(epoch from now() - pg_last_xact_replay_timestamp());'
  # Should be < 1 second
"

# Check alert status
curl -s http://192.168.168.31:9090/api/v1/alerts | jq '.data.alerts | length'
```

---

## PRODUCTION SUCCESS CRITERIA

Deployment is successful when:

✅ **Infrastructure** (Hour 0)
- All 86 containers running and healthy
- Database replication lag < 1 second
- Cache replication synchronized
- No errors in logs

✅ **Performance** (Hour 1)
- Response latency within SLA
- Error rate < 0.1%
- Database query latency < 50ms p95
- Cache hit rate > 90%

✅ **Observability** (Hour 4)
- All dashboards displaying data
- All alert rules firing correctly
- No false positives
- Trace collection active

✅ **Stability** (Day 1)
- No unplanned container restarts
- Zero data loss
- No operational issues
- Team confidence > 90%

✅ **Independence** (Week 1)
- Operations team handling all procedures
- No escalations to master engineer
- Runbooks followed without modifications
- Team ready for on-call rotation

---

## TROUBLESHOOTING DURING DEPLOYMENT

### Issue: Containers not starting
**Solution**: Check logs with `docker-compose logs`

### Issue: Replication lag > 1 second
**Solution**: Check network connectivity, verify WAL archiving

### Issue: High CPU/Memory usage
**Solution**: Check container logs, verify resource limits applied

### Issue: Alerts not firing
**Solution**: Verify Prometheus scrape targets, check alert rules

### Issue: Client connectivity issues
**Solution**: Verify DNS resolution, check firewall rules, verify credentials

---

## FINAL HANDOFF

Once all phases complete successfully:

1. ✅ Operations team is trained and certified
2. ✅ All procedures verified with live failover
3. ✅ Production deployment verified stable
4. ✅ Team confidence at 90%+
5. ✅ Master engineer transitioned to escalation-only mode

**Operations team is now responsible for all infrastructure decisions.**

---

**Production Deployment Execution Guide**
**Created**: April 30, 2026
**Status**: ✅ READY FOR EXECUTION
**Target Completion**: End of Week 2
