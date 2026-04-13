# Phases 15-18: Operations Runbook – Daily Procedures & Emergency Response

**Status**: ✅ **PRODUCTION OPERATIONAL**  
**Maintenance Window**: Sundays 2 AM UTC (1 hour)  
**On-Call**: 24/7 SRE coverage  
**Escalation**: Via PagerDuty (if configured)

---

## Table of Contents
1. Daily Operations Checklist
2. Monitoring & Alert Response
3. Incident Response Procedures  
4. Backup & Recovery Procedures
5. Capacity Planning & Scaling
6. Common Issues & Quick Fixes

---

## Daily Operations Checklist

Execute every 8 hours (morning, afternoon, evening shift). ~15 minutes per checklist.

### Hour 0: System Health Check
```bash
# 1. Verify all services running
docker ps | grep -E "(code-server|postgres|redis|prometheus|grafana|kong|jaeger|linkerd)" | wc -l
# Expected: 12+ services

# 2. Check disk usage  
df -h / | awk 'NR==2 {print $5}'
# Expected: <80% used

# 3. Check memory usage
free -h | awk 'NR==2 {print $3, "/", $2}'
# Expected: <80% used

# 4. Verify database connections
docker exec postgres-db psql -U postgres -c "SELECT datname, usename, count(*) FROM pg_stat_activity GROUP BY datname, usename;"
# Expected: Normal connection counts (<100)

# 5. Check Redis memory
docker exec redis-cache redis-cli info memory | grep used_memory_human
# Expected: <70% of 2GB (< 1.4GB)

# 6. Monitoring connectivity
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3000/api/health
# Expected: Both return 200

# Log results
echo "$(date): All systems operational" >> /var/log/daily-health.log
```

### Hour 1-7: Continuous Monitoring
Monitor dashboards throughout the shift:

**Phase 15 Metrics**:
- p99 latency target: <100ms (alert if >150ms)
- Error rate target: <0.1% (alert if >0.2%)
- Cache hit ratio target: >80% (warning if <70%)

**Phase 16 Metrics**:
- Developer uptime: >99.5% (alert if <99%)
- Deployment success rate: >95% (alert if <90%)

**Phase 17 Metrics**:
- Kong request latency p99: <200ms (alert if >300ms)
- Jaeger trace completion: >95% (warning if <90%)
- Linkerd mTLS success: 100% (alert if <99%)

**Phase 18 Metrics**:
- Multi-region latency: All <250ms (alert if any >300ms)
- Replication lag: <100ms all regions (alert if any >500ms)
- Regional availability: All 100% (alert if any <99%)

### Hour 8: End-of-Shift Report
```bash
# Generate metrics snapshot
bash scripts/phase-15-extended-load-test.sh report

# Check for any warnings
docker logs --since 8h phase-15-orchestrator | grep -i warn
docker logs --since 8h phase-16-orchestrator | grep -i warn
docker logs --since 8h phase-17-kong | grep -i warn
docker logs --since 8h phase-18-ha | grep -i warn

# Document shift summary
cat >> /var/log/shift-summary.log << EOF
$(date)
- All systems operational
- No critical alerts
- Metrics: [INSERT METRICS HERE]
- Actions taken: [IF ANY]
EOF
```

---

## Alert Response Procedures

### HIGH ALERT: Region Unhealthy (Phase 18)
**Trigger**: Any region failing health checks for >1 minute  
**Action Timeline**:
- T+0s: Alert fires
- T+30s: Oncall acknowledges
- T+1min: Begin diagnosis

**Response Steps**:
```bash
# 1. Acknowledge alert in PagerDuty (if configured)
pagerduty ack --incident [ID]

# 2. Check which region failed
docker logs phase-18-ha | grep -i "health check failed" | tail -5

# 3. Verify region status manually
bash scripts/phase-18-disaster-recovery.sh health | grep FAIL
# Output example: "US-West: FAILED (PostgreSQL connection timeout)"

# 4. Attempt auto-recovery
# Most failures recover automatically within 1-2 minutes
sleep 120
bash scripts/phase-18-disaster-recovery.sh health | grep US-West
# If still down, proceed to manual intervention

# 5. Manual intervention (if auto-recovery failed)
# Example: PostgreSQL connection timeout on US-West
docker exec postgres-replica-west supervisorctl status
# If crashed, restart:
docker exec postgres-replica-west supervisorctl restart postgres

# 6. Verify recovery
bash scripts/phase-18-disaster-recovery.sh health
# Expected: All regions HEALTHY

# 7. Confirm DNS failover working (if region was primary)
# If US-East failed and switched to US-West:
nslookup api.example.com
# Expected: Resolves to US-West IP (10.2.0.1)

# 8. Document incident
cat >> /var/log/incidents.log << EOF
$(date)
Region Failure: US-East database timeout
Duration: 5 minutes
Resolution: Restart PostgreSQL service
Status: ✅ RESOLVED
EOF
```

