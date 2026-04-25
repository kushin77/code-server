# Phase 3: Resource Limits Validation & Testing

**Date**: April 26, 2026  
**Phase**: 3 of 4  
**Duration**: 2-3 hours  
**Effort Level**: Medium (automated testing)  
**Risk Level**: Low (read-mostly, limited state changes)  

---

## Overview

Phase 3 validates that resource limits are properly enforced and don't negatively impact service performance. All tests are automated with detailed reporting.

---

## Testing Objectives

✅ **Memory Limits Enforcement**: Verify containers cannot exceed memory limits  
✅ **CPU Throttling**: Confirm CPU limits prevent runaway processes  
✅ **Performance Baseline**: Document performance with limits applied  
✅ **Service Stability**: Ensure no crashes or restarts due to limits  
✅ **Error Logging**: Check for OOMKilled or CPU throttle warnings  
✅ **Monitoring Data**: Verify metrics collection with limits  

---

## Test Suite 1: Memory Limits Enforcement (30 minutes)

### Objective
Verify that containers are prevented from exceeding memory limits and that memory pressure is handled gracefully.

### Test 1.1: PostgreSQL Memory Pressure Test

```bash
# Generate memory pressure in PostgreSQL
docker-compose exec postgres psql -U postgres << 'EOF'
-- Create temporary large table
CREATE TEMP TABLE stress AS
SELECT generate_series(1, 100000000) AS id, 
       md5(random()::text) AS data;

-- Monitor memory usage
SELECT * FROM pg_stat_statements WHERE query LIKE '%stress%' LIMIT 10;

-- Verify query completes without OOMKilled
DROP TABLE stress;
EOF

# Expected Result: Query completes OR gracefully errors with memory exceeded
# NOT EXPECTED: Container restart, OOMKilled event
```

### Test 1.2: Redpanda Memory Test

```bash
# Monitor Redpanda memory during message throughput
docker stats redpanda --no-stream | head -5

# Generate load
docker-compose exec redpanda rpk topic create test-memory -p 3 -r 1

# Publish high volume messages
for i in {1..100000}; do 
  echo "Message $i" | docker-compose exec -T redpanda rpk topic produce test-memory
done

# Verify memory stays within limit
docker stats redpanda --no-stream
```

### Test 1.3: Vector Database Memory Test

```bash
# Test Qdrant memory with vector operations
curl -s -X POST http://localhost:6333/collections/test-memory/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 1, "vector": [0.05, 0.61], "payload": {"field": "value"}},
      {"id": 2, "vector": [0.19, 0.81], "payload": {"field": "value"}}
    ]
  }'

# Monitor memory
docker stats qdrant-vectors --no-stream
```

### Validation Checklist
- [ ] PostgreSQL memory usage stays below 8GB limit
- [ ] Redpanda memory usage stays below 4GB limit
- [ ] Qdrant memory usage stays below 4GB limit
- [ ] No OOMKilled events in docker events
- [ ] Services remain healthy after memory pressure

---

## Test Suite 2: CPU Throttling Verification (30 minutes)

### Objective
Verify CPU limits prevent runaway processes and maintain fair scheduling.

### Test 2.1: CPU Throttling Metric Check

```bash
# Query Prometheus for CPU throttle metrics
curl -s 'http://localhost:9090/api/v1/query?query=container_cpu_cfs_throttled_cpu_usage_seconds_total' \
  | jq '.data.result[] | {container: .metric.container_name, throttle_time: .value[1]}'

# Expected: Minimal throttle time (<100ms) for services not under load
```

### Test 2.2: Scheduler CPU Load Test

```bash
# Generate CPU load in scheduler
docker-compose exec scheduler sh -c 'for i in {1..1000}; do 
  python -c "sum(i*i for i in range(100000))" 
done'

# Monitor CPU usage (should cap at 2 cores / 200%)
docker stats scheduler --no-stream

# Verify query completion and no crashes
```

