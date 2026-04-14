# Phase 13 Day 2 - EXECUTION RUNBOOK
## April 14, 2026 | 24-Hour Sustained Load Test

**Status**: 🟢 READY FOR EXECUTION
**Start**: 09:00 UTC (April 14)
**End**: ~09:00 UTC (April 15)
**Location**: 192.168.168.31 (dev-elevatediq-2)

---

## PRE-EXECUTION (07:00-09:00 UTC) - DevOps Activation

### 07:00 UTC - Team Standup & Activation
```bash
# All teams: Join Slack #code-server-phase13
# Post status: DevOps activated, standing by for execution window
```

### 08:00 UTC - FINAL PRE-FLIGHT (5-minute window)
**Performed by**: DevOps Lead on-call
**Location**: Remote SSH to 192.168.168.31

```bash
# SSH to host
ssh akushnir@192.168.168.31

# 1. DNS Verification (external team confirms)
nslookup kushin77.cloud OR dig kushin77.cloud

# 2. OAuth2 Check (external team activates)
curl -s https://kushin77.cloud/oauth/start | grep -i "status\|error"

# 3. Container Health
docker ps --format "table {{.Names}}\t{{.Status}}"
# Expected: code-server, caddy, redis, oauth2-proxy ALL HEALTHY

# 4. Network Baseline
ping -c 3 8.8.8.8 | grep "time=" | head -1

# 5. Final Log Verification
tail -20 /tmp/code-server-phase13/pre-flight.log
```

**Expected Output**: All systems HEALTHY
**Action if FAIL**: Contact VP Engineering immediately (escalation)

### 08:55 UTC - Pre-Load Test Verification
```bash
ssh akushnir@192.168.168.31

# Verify scripts are executable
chmod +x /tmp/code-server-phase13/phase-13-day2-*.sh

# Check metrics directory exists
mkdir -p /tmp/code-server-phase13/metrics

# Verify Redis connectivity
redis-cli -p 6379 PING
# Expected: PONG
```

---

## EXECUTION PHASE (09:00 UTC)

### Terminal 1: MONITORING (Start FIRST - 09:00:00 UTC)
```bash
ssh akushnir@192.168.168.31
cd /tmp/code-server-phase13

# Start monitoring (runs for ~32 hours)
bash phase-13-day2-monitoring.sh

# Expected output:
# [09:00:00] Starting Phase 13 Day 2 Monitoring
# [09:00:00] Connected to Redis: OK
# [09:00:00] Monitoring infrastructure...
# ...continuous updates every 30 seconds...
```

**Monitor checks every 30 seconds:**
- Container health (code-server, caddy, redis, oauth2-proxy)
- Memory usage
- Disk space
- Network latency (ping 8.8.8.8)
- CPU utilization
- Error log activity

### Terminal 2: ORCHESTRATOR (Start SECOND - 09:00:15 UTC)
```bash
# In new SSH session
ssh akushnir@192.168.168.31
cd /tmp/code-server-phase13

# Start orchestration (manages load test)
bash phase-13-day2-orchestrator.sh

# Expected output:
# [09:00:15] Phase 13 Day 2 Orchestrator Started
# [09:00:15] Initializing load test parameters...
# [09:00:20] Ramp-up phase starting (0-100 users)
# [09:05:00] Ramp-up complete, steady-state beginning
# [09:05:00] Maintaining 100 concurrent users
# ...continuous metrics every 60 seconds...
```

**Orchestrator manages:**
- User ramp-up (0→100 users, 5 minutes)
- Steady-state load (100 users @ 100 req/s)
- Real-time metrics collection
- SLO validation checks
- Auto-scaling decisions
- Cool-down scheduling

### Terminal 3: OBSERVATION (by Performance Team)
```bash
# Performance engineer monitors real-time metrics
# Check dashboard: [TBD - URL to Grafana/monitoring]

# Manual SLO verification every hour:
ssh akushnir@192.168.168.31
tail -100 /tmp/code-server-phase13/metrics/slo-validation.log | grep -E "PASS|FAIL|p99|error_rate"
```

---

## STEADY-STATE PHASE (09:05 UTC - next day ~09:00 UTC)

### 24-Hour Continuous Operation
**Expected behavior:**
- 100 concurrent users maintained
- ~100-150 requests/second throughput
- p99 latency: 42-89ms (baseline was 42-89ms)
- Error rate: 0.0% (baseline was 0.0%)
- Container restarts: 0
- Manual interventions: 0

### Monitoring During Steady State
**Every 1 hour**: Performance engineer checks:
```bash
# Check current SLO status
ssh akushnir@192.168.168.31
tail -5 /tmp/code-server-phase13/metrics/current-slos.txt

# Check error logs
docker logs code-server 2>&1 | grep -i "error\|exception\|fatal" | tail -10
docker logs caddy 2>&1 | grep -i "error" | tail -10
```

**Every 6 hours**: DevOps full check:
```bash
# Full infrastructure verification
docker ps -a
docker stats --no-stream
df -h /
free -h
netstat -an | grep ESTABLISHED | wc -l
```

### Incident Response (if needed during 24-hour test)

**If p99 Latency exceeds 100ms:**
1. Check container resources: `docker stats --no-stream`
2. Check host load: `top -bn1 | head -20`
3. Monitor for slowdown propagation
4. If persistent >2 min: **ESCALATE** to VP Engineering

**If Error Rate exceeds 0.1%:**
1. Check application logs: `docker logs code-server | tail -50`
2. Check network issues: `ping 8.8.8.8 -c 5`
3. Verify container connectivity: `docker ps`
4. If error rate continues >1%: **PAUSE** and escalate

