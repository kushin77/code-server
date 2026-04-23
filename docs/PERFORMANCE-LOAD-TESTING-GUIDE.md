# Performance Load Testing Guide
**Kushnir.cloud Code Server - Production Readiness Validation**

**Version**: 1.0  
**Created**: April 23, 2026  
**Status**: Ready for Execution

---

## Table of Contents
1. [Overview](#overview)
2. [Test Scenarios](#test-scenarios)
3. [Setup Instructions](#setup-instructions)
4. [Running Tests](#running-tests)
5. [Interpreting Results](#interpreting-results)
6. [Success Criteria](#success-criteria)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose
Establish performance baseline and validate system stability under production-level load (100-1000 concurrent users).

### Objectives
- ✅ Identify performance bottlenecks before production
- ✅ Measure baseline performance metrics
- ✅ Validate system stability under stress
- ✅ Document performance characteristics
- ✅ Create baseline for ongoing monitoring

### Key Metrics
1. **Response Time**: p50, p90, p99 latencies
2. **Throughput**: Requests per second (RPS)
3. **Error Rate**: Percentage of failed requests
4. **Resource Usage**: Memory, CPU, database connections
5. **Cache Performance**: Hit rate, eviction rate
6. **Database**: Query time, replication lag

### Environment
- **Test Target**: Staging environment (or isolated production-like setup)
- **Load Generator**: Separate machine (prevent interference)
- **Duration**: 3-4 hours total (baseline + spike + sustained)
- **Monitoring**: Prometheus, logs, system metrics

---

## Test Scenarios

### Scenario 1: Baseline Performance (100 Concurrent Users)
**Duration**: 10 minutes  
**Ramp-up**: 2 minutes (0→100 users)  
**Sustained**: 8 minutes (100 users)

**Purpose**: Establish normal operating performance

**Success Criteria**:
- p50 latency: < 50ms
- p99 latency: < 200ms
- Error rate: < 0.1%
- Memory usage: < 1GB
- CPU usage: < 30%
- RPS: > 1000

### Scenario 2: Spike Test (1000 Concurrent Users)
**Duration**: 5 minutes  
**Ramp-up**: 30 seconds (100→1000 users)  
**Sustained**: 4:30 (1000 users)

**Purpose**: Test system resilience to traffic spikes

**Success Criteria**:
- p99 latency: < 500ms (degraded but acceptable)
- Error rate: < 1%
- No connection failures
- System recovers after spike
- Memory < 2GB peak

### Scenario 3: Sustained Load (500 Concurrent Users, 30 Minutes)
**Duration**: 30 minutes  
**Ramp-up**: 5 minutes (0→500 users)  
**Sustained**: 25 minutes (500 users)

**Purpose**: Detect memory leaks and performance degradation

**Success Criteria**:
- Stable p99 latency (< 300ms)
- No memory growth > 100MB/hour
- Cache hit rate consistent (> 80%)
- Replication lag < 1 second
- No significant log errors

---

## Setup Instructions

### Prerequisites
```bash
# Install k6 (load testing tool)
# macOS
brew install k6

# Ubuntu/Debian
sudo apt-get install k6

# Or from source: https://k6.io/docs/getting-started/installation/

# Install jq (JSON parsing)
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu

# Install curl (should be pre-installed)
# Verify:
curl --version
```

### Environment Setup

**1. Verify Target is Reachable**
```bash
curl -v http://localhost:3000/health
# Expected: 200 OK
```

**2. Prepare Load Generator Machine**
```bash
# Should be separate from target machine
# Ensure good network connectivity to target
# No other resource-intensive processes running

# Test connectivity
ping -c 5 <target-host>
traceroute <target-host>
```

**3. Prepare Monitoring**
```bash
# Start monitoring before tests
# Open Prometheus dashboard: http://localhost:9090

# Ensure these metrics are being collected:
# - http_request_duration_seconds (latency)
# - http_requests_total (throughput)
# - container_memory_usage_bytes (memory)
# - container_cpu_usage_seconds_total (CPU)
```

**4. Check System State**
```bash
# Verify database is healthy
psql $DATABASE_URL -c "SELECT version();"

# Check Redis
redis-cli ping
# Expected: PONG

# Check failover replica
ssh failover-host "pg_ctl status"
# Expected: server is running
```

---

## Running Tests

### Option 1: Automated Test Suite (Recommended)

```bash
# Run all tests automatically
cd /path/to/code-server
bash scripts/ops/performance-load-testing.sh

# Or with custom parameters
TEST_TARGET=http://192.168.168.31:3000 \
BASELINE_USERS=100 \
SPIKE_USERS=1000 \
SUSTAINED_USERS=500 \
bash scripts/ops/performance-load-testing.sh

# Results saved to: artifacts/performance-tests/
```

### Option 2: Individual Tests with k6

**Baseline Test (100 concurrent users)**
```bash
# Create test script
cat > baseline-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },    // Ramp up
    { duration: '8m', target: 100 },    // Sustained
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  const res = http.get('http://localhost:3000/health');
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
}
EOF

# Run test
k6 run --out json=baseline-results.json baseline-test.js
```

**Spike Test (1000 concurrent users)**
```bash
cat > spike-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 1000 },   // Rapid ramp up
    { duration: '4m30s', target: 1000 }, // Sustained
  ],
};

export default function() {
  const res = http.get('http://localhost:3000/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
EOF

k6 run --out json=spike-results.json spike-test.js
```

**Sustained Test (500 concurrent, 30 minutes)**
```bash
cat > sustained-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '5m', target: 500 },   // Ramp up
    { duration: '25m', target: 500 },  // Sustained
  ],
};

export default function() {
  const res = http.get('http://localhost:3000/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
EOF

k6 run --out json=sustained-results.json sustained-test.js
```

### Option 3: Manual Load Testing with curl

```bash
# Simple stress test (if k6 not available)
# Launch concurrent requests
for i in {1..100}; do
  (while true; do
    curl -s http://localhost:3000/health > /dev/null
    sleep 1
  done &)
done

# Monitor results
watch -n 1 'curl -s http://localhost:3000/health'

# Stop after test duration
killall curl
```

---

## Interpreting Results

### k6 Results (JSON Output)

**Key Metrics in JSON**:
```json
{
  "metrics": {
    "http_req_duration": {
      "values": {
        "p(50)": 45,
        "p(90)": 150,
        "p(95)": 180,
        "p(99)": 250
      }
    },
    "http_req_failed": {
      "values": {
        "rate": 0.0005
      }
    },
    "http_reqs": {
      "values": {
        "rate": 1250.5
      }
    }
  }
}
```

### Parse Results with jq

```bash
# Extract latency percentiles
jq '.metrics.http_req_duration.values' baseline-results.json

# Extract error rate
jq '.metrics.http_req_failed.values' baseline-results.json

# Extract throughput (RPS)
jq '.metrics.http_reqs.values.rate' baseline-results.json

# Check passed/failed counts
jq '.metrics.checks.values' baseline-results.json
```

### System Metrics During Test

**Monitor during test**:
```bash
# Watch in real-time
watch -n 1 'curl -s http://localhost:3000/health'

# Check docker memory
docker stats --no-stream code-server

# Check database connections
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity;"

# Check Redis
redis-cli info stats

# Monitor logs
docker logs --follow code-server | grep -E "ERROR|WARN"
```

---

## Success Criteria

### Green Light ✅ (All Good)
```
BASELINE TEST:
✅ p99 latency: 150ms (target: < 200ms)
✅ Error rate: 0.05% (target: < 0.1%)
✅ Memory: 800MB (target: < 1GB)
✅ CPU: 25% (target: < 30%)

SPIKE TEST:
✅ p99 latency: 350ms (target: < 500ms)
✅ Error rate: 0.5% (target: < 1%)
✅ Peak memory: 1.5GB (target: < 2GB)
✅ No timeouts

SUSTAINED TEST:
✅ Stable latency (no growth > 20%)
✅ No memory leaks (growth < 100MB/hour)
✅ Cache hit rate: 85% (target: > 80%)
✅ Replication lag: 0.2s (target: < 1s)
```

**Recommendation**: **GO** for production deployment

---

### Yellow Light ⚠️ (Investigate)
```
BASELINE TEST:
⚠️ p99 latency: 280ms (target: < 200ms) - EXCEEDS by 40%
⚠️ Error rate: 0.08% (acceptable but close to limit)

SUSTAINED TEST:
⚠️ Memory growth: 150MB/hour (target: < 100MB/hour)
⚠️ Cache hit rate: 75% (slightly below 80%)
```

**Action Required**:
1. Investigate latency source (DB queries? Cache misses?)
2. Profile memory usage (potential small leak?)
3. Optimize query or cache strategy
4. Re-test after optimization

**Recommendation**: **CONDITIONAL GO** - Deploy with monitoring alerts

---

### Red Light 🛑 (Block)
```
BASELINE TEST:
🛑 p99 latency: 800ms (target: < 200ms) - 4X OVER LIMIT
🛑 Error rate: 2% (target: < 0.1%) - 20X OVER LIMIT
🛑 Memory: 2.5GB (target: < 1GB) - EXCEEDS PEAK

SPIKE TEST:
🛑 System crashes under 1000 users
🛑 Connection timeouts: 15% of requests
🛑 Database deadlocks detected
```

**Action Required**:
1. STOP - Do not deploy to production
2. Identify root cause (query slowness? memory leak? connection pool?)
3. Fix issue (optimize queries, increase memory, tune config)
4. Re-test from scratch
5. May require re-architecture (caching, load balancing, etc.)

**Recommendation**: **NO GO** - Fix issues before production deployment

---

## Detailed Analysis Template

### Baseline Analysis
```markdown
## Baseline Test Results (100 concurrent users)

### Latency Performance
- p50: ___ ms (acceptable: < 50ms)
- p99: ___ ms (acceptable: < 200ms)
- Average: ___ ms

### Throughput
- Requests/sec: ___
- Total requests: ___
- Test duration: 10 minutes

### Error Analysis
- Failed requests: ___
- Error rate: ___%
- Most common error: ___

### Resource Usage
- Peak memory: ___ MB
- Average memory: ___ MB
- CPU usage: ___%
- Database connections: ___

### Assessment
[GREEN/YELLOW/RED] - Explain findings
```

---

## Troubleshooting

### Issue: "Connection refused" errors

**Cause**: Target service not reachable

**Solution**:
```bash
# Verify service is running
curl http://localhost:3000/health

# Check firewall
sudo iptables -L | grep 3000

# Check Docker
docker ps | grep code-server
```

### Issue: "Too many open files" errors

**Cause**: System running out of file descriptors

**Solution**:
```bash
# Increase limit
ulimit -n 65536

# Verify
ulimit -n
# Should show: 65536

# Re-run test
```

### Issue: High memory growth during sustained test

**Cause**: Potential memory leak

**Solution**:
```bash
# Collect heap dump
docker exec code-server node -e "require('v8').writeHeapSnapshot('/tmp/heap.heapsnapshot')"

# Copy and analyze
docker cp code-server:/tmp/heap.heapsnapshot ./

# Analyze with DevTools or clinic.js
npx clinic.js doctor -- node app.js
```

### Issue: High database query latency

**Cause**: Slow queries or connection pool exhaustion

**Solution**:
```bash
# Check slow query log
psql $DATABASE_URL -c "SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5;"

# Check connections
psql $DATABASE_URL -c "SELECT count(*) as connections FROM pg_stat_activity;"

# Increase pool size if needed
export DB_POOL_SIZE=50
```

### Issue: Cache hit rate too low

**Cause**: Cache not warmed up or cache size too small

**Solution**:
```bash
# Check Redis memory
redis-cli info memory

# Increase Redis maxmemory if needed
redis-cli CONFIG SET maxmemory 2gb

# Verify cache keys
redis-cli KEYS '*' | wc -l
```

---

## Performance Optimization Tips

### 1. Database Query Optimization
```sql
-- Add missing indexes
CREATE INDEX idx_workspace_user_id ON workspaces(user_id);

-- Analyze slow queries
EXPLAIN ANALYZE SELECT ... FROM ...

-- Vacuum and analyze
VACUUM ANALYZE;
```

### 2. Cache Strategy
```javascript
// Cache frequently accessed data
const cache = new Map();
const TTL = 5 * 60 * 1000; // 5 minutes

function getCached(key, fn) {
  if (cache.has(key) && Date.now() - cache.get(key).ts < TTL) {
    return cache.get(key).value;
  }
  const value = fn();
  cache.set(key, { value, ts: Date.now() });
  return value;
}
```

### 3. Connection Pooling
```javascript
// Configure optimal pool size
const pool = new Pool({
  max: 20,              // Max connections
  min: 5,               // Min connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

### 4. Compression
```javascript
// Enable gzip compression
app.use(compression());

// Minify responses
app.use(express.static('public', { maxAge: '1d' }));
```

---

## Next Steps

1. **Run Baseline Test** (Apr 24) - Establish normal performance
2. **Analyze Results** - Compare against success criteria
3. **Run Spike Test** - Verify resilience to traffic spikes
4. **Run Sustained Test** - Check for memory leaks
5. **Optimize if Needed** - Fix any bottlenecks found
6. **Document Baseline** - Create performance baseline for monitoring
7. **Staging Deployment** - Test runbook in staging environment
8. **Production Deployment** (Apr 30) - Deploy with confidence

---

## Appendix: k6 Advanced Usage

### Custom Metrics
```javascript
import { Trend, Rate, Gauge, Counter } from 'k6/metrics';

// Define custom metrics
const errorRate = new Rate('errors');
const latency = new Trend('latency');
const concurrentUsers = new Gauge('concurrent_users');
const requestCount = new Counter('requests');

export default function() {
  const res = http.get('http://localhost:3000/health');
  
  if (res.status !== 200) {
    errorRate.add(1);
  }
  
  latency.add(res.timings.duration);
  concurrentUsers.add(__VU);
  requestCount.add(1);
}
```

### HTTP Requests Testing
```javascript
// Test API endpoints
import http from 'k6/http';
import { check } from 'k6';

export default function() {
  // Test GET
  let res = http.get('http://localhost:3000/api/workspaces');
  check(res, {
    'GET /api/workspaces': (r) => r.status === 200,
  });
  
  // Test POST
  res = http.post('http://localhost:3000/api/sessions', {
    name: 'test-session',
  });
  check(res, {
    'POST /api/sessions': (r) => r.status === 201,
  });
}
```

### Thresholds (Pass/Fail Criteria)
```javascript
export const options = {
  thresholds: {
    http_req_duration: ['p(99)<1000'],  // 99th percentile < 1s
    http_req_failed: ['rate<0.1'],       // < 0.1% errors
    'group:::baseline': ['avg<200'],     // Baseline avg < 200ms
  },
};
```

---

## Support & Questions

For issues or questions:
- Slack: #performance-testing
- Email: performance@kushnir.cloud
- Issues: github.com/kushin77/code-server/issues

---

**Document Version**: 1.0  
**Last Updated**: April 23, 2026  
**Next Review**: May 1, 2026 (post-production deployment)

