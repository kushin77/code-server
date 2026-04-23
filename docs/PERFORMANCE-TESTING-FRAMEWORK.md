# Performance Testing Framework

**Date Created**: April 22, 2026  
**Framework Version**: 1.0  
**Status**: Ready for execution (Apr 24-25)

## Overview

This framework provides comprehensive load and performance testing capabilities to validate system stability under production-like load scenarios. It uses k6 for load generation and Prometheus for metrics collection.

## Test Scenarios

### 1. Baseline Test (10 minutes)
**Purpose**: Establish baseline performance metrics under normal load

**Configuration**:
- Concurrent Users: 100
- Duration: 10 minutes
- Ramp-up Time: 2 minutes
- Metrics Collection: Every request

**Expected Results** (Success Criteria):
- p50 Response Time: < 50ms
- p95 Response Time: < 200ms
- p99 Response Time: < 500ms
- Error Rate: < 0.1%
- CPU Usage: < 30%
- Memory Usage: < 1GB

**k6 Script**: `k6-baseline.js`  
**Scale Profile**: `100x`

### 2. Spike Test (5 minutes)
**Purpose**: Validate system behavior during rapid load increase

**Configuration**:
- Peak Concurrent Users: 1000
- Duration: 5 minutes
- Ramp-up Time: 30 seconds
- Metrics Collection: Every request

**Expected Results** (Success Criteria):
- p95 Response Time: < 500ms
- p99 Response Time: < 1500ms
- Error Rate: < 1%
- System Recovery Time: < 2 minutes after spike
- No connection timeouts

**k6 Script**: `k6-spike.js`  
**Scale Profile**: `1000x`

### 3. Sustained Load Test (30 minutes)
**Purpose**: Detect memory leaks and performance degradation over time

**Configuration**:
- Concurrent Users: 500
- Duration: 30 minutes
- Ramp-up Time: 5 minutes
- Metrics Collection: Every 1 minute

**Expected Results** (Success Criteria):
- Stable p99 Response Time (no growth > 10%)
- Memory Growth: < 100MB
- Cache Hit Rate: > 80%
- No connection pool saturation
- Error Rate: < 0.1% throughout

**k6 Script**: `k6-sustained.js`  
**Scale Profile**: `500x`

## Running Tests

### Prerequisites
```bash
# Install k6 (if not already installed)
npm install -g k6

# Ensure application is running
docker compose up -d code-server

# Ensure Prometheus is accessible
curl http://localhost:9090/api/v1/query?query=up
```

### Run All Tests
```bash
cd scripts/loadtest
bash run-performance-tests.sh all
```

### Run Individual Tests
```bash
# Baseline only
bash run-performance-tests.sh baseline

# Spike only
bash run-performance-tests.sh spike

# Sustained only
bash run-performance-tests.sh sustained
```

### Custom Configuration
```bash
# Override test parameters
BASELINE_VUS=200 BASELINE_DURATION=15m bash run-performance-tests.sh baseline
SPIKE_VUS=2000 bash run-performance-tests.sh spike
SUSTAINED_VUS=700 SUSTAINED_DURATION=45m bash run-performance-tests.sh sustained
```

### Custom Target
```bash
# Test against staging or remote server
TEST_BASE_URL=https://staging.kushnir.cloud bash run-performance-tests.sh all
```

## Metrics Collection

### Application Metrics
- Response Time (p50, p95, p99)
- Request Throughput (RPS)
- Error Rate (HTTP 4xx, 5xx)
- Requests per Second (RPS)
- Failed Requests Count
- Connection Duration

### System Metrics (from Prometheus)
- CPU Usage (percentage)
- Memory Usage (bytes)
- Disk I/O
- Network I/O
- Database Connections Active

### Database Metrics
- Query Latency (p95, p99)
- Slow Query Count
- Connection Pool Utilization
- Replication Lag

### Cache Metrics
- Hit Rate (percentage)
- Miss Rate
- Eviction Rate
- Memory Usage

## Results and Analysis

### Results Location
All test results are saved to: `artifacts/performance/`

### Result Files
- `baseline-TIMESTAMP.json` - Baseline test detailed metrics
- `baseline-TIMESTAMP.log` - Baseline test output log
- `spike-TIMESTAMP.json` - Spike test detailed metrics
- `spike-TIMESTAMP.log` - Spike test output log
- `sustained-TIMESTAMP.json` - Sustained load test metrics
- `sustained-TIMESTAMP.log` - Sustained load test output log
- `prometheus-*.json` - System metrics collected from Prometheus

### Analyzing Results

#### Using k6 JSON Output
```bash
# Extract key metrics
jq '.metrics | keys' artifacts/performance/baseline-*.json

# Get p99 latency
jq '.metrics.http_req_duration.values.p99' artifacts/performance/baseline-*.json

# Get error rate
jq '.metrics.http_req_failed.values.rate' artifacts/performance/baseline-*.json
```

