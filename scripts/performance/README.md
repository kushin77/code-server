# Performance Load Testing Scripts

Comprehensive k6-based load testing suite for validating production infrastructure capacity and performance characteristics.

## Overview

This package contains three complementary load tests designed to establish performance baselines and validate system resilience:

1. **Baseline Load Test** - Normal operating conditions (100 users, 10 min)
2. **Spike Load Test** - Traffic surge scenario (1000 users, 5 min)
3. **Sustained Load Test** - Extended high load (500 users, 30 min)

## Installation

### Prerequisites
- k6 (v0.40.0 or later)
- bash shell (Linux/macOS) or PowerShell (Windows)
- Target environment running on 192.168.168.31 or accessible via BASE_URL

### Install k6

**macOS**:
```bash
brew install k6
```

**Linux (Ubuntu/Debian)**:
```bash
sudo apt-get install k6
```

**Windows**:
```powershell
choco install k6
```

Or download from https://k6.io/docs/getting-started/installation/

## Usage

### Run All Tests (Recommended)

```bash
# Run complete performance testing campaign
bash scripts/performance/run-all-load-tests.sh

# With custom target
BASE_URL=https://ide.kushnir.cloud bash scripts/performance/run-all-load-tests.sh

# With custom target and logging
BASE_URL=http://192.168.168.31:3000 bash scripts/performance/run-all-load-tests.sh 2>&1 | tee performance.log
```

### Run Individual Tests

**Baseline Load Test**:
```bash
k6 run scripts/performance/baseline-load-test.js

# With custom parameters
k6 run \
  -e BASE_URL=http://192.168.168.31:3000 \
  -e RAMP_UP_DURATION=2m \
  -e TEST_DURATION=10m \
  -e MAX_USERS=100 \
  scripts/performance/baseline-load-test.js
```

**Spike Load Test**:
```bash
k6 run scripts/performance/spike-load-test.js

# With custom spike parameters
k6 run \
  -e BASE_URL=http://192.168.168.31:3000 \
  -e SPIKE_USERS=1000 \
  -e SPIKE_DURATION=5m \
  scripts/performance/spike-load-test.js
```

**Sustained Load Test**:
```bash
k6 run scripts/performance/sustained-load-test.js

# With custom sustained parameters
k6 run \
  -e BASE_URL=http://192.168.168.31:3000 \
  -e SUSTAINED_USERS=500 \
  -e SUSTAINED_DURATION=30m \
  scripts/performance/sustained-load-test.js
```

## Test Scenarios

### 1. Baseline Load Test
**Duration**: 12 minutes (2m ramp-up + 10m sustained + 1m ramp-down)  
**Concurrency**: 100 users  
**Pattern**: Linear ramp-up over 2 minutes to 100 concurrent users, maintained for 10 minutes

**Success Criteria**:
- All responses < 5 seconds (p95)
- Error rate < 0.1%
- CPU utilization < 70%
- Stable database connection pool

**Endpoints Tested**:
- Health check (`GET /health`)
- Inline communication threads (`GET /api/inline-communication/threads`)
- Statistics (`GET /api/inline-communication/statistics`)
- Voice channel sessions
- Co-editing sessions

### 2. Spike Load Test
**Duration**: 6m 10s (10s instant spike + 5m maintained + 1m ramp-down)  
**Concurrency**: 1000 users (immediate)  
**Pattern**: Instant jump to 1000 concurrent users (stress test), measure recovery

**Success Criteria**:
- Graceful degradation (no crashes)
- Recovery to < 1s response time within 2 minutes
- Error rate < 1% during spike
- Connection handling verified

**Measures**:
- System resilience under sudden load
- Error recovery mechanisms
- Resource availability under stress
- Recovery time after spike subsides

### 3. Sustained Load Test
**Duration**: 37 minutes (5m ramp-up + 30m sustained + 2m ramp-down)  
**Concurrency**: 500 users  
**Pattern**: Realistic workload mix (reading 30%, writing 30%, searching 30%, heavy 10%)

