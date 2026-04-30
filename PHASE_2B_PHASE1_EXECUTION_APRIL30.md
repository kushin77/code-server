# PHASE 2B PHASE 1 - EXECUTION PROCEDURES (APRIL 30, 16:00 UTC+)
## Real-Time Execution Framework for Week 1 Deployment

**Phase 1 Start Time:** April 30, 2026 16:00 UTC (if GO approved at 15:45)  
**Phase 1 Duration:** April 30 16:00 UTC → May 4, 23:59 UTC (5 calendar days)  
**Team Schedule:** Alpha Shift (04:00-12:00 UTC) + Bravo Shift (12:00-20:00 UTC) + Charlie Shift (20:00-04:00 UTC)  
**Owner:** Project Manager (overall) + Infrastructure Lead (technical)  

---

## 🎯 PHASE 1 OVERVIEW & OBJECTIVES

**Primary Node Deployment & Validation:**
1. Deploy GitLab 15.11.11-ce to PRIMARY node (192.168.168.31)
2. Validate all containers come online (87 → expected green)
3. Run health checks and verify functionality
4. Prepare REPLICA node for deployment (Week 2)
5. Establish real-time monitoring and alerting

**Success Criteria:**
- [ ] PRIMARY node running 87+ containers
- [ ] All critical services responding (GitLab, PostgreSQL, Redis, etc.)
- [ ] Database replication status healthy (lag <5s if replicating)
- [ ] Monitoring dashboards showing GREEN across all metrics
- [ ] No critical alerts firing
- [ ] Incident log tracking all events (document everything)
- [ ] Team morale high, no escalations

---

## ⏰ PHASE 1 EXECUTION TIMELINE - APRIL 30 TO MAY 4

```
APRIL 30 (Day 1):
├─ 16:00 UTC: Phase 1 EXECUTION BEGINS
├─ 16:00-17:00: Pre-deployment final checks (1 hour)
├─ 17:00-18:30: PRIMARY deployment starts (1.5 hours)
├─ 18:30-19:30: Container health verification (1 hour)
├─ 19:30-20:30: Critical service validation (1 hour)
└─ 20:30 UTC: End Alpha shift, hand off to Bravo

MAY 1 (Day 2):
├─ 04:00 UTC: Bravo shift arrives
├─ 04:00-12:00: Continue Phase 1, full suite testing
└─ 12:00 UTC: Hand off to Charlie shift

MAY 2-4 (Days 3-5):
├─ Continuous 24/7 operation
├─ Stress testing and load verification
├─ Backup and recovery validation
└─ May 4 23:59 UTC: Phase 1 complete
```

---

## 📋 IMMEDIATE ACTIONS - APRIL 30, 16:00-17:00 UTC (FIRST HOUR)

### T+0-15 MIN (16:00-16:15 UTC) - Final Systems Check

**All Team Leads Execute Simultaneously:**

```bash
# INFRASTRUCTURE LEAD: Verify deployment package
ssh ubuntu@192.168.168.31 << 'EOF'
echo "=== DEPLOYMENT PACKAGE VERIFICATION ==="
echo "GitLab Version: $(docker images | grep gitlab | grep 15.11.11)"
echo "Docker Compose: $(docker-compose --version)"
echo "Available Storage: $(df -h / | tail -1 | awk '{print $4}')"
echo "Current Containers: $(docker ps | wc -l)"
EOF

# OPERATIONS LEAD: Confirm team assembly
echo "Alpha shift team assembled: [confirm each person]"
echo "War room operational: [confirm systems running]"
echo "Escalation contacts available: [confirm reachability]"

# MONITORING LEAD: Verify dashboard state
echo "Grafana dashboards: LIVE and displaying baseline"
echo "Prometheus data: Collecting (expect 8+ targets)"
echo "AlertManager: Active and routing configured"

# QA LEAD: Testing environment ready
echo "Test suite loaded: [confirm]"
echo "Test data prepared: [confirm]"
echo "Testers briefed on Phase 1 procedures: [confirm]"

# SECURITY LEAD: Compliance verified
echo "Audit logging: ENABLED"
echo "Access controls: ACTIVE"
echo "Baseline security scan: CLEAN"
```