#### Reviewing Logs
```bash
# View test execution log
cat artifacts/performance/baseline-*.log

# Check for errors or warnings
grep -i "error\|warning\|fail" artifacts/performance/baseline-*.log
```

## Success Criteria Decision Matrix

### GO Decision (All pass)
- ✅ All p99 latencies < thresholds
- ✅ Error rates < thresholds
- ✅ No memory leaks detected
- ✅ No connection pool saturation
- ✅ Cache hit rates > 80%
- ✅ System recovers properly from spike

**Recommendation**: Proceed to production deployment

### CONDITIONAL GO (Some concerns, mitigated)
- ⚠️ One or two metrics slightly exceeds thresholds
- ⚠️ Issue is understood and documented
- ⚠️ Mitigation plan exists (scale up resources, optimize code)
- ⚠️ Risk is acceptable for business

**Recommendation**: Proceed with caution; monitor closely in production

### NO-GO (Critical issues)
- ❌ Multiple metrics fail thresholds
- ❌ Memory leak detected
- ❌ Connection pool exhaustion
- ❌ System doesn't recover from spike
- ❌ Unacceptable error rate

**Recommendation**: Do not deploy; fix issues and retest

## Performance Baselines (Target)

| Scenario | Metric | Target | Unit |
|----------|--------|--------|------|
| Baseline | p50 Latency | < 50 | ms |
| Baseline | p95 Latency | < 200 | ms |
| Baseline | p99 Latency | < 500 | ms |
| Baseline | Error Rate | < 0.1 | % |
| Baseline | CPU Usage | < 30 | % |
| Baseline | Memory Usage | < 1 | GB |
| Spike | p99 Latency | < 1500 | ms |
| Spike | Error Rate | < 1 | % |
| Spike | Recovery Time | < 2 | min |
| Sustained | Memory Growth | < 100 | MB |
| Sustained | Cache Hit Rate | > 80 | % |
| Sustained | Connection Pool | < 80 | % util |

## Troubleshooting

### k6 Not Found
```bash
# Install k6 globally
npm install -g k6

# Or use via npx
npx k6 run scripts/loadtest/k6-baseline.js
```

### Connection Refused
```bash
# Ensure application is running
docker compose ps

# Check if target URL is accessible
curl http://localhost:8080/healthz
```

### Prometheus Metrics Not Available
```bash
# Check Prometheus is running
docker compose ps | grep prometheus

# Verify Prometheus URL
curl http://localhost:9090/api/v1/query?query=up
```

### Out of Memory During Test
```bash
# Reduce concurrent users for sustained test
SUSTAINED_VUS=250 bash run-performance-tests.sh sustained

# Or increase system memory
# - Docker Desktop: Settings > Resources > Memory
# - Linux: Check available RAM with `free -h`
```

## Integration with CI/CD

### Running Tests in CI Pipeline
```yaml
- name: Run Performance Tests
  run: bash scripts/loadtest/run-performance-tests.sh all
  
- name: Check Results
  run: |
    jq '.metrics.http_req_failed.values.rate' artifacts/performance/baseline-*.json
    # Fail if error rate > 0.5%
```

### Reporting Results
```bash
# Upload results to artifact storage
mkdir -p performance-reports
cp artifacts/performance/*.json performance-reports/
# Upload to cloud storage or CI artifact system
```

## Timeline

- **Apr 22**: Framework setup and scripts creation (this task)
- **Apr 24, 9:00 AM UTC**: Start baseline test execution
- **Apr 24, 12:00 PM UTC**: Execute spike test
- **Apr 24, 3:00 PM UTC**: Start sustained load test
- **Apr 25, 9:00 AM UTC**: Collect final metrics
- **Apr 25, 3:00 PM UTC**: Complete analysis and publish report

## Success Metrics

✅ Framework scripts created and tested  
✅ Baseline test can execute in < 1 hour  
✅ Spike test can execute in < 10 minutes  
✅ Sustained test can execute in < 40 minutes  
✅ Metrics collected and stored  
✅ Results can be analyzed programmatically  
✅ Go/No-Go decision can be made by Apr 25 EOD

## Next Steps

1. Verify framework works with test run on Apr 23
2. Execute baseline test on Apr 24 morning
3. Execute spike test on Apr 24 afternoon
4. Monitor sustained test overnight (Apr 24-25)
5. Publish analysis report Apr 25 before 5 PM UTC
6. Present findings to team for go/no-go decision

---

**Framework Status**: ✅ READY FOR EXECUTION  
**Last Updated**: April 22, 2026  
**Owner**: Performance Engineering Team