**Success Criteria**:
- ✅ Region recovered OR traffic switched to standby
- ✅ No data loss
- ✅ Users continue operating
- ✅ Incident logged

### HIGH ALERT: Replication Lag >1 Minute (Phase 18)
**Trigger**: Database replication lag exceeds 1 minute on any replica  
**Risk**: Data loss risk if primary fails

**Response Steps**:
```bash
# 1. Check replication lag in real-time
docker exec postgres-db psql -U postgres -c \
  "SELECT client_addr, (pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))::int / 1024 / 1024 as lag_mb, state FROM pg_stat_replication;"

# Expected output (example):
#   client_addr |  lag_mb  |  state
# ─────────────┼──────────┼──────────
#  10.1.1.5    |    2     | streaming  ← US-West
#  10.1.2.5    |   15     | streaming  ← EU-West (HIGH!)

# 2. Check network connectivity between regions
docker exec postgres-db ping -c 1 10.1.2.5
# Expected: <50ms latency
# If >100ms, network issue (contact network team)

# 3. Check PostgreSQL parameters
docker exec postgres-db psql -U postgres -c "SHOW wal_level;"
# Expected: replica (not minimal)

# 4. Check replica is not lagging due to long-running query
docker exec postgres-replica-eu \
  psql -U postgres -c "SELECT pid, usename, state, query FROM pg_stat_activity WHERE state != 'idle';"

# 5. If lag is due to high write load:
#    a) Check if write load is temporary (expected during updates)
#    b) If sustained, may need database scaling → Escalate to DB team

# 6. Monitor lag until it recovers
watch -n 10 'docker exec postgres-db psql -U postgres -c "SELECT (pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))::int / 1024 / 1024 as lag_mb;"'

# Expected: Lag should decrease over next 5-10 minutes
# Success: All replicas <100ms lag

# 7. If lag does NOT improve, trigger failover
# WARNING: Only execute if replication cannot be recovered
bash scripts/phase-18-disaster-recovery.sh failover --force
# This switches to warm standby and may result in minor data loss
```

**Success Criteria**:
- ✅ Replication lag <100ms on all replicas
- ✅ No immediate risk of data loss
- ✅ No failover triggered

### MEDIUM ALERT: p99 Latency >150ms (Phase 15-17)
**Trigger**: Application response time exceeds 150ms for >5 minutes  
**Impact**: Degraded user experience

**Response Steps**:
```bash
# 1. Check which component is slow
docker exec prometheus curl -s 'http://localhost:9090/api/v1/query?query=rate(http_request_duration_seconds_bucket%5B1m%5D)' | jq '.data.result[] | select(.value[1] > "0.15") | .metric.handler'

# Example output:
#  "api/users"      ← Slow
#  "api/projects"   ← Slow

# 2. Check application logs for errors
docker logs code-server --since 5m | grep -i error
docker logs kong --since 5m | grep -i error

# 3. Check system resources (CPU, Memory, IO)
docker stats --no-stream | head -10
# Expected: CPU <80%, Memory <80%

# 4. If resources normal, check cache hit ratio
docker exec prometheus curl -s 'http://localhost:9090/api/v1/query?query=redis_keyspace_hits_total%2F(redis_keyspace_hits_total%2Bredis_keyspace_misses_total)' | jq '.data.result[0].value[1]'
# Expected: >0.8 (80% hit ratio)
# If <0.7, possible cache issue

# 5. If cache is issue:
#    - Check Redis is running: docker ps | grep redis
#    - Check Redis memory: docker exec redis-cache redis-cli info memory
#    - Clear least-used cache: docker exec redis-cache redis-cli EVAL "return redis.call('DEL', unpack(redis.call('KEYS', '*')))" 0

# 6. If resources are bottleneck:
#    - Scale application: docker-compose up -d --scale code-server=2
#    - This adds second container to load balance

# 7. Monitor latency recovery
watch -n 5 'curl -s http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket%5B1m%5D))' | jq '.data.result[0].value[1]'
# Expected: Returns to <100ms within 5-10 minutes
```

**Success Criteria**:
- ✅ p99 latency <120ms
- ✅ No errors in logs
- ✅ Resources <80% utilized

