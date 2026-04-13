# Performance Benchmark Suite - On-Premises

**Phase**: 10 - On-Premises Performance Optimization  
**Purpose**: Establish baseline performance metrics and validate optimization improvements  
**Frequency**: Before/after each optimization, quarterly review

## Baseline Metrics

### 1. API Response Time Benchmarks

**Code-Server API**:
```bash
# GET /health endpoint (should be <50ms)
k6 run scripts/benchmark-health.js

# File operations (list, open, save) - should be <200ms
k6 run scripts/benchmark-file-ops.js

# Workspace operations - should be <500ms
k6 run scripts/benchmark-workspace.js
```

**Agent API**:
```bash
# POST /run_task - should be <2000ms for simple tasks
k6 run scripts/benchmark-agent-task.js

# GET /stream_task SSE - should start streaming <500ms
k6 run scripts/benchmark-agent-stream.js

# POST /rag/search - should be <1000ms
k6 run scripts/benchmark-rag-search.js
```

### 2. Database Performance

**PostgreSQL Query Benchmarks**:
```sql
-- User lookups (should be <10ms with index)
SELECT COUNT(*) FROM users WHERE username = 'example';

-- Session queries (should be <5ms)
SELECT COUNT(*) FROM sessions WHERE user_id = 1 AND active = true;

-- Embedding searches (should be <100ms)
SELECT * FROM embeddings 
WHERE text_hash = md5('example')
LIMIT 10;

-- Complex joins (should be <500ms)
SELECT u.*, COUNT(p.id) as post_count
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
GROUP BY u.id
LIMIT 100;
```

**Connection Pool Performance**:
```bash
# Monitor pool stats
watch 'psql -U postgres -d postgres -c "SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname;"'

# Test under high concurrency
k6 run --vus 100 --duration 60s scripts/benchmark-db-pool.js
```

### 3. Redis Performance

**Redis Benchmarks**:
```bash
# Key-value operations (should be <5ms)
redis-benchmark -h redis-server -p 6379 -n 100000 -c 50

# Pipelined operations (bulk performance)
redis-benchmark -h redis-server -p 6379 -n 100000 -c 50 -P 16

# Memory usage
redis-cli INFO memory | grep used_memory

# Key eviction behavior
redis-cli DBSIZE
redis-cli INFO eviction
```

### 4. Kubernetes Performance

**Pod Performance**:
```bash
# CPU usage
kubectl top pods -A --sort-by=cpu

# Memory usage
kubectl top pods -A --sort-by=memory

# Network I/O
kubectl top nodes

# Pod startup time
kubectl apply -f deployment.yaml
kubectl logs <pod-name> | grep "startup\|ready"
```

## Load Testing Suite

### k6 Load Tests

**File: `scripts/benchmark-api-load.js`**:
```javascript
import http from 'k6/http';
import { check, group, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Ramp-up to 20 users
    { duration: '1m30s', target: 50 }, // Ramp-up to 50 users
    { duration: '20s', target: 0 },    // Ramp-down to 0 users
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.01'],
  },
};

export default function () {
  group('Health Check', () => {
    check(http.get('http://code-server/health'), {
      'status is 200': (r) => r.status === 200,
      'response time < 50ms': (r) => r.timings.duration < 50,
    });
  });

  group('API Endpoint', () => {
    check(http.post('http://agent-api/run_task', { task: 'test' }), {
      'status is 200': (r) => r.status === 200,
      'response time < 2000ms': (r) => r.timings.duration < 2000,
    });
  });

  sleep(1);
}
```

### Load Test Profiles

**Light Load**: 20 concurrent users
- Use case: Dev/testing environments
- Duration: 5 minutes
- Expected metrics: p95 <500ms

**Medium Load**: 50 concurrent users
- Use case: Staging environment
- Duration: 15 minutes
- Expected metrics: p95 <1000ms

**Heavy Load**: 200+ concurrent users
- Use case: Production capacity planning
- Duration: 30+ minutes
- Expected metrics: p95 <2000ms, error rate <0.1%

**Stress Testing**: Gradually increase until failure
- Target: Find breaking point
- Ramp-up: 100 users per minute
- Monitor: Error rate, response time, resource exhaustion

