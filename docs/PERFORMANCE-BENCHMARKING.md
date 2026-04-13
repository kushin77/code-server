# Performance Benchmarking & Load Testing

## Benchmarking Framework

### 1. Setup Load Testing Environment

```bash
# Install K6 (modern load testing tool)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install k6 grafana/k6 \
  --namespace load-testing \
  --create-namespace
```

### 2. Baseline Performance Test

```javascript
// benchmarks/baseline.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 10,           // 10 virtual users
  duration: '5m',    // 5 minute test
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],  // 95% < 500ms, 99% < 1s
    'http_req_failed': ['rate<0.1'],                    // Error rate < 0.1%
  },
};

export default function () {
  // Test code-server API
  let res = http.get('http://code-server:8080/api/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  // Test agent API
  res = http.get('http://agent-api:8080/health');
  check(res, {
    'agent status is 200': (r) => r.status === 200,
  });

  sleep(1);
}
```

### 3. Stress Test (Find Breaking Point)

```javascript
// benchmarks/stress-test.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },   // Ramp up to 100 users
    { duration: '5m', target: 200 },   // Ramp up to 200 users
    { duration: '2m', target: 500 },   // Ramp up to 500 users
    { duration: '5m', target: 1000 },  // Spike to 1000 users
    { duration: '2m', target: 0 },     // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(99)<2000'],  // 99% should stay under 2s
  },
};

export default function () {
  let res = http.post('http://code-server:8080/api/execute', {
    code: 'print("hello")',
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'execution succeeded': (r) => r.body.includes('success'),
  });
}
```

### 4. Endurance Test (Run for Hours)

```javascript
// benchmarks/endurance-test.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus: 50,
  duration: '24h',  // Run for 24 hours
  thresholds: {
    'http_req_duration': ['avg<500', 'p(95)<1000'],
    'http_req_failed': ['rate<0.05'],  // Allow up to 0.05% error
  },
};

export default function () {
  let res = http.get('http://code-server:8080/api/list-files');
  
  check(res, {
    'response status is 200': (r) => r.status === 200,
    'response time acceptable': (r) => r.timings.duration < 500,
    'no memory leaks detected': (r) => parseFloat(r.headers['X-Memory-Usage']) < 8000,  // < 8GB
  });
}
```

### 5. Spike Test (Sudden Traffic Increase)

```javascript
// benchmarks/spike-test.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },    // Normal load
    { duration: '1m', target: 5000 },   // SPIKE to 5000 users
    { duration: '3m', target: 5000 },   // Hold spike
    { duration: '2m', target: 100 },    // Return to normal
  ],
};

export default function () {
  let res = http.get('http://code-server:8080/');
  
  check(res, {
    'spike handled': (r) => r.status < 500,  // 5xx during spike = failure
    'response time degradation < 5x': (r) => r.timings.duration < 2500,
  });
}
```

## 6. Automated Benchmark Execution

```bash
#!/bin/bash
# run-benchmarks.sh

set -e

echo "=== Performance Benchmarking Suite ==="

# Run baseline
echo "1. Running baseline..."
k6 run --vus 10 --duration 5m benchmarks/baseline.js | tee baseline-results.txt

# Run stress test
echo "2. Running stress test..."
k6 run benchmarks/stress-test.js | tee stress-results.txt

# Run spike test
echo "3. Running spike test..."
k6 run benchmarks/spike-test.js | tee spike-results.txt

# Analysis
echo ""
echo "=== Results Analysis ==="

BASELINE_P99=$(grep "p(99)" baseline-results.txt | awk '{print $2}')
STRESS_P99=$(grep "p(99)" stress-results.txt | awk '{print $2}')

echo "Baseline P99: $BASELINE_P99"
echo "Stress P99: $STRESS_P99"

# Check if stress test degraded performance by > 2x
if (( $(echo "$STRESS_P99 / $BASELINE_P99 > 2" | bc -l) )); then
  echo "❌ FAIL: Performance degraded by > 2x under stress"
  exit 1
fi

echo "✅ All benchmarks passed"
```

## 7. Database Benchmarking

### PostgreSQL Query Performance

```bash
#!/bin/bash
# benchmark-postgres.sh

echo "=== Database Benchmarking ==="

# Connect to PostgreSQL
PSQL="kubectl exec -n databases postgresql-0 -- psql -U postgres code_server"

# Test 1: Simple SELECT (should be < 10ms)
echo "Test 1: Simple SELECT..."
$PSQL -t -c "EXPLAIN ANALYZE SELECT COUNT(*) FROM users;" | grep "Execution Time"

# Test 2: JOIN query (should be < 50ms)
echo "Test 2: Complex JOIN..."
$PSQL -t -c "EXPLAIN ANALYZE SELECT u.id, COUNT(a.id) FROM users u LEFT JOIN audit_logs a ON u.id = a.user_id GROUP BY u.id;" | grep "Execution Time"

# Test 3: Index lookup (should be < 5ms)
echo "Test 3: Index hit..."
$PSQL -t -c "EXPLAIN ANALYZE SELECT * FROM users WHERE id = 12345;" | grep "Execution Time"

# Test 4: Sequential scan (should be < 100ms)
echo "Test 4: Sequential scan..."
$PSQL -t -c "EXPLAIN ANALYZE SELECT * FROM audit_logs WHERE created_at > NOW() - INTERVAL '1 day';" | grep "Execution Time"

# Capture slow query log
echo "Slow queries (> 1000ms):"
$PSQL -c "SELECT query, calls, mean_time FROM pg_stat_statements WHERE mean_time > 1000 ORDER BY mean_time DESC LIMIT 10;"
```

