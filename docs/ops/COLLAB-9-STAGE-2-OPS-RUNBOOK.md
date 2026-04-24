#!/usr/bin/env bash
# @file        docs/ops/COLLAB-9-STAGE-2-OPS-RUNBOOK.md
# @module      operations/deployment
# @description Production canary deployment ops runbook for Collab-9
# @status      ready-for-execution

# Collab-9 Stage 2 Production Canary Deployment - Operations Runbook

**Deployment Window:** April 26-27, 2026 (48 hours)  
**Replicas:** Replica 1 (Primary, 192.168.168.31) + Replica 2 (Secondary, 192.168.168.42)  
**Rollout:** 5% user canary → 100% gradual over 3 stages  
**Risk Level:** LOW (feature flagged, polling fallback, instant rollback)

---

## PRE-DEPLOYMENT CHECKLIST (April 25 Evening, 1 day before)

### Verification Steps (Run in Order)

- [ ] **1. Verify staging deployment is still healthy**
  ```bash
  ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose ps | grep -c UP"
  # Expected: 38 or more services running
  ```

- [ ] **2. Verify git state matches main branch**
  ```bash
  ssh akushnir@192.168.168.31 "cd code-server-enterprise && git log --oneline -1"
  # Expected: Latest commit from main branch
  ```

- [ ] **3. Test HTTP connectivity to staging**
  ```bash
  curl -I https://ide.kushnir.cloud/ 2>&1 | grep HTTP
  # Expected: HTTP/2 200 or similar
  ```

- [ ] **4. Verify baseline metrics still valid**
  ```bash
  ssh akushnir@192.168.168.31 "cd code-server-enterprise && node COLLAB-9-BASELINE-LOAD-TEST.js 2>&1 | tail -20"
  # Expected: SLO MET, P99 < 100ms
  ```

- [ ] **5. Confirm monitoring infrastructure is operational**
  ```bash
  curl -s http://192.168.168.31:9090/api/v1/targets 2>&1 | grep -i "prometheus"
  # Expected: Prometheus API responding
  ```

- [ ] **6. Verify alertmanager has alert rules loaded**
  ```bash
  ssh akushnir@192.168.168.31 "docker logs alertmanager 2>&1 | tail -5 | grep -i rule"
  # Expected: Alert rules loaded successfully
  ```

- [ ] **7. Check Grafana dashboard is accessible**
  ```bash
  curl -I http://192.168.168.31:3000/api/dashboards/uid/collab-9 2>&1
  # Expected: HTTP/1.1 200 OK
  ```

- [ ] **8. Verify team is on-call and ready**
  - [ ] Infrastructure lead available
  - [ ] Operations lead on standby
  - [ ] Escalation contact list confirmed
  - [ ] Slack #incidents channel monitored

- [ ] **9. Create deployment runbook screenshot (before state)**
  ```bash
  ssh akushnir@192.168.168.31 "date && docker-compose ps && curl -I https://ide.kushnir.cloud/" > /tmp/before-deployment-state.txt
  ```

**If ANY checks fail: Stop, investigate, fix, then re-verify before proceeding.**

---

## DEPLOYMENT EXECUTION (April 26, 09:00 UTC)

### Phase 1: Pre-Deployment Window (08:00-09:00 UTC)

**0. Connect to Replica 1**
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
```

**1. Pull latest code from main branch (08:15 UTC)**
```bash
git pull origin main --ff-only
# Verify commit matches staging
git log --oneline -1
```

**2. Verify docker-compose configuration (08:20 UTC)**
```bash
# Check environment variables are correct
grep -A 5 "FEATURE_WEBHOOK_ENABLED" docker-compose.yml

# Validate compose file syntax
docker-compose config --quiet
# Expected: No output (valid config)
```

**3. Perform final health check (08:30 UTC)**
```bash
docker-compose ps | grep -c UP
# Expected: 38 services running
```

**4. Verify feature flag is DISABLED (for safety)**
```bash
# Before deployment, feature should be OFF
docker-compose exec -T code-server env | grep FEATURE_WEBHOOK || echo "Feature flag not set (safe)"
```

**5. Announce deployment window to team (08:45 UTC)**
```
Message to #incidents:
"Collab-9 Stage 2 canary deployment starting in 15 minutes. 
5% user rollout on Replica 1 primary. 
Monitoring live at Grafana. 
No user-facing downtime expected."
```

### Phase 2: Execute Deployment (09:00 UTC)

**6. Enable feature flag and deploy to Replica 1 (PRIMARY)**
```bash
# On Replica 1 (192.168.168.31)
FEATURE_WEBHOOK_ENABLED=true \
WEBHOOK_ROLLOUT_PERCENTAGE=5 \
docker-compose up -d code-server appsmith caddy

