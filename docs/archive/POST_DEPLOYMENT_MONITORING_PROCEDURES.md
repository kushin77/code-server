# Post-Deployment Monitoring Procedures

**Effective Date:** May 1, 2026, 1:20 PM EDT  
**Duration:** 24 hours (through May 2, 1:20 PM EDT)  
**Purpose:** Guide operations team through baseline collection period  

---

## Quick Reference Guide

### What to Do Every Hour
1. ✅ Check Grafana dashboard (http://192.168.168.31:3000)
   - Verify no spike in red areas
   - Look for any downward trends
   - Note anything unusual

2. ✅ Run health check
   ```bash
   bash scripts/ops/post-deployment-verification-local.sh 2>&1 | tail -30
   ```

3. ✅ Check container status
   ```bash
   ssh root@192.168.168.31 "docker ps | wc -l"
   # Should show: 51 (38 service + 13 init)
   ```

4. ✅ Quick log check
   ```bash
   ssh root@192.168.168.31 "docker logs code-server-control-plane 2>&1 | tail -10"
   # Should show: Normal operation, no ERROR or CRITICAL
   ```

5. ✅ Update REALTIME_MONITORING_STATUS.md
   - Record any observations
   - Note any alerts
   - Update checkpoint status

### What to Do Every 4 Hours
1. ✅ Run comprehensive health check
   ```bash
   bash scripts/ops/post-deployment-verification-local.sh
   ```

2. ✅ Verify backup jobs completed
   ```bash
   ssh root@192.168.168.31 "docker logs code-server-postgresql 2>&1 | grep -i backup | tail -5"
   ```

3. ✅ Check alert configuration
   - Go to: http://192.168.168.31:9093 (AlertManager)
   - Verify alerts configured correctly
   - Check for any anomalies

4. ✅ Validate trace/metrics export
   - Prometheus: http://192.168.168.31:9090
   - Query: `rate(traces_total[5m])` - should show ongoing trace collection
   - Query: `rate(metrics_total[5m])` - should show ongoing metrics

5. ✅ Deep monitoring review
   - Any pattern changes?
   - Any resource trends?
   - Any unexpected behavior?

### What to Do Every 8 Hours
1. ✅ Comprehensive error log review
   ```bash
   ssh root@192.168.168.31 "for c in \$(docker ps -q); do echo \"Container: \$c\"; docker logs \$c 2>&1 | grep -i error | tail -3; done | head -50"
   ```

2. ✅ Resource constraint check
   - CPU: Check if any container approaching limits
   - Memory: Check if any container at >80% usage
   - Disk: Check if primary or replica >50% full

3. ✅ Multi-tenancy isolation verification
   ```bash
   # Verify tenants are properly isolated
   curl -s http://192.168.168.31:8080/api/tenants/health | jq '.isolation_status'
   ```

4. ✅ Audit log verification
   ```bash
   # Check audit logs are being collected
   docker exec code-server-postgresql psql -U postgres -c "SELECT COUNT(*) FROM audit_logs WHERE created_at > NOW() - INTERVAL '1 hour';"
   ```

---

## Critical Response Procedures

### If Service Goes Down

**Immediate (0-5 minutes):**
1. Verify which service is down
2. Check service logs for error
3. Attempt service restart: `docker restart <service-name>`
4. Page on-call engineer if critical service

**Investigation (5-30 minutes):**
1. Check if service recovers
2. Review recent deployments
3. Check resource usage
4. Review network connectivity

**Escalation (30+ minutes):**
1. Contact platform-eng@example.com
2. Provide: service name, logs, errors
3. Prepare rollback if needed

### If Replication Lag > 5 Minutes

**Immediate (0-5 minutes):**
1. Verify network connectivity between hosts
2. Check replica node health
3. Verify PostgreSQL is running on replica

**Investigation (5-30 minutes):**
1. Check PostgreSQL logs for errors
2. Monitor replication slot status
3. Check network bandwidth usage
4. Review for long-running queries

**Resolution (30+ minutes):**
1. If network issue: Contact network team
2. If PostgreSQL issue: Restart PostgreSQL on replica
3. If persistent: Contact platform-eng@example.com

### If Disk Usage > 80%

**Immediate (0-15 minutes):**
1. Identify which disk is full
2. Check what's consuming space
3. Clean old logs if needed: `docker system prune`
4. Verify Prometheus retention settings

**Investigation (15+ minutes):**
1. Check if something is leaking disk space
2. Review Docker image sizes
3. Check volume usage per container
4. Contact platform-eng@example.com if needed

### If Memory Usage > 90%

**Immediate (0-5 minutes):**
1. Verify it's not just caching
2. Identify which container using most memory
3. Monitor trend
4. If memory pressure too high: prepare for restart

**Investigation (5-30 minutes):**
1. Check for memory leaks
2. Review application logs
3. Check if workload spike causing it
4. Contact platform-eng@example.com if needed

---

## Data Collection Verification

### Files Being Generated

**Location:** `/home/akushnir/code-server/artifacts/baseline-metrics/`

**Expected Files:**
```bash
# Check baseline data is being collected
ls -la artifacts/baseline-metrics/

# Count files
find artifacts/baseline-metrics/ -name "metrics_*.json" | wc -l
# Should increase by 1 every 5 minutes

# View latest metrics
tail artifacts/baseline-metrics/metrics_*.json | head -50
```

**Expected File Count After Each Period:**
```
1 hour:   12 files (5-minute intervals)
4 hours:  48 files
8 hours:  96 files
24 hours: 288 files
```

### Data Quality Checks

**Prometheus is scraping targets:**
```
# Go to: http://192.168.168.31:9090/targets
# Verify: All targets should be "UP" (green)
# Alert: If any targets are "DOWN" (red)
```

**Grafana is receiving data:**
```
# Go to: http://192.168.168.31:3000
# Dashboard: System Overview
# Verify: Graphs showing data, not "No data"
```

**Jaeger is collecting traces:**
```
# Go to: http://192.168.168.31:16686
# Search: All traces
# Verify: Traces appearing with current timestamps
```

---

## Baseline Metric Targets

### Performance Baselines
```
What We're Measuring:           Expected Range    Good Sign When:
──────────────────────────────────────────────────────────────────
Trace throughput               10K+ spans/sec    Consistently above 10K
Metrics throughput             100K+ metrics/sec Consistently above 100K
Query latency (p95)            <100ms            Mostly <100ms, no spikes
Dashboard load                 <2 seconds        Typical 1-2 second range
Alert latency                  <30 seconds       Alerts firing promptly
```

### Resource Baselines
```
What We're Measuring:           Expected Range    Good Sign When:
──────────────────────────────────────────────────────────────────
CPU average                    15-40%            Stable in range, no spikes
Memory average                 40-60%            Stable, not growing
Disk usage (primary)           <50% of total     Stable, not growing
Disk usage (replica)           <50% of total     Stable, not growing
Network (primary)              <100 Mbps avg     Reasonable load, no spikes
```

### HA Baselines
```
What We're Measuring:           Expected Range    Good Sign When:
──────────────────────────────────────────────────────────────────
PostgreSQL replication lag     <100ms            Consistently <100ms
Redis replication lag          <50ms             Consistently <50ms
Redpanda lag                   <500ms            Consistently <500ms
HA failover ready              100%              Always ready, no errors
Data loss risk                 None              Zero replication errors
```

---

## Communication Protocol

### Hourly Status Updates
**To:** ops-team@example.com  
**Frequency:** Top of each hour (automatic if using monitoring system)  
**Content:** Status of all services, any issues, metrics trend

### Issue Notification
**Immediate:** Any critical service down
**Within 30 minutes:** Any warning-level issue
**Include:** What, when, where, impact, initial action taken

### Final Report
**Timing:** May 2, 2026, 1:20 PM EDT (end of 24-hour period)  
**Content:** Baseline metrics summary, any issues found, recommendations

---

## Common Commands Reference

### Check Infrastructure
```bash
# Check containers running on primary
ssh root@192.168.168.31 "docker ps | head -20"

# Check container count
ssh root@192.168.168.31 "docker ps | wc -l"

# Check container health
ssh root@192.168.168.31 "docker ps -a | grep -v 'Up'"

# Check system resources
ssh root@192.168.168.31 "top -b -n 1 | head -20"

# Check disk usage
ssh root@192.168.168.31 "df -h | grep -E 'Filesystem|docker|mnt'"
```

### Check Services
```bash
# Check PostgreSQL
docker exec code-server-postgresql pg_isready

# Check Redis
redis-cli -h 192.168.168.31 ping

# Check Prometheus
curl -s http://192.168.168.31:9090/-/healthy

# Check Grafana
curl -s http://192.168.168.31:3000/api/health | jq '.status'

# Check Jaeger
curl -s http://192.168.168.31:16686/ | grep -q "Jaeger" && echo "UP" || echo "DOWN"
```

### Monitor Replication
```bash
# PostgreSQL replication lag
docker exec code-server-postgresql psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() as lag;"

# Redis replication info
redis-cli -h 192.168.168.31 info replication

# Check Redpanda cluster
docker exec code-server-redpanda rpk cluster health
```

### View Logs
```bash
# Last 50 lines of a service log
docker logs code-server-control-plane -n 50

# Follow logs in real-time
docker logs code-server-postgresql -f --tail 20

# Search logs for errors
docker logs code-server-activity-feed 2>&1 | grep -i error | tail -20

# Get logs from all containers
for c in $(docker ps -q); do 
    echo "=== $(docker inspect $c --format '{{.Name}}') ===" 
    docker logs $c 2>&1 | tail -5
done
```

---

## When to Escalate

### Escalate to platform-eng@example.com If:
- [ ] Any service down for >5 minutes
- [ ] Replication lag > 5 minutes
- [ ] Disk usage > 90%
- [ ] Memory usage > 95%
- [ ] Multiple containers restarting
- [ ] Network connectivity issues
- [ ] Any persistent errors in logs
- [ ] Any unexpected behavior

### Escalate to incidents@example.com If:
- [ ] Data loss detected
- [ ] Cluster unstable
- [ ] Performance degradation >25%
- [ ] Multiple simultaneous failures
- [ ] Unable to restart services
- [ ] Security concern detected

---

## Success Criteria

### 24-Hour Monitoring Success
✅ All services stable for full 24 hours  
✅ No critical alerts triggered  
✅ No manual interventions required  
✅ Baseline metrics collected (288 snapshots)  
✅ No data loss or inconsistencies  
✅ Replication working flawlessly  
✅ No resource exhaustion  
✅ Performance consistent with expectations  

### Ready to Move to Production Operations If:
✅ All success criteria met  
✅ Baseline metrics reviewed and approved  
✅ No surprises or anomalies  
✅ Operations team confident in system  
✅ All procedures documented and tested  
✅ Team training completed  
✅ Escalation procedures verified  

---

## After 24 Hours

### Post-Monitoring Checklist
- [ ] Generate final baseline report
- [ ] Review all metrics collected
- [ ] Compare actual vs expected
- [ ] Document any deviations
- [ ] Update runbooks as needed
- [ ] Brief team on findings
- [ ] Approve for normal operations
- [ ] Schedule regular reviews

### Next Phase
- [ ] Transition to operations-as-normal
- [ ] Implement automated monitoring
- [ ] Begin Phase 25 planning
- [ ] Schedule maintenance windows
- [ ] Plan capacity planning review

---

**Duration:** 24 hours (May 1, 1:20 PM - May 2, 1:20 PM EDT)  
**Status:** Monitoring Active  
**Last Updated:** May 1, 2026, 1:20 PM EDT  