### MEDIUM ALERT: Cache Hit Ratio <70% (Phase 15)
**Trigger**: Redis cache effectiveness dropping  
**Impact**: Increased database load, slower responses

**Response Steps**:
```bash
# 1. Check what's not being cached
docker exec redis-cache redis-cli --scan --pattern "*" | head -20
docker exec redis-cache redis-cli info stats
# Check: keyspace_hits vs keyspace_misses ratio

# 2. Check if cache was recently flushed
docker logs redis-cache --since 30m | grep -i flush

# 3. If cache was manually flushed:
#    - Restart the service to rebuild cache:
#    docker restart code-server
#    - Monitor cache size growing back:
#    watch -n 30 'docker exec redis-cache redis-cli dbsize'

# 4. If cache ratio is consistently low:
#    - May indicate inefficient query patterns
#    - Check with development team for cache invalidation issues
#    - Review: PHASE-15-QUICK-REFERENCE.md (cache optimization section)

# 5. Increase Redis memory if needed
# Current limit: 2GB (edit docker-compose-phase-15.yml)
# Change: "maxmemory": "2gb" → "4gb"
# Restart: docker-compose restart redis-cache
```

**Success Criteria**:
- ✅ Cache hit ratio >80%
- ✅ No repeated cache flushes

### LOW ALERT: Backup Delayed >1 Hour (Phase 18)
**Trigger**: Scheduled backup did not complete on time  
**Impact**: Recovery window extending beyond SLA

**Response Steps**:
```bash
# 1. Check if backup is still running
ps aux | grep backup | grep -v grep

# 2. Check backup logs
docker logs backup-orchestrator --since 2h | tail -20

# 3. If backup is hung (running >2 hours):
#    - Check disk space
df -h /backups
#    - If full, delete old backups:
rm /backups/2026-04-10/*
#    - Kill stuck backup:
pkill -f "pg_basebackup"
#    - Restart backup service:
docker restart backup-orchestrator

# 4. Verify backup completes within 1 hour
watch -n 10 'ls -lh /backups/2026-04-13/ | tail -5'
# Expected: New backup files appearing, size growing

# 5. When backup completes, verify:
docker exec backup-orchestrator /bin/sh -c "tar -tzf /backups/2026-04-13/database.tar.gz | head -5"
# Expected: Backup is valid tar file
```

**Success Criteria**:
- ✅ Backup completed
- ✅ Backup file valid and >100MB
- ✅ Backup <2 hours duration

---

## Emergency Procedures

### CRITICAL: Primary Region Complete Failure (Phase 18)

**Scenario**: US-East (primary) completely down (all services crashed, network down, or data corruption)

**Action Timeline**: 
- T+0m: Alert fires (region unhealthy)
- T+1m: Automatic failover starts
- T+5m: Failover complete, US-West now primary
- T+30m: EU-West promoted to warm standby
- T+2h: Investigate and begin recovery

**Automated Response** (system performs automatically):
```
Phase 18 health monitoring → Detects US-East down
                           ↓
                    Triggers DNS failover
                           ↓
                    Route 53/Cloudflare switches
                    api.example.com → US-West (10.2.0.1)
                           ↓
                    All new connections → US-West
                    Existing connections → Reconnect to US-West
                           ↓
                    Users experience 30-60s interruption
                    (connections timeout and reconnect)
```

**Manual Verification Steps**:
```bash
# 1. Confirm DNS switched
nslookup api.example.com
# Expected: 10.2.0.1 (US-West IP), not 10.1.0.1 (US-East)

# 2. Verify US-West is handling traffic
docker logs phase-18-ha | grep "traffic.*us-west"
# Expected: "Traffic switched to us-west at [TIME]"

# 3. Check that US-West replicated latest data before failure
docker exec postgres-west psql -U postgres -c "SELECT MAX(created_at) FROM users;"
# Compare to US-East backup timestamp
# Expected: Timestamps match (zero data loss)

# 4. Promote EU-West to warm standby
bash scripts/phase-18-disaster-recovery.sh failover setup-secondary-eu

# 5. Begin US-East investigation
#    - Check application logs for crash
#    - Check system logs for hardware errors
#    - Check database logs for corruption
#    - If corrupt, restore from backup:
bash scripts/phase-18-backup-replication.sh restore --location=us-east --time=t-30m

# 6. When US-East recovered:
#    - Apply pending replication from US-West
#    - Validate data consistency
#    - Promote back to primary (if desired)
bash scripts/phase-18-disaster-recovery.sh failover setup-primary-east
```