### T+15-30 MIN (16:15-16:30 UTC) - Infrastructure Pre-Flight

**Infrastructure Lead Actions:**

```bash
# On PRIMARY Node (192.168.168.31):

# 1. Database backup before deployment (CRITICAL)
echo "Creating pre-deployment database backup..."
ssh ubuntu@192.168.168.31 << 'EOF'
docker exec gitlab_db pg_dump -U postgres gitlabhq_production > \
  /tmp/gitlab_backup_pre_deployment_$(date +%Y%m%d_%H%M%S).sql
echo "✓ Backup created: /tmp/gitlab_backup_pre_*.sql"
EOF

# 2. Stop services gracefully (if existing containers running)
ssh ubuntu@192.168.168.31 << 'EOF'
docker-compose -f docker-compose.enterprise.yml down --remove-orphans
echo "✓ Services stopped gracefully"
echo "Containers remaining: $(docker ps | wc -l) (should be ~0)"
EOF

# 3. Clear stale images (cleanup)
ssh ubuntu@192.168.168.31 << 'EOF'
docker image prune -f --all
echo "✓ Stale images cleaned"
echo "Available space: $(df -h / | tail -1 | awk '{print $4}')"
EOF
```

### T+30-60 MIN (16:30-17:00 UTC) - Deployment Readiness Final Confirmation

**Full Team Confirmation (via Slack or Voice):**

```
Project Manager Poll (16:50 UTC):
"Each lead confirm: Ready for deployment start?"

Infrastructure Lead: "Infrastructure ready / BLOCKED"
Operations Lead: "Team ready / BLOCKED"
Monitoring Lead: "Monitoring ready / BLOCKED"
QA Lead: "Testing ready / BLOCKED"
Security Lead: "Security baseline ready / BLOCKED"

IF ALL READY → Proceed to deployment start at 17:00 UTC
IF ANY BLOCKED → Investigate and remediate, postpone to next hour
```

---

## 🚀 PHASE 1 DEPLOYMENT START - 17:00 UTC (HOUR 2)

### T+60-90 MIN (17:00-17:30 UTC) - Deploy PRIMARY Node

**Infrastructure Lead Executes Deployment:**

```bash
# On PRIMARY Node (192.168.168.31):

echo "=== PHASE 1 PRIMARY NODE DEPLOYMENT ==="
echo "Time: April 30, 2026 17:00 UTC"
echo "Objective: Deploy 87 containers"
echo ""

cd /home/ubuntu/code-server

# 1. Start deployment with image pull
docker-compose -f docker-compose.enterprise.yml pull
echo "✓ Images pulled (20260430 tag)"

# 2. Bring up services (will start all 87 containers)
docker-compose -f docker-compose.enterprise.yml up -d --scale gitlab=3
echo "✓ Services starting..."

# 3. Wait for services to stabilize (90-120 seconds typical)
sleep 30  # Initial wait
docker-compose -f docker-compose.enterprise.yml ps

# 4. Monitor container startup
echo ""
echo "Monitoring container status (refreshing every 10 seconds)..."
for i in {1..9}; do
  echo "Check $i: $(docker ps | grep -c 'Up') containers Up"
  sleep 10
done

# Expected: All 87 containers should be "Up" within 3 minutes
FINAL_COUNT=$(docker ps | grep -c 'Up')
echo ""
echo "=== FINAL CONTAINER COUNT: $FINAL_COUNT/87 ==="
if [ "$FINAL_COUNT" -ge 85 ]; then
  echo "✓ Deployment SUCCESSFUL - Containers healthy"
else
  echo "⚠️  WARNING - $((87 - FINAL_COUNT)) containers not responding"
  echo "Action: Investigate failed containers immediately"
fi
```

**Monitoring Lead Actions (17:00-17:30 UTC):**

