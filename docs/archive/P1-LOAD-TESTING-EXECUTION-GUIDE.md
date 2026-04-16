# P1 Load Testing Guide & Execution Manual

**Status**: ✅ Ready for execution  
**Date**: April 15, 2026  
**Tests**: Baseline (1x), Spike (5x), Chaos (failure injection)  
**Target Duration**: 9 hours total (3 hours per test phase)  

---

## Quick Start

### Prerequisites

1. **k6 installed**: `k6 version` (or install from https://k6.io/docs/getting-started/installation/)
2. **Production environment stable**: All 11/11 services healthy on 192.168.168.31
3. **Network access**: Can reach 192.168.168.31:8080 from test location
4. **No active deployments**: Wait for any pending changes to settle

### Install k6

**macOS**:
```bash
brew install k6
```

**Linux**:
```bash
sudo apt-get install k6  # Debian/Ubuntu
or
yum install k6           # RHEL/CentOS
```

**Windows (PowerShell)**:
```powershell
choco install k6  # Via Chocolatey
```

### Verify Installation

```bash
k6 version
# Output: k6 v0.x.x
```

---

## Test Execution Plan

### Phase 1: Baseline Load Test (1x Load)

**Purpose**: Establish performance baseline under normal load  
**Duration**: ~7 minutes (1 min ramp-up + 3 min hold + 1 min ramp-down + overhead)  
**Load**: 50 VUs (virtual users)  
**Endpoint**: 192.168.168.31:8080 (production)

**Run command**:
```bash
k6 run tests/p1-baseline-load-test.js \
  --vus 50 \
  --duration 5m
```

**Expected Results** (PASS Criteria):
- ✅ p99 latency: <50ms
- ✅ Average latency: <40ms
- ✅ Error rate: <1%
- ✅ All health checks: PASS

**What to Watch For**:
- Response time should be consistent (not increasing over time)
- No 5xx errors (service degradation)
- CPU/memory usage on production stays <80%

**Troubleshooting**:
- **All requests failing**: Verify connectivity to 192.168.168.31:8080
- **High latency (>100ms)**: Check production load, network congestion
- **Connection errors**: Ensure oauth2-proxy/caddy services are running

### Phase 2: Spike Load Test (5x Load)

**Purpose**: Verify system handles sudden traffic surge without degradation  
**Duration**: ~3 minutes (10s ramp-up + 2 min hold + 30s ramp-down)  
**Load**: 250 VUs (sudden spike from 0)  
**Endpoint**: 192.168.168.31:8080

**Run command**:
```bash
k6 run tests/p1-spike-load-test.js \
  --vus 250 \
  --ramp-up 10s \
  --duration 2m
```

**Expected Results** (PASS Criteria):
- ✅ p99 latency: <100ms (relaxed threshold under load)
- ✅ Average latency: <80ms
- ✅ Error rate: <1%
- ✅ Connection pool exhaustion: <5%

**What to Watch For**:
- Latency spike during VU ramp-up (expected)
- Recovery time when ramp-down starts (should drop quickly)
- Any 503 (Service Unavailable) errors (indicates overload)

**Troubleshooting**:
- **Sustained high latency (>200ms)**: Connection pool may be exhausted
- **503 errors >5%**: Database or backend services struggling
- **Request timeouts**: Increase timeout in spike-load-test.js

### Phase 3: Chaos Load Test (Failure Injection)

**Purpose**: Verify graceful degradation and recovery after backend failures  
**Duration**: ~3 minutes (1 min normal + 30s chaos + 1 min recovery)  
**Load**: 50 VUs (normal load)  
**Scenarios**: Database down, connection pool exhausted, timeout

**Run command**:
```bash
k6 run tests/p1-chaos-load-test.js \
  --vus 50 \
  --duration 3m \
  --env FAILURE_START=60 \
  --env FAILURE_DURATION=30
```

**Expected Results** (PASS Criteria):
- ✅ Recovery time (p99): <30 seconds
- ✅ Circuit breaker trips: >0 (detected failures)
- ✅ Fallback responses: >0 (used fallback gracefully)
- ✅ Error rate during chaos: <10% (acceptable under failure)
- ✅ Error rate after recovery: <1% (returns to normal)

**What to Watch For**:
- Circuit breaker should trip during chaos window (503 responses)
- Fallback endpoint (/api/users/cached) should respond with cached data
- Services should recover fully within 30 seconds after chaos ends

**Troubleshooting**:
- **Circuit breaker not tripping**: Check circuit-breaker-service.js implementation
- **No fallback responses**: Verify caching layer is functional (Redis)
- **Recovery time >30s**: Check database startup time, connection pool reset

---

## Full Test Run (Sequential)

To run all three tests in sequence with logging:

```bash
#!/bin/bash
# run-all-p1-tests.sh

set -e
LOG_DIR="./test-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== P1 Load Testing Suite (3-part execution) ==="
echo "Results saved to: $LOG_DIR"

# Phase 1: Baseline
echo -e "\n[1/3] Running baseline load test..."
k6 run tests/p1-baseline-load-test.js \
  --vus 50 \
  --duration 5m \
  --out json="$LOG_DIR/baseline-results.json" \
  > "$LOG_DIR/baseline-output.txt" 2>&1

echo "✅ Baseline complete. Results in $LOG_DIR/baseline-results.json"

# Pause between tests
sleep 30

# Phase 2: Spike
echo -e "\n[2/3] Running spike load test..."
k6 run tests/p1-spike-load-test.js \
  --vus 250 \
  --out json="$LOG_DIR/spike-results.json" \
  > "$LOG_DIR/spike-output.txt" 2>&1

echo "✅ Spike test complete. Results in $LOG_DIR/spike-results.json"

# Pause between tests
sleep 30

# Phase 3: Chaos
echo -e "\n[3/3] Running chaos load test..."
k6 run tests/p1-chaos-load-test.js \
  --vus 50 \
  --out json="$LOG_DIR/chaos-results.json" \
  > "$LOG_DIR/chaos-output.txt" 2>&1

echo "✅ Chaos test complete. Results in $LOG_DIR/chaos-results.json"

echo -e "\n=== All Tests Complete ===\n"
echo "Results saved to: $LOG_DIR/"
ls -lh "$LOG_DIR/"
```

**Run full suite**:
```bash
bash run-all-p1-tests.sh
```

---

## Performance Metrics & Thresholds

### P1 Success Gates (All Must PASS)

| Metric | Baseline | Spike | Chaos | Gate |
|--------|----------|-------|-------|------|
| **p99 Latency** | <50ms | <100ms | <50ms (post-recovery) | PASS if all met |
| **Error Rate** | <1% | <1% | <10% (chaos), <1% (recovery) | PASS if all met |
| **Dedup Ratio** | >20% | >20% | N/A | PASS if met |
| **Cache Hit Rate** | >40% | >40% | N/A | PASS if met |
| **Connection Reuse** | >90% | >90% | >85% (chaos load) | PASS if met |
| **Recovery Time** | N/A | N/A | <30s | PASS if met |
| **Pool Exhaustion** | <1% | <5% | <10% | PASS if met |

### Interpretation

**PASS**: All thresholds met → Proceed to merge  
**FAIL**: Any threshold missed → Debug and iterate  
**UNKNOWN**: Missing metrics → Re-run with metrics collection enabled

---

## Monitoring During Tests

### Real-Time Dashboard (Optional)

If production has Grafana (port 3000) running:

1. Open http://192.168.168.31:3000 (admin/admin123)
2. View "System Metrics" dashboard
3. Monitor:
   - CPU usage (should stay <80%)
   - Memory usage (should stay <70%)
   - Database connection count (should stay <20)
   - Request latency (should match k6 reports)

### Production SSH Monitoring

```bash
ssh akushnir@192.168.168.31

# Watch service health
watch -n 2 'docker-compose ps --format "table {{.Names}}\t{{.Status}}"'

# Watch resource usage
docker stats --no-stream

# Monitor postgres connection count
docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Monitor redis memory
docker exec redis redis-cli INFO memory
```

---

## After Tests Complete

### 1. Analyze Results

```bash
# View baseline results
cat test-results/*/baseline-output.txt

# Extract summary
grep -E "^(✓|✗|ERROR)" test-results/*/baseline-output.txt

# Compare baselines (if running multiple times)
# Watch for regression from first baseline run
```

### 2. Validate Success Gates

**Checklist**:
- [ ] Baseline p99 < 50ms? ✅
- [ ] Baseline error rate < 1%? ✅
- [ ] Spike handles 5x load without >1% errors? ✅
- [ ] Chaos recovers in <30 seconds? ✅
- [ ] All 2+ peer reviews passed? ✅
- [ ] SAST security scan clean? ✅

### 3. Decision: Merge or Iterate

**PASS ALL GATES** → Ready for merge:
```bash
git checkout dev
git pull origin dev
git merge feat/elite-p1-performance
git push origin dev
```

**FAIL ANY GATE** → Debug and iterate:
1. Identify failed threshold
2. Check P1 services for implementation issues:
   - `services/request-deduplication-layer.js` — Cache working?
   - `services/db-connection-pool.py` — Pool size correct?
   - `frontend/src/hooks/useUserManagement.ts` — N+1 queries fixed?
   - `services/api-caching-middleware.js` — ETags working?
3. Fix issue locally
4. Re-run tests
5. Repeat until all gates pass

---

## Advanced: Custom Test Runs

### Higher Load for Stress Testing

```bash
# Extreme stress: 1000 VUs for 10 minutes
k6 run tests/p1-baseline-load-test.js \
  --vus 1000 \
  --duration 10m
```

### Specific Endpoint Testing

```bash
# Create custom test targeting specific endpoint
k6 run --script='
import http from "k6/http";
import { check } from "k6";
export default function() {
  let res = http.get("http://192.168.168.31:8080/api/users");
  check(res, {"status 200": (r) => r.status === 200});
}' \
  --vus 100 \
  --duration 1m
```

### Distributed Load Testing

For large-scale testing from multiple hosts:

```bash
# Host 1 (50 VUs)
k6 run tests/p1-baseline-load-test.js --vus 50 --duration 5m

# Host 2 (50 VUs)
k6 run tests/p1-baseline-load-test.js --vus 50 --duration 5m

# Total: 100 VUs from 2 hosts
# Useful for saturating multi-core systems
```

---

## Troubleshooting Common Issues

### "Connection Refused"
**Cause**: Can't reach 192.168.168.31:8080  
**Fix**: 
```bash
curl -v http://192.168.168.31:8080/health
# Should return 200 OK
```

### "All Requests Failed"
**Cause**: Service down or misconfigured  
**Fix**:
```bash
ssh akushnir@192.168.168.31 "docker-compose ps"
# Verify all 10 services are running
```

### "High Latency (>500ms)"
**Cause**: Backend struggling or network congestion  
**Fix**:
```bash
# Check production load
ssh akushnir@192.168.168.31 "docker stats"

# Check connection pool size
docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

### "Circuit Breaker Not Tripping in Chaos"
**Cause**: Circuit breaker may not be detecting failures  
**Fix**:
```bash
# Verify circuit-breaker-service.js is running
curl http://192.168.168.31:8080/api/circuit-breaker/status

# Check log output
docker logs code-server | grep -i circuit
```

---

## Success Criteria Summary

**P1 READY FOR MERGE WHEN:**

✅ Baseline test PASS (all thresholds met)  
✅ Spike test PASS (handles 5x without degradation)  
✅ Chaos test PASS (recovers <30s after failures)  
✅ 2+ peer code reviews completed  
✅ SAST security scan clean  
✅ All 4 P1 services integrated (dedup, pooling, N+1, caching)  
✅ Production health verified (11/11 services)  

**Timeline**: Baseline (7 min) + Spike (4 min) + Chaos (4 min) = ~15 minutes execution time + analysis

---

## Next Steps After Merge

1. Monitor production metrics for 24 hours post-merge
2. Compare actual vs. expected improvements
3. Document any deviations
4. Proceed to P2 (file consolidation) on April 16

---

**P1 Load Testing: READY FOR EXECUTION**  
**Estimated Completion**: April 15, 2026 (3-4 hours total execution)  
**Status**: All test scripts created, production environment verified, ready for go/no-go decision
