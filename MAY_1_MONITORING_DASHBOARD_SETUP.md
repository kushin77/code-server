# MAY 1 DEPLOYMENT DAY - MONITORING DASHBOARD SETUP

**Purpose:** Prepare monitoring dashboards for real-time deployment day oversight  
**Setup Time:** 15 minutes (can be done today or tomorrow morning)  
**Audience:** On-Call L1/L2, DevOps Lead  

---

## 📊 Dashboard Access & Setup

### Grafana Dashboards (http://192.168.168.31:3000)

**Login:** admin / [admin-password]

#### Dashboard 1: Infrastructure Overview
**Purpose:** CPU, memory, disk, and network across both servers

**Setup Steps:**
1. Go to Dashboards → Infrastructure
2. Set time range to "Last 1 hour" (top right)
3. Auto-refresh every 30 seconds
4. Keep browser tab open during deployment

**Key Metrics to Monitor:**
- [ ] CPU usage on primary (should be < 70%)
- [ ] CPU usage on replica (should be < 70%)
- [ ] Memory usage (should have > 10% free)
- [ ] Disk usage (should be < 80%)
- [ ] Network throughput (monitor for spikes)

#### Dashboard 2: PostgreSQL Status
**Purpose:** Database replication health

**Setup Steps:**
1. Go to Dashboards → PostgreSQL
2. Verify these panels visible:
   - Replication lag (should be < 1s)
   - Connected clients (should be stable)
   - Write performance (queries/sec)
   - Replication slots status (should be active)
3. Set time range to "Last 30 minutes"
4. Auto-refresh every 15 seconds

**Critical Alerts to Watch:**
- [ ] Replication lag > 10 seconds (alert fires)
- [ ] Connected clients > 200 (unusual spike)
- [ ] Write latency > 100ms (degradation)

#### Dashboard 3: API Performance
**Purpose:** Application health and response times

**Setup Steps:**
1. Go to Dashboards → API Performance
2. Verify these panels visible:
   - Request rate (requests/sec)
   - Error rate (% of requests failing)
   - Response time P50/P95/P99
   - Active connections
3. Set time range to "Last 30 minutes"
4. Auto-refresh every 15 seconds

**Success Indicators:**
- [ ] Error rate stays < 1%
- [ ] Response time P95 < 2 seconds
- [ ] Request rate stable (no drops)

#### Dashboard 4: Container Health
**Purpose:** Docker container status and resource usage

**Setup Steps:**
1. Go to Dashboards → Container Health
2. Filter to code-server containers
3. Verify these panels visible:
   - Container restart count (should not increase)
   - Container CPU usage by service
   - Container memory usage by service
   - Network I/O by container
4. Set time range to "Last 1 hour"
5. Auto-refresh every 30 seconds

**Warning Signs:**
- [ ] Any container restarting (red flag)
- [ ] CPU > 90% on any service (degrading)
- [ ] Memory > 80% on any service (near limits)

---

### Prometheus Alerts (http://192.168.168.31:9090)

**Setup Steps:**
1. Go to Alerts
2. Sort by "Severity" (descending)
3. Expected view shows firing rules

**Critical Alerts to Monitor:**
```
PostgreSQL Alerts:
  • PostgreSQL Replication Lag > 10s
  • PostgreSQL Connection Pool Saturated
  • PostgreSQL Replication Slot Inactive
  
Redis Alerts:
  • Redis Memory Usage > 80%
  • Redis Sentinel Offline
  
Container Alerts:
  • Container Restart Rate High
  • Container Memory Limit Near
  • Container CPU Near Limit
  
API Alerts:
  • API Error Rate > 1%
  • API Response Time P95 > 2s
  
Infrastructure Alerts:
  • Host CPU > 90%
  • Host Memory > 90%
  • Disk Usage > 85%
  • Network Connectivity Down
```

**Setup Procedure:**
1. Create new browser tab with Prometheus Alerts page
2. Add to bookmarks (name: "Prometheus Alerts - May 1")
3. Set browser tab to auto-refresh (F5 every 30s)
4. Keep tab open during deployment window

---

### AlertManager (http://192.168.168.31:9093)

**Purpose:** View all alerts and acknowledgments

**Setup Steps:**
1. Go to AlertManager dashboard
2. Verify receiver routing shows:
   - Slack #critical-incidents (for CRITICAL alerts)
   - Email (for HIGH alerts)
   - Slack #incidents (for all alerts)