### Test 2.3: API Service CPU Response Time

```bash
# Baseline response time (before CPU load)
for i in {1..10}; do
  time curl -s http://localhost:3100/api/health > /dev/null
done

# Generate sustained CPU load in background
docker-compose exec scheduler sh -c 'while true; do 
  python -c "sum(i*i for i in range(1000000))" 
done' &

# Measure response time under load
for i in {1..10}; do
  time curl -s http://localhost:3100/api/health > /dev/null
done

# Expected: Response time degradation <50% (still acceptable)
# NOT EXPECTED: Service hangs or timeouts
```

### Validation Checklist
- [ ] CPU throttling active when services exceed limits
- [ ] CPU throttling doesn't cause crashes
- [ ] Response times degrade gracefully under load
- [ ] Services remain responsive with <50% degradation
- [ ] No persistent errors in logs

---

## Test Suite 3: Performance Baseline (30 minutes)

### Objective
Document performance characteristics with resource limits applied.

### Test 3.1: Database Query Performance

```bash
# Run query performance tests
docker-compose exec postgres psql -U postgres -d paperclip << 'EOF'
-- Simple SELECT (should complete in <100ms)
\timing
SELECT COUNT(*) FROM users;

-- Complex JOIN (should complete in <500ms)
SELECT COUNT(*) FROM users u 
JOIN user_sessions us ON u.id = us.user_id;

-- Aggregation query
SELECT status, COUNT(*) FROM users GROUP BY status;
EOF

# Record baseline latencies
```

### Test 3.2: API Response Time Baseline

```bash
# Test various endpoints
endpoints=(
  "http://localhost:3100/api/health"
  "http://localhost:3100/api/agents"
  "http://localhost:3100/api/metrics"
)

for endpoint in "${endpoints[@]}"; do
  echo "Testing: $endpoint"
  for i in {1..5}; do
    /usr/bin/time -f "%E elapsed" curl -s "$endpoint" > /dev/null
  done
done

# Record baseline response times
```

### Test 3.3: Message Broker Throughput

```bash
# Test Redpanda message throughput
docker-compose exec redpanda rpk topic create perf-test -p 3 -r 1

# Produce messages and measure throughput
docker-compose exec redpanda rpk topic produce perf-test \
  -H 'key:test' \
  -n 10000 \
  --ms-between-messages 1

# Consume and measure throughput
docker-compose exec redpanda rpk topic consume perf-test \
  --from-beginning \
  --num 10000 | tail -10

# Expected: >1000 messages/sec throughput
```

### Validation Checklist
- [ ] Database query latency within acceptable range
- [ ] API response time baseline documented
- [ ] Message broker throughput acceptable
- [ ] No performance regressions vs. Phase 1
- [ ] All measurements logged

---

## Test Suite 4: Service Stability (30 minutes)

### Objective
Verify no unexpected crashes, restarts, or errors due to resource limits.

### Test 4.1: Service Uptime Verification

```bash
# Check service restart count
docker-compose ps --format '{{.Names}}\t{{.State}}' | grep -E 'Exited|Restarting'

# Expected: All services in "Up" state, restart count = 0
```

### Test 4.2: Error Log Analysis

```bash
# Check for OOMKilled events
docker events --filter 'type=container' --filter 'status=oom' --since 1h

# Check for CPU throttle warnings
docker-compose logs --since 1h | grep -i 'throttle\|cpu\|memory'

# Check for resource exhaustion errors
docker-compose logs --since 1h | grep -i 'out of memory\|resource limit'

# Expected: No events or minimal expected logging
```

### Test 4.3: Health Check Validation

```bash
# Verify all health checks passing
docker-compose ps | grep -E 'healthy|unhealthy'

# Expected: All services showing "healthy" status
```

### Test 4.4: Database Integrity Check