**Recovery Timeline**:
- 0-1m: Failover automatic
- 1-5m: Verification
- 5-30m: EU-West promotion
- 30m-2h: US-East investigation
- 2-4h: Data restore (if needed)
- **Total RTO: <5 minutes** ✅

### CRITICAL: Data Corruption Detected (Phase 18)

**Scenario**: Database integrity check fails, possible corruption detected

**Response**:
```bash
# 1. IMMEDIATELY stop writes to avoid spreading corruption
# WARNING: This will interrupt service, but prevents data loss
bash scripts/phase-18-disaster-recovery.sh failover pause-writes

# 2. Run data integrity check
docker exec postgres-db psql -U postgres -c "REINDEX DATABASE postgres;"

# 3. Assess extent of corruption
docker exec postgres-db psql -U postgres -c "\dt" | wc -l
# Verify all tables present
docker exec postgres-db psql -U postgres -c "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM projects;"

# 4. If corruption severe:
#    - Restore from clean backup
bash scripts/phase-18-backup-replication.sh restore --location=s3://backups/t-2h
#    - This restores to 2 hours ago (some data loss but less than corruption)

# 5. Verify restoration
docker exec postgres-db psql -U postgres -c "SELECT COUNT(*) FROM users;" | head -1
# Compare to expected count before corruption

# 6. Resume writes
bash scripts/phase-18-disaster-recovery.sh failover resume-writes

# 7. Document incident
# Record: Time detected, extent, cause, resolution time
```

**Recovery Timeline**:
- 0-5m: Pause writes, prevent spread
- 5-10m: Data integrity check
- 10-30m: Restore from backup (if needed)
- 30-45m: Verify and resume
- **Total RTO: <1 hour** (with data loss)

---

## Backup & Recovery Procedures

### Daily Backup Verification
```bash
# Verify backup from this morning completed
ls -lh /backups/$(date +%Y-%m-%d)/database.tar.gz
# Expected: File exists, >500MB

# Verify S3 backup uploaded
aws s3 ls s3://backups/$(date +%Y-%m-%d)/ | grep database
# Expected: Shows uploaded file with timestamp

# Check backup age
stat /backups/$(date +%Y-%m-%d)/database.tar.gz | grep Modify
# Expected: Timestamp from 2-3 hours ago (morning backup)
```

### Test Restore Procedure (Monthly)
```bash
# Once per month, test restoring from backup
# Execute on staging environment ONLY, not production

# 1. Download latest backup
aws s3 cp s3://backups/$(date +%Y-%m-%d)/database.tar.gz /tmp/test-restore.tar.gz

# 2. Extract and validate
tar -tzf /tmp/test-restore.tar.gz | head -10
# Expected: Valid tar file, contains database files

# 3. Restore to test database
docker exec postgres-test pg_restore -U postgres -d testdb /tmp/test-restore.tar.gz

# 4. Verify restored data
docker exec postgres-test psql -U postgres -d testdb -c "SELECT COUNT(*) FROM users;"
# Expected: Same count as production

# 5. Document test
cat >> /var/log/restore-tests.log << EOF
$(date)
Backup tested: /backups/$(date +%Y-%m-%d)/database.tar.gz
Status: ✅ SUCCESSFUL
Record count verified: $(docker exec postgres-test psql -U postgres -d testdb -c "SELECT COUNT(*) FROM users;")
EOF
```

---

## Capacity Planning & Scaling

### Monthly Capacity Review
```bash
# Check resource trends
sar -u -P ALL 1 50 > /tmp/cpu-metrics.txt  # CPU over last day
sar -r 1 50 > /tmp/memory-metrics.txt      # Memory over last day

# Analyze trends
tail -20 /tmp/cpu-metrics.txt | awk '{print $3, $4}'
# Average CPU should be <60%, peak <80%

# Check database size growth
docker exec postgres-db du -h /var/lib/postgresql/data
# Expected: <10GB for typical deployment
# If >20GB, may need to cleanup or scale database

# Check Redis memory
docker exec redis-cache redis-cli info memory | grep used_memory_human
# Expected: <70% of max (if 2GB, <1.4GB used)
# If >90%, increase maxmemory or reduce TTL

# Forecast next month
# If current: [SIZE], growth: [%], then next month: [FORECAST]
# If forecast >100GB database, begin Phase 19 scaling
```

### Auto-Scaling Rules

**CPU Scaling** (Phase 17):
- If CPU >70% for >5 min → Scale Kong to 2 instances
- If CPU >85% for >5 min → Scale Kong to 3 instances
- If CPU <30% for >30 min → Scale back to 1 instance

