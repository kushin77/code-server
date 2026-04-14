# PHASE 15 QUICK EXECUTION RUNBOOK

**Accuracy**: < 30 minutes total execution  
**Status**: Production-Ready  
**Owner**: Performance & DevOps Teams  
**Trigger**: Upon Phase 14 Stage 3 Completion (April 15 @ 02:55 UTC)

---

## QUICK EXECUTION OVERVIEW

Validates Redis caching + advanced observability stack in 30 minutes with focused load testing.

**Execution Pattern:**
```
T+00:00 - Setup phase (5 min)
T+05:00 - Observability deployment (5 min)
T+10:00 - Load test 300 concurrent users (5 min)
T+15:00 - Load test 1000 concurrent users (10 min)
T+25:00 - Results analysis (5 min)
T+30:00 - Go/No-Go decision
```

---

## PRE-EXECUTION CHECKLIST (T-10 min)

**Verify Production Host (192.168.168.31):**
```bash
ssh akushnir@192.168.168.31 << 'EOF'
echo "=== PRE-PHASE-15 VERIFICATION ==="
docker ps --format "table {{.Names}}\t{{.Status}}"
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3000/api/health
echo "Memory: $(free -h | grep Mem)"
echo "Disk: $(df -h /)"
EOF
```

**Checklist Items:**
- [ ] 4/6 critical containers running
- [ ] Prometheus healthy (responding to queries)
- [ ] Grafana healthy (dashboard accessible)
- [ ] Memory: > 8GB available
- [ ] Disk: > 50GB available
- [ ] Network: All IPs pingable

**Failover Host Verification:**
```bash
ssh akushnir@192.168.168.30 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

---

## PHASE 15 QUICK EXECUTION (30 minutes)

### Stage 1: Redis Cache Deployment (T+00:00 - T+05:00)

**SSH to Production Host:**
```bash
ssh akushnir@192.168.168.31
```

**Execute Deployment:**
```bash
cd ~/code-server-phase13
bash scripts/phase-15-redis-deployment.sh
```

**Expected Output:**
```
=== PHASE 15 REDIS CACHE DEPLOYMENT ===
Creating redis container...
✓ Redis 7.2 started (port 6379)
✓ Memory policy: volatile-lru (2GB max)
✓ Persistence: RDB snapshots enabled
Testing cache connection...
✓ Cache responds to PING
✓ Test key SET/GET: OK
```

**Validation:**
```bash
redis-cli -h localhost PING
# Expected: PONG

redis-cli -h localhost INFO stats | grep keyspace_hits
```

**Go/No-Go**:
- ✅ GO if redis-cli PING returns PONG
- 🔴 NO-GO if redis connection fails (redeploy)

### Stage 2: Observability Stack Deployment (T+05:00 - T+10:00)

**Execute:**
```bash
bash scripts/phase-15-advanced-observability.sh
```

**Expected Output:**
```
=== PHASE 15 OBSERVABILITY STACK ===
Creating Prometheus custom config...
✓ Custom recording rules loaded
Creating Grafana dashboards...
✓ Redis monitoring dashboard created
✓ Performance baseline dashboard created
✓ SLO tracking dashboard created
Configuring AlertManager...
✓ Alert rules for latency > 120ms
✓ Alert rules for error rate > 0.2%
✓ Alert rules for memory > 90%
```

**Validation:**
```bash
curl -s http://localhost:3000/api/search?query=redis | jq .
curl -s http://localhost:9090/api/v1/targets | jq '.data | length'
```

**Dashboard Access:**
- Grafana: http://192.168.168.31:3000 (admin/admin)
- Prometheus: http://192.168.168.31:9090

**Go/No-Go**:
- ✅ GO if both Grafana and Prometheus accessible
- 🔴 NO-GO if dashboards not loaded (check logs)

### Stage 3: 300 Concurrent User Load Test (T+10:00 - T+15:00)

**Terminal 1: Start Load Generator**
```bash
bash scripts/phase-15-load-generator.sh --users=300 --duration=5m
```

**Terminal 2: Monitor SLOs (run simultaneously)**
```bash
watch -n 5 'curl -s http://localhost:9090/api/v1/query \
  "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))" | jq .'
```

**Terminal 3: Watch Container Metrics** 
```bash
watch -n 2 'docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"'
```

**Expected Metrics at T+5:00 (300 users):**
- p99 Latency: 45-60ms
- Error Rate: 0.0%
- Throughput: 50-75 req/sec
- Memory: < 2.5GB
- CPU: < 40%

**Go/No-Go**:
- ✅ GO if p99 < 80ms and error rate = 0%
- 🔴 NO-GO if p99 > 100ms or errors detected (check redis log)

### Stage 4: 1000 Concurrent User Load Test (T+15:00 - T+25:00)

**Terminal 1: Start Heavier Load**
```bash
bash scripts/phase-15-load-generator.sh --users=1000 --duration=10m
```

**Terminal 2 & 3: Continue monitoring** (same commands as Stage 3)

**Expected Metrics During 1000-user test:**
- p99 Latency: 85-110ms (within <100ms even under load)
- Error Rate: < 0.1% (very few errors acceptable)
- Throughput: 130-150+ req/sec
- Memory: 3-4GB
- CPU: 60-75%

**Critical Observation Points:**
- T+15:00 (ramp begins): Latency should increase smoothly
- T+18:00 (peak load): Check if p99 stays under 120ms
- T+22:00 (sustained peak): Error rate should remain < 0.1%
- T+25:00 (ramp down): Should recover to baseline quickly

**Live Dashboard Check:**
- Open Grafana dashboard
- Verify "SLO Tracking" panel shows green lights
- Check "Redis Cache Hit Rate" > 70%
- Verify "Memory Utilization" < 85%

**Go/No-Go**:
- ✅ GO if p99 < 100ms and error rate < 0.1% for entire 10 min
- ⚠️ CAUTION if p99 occasionally spikes to 105-120ms but recovers
- 🔴 NO-GO if p99 sustained > 120ms or error rate > 0.2%

### Stage 5: Results Analysis (T+25:00 - T+30:00)

**Automatic Report Generation:**
```bash
bash scripts/phase-15-results-analyzer.sh
```

**Expected Report:**
```
=== PHASE 15 QUICK TEST RESULTS ===