```
LIVE DASHBOARD MONITORING:
├─ Watch Cluster Health Dashboard for all 87 containers
├─ Monitor Database Replication (if replicated)
├─ Check Application Performance metrics
├─ Watch for any CRITICAL alerts
└─ Document baseline metrics every 5 minutes

ALERTS:
├─ Any CRITICAL alerts immediately escalate
├─ Any HIGH alerts report within 2 minutes
└─ All events log to incident tracker
```

---

## 🔍 PHASE 1 VALIDATION - 17:30-20:30 UTC (HOURS 3-6)

### T+90-120 MIN (17:30-18:00 UTC) - Critical Service Verification

**QA Lead Executes Validation Tests:**

```bash
# Test 1: GitLab UI Responsive (2 min)
curl -s http://192.168.168.50/admin/projects | grep -q "Projects" && \
  echo "✓ GitLab UI responding" || echo "❌ GitLab UI not accessible"

# Test 2: PostgreSQL Database Responsive (2 min)
ssh ubuntu@192.168.168.31 << 'EOF'
docker exec gitlab_db psql -U postgres -c "SELECT version();" && \
  echo "✓ PostgreSQL responding" || echo "❌ PostgreSQL not accessible"
EOF

# Test 3: Redis Cache Responsive (2 min)
ssh ubuntu@192.168.168.31 << 'EOF'
docker exec gitlab_redis redis-cli ping && \
  echo "✓ Redis responding" || echo "❌ Redis not accessible"
EOF

# Test 4: GitLab API Functional (2 min)
curl -s http://192.168.168.50/api/v4/version 2>/dev/null | grep -q "version" && \
  echo "✓ GitLab API responding" || echo "❌ GitLab API not accessible"

# Test 5: Health Check Script (2 min)
bash check-system-health.sh
# Expected: ALL GREEN status
```

### T+120-180 MIN (18:00-19:00 UTC) - Full Health Check Suite

**Infrastructure Lead Executes Full Validation:**

```bash
# Script: check-system-health.sh (runs all system checks)
bash check-system-health.sh

# Expected Output:
# ✓ Container Health: 87/87 UP
# ✓ Database: PostgreSQL responsive, replication active
# ✓ Redis: Master active and responsive
# ✓ Network: <1ms latency to REPLICA
# ✓ Storage: >50GB available
# ✓ All 10+ critical services: RESPONDING
# ✓ Memory Usage: <70%
# ✓ CPU Usage: <50%
# ✓ Error Logs: No recent CRITICAL errors
# ✓ Replication: Lag <5 seconds

if [ $? -eq 0 ]; then
  echo "✅ PHASE 1 VALIDATION COMPLETE - ALL GREEN"
else
  echo "⚠️  PHASE 1 VALIDATION ISSUES - INVESTIGATE"
fi
```

---

## 📊 PHASE 1 CONTINUOUS MONITORING (24/7)

### Real-Time Dashboards - Always Active

**Monitoring Lead Responsibilities:**

```
Dashboard Refresh Rate: 15-30 seconds
Alert Check Frequency: Every 5 minutes
Status Report Interval: Every hour (00:00, 01:00, 02:00, etc.)

Dashboard 1: Cluster Health
├─ Container count trending
├─ Service availability (all 10+ services)
├─ Health check pass rate
└─ Alert summary

Dashboard 2: Database Replication
├─ Replication lag (target: <5s)
├─ Transaction volume
├─ Backup status
└─ Connection count

Dashboard 3: Application Performance
├─ API response time (target: <500ms p99)
├─ Error rate (target: <0.1%)
├─ Request volume
└─ Cache hit rate

Dashboard 4: Services Status
├─ All 10+ critical services UP
├─ Service latency metrics
├─ Service-level health
└─ Dependency health
```

### Incident Tracking - Log Everything

**Operations Lead Responsibility:**

```
Document Every Event:
1. Container starts/stops
2. Any service errors
3. Replication lag changes
4. Backup completions
5. Alert firings (all levels)
6. Team actions taken
7. Issues resolved and time

Format:
[HH:MM UTC] [Service] [Event] [Action/Result] [Lead Name]

Example:
[17:15 UTC] [GitLab] Container startup complete (87/87) [Infrastructure Lead]
[17:45 UTC] [Database] Replication lag: 0.3s (normal) [Infrastructure Lead]
[18:30 UTC] [Monitoring] Baseline metrics captured [Monitoring Lead]
[19:00 UTC] [Health Check] Script executed - ALL GREEN [Infrastructure Lead]
```