**If Container Crashes:**
1. Immediately restart: `docker restart code-server`
2. Check logs for crash reason: `docker logs code-server | grep -i crash`
3. Log incident timestamp
4. **RECORD** time and reason in test log
5. Failure triggers: Detailed root cause analysis required

---

## END-OF-TEST PHASE (~09:00 UTC, April 15)

### Cool-Down (Final 10 minutes)
```bash
# Orchestrator automates cool-down
# Expected output (in Terminal 2):
# [33:55:00] Cool-down phase initiating
# [33:55:01] Reducing load: 100 → 0 users (5 min ramp)
# [34:00:00] Load test complete
# [34:00:05] Collecting final metrics...
# [34:05:00] Orchestration complete
```

### Final Data Collection
```bash
# Monitoring script finishes automatically
# Expected output (Terminal 1):
# [34:05:00] Stopping infrastructure monitoring
# [34:05:01] Final metrics collection
# [34:05:02] Data aggregation complete
```

### Analysis Window (09:00-10:00 UTC, April 15)
```bash
ssh akushnir@192.168.168.31

# 1. Generate test report
bash /tmp/code-server-phase13/phase-13-day2-analysis.sh

# 2. Verify metrics files
ls -lh /tmp/code-server-phase13/metrics/

# 3. Compare to baseline
cat /tmp/code-server-phase13/day2-vs-day1-comparison.txt
```

---

## GO/NO-GO DECISION CRITERIA

### ✅ PASS CONDITIONS (All must be true)
- **p99 Latency**: Remained < 100ms for 99%+ of test
- **Error Rate**: Remained < 0.1% throughout test
- **Throughput**: Maintained > 100 req/s
- **Availability**: Zero unplanned crashes or restarts
- **Resource Stability**: No memory leaks, disk growth normal
- **Manual Interventions**: Zero required

**Result**: 🟢 **PROCEED TO PHASE 14 (Production Go-Live)**

### 🔴 FAIL CONDITIONS (Any one triggers failure)
- **p99 Latency exceeds 100ms** for >5% of test
- **Error Rate exceeds 0.1%** at any point
- **Container crash** during test (without recovery)
- **Unscheduled restart** of core services
- **Memory leak** detected (>50% growth)
- **Manual intervention required** to maintain SLOs

**Result**: 🔴 **ROOT CAUSE ANALYSIS → FIX → RETRY (2-5 days)**

---

## POST-TEST RESPONSIBILITIES

### Immediate (within 1 hour)
- [ ] Performance: Generate final report
- [ ] DevOps: Archive all telemetry data
- [ ] Security: Verify audit logs captured
- [ ] Operations: Document any incidents

### Within 24 hours
- [ ] VP Engineering: Final GO/NO-GO decision
- [ ] Team: Post-mortem if failures occurred
- [ ] Platform: Plan Phase 14 activation (if GO)

### Within 72 hours
- [ ] All teams: Lessons learned review
- [ ] Operations: Update runbooks based on learnings
- [ ] Platform: Begin Phase 14 preparation (if GO)

---

## ESCALATION MATRIX

| Severity | Trigger | Action | Owner |
|----------|---------|--------|-------|
| 🔴 CRITICAL | Container crash during load test | IMMEDIATE pause & escalate | VP Engineering |
| 🔴 CRITICAL | Error rate > 1% sustained | PAUSE test, root cause | Platform Lead |
| 🟠 HIGH | p99 latency > 150ms | Alert team, monitor trend | DevOps Lead |
| 🟠 HIGH | Memory growth > 20% in 1 hour | Investigate, decide continue/pause | Performance Lead |
| 🟡 MEDIUM | Single metric spike (recovers) | Log incident, continue monitoring | On-call DevOps |

---

## KEY CONTACTS

**DevOps Lead On-Call**: [TBD - Configure before April 14]
**Performance Team Lead**: [TBD - Configure before April 14]
**VP Engineering**: [TBD - Escalation contact]
**Slack #code-server-phase13**: Real-time team channel
**Emergency Contact**: [TBD - Out-of-hours escalation]

---

## APPENDIX: Quick Reference

### SSH to Host
```bash
ssh akushnir@192.168.168.31
```

### Monitor logs
```bash
tail -f /tmp/code-server-phase13/orchestrator.log
tail -f /tmp/code-server-phase13/monitoring.log
```

### Kill test (emergency stop)
```bash
pkill -9 -f "phase-13-day2"
docker restart code-server caddy
```

### Collect quick metrics
```bash
docker ps
docker stats --no-stream
df -h /
free -h
```

### Check SLO status NOW
```bash
redis-cli -p 6379 GET "slo:p99_latency"
redis-cli -p 6379 GET "slo:error_rate"
```

---

**DOCUMENT VERSION**: 1.0
**LAST UPDATED**: April 13, 2026, 23:50 UTC
**AUTHOR**: Code-Server DevOps Team (Copilot-assisted)
**NEXT REVIEW**: Post-Phase 13 analysis (April 15)

---

## Sign-Off Checklist (DevOps Lead - April 14, 08:00 UTC)

- [ ] Read entire runbook
- [ ] Reviewed all pre-flight procedures
- [ ] Confirmed team availability for 24+ hour window
- [ ] Set calendar reminders (09:00, 15:00, 21:00 UTC checks)
- [ ] Configured escalation contacts
- [ ] SSH access verified to 192.168.168.31
- [ ] Terminal setup ready (3 SSH windows prepared)
- [ ] Slack notifications enabled
- [ ] Ready to execute

**Sign-Off**: ___________________  Date: ___________
