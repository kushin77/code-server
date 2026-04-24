# Performance Testing Guide - April 24-25, 2026

## Overview

This guide provides step-by-step instructions for executing the critical performance load tests that will validate system readiness for April 30 production deployment.

**Status**: Ready to Execute  
**Date**: April 24, 2026, 9:00 AM UTC  
**Expected Duration**: ~4 hours (testing + analysis)

---

## Pre-Test Setup (Apr 24, 8:00-9:00 AM UTC)

### 1. Verify Monitoring Infrastructure

```bash
# Check Prometheus
curl http://localhost:9090/-/healthy

# Check Grafana (in browser)
open http://localhost:3000/monitoring

# Verify application is running
curl http://localhost:3000/health | jq '.'
```

**Expected Output**:
- Prometheus: 200 OK
- Grafana: Dashboard loads with data
- Application: `{ "status": "ok" }`

### 2. Setup Monitoring

```bash
# Run monitoring setup script
bash scripts/performance/setup-monitoring.sh

# Expected output:
# ✅ Prometheus is healthy
# ✅ Scrape targets configured
# ✅ Application is healthy
# ✅ Monitoring queries reference created
# ✅ Test configuration created
```

### 3. Create Artifact Directories

```bash
mkdir -p artifacts/performance-tests/apr24-25/{logs,results,reports,metrics}
echo "Artifact directory created"
```

### 4. Open Monitoring Dashboards (in separate browser windows)

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000/monitoring
- **Application**: http://localhost:3000

Keep these open during tests to watch real-time metrics.

---

## Test Execution (Apr 24, 9:00 AM - 1:00 PM UTC)

### Phase 1: Baseline Test (9:00-9:15 AM UTC)

**Purpose**: Establish performance baseline with 100 concurrent users

```bash
# Run baseline test
bash scripts/performance/load-test-baseline.sh

# Expected duration: 15 minutes (2 min ramp-up + 10 min sustained + 3 min cool-down)
```

**Monitor During Test**:
- Response time in Grafana dashboard
- Error rate (should be < 0.1%)
- Memory usage (should be < 1GB)
- CPU usage (should be < 30%)

**Success Criteria**:
- ✅ p99 latency < 200ms
- ✅ Error rate < 0.1%
- ✅ Memory < 1GB
- ✅ CPU < 30%

**If Test Fails**:
1. Check logs: `artifacts/performance-tests/*/logs/baseline.log`
2. Review errors: `grep -v "200" artifacts/performance-tests/*/logs/baseline.log`
3. Check application health: `curl http://localhost:3000/health`
4. Check database: `psql $DATABASE_URL -c "SELECT 1"`

---

### Phase 2: Spike Test (9:30-9:40 AM UTC)

**Purpose**: Test system behavior under sudden traffic spike (1000 concurrent users)

```bash
# Run spike test
bash scripts/performance/load-test-spike.sh

# Expected duration: 10 minutes (30 sec ramp-up + 5 min sustained + 3 min cool-down)
```

**Monitor During Test**:
- Watch latency spike and recovery
- Monitor error rate (some errors expected)
- Watch memory and CPU peaks
- Verify system doesn't crash

**Success Criteria**:
- ✅ p99 latency < 500ms
- ✅ Error rate < 1% (some errors acceptable)
- ✅ No connection timeouts
- ✅ System recovers after spike

**If Test Fails**:
1. Application became unresponsive? Check logs: `docker logs code-server --tail 50`
2. Database connection pooled out? Check: `psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity"`
3. Memory spike? Check: `docker stats code-server`

---

### Phase 3: Sustained Load Test (10:00-10:40 AM UTC)

**Purpose**: Verify stability over extended period (30 minutes)

```bash
# Run sustained load test
bash scripts/performance/load-test-sustained.sh

# Expected duration: 38 minutes (5 min ramp-up + 30 min sustained + 3 min cool-down)
```

**Monitor During Test**:
- Check for memory leaks (memory should stay stable)
- Watch cache hit rate consistency
- Verify no performance degradation over time
- Check database replication lag

**Success Criteria**:
- ✅ Stable performance throughout
- ✅ Memory growth < 100MB
- ✅ Cache hit rate > 80% (consistent)
- ✅ Error rate < 0.1%

**Key Observation Points**:
- 5 min: System should stabilize
- 15 min: Check for memory growth
- 30 min: Verify sustained performance

**If Test Fails**:
1. Memory growing continuously? Possible memory leak. Check: `docker stats --stream code-server`
2. Performance degrading? Check: `curl http://localhost:3000/api/workspaces` (should be fast)
3. Cache hit rate dropping? Check Redis: `redis-cli INFO stats`

---

### Phase 4: Database Stress Check (11:00-11:15 AM UTC)

**Purpose**: Verify database can handle load

```bash
# Check slow queries
psql $DATABASE_URL -c "
  SELECT 
    query,
    calls,
    mean_exec_time,
    total_exec_time
  FROM pg_stat_statements 
  WHERE mean_exec_time > 100
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"

# Check active connections
psql $DATABASE_URL -c "
  SELECT 
    datname,
    usename,
    application_name,
    state,
    count(*) as connections
  FROM pg_stat_activity 
  GROUP BY datname, usename, application_name, state
  ORDER BY connections DESC;
"

# Check for deadlocks
psql $DATABASE_URL -c "
  SELECT 
    database,
    conflicts,
    confl_deadlock
  FROM pg_stat_database
  WHERE confl_deadlock > 0;
"
```

**Success Criteria**:
- ✅ No slow queries (> 100ms)
- ✅ Connection pool < 20 active
- ✅ No deadlocks
- ✅ Replication lag < 1 second