# Wait for containers to be ready
sleep 10

# Verify services are running
docker-compose ps | grep -E "(code-server|appsmith|caddy)" | grep UP
# Expected: All three services UP
```

**7. Verify HTTP connectivity immediately (09:05 UTC)**
```bash
curl -v https://ide.kushnir.cloud/ 2>&1 | head -20
# Expected: HTTP/2 200 or 302, no SSL errors
```

**8. Trigger baseline load test on Replica 1 to warm up connections (09:10 UTC)**
```bash
timeout 60 node COLLAB-9-BASELINE-LOAD-TEST.js
# Expected: SLO MET within 1 minute
```

**9. Deploy to Replica 2 (SECONDARY - feature DISABLED as safety)**
```bash
# On Replica 2 (192.168.168.42)
FEATURE_WEBHOOK_ENABLED=false \
WEBHOOK_ROLLOUT_PERCENTAGE=0 \
docker-compose up -d code-server appsmith caddy

# Wait for containers
sleep 10

# Verify
docker-compose ps | grep -E "(code-server|appsmith|caddy)" | grep UP
# Expected: All three services UP, feature disabled
```

**10. Verify load balancer is routing traffic (09:15 UTC)**
```bash
# HAProxy or Caddy should route traffic across both replicas
# Test a few requests and verify both replicas respond
for i in {1..5}; do
  curl -I https://ide.kushnir.cloud/ 2>&1 | grep HTTP