```bash
# Verify database integrity
docker-compose exec postgres psql -U postgres -d paperclip << 'EOF'
-- Check for table corruption
ANALYZE;
REINDEX DATABASE paperclip;

-- Verify table counts are reasonable
SELECT schemaname, tablename, n_live_tup 
FROM pg_stat_user_tables 
ORDER BY n_live_tup DESC LIMIT 10;
EOF

# Expected: No errors, database integrity verified
```

### Validation Checklist
- [ ] No service restarts due to resource limits
- [ ] No OOMKilled events observed
- [ ] No CPU throttle-related crashes
- [ ] All health checks passing
- [ ] Database integrity verified
- [ ] Application logs clean (no resource errors)

---

## Test Suite 5: Monitoring & Metrics (30 minutes)

### Objective
Verify monitoring systems are collecting metrics properly with resource limits.

### Test 5.1: Prometheus Data Collection

```bash
# Verify Prometheus has memory metrics
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_limit_bytes' \
  | jq '.data.result | length'

# Expected: 20+ results (one per service)

# Query memory usage
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes' \
  | jq '.data.result | sort_by(.value[1]) | reverse | .[0:5]'

# Expected: All services reporting memory usage
```

### Test 5.2: Grafana Dashboard Update

```bash
# Verify Grafana dashboards update with limit metrics
# Manually check: http://localhost:3000/d/resource-limits

# Dashboard should show:
# - Memory usage vs limits for each service
# - CPU usage vs limits for each service
# - Memory pressure indicators
# - CPU throttle metrics
```

### Test 5.3: Alert Rule Validation

```bash
# Verify alerting rules loaded
curl -s 'http://localhost:9090/api/v1/rules' \
  | jq '.data.groups[] | select(.name=="ResourceLimits")'

# Expected: 5+ alert rules for resource limit violations
```

### Validation Checklist
- [ ] Prometheus collecting memory/CPU limit metrics
- [ ] Grafana displaying resource limit dashboards
- [ ] Alert rules configured and active
- [ ] Metrics data is accurate and current
- [ ] No monitoring gaps for limited services

---

## Test Results Documentation

After completing all test suites, create summary report:

```markdown
# Phase 3 Validation Results

**Date**: [DATE]  
**Services Tested**: 20  
**Total Tests**: 20+  
**Pass Rate**: [X]%  

## Summary
- Memory limits: [PASS/FAIL]
- CPU throttling: [PASS/FAIL]
- Performance baseline: [PASS/FAIL]
- Service stability: [PASS/FAIL]
- Monitoring: [PASS/FAIL]

## Issues Found
[List any issues, severity, action items]

## Remediation
[Steps taken to resolve issues]

## Sign-Off
✅ All tests passing
✅ Ready for Phase 4
```

---

## Phase 3 Completion Checklist

- [ ] Memory limits enforcement verified (all services)
- [ ] CPU throttling working correctly (all services)
- [ ] Performance baseline documented
- [ ] Service stability verified (no crashes/restarts)
- [ ] Error logs clean (no resource-related errors)
- [ ] Monitoring systems collecting accurate data
- [ ] Health checks all passing
- [ ] Database integrity verified
- [ ] Alert rules configured and tested
- [ ] Test results documented
- [ ] Compliance increase from 70% to 85%
- [ ] Ready for Phase 4 (Monitoring setup)

---

## Expected Outcomes

✅ **After Phase 3**:
- Resource limits validated across all 20 services
- Performance impact documented and acceptable
- No unexpected crashes or errors
- Monitoring infrastructure ready
- Compliance Score: 85/100 (+15 points)
- Q3 Readiness: 90%

---

## Execution Timeline

**Phase 3 Start**: After Phase 2 completion  
**Memory Tests**: 30 minutes  
**CPU Tests**: 30 minutes  
**Performance Baseline**: 30 minutes  
**Stability Verification**: 30 minutes  
**Monitoring Validation**: 30 minutes  
**Documentation**: 30 minutes  
**Total**: 2-3 hours  

---

**Phase 3 Status**: Ready to Execute (after Phase 2)