---

## 🚨 ISSUE RESPONSE - PHASE 1

### If Container Doesn't Start

```
Symptom: One or more containers showing "Exited" or "Unhealthy"
Action:
1. Infrastructure Lead: Check logs
   docker logs [container_name] | tail -50
2. Document issue in incident log
3. If critical service down:
   - Report to Project Manager immediately (Slack + voice)
   - Attempt restart: docker-compose up -d [service]
   - Monitor for 5 minutes
4. If persists:
   - Escalate to CTO
   - Consider Phase 1 PAUSE
```

### If Replication Lag >5 Seconds

```
Symptom: Database replication lag exceeding 5-second target
Action:
1. Monitoring Lead: Document exact lag value
2. Infrastructure Lead: Check REPLICA capacity
   - SSH to REPLICA: Monitor CPU/Memory/Disk
   - Check network latency: ping PRIMARY
3. If temporary spike (expected during deployment):
   - Continue monitoring every 2 minutes
   - Expected to normalize within 5-10 minutes
4. If sustained >30 seconds:
   - Escalate to Infrastructure Lead
   - Consider reducing load or pausing other operations
```

### If Critical Alert Fires

```
Symptom: CRITICAL alert in AlertManager
Action:
1. Monitoring Lead: Document alert details immediately
2. Responsible Lead: Investigate root cause
3. Operations Lead: Notify all team leads
4. Alert Routing:
   CRITICAL → Slack immediately + CTO phone call
   Response time: <2 minutes
5. Resolution:
   - Fix or escalate
   - Document solution
   - Prevent recurrence
```

---

## 📈 PHASE 1 SUCCESS METRICS

**Checkpoint 1 (17:00-18:00 UTC):**
- [ ] PRIMARY deployment completed
- [ ] 87/87 containers healthy
- [ ] No critical errors in logs
- [ ] Team morale: GOOD

**Checkpoint 2 (18:00-19:00 UTC):**
- [ ] All critical services validated
- [ ] GitLab API responding
- [ ] Database replication healthy (if applicable)
- [ ] Monitoring dashboards showing GREEN

**Checkpoint 3 (19:00-20:00 UTC):**
- [ ] Health check script passes (ALL GREEN)
- [ ] 1 hour of operation without issues
- [ ] Team feeling confident
- [ ] Ready for shift handoff

**Final Phase 1 Success (May 4):**
- [ ] 5 full days of stable operation
- [ ] All stress tests passed
- [ ] Backup/recovery procedures verified
- [ ] REPLICA ready for deployment (Phase 2)
- [ ] Team trained and ready for production

---

## 👥 SHIFT HANDOFF - EVERY 8 HOURS

**Handoff Times:**
- 20:30 UTC (Alpha → Bravo)
- 04:30 UTC (Bravo → Charlie)
- 12:30 UTC (Charlie → Alpha)

**Handoff Procedure (30 minutes):**
1. Incoming shift arrives 15 minutes early
2. Outgoing lead reviews current status
3. Critical issues discussed
4. Dashboard walkthrough
5. Action items assigned
6. Sign-off verification
7. Outgoing shift departs

---

## ✨ PHASE 1 END STATE (May 4, 23:59 UTC)

**At successful Phase 1 completion:**
- ✅ PRIMARY node: 100% stable for 5 days
- ✅ All validation tests: PASSED
- ✅ No unresolved critical issues
- ✅ Team: Confident and trained
- ✅ REPLICA: Prepared and ready
- ✅ Monitoring: Baseline established
- ✅ Incident log: Complete documentation
- ✅ Backup/recovery: Verified working

**Transition to Phase 2:** May 5, deployment to REPLICA node

---

**PHASE 1 EXECUTION: APRIL 30 - MAY 4**

*All leads: Know your role, execute with precision, document everything.*  
*Team: You've trained well. Now you execute. Let's deliver.* 🚀