3. Keep tab open to track alert acknowledgments

**What You'll See:**
- Active alerts (red = currently firing)
- Acknowledgments (when L1 acknowledges alert)
- Grouped alerts (related alerts grouped together)

**Manual Alert Acknowledgment:**
```bash
# If alert needs manual acknowledgment (run on primary)
curl -X POST http://localhost:9093/api/v1/alerts/ack \
  -H "Content-Type: application/json" \
  -d '[{"Labels": {"alertname": "PostgreSQLReplicationLag"}}]'
```

---

## 🖥️ DEPLOYMENT DAY MONITORING SETUP (30 min before deployment)

### One Hour Before Deployment (08:00 UTC, May 1)

**On-Call L1 Setup (30 minutes before go-live):**

```bash
# Terminal 1: Grafana dashboards
# Open 4 browser tabs (each in separate window):
Tab 1: Grafana Infrastructure Dashboard
  - URL: http://192.168.168.31:3000/d/infrastructure
  - Time range: Last 1 hour
  - Refresh: 30 seconds
  
Tab 2: Grafana PostgreSQL Dashboard
  - URL: http://192.168.168.31:3000/d/postgresql
  - Time range: Last 30 minutes
  - Refresh: 15 seconds
  
Tab 3: Grafana API Performance Dashboard
  - URL: http://192.168.168.31:3000/d/api-performance
  - Time range: Last 30 minutes
  - Refresh: 15 seconds
  
Tab 4: Prometheus Alerts
  - URL: http://192.168.168.31:9090/alerts
  - Auto-refresh enabled

# Terminal 2: AlertManager monitoring
# Keep running and check every 5 minutes
watch -n 5 'curl -s http://localhost:9093/api/v1/alerts | jq ".[].Labels.alertname" | sort | uniq -c'

# Terminal 3: Log monitoring (run on primary)
ssh ubuntu@192.168.168.31
tail -f /var/log/deployment.log  # If available
# OR
docker logs -f prometheus 2>&1 | grep -i warn\|error

# Terminal 4: Ready for escalation
# Keep this terminal clear for immediate SSH access
ssh ubuntu@192.168.168.31  # But don't use yet, just verify access
```

---

## 📊 MONITORING CHECKLIST - DEPLOYMENT DAY MORNING

### 08:00 UTC (1 hour before deployment)

- [ ] All 4 Grafana dashboards loaded and visible
- [ ] Prometheus Alerts page open and monitored
- [ ] AlertManager page open
- [ ] Slack #deployment channel joined
- [ ] Slack #alerts channel joined (for alert notifications)
- [ ] Email notifications tested and active
- [ ] Phone nearby and notifications enabled
- [ ] Team assembled and standing by
- [ ] Previous alerts acknowledged and cleared
- [ ] Baseline metrics recorded (for comparison)

### During Deployment (09:00-09:30 UTC)

**Monitoring Actions (Every 5 minutes):**
- [ ] Check Grafana CPU/memory usage (should remain stable)
- [ ] Check Prometheus alerts (new alerts = issues)
- [ ] Check AlertManager for new firing alerts
- [ ] Monitor Slack for alert notifications
- [ ] Report status to DevOps Lead
- [ ] Log any anomalies in deployment.log

**Expected Patterns:**
- CPU usage increases slightly during deployment
- Memory usage increases slightly
- Network I/O increases (data transfers)
- Some transient alerts may fire and resolve
- Container restarts should be 0-1 total

