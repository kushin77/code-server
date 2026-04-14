# Phase 13 Day 2: 24-Hour Sustained Load Testing
## Execution Checklist - April 14, 2026

### 📋 Pre-Execution (April 13, 5:00 PM UTC)

#### Infrastructure Status Verification
- [x] code-server container running and healthy
- [x] caddy container running and healthy
- [x] oauth2-proxy container running and healthy
- [x] redis container running and healthy
- [⚠️] ssh-proxy container status: Restarting (exit code 0, not blocking)
- [x] Available memory: ~29GB sufficient
- [x] Available disk: ~54GB sufficient

#### Phase 13 Orchestration Scripts
- [x] `/scripts/phase-13-day2-orchestrator.sh` exists and verified
- [x] `/scripts/phase-13-day2-monitoring.sh` exists and verified
- [x] SLO targets defined: p99 <100ms, error rate <0.1%, throughput >100 req/s
- [x] Load test duration configured: 24 hours (86,400 seconds)
- [x] Ramp-up period configured: 5 minutes (0 → 100 concurrent users)
- [x] Health check interval: 30 seconds
- [x] Logging configured to `/tmp/phase-13-day2/`

#### Team Communication Setup
- [ ] Slack channel #phase-13-execution created/active
- [ ] Team briefing email sent with timeline
- [ ] On-call team confirmed for April 14-15 monitoring
- [ ] Escalation contacts updated
- [ ] Incident response team on standby

---

### ⏰ Execution Timeline (April 14, 2026)

#### Pre-Start Preparations (08:00 - 08:55 UTC)
**[ ] 08:00 UTC** - Team assembles, final readiness check
- [ ] All team members logged into Slack
- [ ] SSH access to 192.168.168.31 verified
- [ ] Terminal windows prepared
- [ ] Dashboards/monitoring tools loaded in browser

**[ ] 08:15 UTC** - Final infrastructure pre-flight
```bash
ssh akushnir@192.168.168.31 "docker ps | grep -E 'code-server|caddy|oauth2|redis'"
# Expected: All 4 main services UP and healthy
```

**[ ] 08:20 UTC** - Verify code-server health endpoint
```bash
ssh akushnir@192.168.168.31 "curl -sf http://localhost:8080/"
# Expected: HTTP 200 response
```

**[ ] 08:30 UTC** - Check available metrics and logging infrastructure
- [ ] `/tmp/phase-13-day2/` directory exists
- [ ] Previous logs (if any) backed up
- [ ] Metrics collection path verified
- [ ] Logging format verified

**[ ] 08:45 UTC** - Final go/no-go decision
- [ ] Infrastructure: GO ✓
- [ ] Team ready: GO ✓
- [ ] Monitoring ready: GO ✓
- [ ] **DECISION**: PROCEED ✓

**[ ] 08:55 UTC** - Announce start in Slack: "Beginning Phase 13 Day 2 execution in 5 minutes"

#### Phase 1: Execution Start (09:00 - 09:05 UTC)
**[ ] 09:00 UTC Sharp** - Launch orchestrator (Terminal 1)
```bash
cd /tmp/code-server-phase13
bash phase-13-day2-orchestrator.sh &
# Logs to: /tmp/phase-13-day2/results-*.txt
```

**[ ] 09:01 UTC** - Launch monitoring (Terminal 2)
```bash
ssh akushnir@192.168.168.31 "bash /tmp/code-server-phase13/phase-13-day2-monitoring.sh"
# Continuous health monitoring for 24+ hours
```

**[ ] 09:02 UTC** - Setup metrics collection (Terminal 3)
```bash
ssh akushnir@192.168.168.31 "tail -f /tmp/phase-13-day2/metrics-*.txt"
# Real-time metrics streaming
```

**[ ] 09:03 UTC** - Slack update: System ramping, monitoring in-flight
- [ ] Post: "System load test started. Ramping from 0 → 100 concurrent users. ETA 09:08 UTC full capacity."

**[ ] 09:05 UTC** - Ramp-up phase begins
- Expected: ~1 user per second for 5 minutes
- Monitor for any errors/latency spikes during ramp
- [ ] p99 latency trending: Should remain <100ms
- [ ] Error rate trending: Should remain <0.1%

#### Phase 2: Steady State (09:05 - 09:20 UTC, continuing through April 15 10:00 UTC)
**[ ] 09:10 UTC** - Steady state begins (100 concurrent users)
- [ ] Metrics stabilizing
- [ ] Error rate <0.1%
- [ ] p99 latency <100ms
- [ ] No pod restarts

**[ ] 09:15 UTC** - Post interim status to Slack
- "✅ Steady state achieved. 100 concurrent users. Metrics nominal. Monitoring: ON"

**[ ] Every 4 hours** - Checkpoint reports (automated or manual)
- Checkpoint times:
  - [ ] 09:00 UTC (Start)
  - [ ] 13:00 UTC (4h)
  - [ ] 17:00 UTC (8h)
  - [ ] 21:00 UTC (12h)
  - [ ] 01:00 UTC April 15 (16h)
  - [ ] 05:00 UTC April 15 (20h)

Each checkpoint verification:
```
Infrastructure:
  - code-server: [UP/DOWN]
  - caddy: [UP/DOWN]
  - Memory: [%Used/%Available]
  - Disk: [%Used/%Available]

Metrics:
  - p99 Latency: [___ ms]  (target: <100ms)
  - Error Rate: [___%]    (target: <0.1%)
  - Throughput: [___ req/s] (target: >100)
  - Pod Restarts: [__]   (target: 0)

Status: [✓ NOMINAL / ⚠️ WARNING / ✗ CRITICAL]
```