**Success Criteria**:
- Memory stable (no leak patterns)
- No connection pool exhaustion
- Cache performance consistent
- Error rate < 0.1%

**Workload Mix**:
- 30% Read operations (list threads, get statistics)
- 30% Write operations (create threads, add comments)
- 30% Search operations (query threads)
- 10% Heavy operations (multiple batch requests)

## Results

Results are saved to `artifacts/performance/` directory:

```
artifacts/performance/
├── baseline-results.json          # Detailed baseline metrics
├── spike-results.json              # Detailed spike metrics
├── sustained-results.json          # Detailed sustained load metrics
├── load-tests-TIMESTAMP.log        # Aggregated test log
└── PERFORMANCE-TEST-SUMMARY-TIMESTAMP.md  # Executive summary
```

## Interpreting Results

### Key Metrics

**Response Time**:
- Average (avg): Mean response time across all requests
- P50 (median): 50th percentile response time
- P95: 95% of responses faster than this time
- P99: 99% of responses faster than this time

**Throughput**:
- Requests per second (req/s)
- Total number of requests

**Error Rate**:
- Percentage of requests that failed
- Compare against success criteria

**Resource Utilization**:
- CPU: Should not exceed 70% under baseline load
- Memory: Should remain stable (no leaks)
- Connections: Pool usage should stay below limits

## Customization

### Modifying Load Profiles

Edit the `stages` in each test file to customize:

```javascript
export const options = {
  stages: [
    { duration: '5m', target: 200 },   // Ramp-up to 200 users over 5 minutes
    { duration: '15m', target: 200 },  // Stay at 200 for 15 minutes
    { duration: '2m', target: 0 },     // Ramp-down
  ],
};
```

### Adding Custom Endpoints

Add new test endpoints to the workload:

```javascript
group('Custom Feature', () => {
  const res = http.get(`${BASE_URL}/api/custom/endpoint`);
  check(res, {
    'custom endpoint success': (r) => r.status === 200,
  });
});
```

### Adjusting Thresholds

Modify success criteria:

```javascript
thresholds: {
  'response_time': ['p(95)<3000'],  // Change p95 threshold to 3s
  'errors': ['rate<0.005'],         // Change error rate to 0.5%
}
```

## Troubleshooting

### k6 Installation Issues
```bash
# Verify k6 is installed
k6 version

# Check PATH
which k6
```

### Connection Refused
```bash
# Verify target is running
curl -i http://localhost:3000/health

# Check connectivity
ping 192.168.168.31
ssh akushnir@192.168.168.31 'docker compose ps'
```

### Out of Memory
- Run spike test with fewer concurrent users
- Increase system memory
- Run tests on dedicated test machine

### Test Timeouts
- Increase test duration thresholds
- Reduce concurrent user count
- Check network connectivity to target

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Performance Tests
on: [workflow_dispatch]

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: grafana/k6-action@v0.3.0
        with:
          filename: scripts/performance/baseline-load-test.js
          env: BASE_URL=http://192.168.168.31:3000
```

## Performance Targets

### Baseline (100 users)
- Response time (p95): < 5 seconds ✅
- Error rate: < 0.1% ✅
- Throughput: > 50 req/s ✅

### Spike (1000 users)
- Recovery time: < 2 minutes ✅
- Error rate during spike: < 1% ✅
- Graceful degradation: No crashes ✅

### Sustained (500 users, 30 minutes)
- Memory stability: Flat line (no growth) ✅
- Connection pool: < 90% usage ✅
- Error rate: < 0.1% ✅

## Related Issues

- #1517: Performance Load Testing & Validation Campaign
- #1468: Production Deployment
- #1232: Inline Communication Service (tested)
- #1222: Real-Time Co-Editing (tested)

## Support

For issues or questions:
1. Check test logs: `artifacts/performance/load-tests-*.log`
2. Review detailed JSON results
3. Verify infrastructure status
4. Check GitHub issue #1517 for updates

---

**Last Updated**: April 23, 2026  
**Maintained By**: QA/Operations Team  
**Production Status**: Ready
