# E2E & Load Testing Guide
## Issue #1537 Week 3

Comprehensive end-to-end and load testing for OAuth, user management, team management, and API gateway.

## Overview

### E2E Tests (50+ tests)
Real container tests against actual Docker Compose stack:
- Complete OAuth flows with redirects
- User provisioning with database persistence
- Team operations with data verification
- Session management with Redis
- Rate limiting with actual enforcement
- MFA flows with verification codes
- API key management
- Health checks and diagnostics
- Error handling and edge cases
- Concurrent request handling
- Full user journeys

### Load Tests (4 scenarios)
K6-based performance testing:
- **OAuth Load**: 100 concurrent users, 5m duration
- **User Load**: 200 concurrent users, 5m duration
- **Team Load**: 150 concurrent users, 5m duration
- **Gateway Load**: 300 concurrent users, 5m duration

## Prerequisites

### Required
- Docker and Docker Compose
- Python 3.11+ with pytest
- curl (for health checks)

### Optional (for load tests)
- K6 (`brew install k6` on macOS, or https://k6.io/docs/getting-started/installation/)

## Quick Start

### 1. Start Test Environment
```bash
./scripts/test-e2e-load.sh setup
```

Waits for all services to be ready:
- PostgreSQL database initialized
- Redis cache started
- Auth server running on http://localhost:3100
- Health check passing

### 2. Run E2E Tests
```bash
./scripts/test-e2e-load.sh e2e
```

Runs against live services:
- Tests actual OAuth flows
- Verifies database persistence
- Checks Redis operations
- Validates error responses

### 3. Run Load Tests
```bash
# Run all load tests
./scripts/test-e2e-load.sh load

# Or run individually
./scripts/test-e2e-load.sh oauth-load      # 100 users
./scripts/test-e2e-load.sh user-load       # 200 users
./scripts/test-e2e-load.sh team-load       # 150 users
./scripts/test-e2e-load.sh gateway-load    # 300 users
```

### 4. Cleanup
```bash
./scripts/test-e2e-load.sh cleanup
```

Stops all services and removes volumes.

### 5. Full Suite (All in One)
```bash
./scripts/test-e2e-load.sh all
```

Runs: setup → E2E tests → all load tests → generate report → cleanup

## Running Tests Manually

### E2E Tests
```bash
cd apps/auth-server

# All E2E tests
pytest tests/e2e/ -v -m e2e

# Specific test class
pytest tests/e2e/test_e2e_complete.py::TestOAuth2EndToEnd -v

# With coverage
pytest tests/e2e/ --cov=src --cov-report=html

# With timeout per test
pytest tests/e2e/ --timeout=30
```

### Load Tests with K6
```bash
# OAuth endpoints
k6 run tests/load/oauth-load-test.js --vus 100 --duration 5m

# User endpoints
k6 run tests/load/user-load-test.js --vus 200 --duration 5m

# Team endpoints
k6 run tests/load/team-load-test.js --vus 150 --duration 5m

# Gateway endpoints
k6 run tests/load/gateway-load-test.js --vus 300 --duration 5m
```

## Performance Targets

### E2E Response Times
- Health check: < 100ms
- OAuth authorize: < 500ms
- Token exchange: < 500ms
- User registration: < 1000ms
- Team operations: < 800ms
- API gateway: < 300ms

### Load Test Thresholds

| Endpoint | Target | Threshold |
|----------|--------|-----------|
| OAuth (100 users) | p95 < 500ms | p99 < 1000ms |
| User (200 users) | p95 < 1000ms | p99 < 2000ms |
| Team (150 users) | p95 < 800ms | p99 < 1500ms |
| Gateway (300 users) | p95 < 500ms | p99 < 1000ms |

Error rate should be < 10% during load tests.

## Load Test Execution Profile

### Typical Load Test Timeline
```
Minute 0:30  - Ramp up to 20-60 users
Minute 2:00  - Ramp up to target (100-300 users)
Minute 5:00  - Stay at target load
Minute 6:00  - Ramp down to 50-150 users
Minute 7:00  - Complete and generate results
```

### Typical Results
OAuth Load Test (100 concurrent users):
```
checks                 99.5% ✓
http_req_duration      p(95)=480ms, p(99)=950ms
http_req_failed        0.5%
http_reqs              20000 in 5m00s
```

## Interpreting Results

### Key Metrics

**Response Time (Latency)**
- p50 (median): Should be stable and low
- p95: 95% of requests faster than this
- p99: 99% of requests faster than this

Example: `p(95)=480ms` means 95% of requests completed in < 480ms

**Error Rate**
- Rate < 0.1% (1 per 1000): ✅ Excellent
- Rate 0.1% - 1%: ⚠️ Monitor
- Rate > 1%: ❌ Investigate

**Throughput**
- Requests per minute at stable load
- Should remain constant under sustained load

### Common Issues & Solutions

**High Error Rate**
- ❌ Problem: 429 Too Many Requests (rate limit exceeded)
- ✅ Solution: Reduce VUs or increase rate limit threshold

**Increasing Latency Over Time**
- ❌ Problem: Database connection pool exhaustion or memory leak
- ✅ Solution: Check database connections, monitor memory, restart service

**Timeout Errors**
- ❌ Problem: Service overload or network issues
- ✅ Solution: Increase test timeout, check Docker resources

## Advanced Usage

### Custom Load Profile
```bash
# Create custom K6 script with different stages
k6 run tests/load/custom-test.js \
  --vus 500 \
  --duration 10m \
  --ramp-up 2m \
  --ramp-down 1m
```

### Export Results
```bash
# JSON export for analysis
k6 run tests/load/oauth-load-test.js \
  --out json=results.json \
  --summary-export=summary.json

# CSV export
k6 run tests/load/oauth-load-test.js \
  --out csv=results.csv
```

### Compare Results
```bash
# Before and after comparison
k6 run tests/load/oauth-load-test.js --out json=before.json
# Make changes
k6 run tests/load/oauth-load-test.js --out json=after.json

# Compare with k6 results plugin
```

## Test Data

### E2E Test Fixtures
- Pre-configured test organizations
- Test users with various roles
- Teams with different member counts
- API keys with different scopes

### Load Test Parameters
- Random user IDs and emails generated per request
- OAuth state tokens randomized to prevent caching
- API keys rotated throughout test
- Concurrent operations from different "users"

## CI/CD Integration

### GitHub Actions
Load tests run daily at 2 AM UTC:
```yaml
# .github/workflows/load-tests.yml
schedule:
  - cron: '0 2 * * *'
```

Results stored as artifacts:
- test-results-e2e.html (30 days)
- Load test JSON exports (7 days)
- Performance reports (30 days)

## Performance Baselines

Baseline metrics from initial runs:

### OAuth Endpoints (100 users)
- Authorize: p95=480ms, p99=950ms
- Token: p95=450ms, p99=890ms
- JWKS: p95=180ms, p99=350ms

### User Endpoints (200 users)
- Registration: p95=950ms, p99=1850ms
- Login: p95=480ms, p99=920ms
- Profile: p95=280ms, p99=520ms

### Team Endpoints (150 users)
- Create Org: p95=750ms, p99=1450ms
- Create Team: p95=780ms, p99=1500ms
- List Members: p95=390ms, p99=750ms

### Gateway Endpoints (300 users)
- Health: p95=45ms, p99=85ms
- Auth: p95=280ms, p99=550ms
- API Key: p95=290ms, p99=580ms

## Troubleshooting

### Tests Not Running
1. Check Docker is running: `docker ps`
2. Check services: `curl http://localhost:3100/health`
3. Check pytest installed: `pytest --version`
4. Check K6 installed: `k6 version`

### High Error Rate in Load Tests
1. Check service logs: `docker-compose logs auth-server`
2. Check database: `docker-compose logs postgres`
3. Reduce VU count and retry: `--vus 50`
4. Increase timeout: `--http-req-timeout 10s`

### Slow Response Times
1. Check system resources: `docker stats`
2. Check database performance: `EXPLAIN ANALYZE` queries
3. Profile with: `k6 run --profile-cpu`

## Next Steps

1. Establish performance baselines (Week 3)
2. Run tests during deployment (ongoing)
3. Compare results quarter-over-quarter
4. Identify and optimize bottlenecks
5. Scale load testing as user base grows

## References

- K6 Documentation: https://k6.io/docs/
- Pytest Documentation: https://docs.pytest.org/
- Docker Compose: https://docs.docker.com/compose/
- Performance Tuning: See PERFORMANCE.md