Test Duration: 30 minutes
Load Profile: 0→300→1000 concurrent users

SLO VALIDATION:
  p50 Latency:    35ms    (target: <50ms)     ✓ PASS
  p99 Latency:    95ms    (target: <100ms)    ✓ PASS
  Error Rate:     0.02%   (target: <0.1%)     ✓ PASS
  Throughput:     145/s   (target: >100/s)    ✓ PASS
  Availability:   100%    (target: >99.9%)    ✓ PASS

RESOURCE UTILIZATION:
  Peak Memory:    78%     (target: <85%)      ✓ PASS
  Peak CPU:       71%     (target: <80%)      ✓ PASS
  Disk I/O:       Normal  (no anomalies)      ✓ PASS

CACHE PERFORMANCE:
  Redis Hit Rate: 74%     (target: >70%)      ✓ PASS
  Cache Latency:  <2ms    (overhead minimal)  ✓ PASS

DECISION: 🟢 GO FOR EXTENDED TESTING

Recommendation: Phase 15 infrastructure validated. 
  Ready for Phase 16 scaling procedures.
  Ready for Phase 15 Extended (24h) if needed.
```

---

## GO/NO-GO DECISION FRAMEWORK

### Success Criteria (ALL must pass)

```
PHASE 15 QUICK TEST PASS:
✓ p99 Latency < 100ms (500 & 1000 user stages)
✓ Error Rate < 0.1% (during peak load)
✓ Availability 100% (no unplanned downtime)
✓ Cache hit rate > 70%
✓ Memory < 85% peak
✓ CPU < 80% peak
✓ No container restarts during test
✓ Failover tested and responding
```

### Guidance for Results

**If All PASS (Green):**
```
🟢 EXCELLENT - Professional Grade Performance

Actions:
1. Phase 15 infrastructure: VALIDATED ✓
2. Phase 16 scaling: APPROVED ✓
3. Continue Phase 15 Extended (24h) - OPTIONAL
4. Document results to #phase-15-results
5. Decomission Phase 14 standby (optional)
6. Proceed to Phase 16 onboarding
```

**If Most PASS with Minor Issues (Yellow):**
```
🟡 ACCEPTABLE - Monitor & Proceed

Actions:
1. Note specific areas of concern
2. Schedule targeted tuning (24-48h)
3. Phase 16 scaling: PROCEED WITH CAUTION
4. Increase monitoring intensity
5. Run Phase 15 Extended for deeper validation
6. Document findings for future reference
```

**If Some FAIL (Red):**
```
🔴 BLOCKER - Investigate & Retry

Failure Triggers: Any SLO not met consistently

Actions:
1. Begin root cause analysis
   - Check Redis logs for errors
   - Verify network connectivity
   - Review container resource limits
2. Document failure mode
3. Create fix plan
4. Re-run Phase 15 Quick after fixes (24h delay min)
5. Do NOT proceed to Phase 16 until PASS
```

---

## QUICK REFERENCE COMMANDS

### Emergency Abort
```bash
# Stop load generator
pkill -f "phase-15-load-generator"

# Revert to Phase 14 state
terraform apply -var=phase_15_enabled=false -auto-approve
```

### Logs Access
```bash
# Redis logs
docker logs redis

# Application logs
docker logs code-server

# Prometheus logs
tail -f /var/log/prometheus.log
```

### Metric Queries (useful for debugging)
```bash
# Current p99 latency
curl 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.99, http_request_duration_seconds_bucket)'

# Error rate
curl 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(http_requests_total{job="code-server"}[5m])'

# Cache hit rate
curl 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=redis_keyspace_hits_total'
```

### Reset & Retry
```bash
# Full cleanup
docker-compose -f docker-compose-phase-15.yml down -v

# Redeploy Phase 15
docker-compose -f docker-compose-phase-15.yml up -d
bash scripts/phase-15-master-orchestrator.sh --quick
```

---

## TIMELINE EXECUTION CHECKLIST

- [ ] T-10 min: Pre-execution verification complete
- [ ] T+00:00: Redis deployment started
- [ ] T+05:00: Observability stack deployed
- [ ] T+10:00: 300-user load test started
- [ ] T+15:00: 1000-user load test started
- [ ] T+25:00: Results analysis started
- [ ] T+30:00: Final go/no-go decision reached
- [ ] T+30:05: Results posted to #phase-15-results
- [ ] T+30:10: Next phase trigger (Phase 16 or Extended)

---

## POST-EXECUTION DOCUMENTATION

**All results automatically archived to:**
- Metrics archive: `/metrics/phase-15-quick-[timestamp].json`
- Dashboard snapshots: `/dashboards/phase-15-quick-[timestamp]/`
- Performance report: `/reports/phase-15-quick-results-[timestamp].md`

**Slack notification (auto-posted to #phase-15-results):**
- Test duration
- SLO compliance status
- Recommendation for next phase
- Link to full results dashboard

---

**READY FOR 30-MINUTE QUICK EXECUTION**

Phase 15 quick test is fully automated with human oversight at go/no-go points.
Trigger: Automatically on April 15 @ 02:55 UTC (upon Phase 14 Stage 3 completion)