done
```

**11. Announce deployment complete (09:20 UTC)**
```
Message to #incidents:
"✅ Collab-9 Stage 2 canary deployment COMPLETE
- Feature enabled on Replica 1 (5% rollout)
- Feature disabled on Replica 2 (safety fallback)
- All services healthy
- Monitoring active in Grafana
- Next checkpoint: 12:00 UTC (3 hours)"
```

---

## MONITORING PHASE 1: First 8 Hours (09:00-17:00 UTC)

### Hourly Checklist (Execute Every 1 Hour)

**Every hour at :00 minute:**

1. **Check SLO metrics in Prometheus**
   ```bash
   # From any host with curl access to Prometheus
   curl -s 'http://192.168.168.31:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))' | jq .
   # Expected: Value < 0.1 (100ms)
   ```

2. **Verify error rate**
   ```bash
   curl -s 'http://192.168.168.31:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])' | jq .
   # Expected: Value close to 0 (< 0.5%)
   ```

3. **Check container memory usage**
   ```bash
   ssh akushnir@192.168.168.31 "docker stats --no-stream | grep -E '(code-server|appsmith|caddy)'"
   # Expected: All containers < 80% memory limit
   ```

4. **Review recent logs for errors**
   ```bash
   ssh akushnir@192.168.168.31 "docker logs --tail 50 code-server 2>&1 | grep -i error || echo 'No errors'"
   ```

5. **Record metrics in spreadsheet**
   - Timestamp
   - P99 latency (ms)
   - Error rate (%)
   - Success rate (%)
   - Active connections
   - Memory usage (%)

**If ANY metric exceeds threshold during this period:**
- [ ] Stop and investigate immediately
- [ ] Check logs and error details
- [ ] Decide: investigate further (hold) or rollback

---

## CHECKPOINT 1: 12-Hour Mark (April 26, 21:00 UTC)

**Decision Point: Continue to 25% or HOLD?**

### Checkpoint Evaluation

Review accumulated metrics over first 12 hours:

| Metric | Target | Actual | Decision |
|--------|--------|--------|----------|
| P99 Latency | < 100ms | ? | ? |
| Success Rate | > 99% | ? | ? |
| Error Rate | < 0.5% | ? | ? |
| Memory Pressure | < 80% | ? | ? |
| Database Latency | < 50ms | ? | ? |

### GO/NO-GO Decision

**✅ GO (Proceed to 25% rollout)** if:
- ✓ P99 latency consistently < 100ms
- ✓ Success rate > 99.5%
- ✓ Error rate < 0.5%
- ✓ No container restarts
- ✓ No database errors
- ✓ Load balancer routing working

**🔴 HOLD (Investigate before proceeding)** if:
- ✗ P99 latency exceeds 100ms
- ✗ Success rate drops < 99%
- ✗ Error rate > 0.5%
- ✗ Container restart loops
- ✗ Database connection errors
- ✗ Memory pressure > 80%

### If GO Decision Made

1. **Update feature flag to 25%**
   ```bash
   ssh akushnir@192.168.168.31
   cd code-server-enterprise
   
   # Edit docker-compose.yml or .env
   export WEBHOOK_ROLLOUT_PERCENTAGE=25
   
   docker-compose up -d code-server
   sleep 10
   docker-compose ps | grep code-server
   ```

2. **Announce progression**
   ```
   "#incidents: Checkpoint 1 PASSED
   Proceeding to 25% user rollout
   Continue monitoring every 2 hours"
   ```

3. **Continue monitoring (every 2 hours)**

### If HOLD Decision Made

1. **Capture diagnostics**
   ```bash
   # Collect logs, metrics, configuration
   docker logs code-server > /tmp/debug-code-server.log
   docker logs appsmith > /tmp/debug-appsmith.log
   docker stats --no-stream > /tmp/debug-stats.txt
   ```

2. **Analyze root cause**
   - Check application logs
   - Review database query performance
   - Examine network latency
   - Verify disk I/O

3. **Make remediation plan**
   - If code issue: revert and fix
   - If infrastructure issue: scale resources or optimize
   - If load too high: keep at 5% longer before progressing

4. **Announce hold status**
   ```
   "#incidents: Checkpoint 1 INVESTIGATION
   Issue identified. Team investigating.
   Keeping 5% canary active. Do not progress to 25%.
   ETA for next checkpoint: TBD"
   ```

---

## MONITORING PHASE 2: Hours 13-24 (21:00 UTC Apr 26 - 21:00 UTC Apr 27)

### 2-Hourly Checklist

(Same as hourly checklist but run every 2 hours instead)

Record metrics:
- Every 2-hour timestamp
- P99 latency, error rate, success rate
- Container resource usage
- Note any anomalies

---

## CHECKPOINT 2: 24-Hour Mark (April 27, 21:00 UTC)

**Final Decision: Proceed to Full Rollout or Rollback?**

### Metrics Review (Full 24-Hour Window)

Aggregate statistics from all monitoring intervals:

| Metric | Target | 24h Avg | 24h Max | Decision |
|--------|--------|---------|---------|----------|
| P99 Latency | < 100ms | ? | ? | ? |
| Success Rate | > 99% | ? | ? | ? |
| Error Rate | < 0.5% | ? | ? | ? |
| Memory Stability | < 80% | ? | ? | ? |
| Database Health | Stable | ? | ? | ? |

### ✅ PROCEED TO FULL ROLLOUT (100%)

If metrics meet targets:

1. **Update feature flag to 100%**
   ```bash
   ssh akushnir@192.168.168.31
   cd code-server-enterprise
   export WEBHOOK_ROLLOUT_PERCENTAGE=100
   docker-compose up -d code-server
   ```

2. **Verify all users on webhook**
   ```bash
   docker logs code-server 2>&1 | grep -i "webhook\|polling" | tail -10
   ```

3. **Announce full rollout**
   ```
   "#incidents: ✅ COLLAB-9 STAGE 2 SUCCESS
   24-hour canary PASSED all SLOs
   Progressing to 100% rollout
   Monitoring continues for Stage 3 (48h stable state)"
   ```

4. **Enter Stage 3 (Stable State Validation)**
   - Continue monitoring for next 48 hours
   - Daily checkpoint reviews
   - Ready for Phase 2 migration (WebSocket optimization)

### 🔴 ROLLBACK (Disable Feature)

If metrics fail targets:

1. **Disable webhook feature on all replicas**
   ```bash
   # Replica 1
   ssh akushnir@192.168.168.31 "cd code-server-enterprise && FEATURE_WEBHOOK_ENABLED=false docker-compose up -d code-server"
   
   # Replica 2
   ssh akushnir@192.168.168.42 "cd code-server-enterprise && FEATURE_WEBHOOK_ENABLED=false docker-compose up -d code-server"
   
   # Wait for services
   sleep 10
   ```

2. **Verify rollback successful**
   ```bash
   docker logs code-server 2>&1 | grep -i "polling" | tail -5
   # Expected: Services falling back to polling
   ```

3. **Capture post-mortem data**
   ```bash
   # Collect all logs and metrics for analysis
   docker logs code-server > /tmp/collab9-failure.log
   docker logs appsmith > /tmp/appsmith-failure.log
   # Save Prometheus metrics snapshot
   ```

4. **Announce rollback**
   ```
   "#incidents: COLLAB-9 STAGE 2 ROLLBACK
   Metrics exceeded thresholds at 24-hour mark
   Feature disabled on all replicas
   Fallback to polling active
   Post-mortem scheduled: [date/time]"
   ```

5. **Schedule post-mortem review**
   - Analyze logs and metrics
   - Identify root cause
   - Plan remediation
   - Retry Stage 2 after fixes implemented

---

## ROLLBACK PROCEDURE (Emergency)

If immediate rollback needed at ANY time:

### Quick Rollback Steps

**Step 1: Disable feature on both replicas (< 2 minutes)**
```bash
# Parallel execution on both replicas
ssh akushnir@192.168.168.31 "cd code-server-enterprise && FEATURE_WEBHOOK_ENABLED=false docker-compose up -d code-server" &
ssh akushnir@192.168.168.42 "cd code-server-enterprise && FEATURE_WEBHOOK_ENABLED=false docker-compose up -d code-server" &
wait