**Warning Signs:**
- CPU stays > 80% (might be deployment, but watch)
- Memory usage > 90% (potential issue)
- Container restarts > 2 (check what's restarting)
- Alert spam (> 10 alerts/min = something wrong)
- Error rate > 5% (degradation)

---

## 🔴 CRITICAL ALERT SCENARIOS

### If PostgreSQL Replication Lag Alert Fires

```
Alert: PostgreSQL Replication Lag > 10 seconds

Action Plan:
1. Check on Prometheus: SELECT pg_is_in_recovery(); (should be t)
2. Check on primary: SELECT lag from pg_stat_replication;
3. If lag > 30s: Escalate to L2 immediately
4. If lag < 30s: Continue monitoring (may self-resolve)
5. Update DevOps Lead every 2 minutes

If not resolving:
  • Check replica CPU (high CPU = slow replication)
  • Check network latency between servers
  • Check replica disk I/O (full disk = slow replication)
```

### If Container Restart Alert Fires

```
Alert: Container Restart Rate High

Action Plan:
1. Identify which container is restarting
2. Check logs: docker logs -f <container_name> --tail 50
3. If restarts continue: Escalate to L2
4. Do NOT manually restart (let it auto-recover)
5. Report to DevOps Lead

Acceptable causes:
  • Container restarting due to deployment (normal)
  • Container restarting 1-2 times total (normal)
  • Container restart rate stabilizing (normal)

Unacceptable causes:
  • Container restart > 5 times (problematic)
  • Container in crash loop (unrecoverable)
  • Multiple containers restarting together (cascade failure)
```

### If API Error Rate Alert Fires

```
Alert: API Error Rate > 1%

Action Plan:
1. Check API logs: docker logs api-server --tail 100 | grep -i error
2. Check if database connected: curl http://api-server:5432
3. Check if Redis connected: curl http://redis:6379
4. Report error samples to L2

If database errors:
  • Escalate to L2 immediately
  • May need database restart
  
If Redis errors:
  • Try restart: docker-compose restart redis
  • If persists: Escalate to L2
  
If API errors with no dependency issues:
  • Check API application logs
  • Restart API: docker-compose restart api-server
  • If persists: Escalate to L2
```

### If Disk Usage Alert Fires

```
Alert: Disk Usage > 85%

Action Plan:
1. Check disk space: df -h /
2. Identify large files: du -sh /* | sort -rh | head
3. If > 90%: Stop deployment, escalate immediately

Mitigation:
  • Clean old Docker images: docker image prune -a
  • Clean unused volumes: docker volume prune
  • Check/clean old logs if applicable
  • Restart docker daemon if needed
```

---

## 📋 POST-DEPLOYMENT MONITORING (10:00 UTC - 10:00 UTC May 2)

### 24-Hour Monitoring Window

**First 4 Hours (10:00-14:00 UTC, May 1):**
- [ ] Check dashboards every 15 minutes
- [ ] Report status every hour
- [ ] Alert on any critical fires
- [ ] Document any issues

**Rest of Day (14:00 UTC May 1 - 10:00 UTC May 2):**
- [ ] Check dashboards every 1 hour
- [ ] Escalate only critical issues
- [ ] Daily monitoring continues
- [ ] Keep alerts acknowledged

**Success Metrics After 24 Hours:**
- ✅ Uptime: > 99.9%
- ✅ Error rate: < 0.1%
- ✅ Response time P95: < 1 second
- ✅ Replication lag: < 100ms consistently
- ✅ Container restarts: < 1 total
- ✅ No unacknowledged critical alerts

---

## 📞 ESCALATION FROM MONITORING

**When to Escalate:**
1. **Immediately to L2:** Any CRITICAL alert that doesn't resolve in 5 minutes
2. **To DevOps Lead:** Any alert pattern that seems unusual
3. **To Manager:** If system appears degraded but no alerts firing

**Escalation Message Template:**
```
AlertName: [PostgreSQL Replication Lag]
Severity: [CRITICAL]
Firing Since: [HH:MM UTC]
Current Value: [lag > 30 seconds]
Status: [Not self-resolving, manual intervention needed]
Recommendation: [Check replica replication status, may need restart]
```

---

## ✅ MONITORING READINESS CHECKLIST

**Complete by 08:00 UTC, May 1:**
- [ ] Grafana dashboards loaded and visible
- [ ] Prometheus Alerts page open
- [ ] AlertManager dashboard open
- [ ] Slack channels joined (#deployment, #alerts)
- [ ] Email notifications tested
- [ ] Previous alerts cleared
- [ ] All browser tabs set to auto-refresh
- [ ] Terminal ready for SSH escalations
- [ ] Team members have this guide
- [ ] Escalation contacts verified

---

## 🎯 YOUR MONITORING JOB

**Is simple:**
1. Watch the dashboards (they tell the story)
2. Report status every 5 minutes to team
3. Escalate if you see red (critical alerts)
4. Log everything in deployment.log

**You don't need to:**
- Fix things yourself (that's L2 job)
- Interpret complex metrics (dashboards do that)
- Make deployment decisions (that's Lead's job)

**Just monitor and communicate!**

---

**Questions?** See [MAY_1_DEPLOYMENT_DAY_CHECKLIST.md](MAY_1_DEPLOYMENT_DAY_CHECKLIST.md)  
**Issues during deployment?** Slack → #deployment or call escalation contact