### Redis Performance

```bash
# benchmark-redis.sh

echo "=== Redis Benchmarking ==="

# Simple ping test
echo "Ping latency (should be < 1ms):"
redis-cli --latency-history -i 1 | head -10

# Set/Get performance
echo "Set/Get throughput:"
redis-benchmark -t set,get -n 100000 -q

# SET with TTL
echo "SET with TTL throughput:"
redis-benchmark -t set -n 100000 -d 1024 -q

# Cache hit ratio during load
echo "Cache statistics:"
redis-cli INFO stats | grep hit_ratio

# Memory usage
echo "Memory usage:"
redis-cli INFO memory | grep used_memory_human
```

## 8. Continuous Benchmarking (Automated, Weekly)

```bash
#!/bin/bash
# continuous-benchmark-job.yaml

apiVersion: batch/v1
kind: CronJob
metadata:
  name: performance-benchmark
  namespace: monitoring
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: benchmark-sa
          containers:
          - name: benchmark
            image: grafana/k6:latest
            command:
            - /bin/sh
            - -c
            - |
              k6 run --out json=/results/baseline-$(date +%Y%m%d).json benchmarks/baseline.js
              k6 run --out json=/results/stress-$(date +%Y%m%d).json benchmarks/stress-test.js
              
              # Upload results to storage
              tar -czf /results/benchmark-$(date +%Y%m%d).tar.gz /results/*.json
              cp /results/benchmark-$(date +%Y%m%d).tar.gz /mnt/backups/benchmarks/
            volumeMounts:
            - name: benchmarks
              mountPath: /benchmarks
            - name: results
              mountPath: /results
            - name: backups
              mountPath: /mnt/backups
          volumes:
          - name: benchmarks
            configMap:
              name: k6-benchmarks
          - name: results
            emptyDir: {}
          - name: backups
            persistentVolumeClaim:
              claimName: benchmarks-pvc
          restartPolicy: OnFailure
```

## 9. Performance Dashboard

### Key Metrics to Track

```prometheus
# Request latency percentiles
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Throughput
rate(http_requests_total[5m])

# Error rate
rate(http_requests_total{status=~"5.."}[5m])

# Database query time
rate(db_query_duration_seconds[5m])

# Cache efficiency
rate(cache_hits_total[5m]) / (rate(cache_hits_total[5m]) + rate(cache_misses_total[5m]))

# Resource utilization
container_memory_usage_bytes / container_spec_memory_limit_bytes
rate(container_cpu_usage_seconds_total[5m]) / container_spec_cpu_quota
```

## 10. Performance SLO

Target performance metrics:

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| P50 Latency | < 100ms | > 200ms |
| P95 Latency | < 500ms | > 1000ms |
| P99 Latency | < 1000ms | > 2000ms |
| Error Rate | < 0.1% | > 0.5% |
| Availability | 99.95% | < 99.9% |
| Throughput | > 100 req/s | < 50 req/s |

## 11. Benchmark Results Storage

```bash
# Store results for long-term trend analysis
# Every benchmark run saved with metadata

├── benchmarks/results/
│   ├── baseline-20260413.json
│   ├── stress-20260413.json
│   ├── spike-20260413.json
│   ├── baseline-20260406.json  (previous week)
│   └── baseline-20260330.json  (4 weeks ago)

# Compare week-over-week
k6 report baseline-20260413.json > comparison-latest.html
```

## 12. Performance Trend Analysis

```python
# analyze_benchmarks.py
import json
import glob
from datetime import datetime

def analyze_performance_trends():
    """Compare performance over time"""
    
    results = {}
    
    # Load all benchmark results
    for file in sorted(glob.glob("benchmarks/results/*.json")):
        with open(file) as f:
            data = json.load(f)
            date = file.split("-")[-1].replace(".json", "")
            
            results[date] = {
                "p95_latency": data.get("metrics", {}).get("http_req_duration", {}).get("p(95)", 0),
                "p99_latency": data.get("metrics", {}).get("http_req_duration", {}).get("p(99)", 0),
                "error_rate": data.get("metrics", {}).get("http_req_failed", {}).get("rate", 0),
            }
    
    # Detect trends
    print("Performance Trends (Last 4 Weeks)")
    print("================================")
    
    for date, metrics in sorted(results.items())[-4:]:
        print(f"{date}:")
        print(f"  P95: {metrics['p95_latency']}ms")
        print(f"  P99: {metrics['p99_latency']}ms")
        print(f"  Error Rate: {metrics['error_rate']*100:.2f}%")
    
    # Warning if trending up
    latest = list(results.values())[-1]
    previous = list(results.values())[-2]
    
    if latest["p99_latency"] > previous["p99_latency"] * 1.2:
        print("\n⚠️  WARNING: P99 latency increased by > 20%!")
        print("Review recent code changes and database indexes.")

if __name__ == "__main__":
    analyze_performance_trends()
```

---

## Next Steps

1. **Week 1**: Run baseline benchmarks, establish SLO targets
2. **Week 2**: Run stress test, identify breaking point  
3. **Week 3**: Run endurance test, check for memory leaks
4. **Week 4**: Optimize based on findings, re-benchmark

Expected results after optimization: **3-5x latency improvement**, **10x throughput increase**.