# Verify (should show polling logs within 30s)
sleep 30
ssh akushnir@192.168.168.31 "docker logs code-server 2>&1 | grep polling | tail -3"
```

**Step 2: Verify fallback working (< 1 minute)**
```bash
# Test HTTP connectivity
curl -I https://ide.kushnir.cloud/

# Verify error rate dropped
curl -s 'http://192.168.168.31:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[1m])'
# Expected: Error rate near 0
```

**Step 3: Announce incident status (< 1 minute)**
```
"#incidents: EMERGENCY ROLLBACK EXECUTED
Collab-9 webhook feature disabled
Fallback to polling active
Services returning to normal
Incident response team: investigate logs"
```

**Total rollback time: ~5 minutes from issue detection to full recovery**

---

## MONITORING DASHBOARD

During the entire 48-hour window, monitor these key metrics continuously:

**Dashboard URL:** http://192.168.168.31:3000/d/collab-9/collab-9-task-sync

### Key Panels to Watch

1. **P99 Latency (Red line at 100ms)**
   - Expected: Stays below 50ms during canary
   - Alert trigger: > 100ms for 5 minutes

2. **Success Rate (Green line at 99%)**
   - Expected: > 99.5%
   - Alert trigger: < 99% for 2 minutes

3. **Error Rate (Red bar chart)**
   - Expected: < 0.5%
   - Alert trigger: > 1% for 3 minutes

4. **Container Memory Usage**
   - Expected: Stable, < 50% of limits
   - Alert trigger: > 75% for 10 minutes

5. **Database Connections**
   - Expected: 10-50 active
   - Alert trigger: > 100 (pool exhaustion risk)

6. **WebSocket Connected Clients**
   - Expected: Increases as rollout % increases
   - Alert trigger: Sudden drops (reconnection issues)

---

## ESCALATION CONTACTS

If metrics exceed thresholds during deployment:

**Level 1: Engineering (On-Call)**
- Name: [Team member name]
- Slack: @oncall-engineering
- Phone: [phone number]
- Action: Investigate logs, assess severity, recommend hold/rollback

**Level 2: Infrastructure Lead**
- Name: [Infrastructure lead name]
- Slack: @infrastructure-lead
- Phone: [phone number]
- Action: Approve rollback decision, coordinate remediation

**Level 3: Operations Manager**
- Name: [Operations manager name]
- Slack: @ops-manager
- Phone: [phone number]
- Action: Make final go/no-go decisions, communicate to stakeholders

---

## POST-DEPLOYMENT

After successful 48-hour canary (if GO decision):

1. **Update documentation**
   - Add actual metrics to comparison table
   - Document any optimizations applied
   - Update runbooks with lessons learned

2. **Schedule Phase 2 WebSocket optimization**
   - Date: May 5, 2026 (after Phase 1 stabilization)
   - Feature: Disable polling fallback, require WebSocket
   - Expected SLO improvement: P99 < 20ms

3. **Archive logs and metrics**
   - Save all Prometheus scrape data
   - Archive application logs
   - Store performance reports

4. **Celebrate! 🎉**
   - Collab-9 successfully deployed to production
   - Share success metrics with team
   - Schedule retrospective to document learnings

---

## QUICK REFERENCE - Command Cheat Sheet

```bash
# Check services running
docker-compose ps | grep -E "(code-server|appsmith|caddy)" | grep UP

# View feature flag status
docker-compose exec -T code-server env | grep FEATURE_WEBHOOK

# Test latency
curl -w "@curl-format.txt" -o /dev/null -s https://ide.kushnir.cloud/

# Check error logs
docker logs code-server 2>&1 | tail -50

# Get Prometheus metrics
curl 'http://localhost:9090/api/v1/query?query=http_requests_total'

# View Grafana dashboard
open http://192.168.168.31:3000/d/collab-9/collab-9-task-sync

# Run baseline test
node COLLAB-9-BASELINE-LOAD-TEST.js

# Disable feature (emergency)
FEATURE_WEBHOOK_ENABLED=false docker-compose up -d code-server

# View live logs
docker logs -f code-server
```

---

**This runbook is your guide through the 48-hour production canary deployment. Execute it step-by-step, record metrics, make decisions at each checkpoint. Success depends on following the procedures and monitoring continuously.**

**Status: Ready for execution April 26, 2026 09:00 UTC**