**Memory Scaling** (Phase 15):
- If Redis memory >80% → Increase maxmemory to 4GB
- If Database memory >75% → Increase PostgreSQL shared_buffers

**Multi-Region Scaling** (Phase 18):
- Monitor EU-West (cold standby) to ensure it has same capacity as primary
- If US-East scales, apply same scaling to other regions

---

## Common Issues & Quick Fixes

### "connection refused" on localhost:8080
```bash
# Check if code-server is running
docker ps | grep code-server

# If not running:
docker-compose up -d code-server

# If running but not responding:
docker logs code-server | tail -20
# Check for startup errors

# If stuck in restart loop:
docker logs code-server | grep -i error | head -5
# Address the error (may require code fix)
```

### "Redis: connection refused"  
```bash
# Verify Redis running
docker ps | grep redis

# If not running:
docker-compose up -d redis-cache

# If connection pool exhausted:
docker exec redis-cache redis-cli info stats | grep connected_clients
# If >1000 clients, may indicate memory leak
# Restart: docker restart redis-cache
```

### "Database: connection timeout"
```bash
# Check PostgreSQL responding
docker exec postgres-db pg_isready -U postgres
# Expected: "accepting connections"

# If timeout, check disk:
df -h | grep "/$"
# If >95% full, delete old data or expand disk

# If still timeout, check network to replica regions:
docker exec postgres-db ping -c 1 10.1.1.5  # US-West
docker exec postgres-db ping -c 1 10.1.2.5  # EU-West
# If timeout, network issue - contact network team
```

### "Kong: all upstream peers are down"
```bash
# Check code-server is running
docker ps | grep code-server | grep -v kong

# If not running:
docker-compose up -d code-server

# If running, check Kong routing
docker exec kong kong-admin curl -s http://localhost:8001/services/code-server
# Expected: Service config returned

# If service missing, re-register:
docker exec kong kong-admin /bin/sh -c \
  "curl -X POST http://localhost:8001/services \
  -d 'name=code-server' \
  -d 'host=code-server' \
  -d 'port=8080'"
```

### "Jaeger: traces not appearing"
```bash
# Check Jaeger collector running
docker ps | grep jaeger | grep collector

# Verify application sending traces
docker logs code-server | grep -i jaeger
# Expected: "Connected to Jaeger agent" or similar

# If not sending, restart application with Jaeger env vars:
docker-compose down code-server
docker-compose up -d -e JAEGER_AGENT_HOST=jaeger-agent \
  -e JAEGER_AGENT_PORT=6831 code-server

# Check Cassandra (Jaeger backend) has space:
df -h | grep "cassandra"
# If >90% full, old traces may be deleted
```

### "Linkerd: sidecar injection failing"
```bash
# Check Linkerd control plane
linkerd check

# If issues found, fix:
linkerd check --repair

# Restart sidecar injector:
kubectl rollout restart deployment/linkerd-proxy-injector -n linkerd

# Re-inject namespace:
kubectl annotate namespace default linkerd.io/inject=enabled --overwrite
kubectl rollout restart deployment code-server
```

---

## Shift Handoff Template

**Outgoing Shift Lead** → **Incoming Shift Lead**

```
=== SHIFT HANDOFF REPORT ===
Date/Time: [YYYY-MM-DD HH:MM UTC]
Shift Lead (Outgoing): [NAME]
Shift Lead (Incoming): [NAME]

== SYSTEM STATUS ==
Overall: ✅ HEALTHY / ⚠️ DEGRADED / ❌ CRITICAL

Components:
- Phase 15 (Performance): ✅ / ⚠️ / ❌
- Phase 16 (Rollout): ✅ / ⚠️ / ❌  
- Phase 17 (Advanced): ✅ / ⚠️ / ❌
- Phase 18 (HA/DR): ✅ / ⚠️ / ❌

== KEY METRICS ==
p99 Latency: [XXXms] Target: <100ms
Error Rate: [X.XX%] Target: <0.1%
Cache Hit Ratio: [XX%] Target: >80%
Availability: [XX.XX%] Target: >99.9%

== INCIDENTS THIS SHIFT ==
[List any: incidents, recoveries, alerts, escalations]

== PENDING ACTIONS ==
[Critical items for next shift to monitor/handle]

== NOTES FOR NEXT SHIFT ==
[Important context, known issues, etc.]

Incoming Shift Lead Acknowledgment: _____ (signature)
```

---

**All operators must review this runbook quarterly. Last updated: April 13, 2026.**