---

### ⏹️ Cool-Down & Wrap-Up (April 15, 10:00 UTC)

**[ ] 10:00 UTC** - Begin cool-down phase
```bash
# Monitor will automatically start ramp-down: 100 → 0 concurrent users
# Duration: ~5 minutes
```

**[ ] 10:05 UTC** - Cool-down complete, metrics collection stops
- [ ] Orchestrator has completed and logged results
- [ ] Monitoring has stopped
- [ ] All logs preserved in `/tmp/phase-13-day2/`

**[ ] 10:15 UTC** - Analysis begins
- [ ] Compare Day 2 metrics to Day 1 baseline
- [ ] Generate summary report
- [ ] Identify any anomalies or performance issues
- [ ] Determine go/no-go for Day 3

#### Analysis Tasks
- [ ] p99 Latency comparison
- [ ] Error rate trend analysis
- [ ] Resource utilization review
- [ ] Pod stability report (restarts, crashes)
- [ ] Performance deviations identified

**[ ] 12:00 UTC** - Final go/no-go decision
- [ ] All metrics reviewed
- [ ] Requirements met: YES/NO
  - p99 latency <100ms: [✓/✗]
  - Error rate <0.1%: [✓/✗]
  - Zero pod restarts: [✓/✗]
  - All services stable: [✓/✗]
- [ ] Decision: **[GO to Day 3 / NO-GO - Debug Required]**

**[ ] 12:30 UTC** - Post final update to GitHub issue #210 with results link
- Summary of 24-hour test
- Metrics CSV download link
- Go/No-Go decision
- Next steps

---

### 🚨 Escalation Procedures

#### Critical Issues During Load Test

**If p99 latency exceeds 200ms for 5+ minutes:**
1. [ ] Screenshot alerting dashboard
2. [ ] Post urgent Slack message: "@channel p99 latency elevated: ___ms"
3. [ ] Check resource utilization (CPU, memory)
4. [ ] Enter debugging mode: reduce load to 50 concurrent users
5. [ ] Investigate root cause
6. [ ] Page infrastructure lead if needed

**If error rate exceeds 1% for any period:**
1. [ ] Immediately capture error logs
2. [ ] Post urgent message to Slack
3. [ ] Reduce load to minimum to stabilize
4. [ ] Review error types and frequency
5. [ ] Investigate application errors
6. [ ] Page application team lead

**If any container crashes or restarts:**
1. [ ] Immediately note timestamp and container name
2. [ ] Capture logs: `docker logs [container-name]`
3. [ ] Post alert to Slack with container details
4. [ ] Restart container if needed
5. [ ] Investigate root cause immediately
6. [ ] Document in incident log

**If disk or memory becomes critically low (<10% available):**
1. [ ] Pause load test
2. [ ] Investigate disk/memory leaks
3. [ ] Clean up if possible or restart containers
4. [ ] Resume load test
5. [ ] Mark as warning condition in final report

---

### 📊 Success Criteria (MUST ALL PASS)

- [ ] **Latency**: p99 latency remained <100ms throughout 24-hour test
- [ ] **Reliability**: Error rate stayed <0.1% (no spike > 1%)
- [ ] **Stability**: Zero container restarts or crashes
- [ ] **Autonomy**: No manual intervention required during test
- [ ] **Instrumentation**: All metrics logged continuously
- [ ] **Completeness**: 24+ hours of clean load test data collected

#### If ALL criteria pass:
✅ **PHASE 13 DAY 2: PASSED** → Proceed to Days 3-7 production validation

#### If ANY criterion fails:
❌ **PHASE 13 DAY 2: FAILED** → Debug and retry; may require infrastructure tweaks

---

### 📁 Artifacts & Log Locations

After execution, all results will be in: `/tmp/phase-13-day2/`

Key files:
- `results-*.txt` - Main execution log
- `metrics-*.txt` - Raw metrics data
- `latencies-*.txt` - Latency samples
- `health-*.txt` - Container health checks

### 📤 Handoff for Days 3-7

Upon successful completion of Day 2, proceed to:
- **Day 3**: Security validation + performance validation
- **Day 4-5**: Developer onboarding + monitoring setup
- **Day 6**: On-call readiness + runbook training
- **Day 7**: Production go-live

See issue #199 for full Phase 13 production rollout plan.

---

### ✅ Sign-Off

- [ ] Checklist reviewed by Infrastructure Lead
- [ ] Checklist reviewed by DevOps Lead
- [ ] Team briefed on execution plan
- [ ] All prerequisites met
- [ ] **READY FOR APRIL 14, 09:00 UTC EXECUTION** ✓

**Prepared by**: GitHub Copilot
**Prepared on**: April 13, 2026 22:45 UTC
**Review date**: April 14, 2026 08:00 UTC

---

## Quick Reference - Copy-Paste Commands

### Start Monitoring (Terminal 1)
```bash
ssh akushnir@192.168.168.31 "cd /tmp/code-server-phase13 && bash phase-13-day2-monitoring.sh"
```

### Start Orchestrator (Terminal 2)
```bash
ssh akushnir@192.168.168.31 "cd /tmp/code-server-phase13 && bash phase-13-day2-orchestrator.sh"
```

### Watch Metrics in Real-Time (Terminal 3)
```bash
ssh akushnir@192.168.168.31 "tail -f /tmp/phase-13-day2/metrics-*.txt"
```

### Check Container Health
```bash
ssh akushnir@192.168.168.31 "docker ps --all"
```

### View Recent Logs
```bash
ssh akushnir@192.168.168.31 "ls -lrt /tmp/phase-13-day2/ | tail"
```