---

### Phase 5: Cache Behavior Check (11:30 AM UTC)

**Purpose**: Verify Redis cache effectiveness

```bash
# Check Redis stats
redis-cli INFO stats

# Output should show:
# keyspace_hits:XXXXX
# keyspace_misses:YYYY

# Calculate hit rate (should be > 80%)
redis-cli --eval scripts/cache-hit-rate.lua 0

# Check memory
redis-cli INFO memory

# Should show:
# used_memory_human:[value]MB (should be < 500MB)
```

**Success Criteria**:
- ✅ Cache hit rate > 80%
- ✅ Memory < 500MB
- ✅ Minimal evictions

---

## Results Analysis & Reporting (11:30 AM - 1:00 PM UTC)

### 1. Collect All Metrics

```bash
# Metrics are automatically collected in:
# artifacts/performance-tests/apr24-25/

# Review raw data
ls -lh artifacts/performance-tests/apr24-25/

# Expected structure:
# ├── logs/
# │   ├── baseline.log
# │   ├── spike.log
# │   └── sustained.log
# ├── results/
# │   ├── baseline-summary.txt
# │   ├── spike-summary.txt
# │   └── sustained-summary.txt
# └── reports/
#     └── [generated report]
```

### 2. Generate Report

```bash
# Create comprehensive report
bash scripts/performance/generate-report.sh artifacts/performance-tests/apr24-25/

# Report will include:
# - Executive summary
# - Test results summary (all 3 tests)
# - Detailed metrics tables
# - Performance graphs (Prometheus data)
# - Recommendations
```

### 3. Analyze Results Against Success Criteria

```bash
# Compare against thresholds
cat artifacts/performance-tests/apr24-25/results/analysis.txt

# Expected: PASS on all criteria
```

### 4. Document Findings

```bash
# Update GitHub issue #1474 with results
# Include:
# - Summary of all 3 tests
# - Metrics comparison table
# - Any bottlenecks or issues
# - Recommendation: GO or CAUTION
```

---

## Troubleshooting Guide

### Application Becomes Unresponsive

**Symptom**: Requests timeout or hang

```bash
# Check application logs
docker logs code-server --tail 100

# Check if service is running
docker ps | grep code-server

# Check system resources
docker stats code-server

# Restart if needed
docker restart code-server
```

### High Error Rate (> target threshold)

**Symptom**: Many HTTP 500 errors

```bash
# Check error logs
docker logs code-server --since 10m | grep ERROR

# Common causes:
# 1. Database connection pool exhausted
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity"

# 2. Cache failure
redis-cli PING

# 3. Out of memory
free -h

# 4. Disk full
df -h
```

### Memory Leak Suspected

**Symptom**: Memory continuously growing

```bash
# Monitor memory over time
watch -n 5 'docker stats --no-stream code-server | tail -1'

# If growing > 100MB per minute:
# - Check application logs for memory leak
# - May need to enable heap dumps
# - Consider scaling or code optimization
```

### Database Issues

**Symptom**: Slow queries or connection pool saturation

```bash
# Check active queries
psql $DATABASE_URL -c "SELECT pid, duration, query FROM pg_stat_activity WHERE duration > '1 min'"

# Check table sizes (may need vacuum)
psql $DATABASE_URL -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC"

# Run vacuum if needed
psql $DATABASE_URL -c "VACUUM ANALYZE"
```

---

## Success Scenarios

### Scenario A: All Tests Pass (IDEAL)
```
✅ Baseline: p99 latency 120ms, error rate 0.01%
✅ Spike: p99 latency 350ms, error rate 0.5%, recovery in 60s
✅ Sustained: Stable, memory growth 50MB, cache hit 85%

→ RECOMMENDATION: GO for production deployment
```

### Scenario B: Minor Issues, Mitigated (CONDITIONAL GO)
```
⚠️ Baseline: p99 latency 180ms (within threshold), error rate 0.05%
⚠️ Spike: p99 latency 450ms (within threshold), recovers within 90s
✅ Sustained: Stable

→ RECOMMENDATION: CONDITIONAL GO with enhanced monitoring
```

### Scenario C: Critical Issues (NO-GO)
```
❌ Baseline: p99 latency > 300ms
❌ Spike: System crashes or doesn't recover
❌ Sustained: Memory leak detected (> 200MB growth)

→ RECOMMENDATION: DELAY deployment, investigate and fix issues
```

---

## Next Steps After Testing

### If Results Are GOOD ✅
1. Document findings in GitHub issue #1474
2. Schedule team sign-offs (#1464)
3. Proceed with staging validation (#1466)
4. Target GO/NO-GO decision April 29

### If Results Need Investigation ⚠️
1. Identify specific bottleneck
2. Review application code/config
3. Plan optimization or fix
4. Re-test in 24 hours
5. Update timeline if needed

---

## Contacts & Escalation

**Test Lead**: Operations Lead  
**Issues During Test**: Slack #deployment  
**Critical Issues**: Escalate to Infrastructure Lead  

---

## Appendix: Useful Commands

```bash
# Health checks
curl http://localhost:3000/health | jq '.'

# Database health
psql $DATABASE_URL -c "SELECT now()"

# Cache health
redis-cli PING

# System resources
docker stats code-server

# Real-time logs
docker logs code-server -f

# Prometheus queries
curl "http://localhost:9090/api/v1/query?query=up"

# Grafana dashboards
open http://localhost:3000/monitoring
```

---

**Document Version**: 1.0  
**Created**: April 22, 2026  
**For**: April 24-25, 2026 Performance Tests  
**Status**: Ready for Execution