## Memory Profiling

### Heap Dump Analysis

**Capture heap dump**:
```bash
# Node.js process
kill -USR2 <pid>  # Trigger signal
# or via API
curl -X POST http://localhost:8000/debug/heap-dump

# Analyze with clinic.js
npm install -g @clinic/clinic
clinic doctor -- node main.js
```

**Analyze memory leaks**:
```javascript
// Enable memory profiling in code
const heapdump = require('heapdump');

// Take snapshots and compare
heapdump.writeSnapshot();

// Memory leak detection
const memwatch = require('@airbnb/node-memwatch');
// Wait for leak detection
```

**Memory usage targets**:
- Code-server: <1GB (small), <2GB (medium)
- Agent API: <2GB (small), <3GB (medium)
- Embeddings: <3GB (small), <4GB (medium)

## CPU Profiling

### Flame Graph Generation

**Using clinic.js**:
```bash
clinic flame -- node main.py
clinic bubbleprof -- node main.py
```

**Using py-spy** (Python):
```bash
pip install py-spy
py-spy record -o profile.svg -- python main.py
py-spy top -p <pid>  # Real-time CPU usage
```

**Flame graph interpretation**:
- Wide bars = CPU hot spots (optimization opportunities)
- Tall stacks = Deep call chains (refactoring candidates)
- Target: <70% CPU utilization at peak load

## Storage I/O Benchmarking

### Disk Performance Tests

**I/O Benchmark Tool**:
```bash
# Install fio (flexible I/O tester)
# Sequential read
fio --name=seqread --rw=read --bs=1M --size=10G

# Random read (embeddings search simulation)
fio --name=randread --rw=randread --bs=4K --size=10G

# Write performance (backup simulation)
fio --name=seqwrite --rw=write --bs=1M --size=10G

# Mixed workload (real application)
fio --name=mixed --rw=randrw --bs=4K --size=10G
```

**Expected Performance (NFS)**:
- Sequential read: >100 MB/s
- Sequential write: >50 MB/s
- Random read (4K): >5000 IOPS
- Random write (4K): >1000 IOPS

**Expected Performance (Local SSD)**:
- Sequential read: >500 MB/s
- Sequential write: >300 MB/s
- Random read (4K): >50000 IOPS
- Random write (4K): >15000 IOPS

## Benchmark Reports

### Weekly Report Template

```markdown
# Performance Report - Week of [DATE]

## Baseline Metrics
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| API p95 | <500ms | XXms | ✅/❌ |
| DB Query p95 | <100ms | XXms | ✅/❌ |
| Redis p50 | <5ms | XXms | ✅/❌ |
| Memory usage | <2GB | XGB | ✅/❌ |
| CPU usage | <70% | XX% | ✅/❌ |

## Load Test Results
- Test: [Type] - [Users] concurrent
- Duration: XXm
- p50: XXms, p95: XXms, p99: XXms
- Error rate: XX%
- Status: ✅ Pass / ❌ Fail

## Improvements Made
1. [Optimization A]
   - Before: XXX
   - After: XXX
   - Improvement: XX%

## Next Week's Focus
- [ ] [Optimization B]
- [ ] [Optimization C]
```

## Automation

### Benchmark CI/CD Integration

**GitHub Actions Workflow** (`benchmark.yml`):
```yaml
name: Performance Benchmarks

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2 AM
  workflow_dispatch:

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run k6 tests
        run: |
          npm install -g k6
          k6 run scripts/benchmark-api-load.js --summary-export=results.json
      - name: Generate report
        run: |
          ./scripts/generate-benchmark-report.sh results.json
      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: benchmark-results
          path: reports/
```

## Performance SLOs

**Code-Server API**:
- p95 response time: <500ms
- p99 response time: <1000ms
- Availability: 99.9%
- Error rate: <0.1%

**Agent API**:
- Task completion: <5 minutes for 95% of tasks
- Stream latency: <500ms to first chunk
- Availability: 99.9%

**Database**:
- Query p95: <100ms
- Connection pool availability: 100%
- Backup completion: <1 hour

---

**Run baseline benchmarks before deployment to establish reference metrics. Compare optimizations against baseline to measure improvement percentage.** 