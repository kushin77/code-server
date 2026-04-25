# Load Testing with k6

This directory contains load testing scripts for code-server infrastructure using k6.

## Overview

Load testing validates system performance under various conditions:
- **Load Test**: Gradual increase from 100 to 1000 concurrent users
- **Stress Test**: Find breaking point with extreme load (up to 5000 VUs)
- **Spike Test**: Sudden 10-15x load spikes to test recovery

## Prerequisites

### Install k6

**macOS**:
```bash
brew install k6
```

**Windows** (with Chocolatey):
```bash
choco install k6
```

**Linux**:
```bash
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3232A
echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

**Docker**:
```bash
docker run -i grafana/k6 run - <script.js
```

### Verify Installation

```bash
k6 version
# Should output: k6 vX.X.X
```

## Running Tests

### 1. Load Test (Recommended for CI/CD)

Gradual load increase with performance validation:

```bash
# Run with default settings (against http://localhost:3000)
k6 run tests/load/load-test.js

# Run against custom host
BASE_URL=https://ide.kushnir.cloud k6 run tests/load/load-test.js

# Run with custom think time (ms between requests)
THINK_TIME=3000 k6 run tests/load/load-test.js

# Run with custom concurrency
k6 run --vus 500 --duration 10m tests/load/load-test.js

# Run in cloud (if k6 Pro enabled)
k6 cloud tests/load/load-test.js
```

**Test Profile**:
- Duration: ~20 minutes
- Max concurrent users: 1000
- Phases: Ramp (2+3+5+5+3+2 min)
- Performance thresholds:
  - Response time p95: < 500ms (GET)
  - Response time p99: < 2000ms
  - Error rate: < 0.1%

### 2. Stress Test (Find Breaking Point)

Find maximum capacity:

```bash
# Find breaking point
k6 run tests/load/stress-test.js

# Run with higher max load
k6 run --vus 7000 --duration 25m tests/load/stress-test.js

# Run with custom API base
API_BASE=https://api.kushnir.cloud k6 run tests/load/stress-test.js
```

**Test Profile**:
- Duration: ~30 minutes
- Max concurrent users: 5000+
- Phases: Ramp (5+5+5+5+5+5+5+5+5+5 min)
- Threshold increase detection: Watch for error rate > 10%

### 3. Spike Test (Recovery Validation)

Test sudden load spikes:

```bash
# Basic spike test
k6 run tests/load/spike-test.js

# With custom baseline
k6 run --vus 200 tests/load/spike-test.js

# Monitor recovery metrics
THINK_TIME=1000 k6 run tests/load/spike-test.js
```

**Test Profile**:
- Duration: ~18 minutes
- Spikes: 10x (1000 VUs) → 15x (1500 VUs)
- Recovery validation: After each spike
- Thresholds relaxed to allow spike observation

## Performance Targets

### API Latency (Load Test)
- **GET Requests**:
  - p50: < 100ms
  - p95: < 500ms
  - p99: < 2000ms
- **POST Requests**:
  - p50: < 200ms
  - p95: < 800ms
  - p99: < 3000ms

### Throughput at 1000 Concurrent Users
- Minimum: 500 requests/second
- Target: 1000 requests/second
- Maximum (degraded): 100 requests/second

### Error Rates
- Acceptable: < 0.1% (1 in 1000 requests)
- Stress test: Watch for breaking point (> 10% errors)

### Resource Utilization
- API CPU: < 80% during peak load
- Database CPU: < 75% during peak load
- Memory: < 85% utilization

## Interpreting Results

### Metrics in k6 Output

```
✓ checks............................ 98% (5000/5100)
✓ data_received..................... 1.2 MB
✓ data_sent......................... 650 KB
✓ http_req_blocked.................. avg=5ms
✓ http_req_connecting............... avg=2ms
✓ http_req_duration................. avg=342ms p(95)=821ms p(99)=1200ms
✓ http_req_failed................... 0% (0/5000)
✓ http_req_receiving................ avg=10ms
✓ http_req_sending.................. avg=5ms
✓ http_req_tls_handshaking.......... avg=0ms
✓ http_req_waiting.................. avg=322ms
✓ http_reqs......................... 5000 (83.3 req/sec)
✓ iteration_duration................ avg=12.3s
✓ iterations........................ 1000
✓ vus............................. avg=100
✓ vus_max........................... 1000
```

**Key Metrics**:
- `http_req_duration`: Response time (should track thresholds)
- `http_req_failed`: Error rate percentage
- `http_reqs`: Total requests and requests/sec
- `vus`: Virtual users count over time
- `checks`: Assertion pass rate (should be near 100%)

### Expected Results

#### Load Test (1000 VUs)
- ✅ All thresholds passed
- ✅ Error rate < 0.1%
- ✅ p95 response time < 500ms (GET) / < 800ms (POST)
- ✅ Requests/sec > 500

#### Stress Test
- Note when error rate exceeds 10% (breaking point)
- Observe recovery as load decreases
- Document resource utilization at breaking point

#### Spike Test
- Measure response time spike impact
- Verify recovery to baseline metrics
- Check for cascading failures

## Exporting Results

### HTML Report

```bash
# Run with HTML reporter
k6 run --out html=results.html tests/load/load-test.js

# Open report
open results.html
```

### JSON Output (for analysis)

```bash
# Export to JSON
k6 run --out json=results.json tests/load/load-test.js

# Parse with jq
cat results.json | jq '.metrics'
```

### InfluxDB Integration (for Grafana dashboards)

```bash
# Run against InfluxDB (requires setup)
k6 run --out influxdb=http://localhost:8086/k6 tests/load/load-test.js

# Then visualize in Grafana
```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run Load Test
  run: |
    k6 run \
      --vus 500 \
      --duration 10m \
      --out json=load-test-results.json \
      tests/load/load-test.js
  env:
    BASE_URL: https://staging.kushnir.cloud

- name: Upload Results
  uses: actions/upload-artifact@v2
  with:
    name: load-test-results
    path: load-test-results.json
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:3000` | Base URL for testing |
| `API_BASE` | `${BASE_URL}/api` | API base URL |
| `THINK_TIME` | `2000` (ms) | Delay between requests (simulate user think time) |
| `VUS` | From script stages | Number of virtual users |
| `DURATION` | From script stages | Test duration |

## Troubleshooting

### Connection Errors
```
error: Get http://localhost:3000: dial tcp 127.0.0.1:3000: connect: connection refused
```
- Verify application is running on correct host/port
- Check firewall rules
- Use `curl http://localhost:3000` to verify connectivity

### High Error Rate
- Check application logs for errors
- Verify database connectivity
- Check resource utilization (CPU, memory, disk)
- Reduce `--vus` or `--duration`

### Memory Issues
- Run with smaller `--vus` count
- Increase system memory
- Split test across multiple runs

### Slow Response Times
- Check application performance
- Look for database query bottlenecks
- Monitor network latency
- Reduce think time (`THINK_TIME`)

## Best Practices

1. **Start Small**: Begin with 100 VUs, gradually increase
2. **Monitor System**: Watch server metrics during test
3. **Baseline First**: Establish baseline at normal load (100 VUs)
4. **Multiple Runs**: Run tests multiple times for consistency
5. **Test Staging**: Always test against staging before production
6. **Gradual Ramp**: Simulate realistic user arrival patterns
7. **Think Time**: Include realistic delays between user actions
8. **Validation**: Use checks to validate response correctness
9. **Thresholds**: Set realistic thresholds based on requirements
10. **Documentation**: Document test results and findings

## Example Results Analysis

```
Load Test Summary:
✅ Target Load: 1000 concurrent users
✅ Duration: 20 minutes
✅ Total Requests: 120,000
✅ Requests/sec: 100 avg
✅ Error Rate: 0.05% (60 failures)
✅ p95 Response Time: 450ms (GET), 750ms (POST)

Bottleneck: Database was at 73% CPU during peak load
Recommendation: Add read replicas or caching layer
```

## References

- [k6 Documentation](https://k6.io/docs/)
- [k6 Best Practices](https://k6.io/docs/misc/best-practices/)
- [Performance Testing Guide](https://en.wikipedia.org/wiki/Software_performance_testing)
- [Stages Configuration](https://k6.io/docs/using-k6/options#stages)
- [Thresholds](https://k6.io/docs/using-k6/thresholds/)
