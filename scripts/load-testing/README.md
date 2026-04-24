# Load Testing Framework

This directory contains k6-based load testing scripts for validating infrastructure performance and reliability.

## Prerequisites

- **k6**: Install from https://k6.io/docs/getting-started/installation/
  ```bash
  # macOS
  brew install k6
  
  # Linux
  sudo apt install k6
  
  # Windows (via Chocolatey)
  choco install k6
  ```

- **jq**: For parsing test results
  ```bash
  # macOS
  brew install jq
  
  # Linux
  sudo apt install jq
  
  # Windows (via Chocolatey)
  choco install jq
  ```

## Quick Start

### Dry Run (Safe Preview)
```bash
# Preview load test configuration without sending actual requests
DRY_RUN=1 ./run-comprehensive-load-tests.sh

# Preview specific test
DRY_RUN=1 SCENARIO=moderate ./run-oauth-flow-load-test.sh
```

### Execute Tests
```bash
# Light load (development/testing)
DRY_RUN=0 SCENARIO=light ./run-comprehensive-load-tests.sh

# Moderate load (staging validation)
DRY_RUN=0 SCENARIO=moderate ./run-comprehensive-load-tests.sh

# Stress test (production readiness)
DRY_RUN=0 SCENARIO=stress ./run-comprehensive-load-tests.sh
```

## Available Tests

### 1. OAuth Flow Load Test
Validates OAuth login flow performance and capacity.

**File**: `run-oauth-flow-load-test.sh`

**Scenarios**:
- **light**: 10 virtual users, 30s duration, ~5 RPS
- **moderate**: 50 virtual users, 60s duration, ~25 RPS
- **stress**: 200 virtual users, 120s duration, ~100 RPS

**Run**:
```bash
DRY_RUN=0 BASE_URL=https://ide.kushnir.cloud ./run-oauth-flow-load-test.sh light
```

**Validates**:
- Login page loads successfully
- OAuth redirect initiates correctly
- Callback handling under load
- JWT cookie generation and management

### 2. JWT Token Acquisition Load Test
Validates token endpoint performance and caching efficiency.

**File**: `run-jwt-token-load-test.sh`

**Scenarios**:
- **light**: 5 VUS, 30s duration, ~50 tokens/sec
- **moderate**: 20 VUS, 60s duration, ~200 tokens/sec
- **stress**: 50 VUS, 120s duration, ~500+ tokens/sec

**Run**:
```bash
DRY_RUN=0 CLIENT_ID=code-server CLIENT_SECRET=*** ./run-jwt-token-load-test.sh moderate
```

**Validates**:
- Token acquisition latency
- Token caching efficiency
- OIDC issuer throughput
- Token expiration handling

### 3. WebSocket Connection Load Test
Validates WebSocket stability and message throughput.

**File**: `run-websocket-load-test.sh`

**Scenarios**:
- **light**: 10 VUS, 1 connection/user, 1 msg/sec
- **moderate**: 50 VUS, 2 connections/user, 5 msgs/sec
- **stress**: 200 VUS, 3 connections/user, 10 msgs/sec

**Run**:
```bash
DRY_RUN=0 WS_ENDPOINT=wss://ide.kushnir.cloud/ws ./run-websocket-load-test.sh moderate
```

**Validates**:
- WebSocket connection establishment
- Message delivery latency
- Connection stability over time
- Bidirectional communication

### 4. Session Creation Load Test
Validates session-broker throughput and resource management.

**File**: `run-session-creation-load-test.sh`

**Scenarios**:
- **light**: 10 VUS, 50 sessions total
- **moderate**: 50 VUS, 200 sessions total
- **stress**: 200 VUS, 600 sessions total

**Run**:
```bash
DRY_RUN=0 SESSION_ENDPOINT=https://ide.kushnir.cloud/api/sessions ./run-session-creation-load-test.sh moderate
```

**Validates**:
- Session creation latency
- Session validation performance
- Session cleanup efficiency
- Resource usage under concurrent session load
- Database connection pool capacity

### 5. API Endpoint Load Test
Validates authenticated API performance including authorization and RBAC.

**File**: `run-api-endpoint-load-test.sh`

**Scenarios**:
- **light**: 10 VUS, ~50 req/sec
- **moderate**: 50 VUS, ~200 req/sec
- **stress**: 200 VUS, ~500 req/sec

**Run**:
```bash
DRY_RUN=0 API_ENDPOINT=https://ide.kushnir.cloud/api/v1 ./run-api-endpoint-load-test.sh moderate
```

**Validates**:
- API endpoint performance under load
- JWT authentication overhead
- RBAC authorization checks
- Permission enforcement correctness

### 6. Collaboration Platform Load Test with SLO Validation

Validates real-time collaboration features with comprehensive SLO monitoring.

**Files**:
- `collaboration-platform-load-test.js` — k6 load test script with SLO validation
- `run-collaboration-platform-load-test.sh` — Command-line runner

**Features**:
- Real-time collaborative editing with conflict detection
- Presence awareness and cursor tracking
- WebSocket stability and message delivery
- Session recovery and resilience
- Comprehensive SLO threshold validation

**SLO Thresholds** (FAANG-level quality targets):
- Collaboration Latency P99: < 200ms
- Collaboration Latency P95: < 100ms
- Message Delivery Success: > 99.9%
- Presence Sync P95: < 100ms
- Edit Conflict Rate: < 10%
- WebSocket Health Success: > 99.8%
- Connection Establishment P95: < 500ms

**Scenarios**:
- **light**: 10 VUS, 5 min duration
- **moderate**: 20 VUS, 10 min duration (default)
- **stress**: 50-100 VUS, 15+ min duration

**Run**:
```bash
# Dry run (validate configuration only)
./run-collaboration-platform-load-test.sh --dry-run

# Execute moderate load test
./run-collaboration-platform-load-test.sh --execute --scenario moderate

# Stress test with custom VUs
./run-collaboration-platform-load-test.sh --execute --scenario stress --vus 100

# Custom configuration
./run-collaboration-platform-load-test.sh --execute \
  --scenario moderate \
  --duration 15m \
  --vus 30 \
  --url https://staging.kushnir.cloud \
  --ws-url wss://staging.kushnir.cloud/ws
```

**Validates**:
- Collaborative editing latency under load
- Edit conflict detection and resolution
- Presence synchronization within SLO bounds
- WebSocket connection reliability
- Message delivery success rates
- Session recovery after network failures
- Performance at various VU levels
- Real-time metrics collection for SLO monitoring
- Error handling with unauthorized requests
- Unauthorized access denial

### 6. Failover Load Test
Validates system resilience during primary-to-replica failover.

**File**: `run-failover-load-test.sh`

**Scenarios**:
- **monitor**: Light monitoring during failover (5 VUS)
- **light**: Light load during failover (10 VUS)
- **moderate**: Moderate load during failover (50 VUS)

**Run**:
```bash
# Requires manual intervention to trigger failover
DRY_RUN=0 FAILOVER_TRIGGER_DELAY=30 ./run-failover-load-test.sh light
```

**Validates**:
- Failover detection time (RTO - Recovery Time Objective)
- Error rate during failover transition
- Traffic routing to replica
- Request recovery post-failover
- Connection stability during infrastructure switch
- Data consistency across failover

### 7. Comprehensive Load Test Suite
Orchestrates all tests and generates consolidated report.

**File**: `run-comprehensive-load-tests.sh`

**Run**:
```bash
DRY_RUN=0 SCENARIO=light ./run-comprehensive-load-tests.sh
```

**Output**:
- Individual test results in `artifacts/load-test-results/<timestamp>/`
- Comprehensive report: `LOAD-TEST-REPORT.md`
- Per-test metrics JSON files
- Test logs for debugging

## Environment Variables

### Common
- `BASE_URL` (default: `https://ide.kushnir.cloud`)
- `SCENARIO` (default: `light`) - Options: light, moderate, stress
- `DRY_RUN` (default: `1`) - Set to 0 to execute actual tests

### OAuth Flow Test
- `BASE_URL` - Target URL for OAuth flow

### JWT Token Test
- `TOKEN_ENDPOINT` - Token acquisition endpoint
- `CLIENT_ID` - OAuth client ID (default: `code-server`)
- `CLIENT_SECRET` - OAuth client secret

### WebSocket Test
- `WS_ENDPOINT` - WebSocket server endpoint
- `BASE_URL` - For constructing WS endpoint if needed

### Orchestrator
- `GENERATE_REPORT` (default: `1`) - Generate markdown report
- `UPLOAD_RESULTS` (default: `0`) - Upload results to GitHub (future)

## Example Workflows

### Full Production Readiness Validation
```bash
# 1. Start with light load
DRY_RUN=0 SCENARIO=light ./run-comprehensive-load-tests.sh

# 2. Escalate to moderate load
DRY_RUN=0 SCENARIO=moderate ./run-comprehensive-load-tests.sh

# 3. Final stress test
DRY_RUN=0 SCENARIO=stress ./run-comprehensive-load-tests.sh
```

### Individual Component Validation
```bash
# Focus on OAuth flow under stress
DRY_RUN=0 SCENARIO=stress ./run-oauth-flow-load-test.sh

# Validate token caching efficiency
DRY_RUN=0 SCENARIO=moderate ./run-jwt-token-load-test.sh

# Test WebSocket stability
DRY_RUN=0 SCENARIO=light ./run-websocket-load-test.sh
```

### CI/CD Integration
```bash
# In GitHub Actions workflow:
bash scripts/load-testing/run-comprehensive-load-tests.sh light
```

## Interpreting Results

### Key Metrics

**Response Time** (p95, p99):
- ✓ < 200ms: Excellent
- ✓ 200-500ms: Good
- ⚠ 500ms-1s: Acceptable but monitor
- ✗ > 1s: Performance issue

**Error Rate**:
- ✓ < 1%: Excellent
- ✓ 1-5%: Good
- ⚠ 5-10%: Acceptable for stress testing
- ✗ > 10%: Critical issue

**Cache Hit Rate** (token tests):
- ✓ > 90%: Excellent caching
- ✓ 70-90%: Good
- ⚠ < 70%: Consider increasing TTL

**Connection Stability** (WebSocket):
- ✓ > 99%: Excellent
- ✓ 95-99%: Good
- ⚠ < 95%: Review server logs

## Test Results Directory

Results are stored in: `artifacts/load-test-results/<timestamp>/`

**Contents**:
```
<timestamp>/
├── LOAD-TEST-REPORT.md              # Comprehensive report
├── oauth-flow-summary.json          # OAuth test metrics
├── oauth-flow-detailed.json         # Detailed response data
├── oauth-flow.log                   # Test execution log
├── jwt-token-summary.json           # Token test metrics
├── jwt-token.log                    # Token test log
├── websocket-summary.json           # WebSocket metrics
├── websocket.log                    # WebSocket test log
└── *.metadata.json                  # Test metadata
```

## Troubleshooting

### k6 Not Found
```bash
# Verify installation
k6 version

# Install or reinstall
go install github.com/grafana/k6@latest
```

### Connection Refused
```bash
# Verify target endpoint is accessible
curl -i https://ide.kushnir.cloud

# Check network/firewall
ping ide.kushnir.cloud
```

### Tests Hang or Timeout
- Check infrastructure performance
- Reduce load scenario (light → dry run)
- Review server logs for errors
- Verify no ongoing maintenance

### Metrics Parse Errors
```bash
# Verify jq is installed
jq --version

# Manually inspect results
cat artifacts/load-test-*-summary.json | jq .
```

## Performance Baselines (Target)

These are **target** performance baselines for production readiness. Your infrastructure should meet or exceed these under the specified load.

| Test | Scenario | P95 Latency | Success Rate | Notes |
|------|----------|-------------|--------------|-------|
| OAuth Flow | light (10 VUS) | < 500ms | > 99% | Login critical path |
| OAuth Flow | moderate (50 VUS) | < 500ms | > 98% | Peak user hours |
| JWT Token | light (50 tok/s) | < 200ms | > 99% | With caching |
| JWT Token | moderate (200 tok/s) | < 300ms | > 98% | Cache efficiency >75% |
| WebSocket | light (10 conn) | < 100ms | > 99% | Real-time channels |
| WebSocket | moderate (50 conn) | < 150ms | > 98% | Scaling test |
| Session | light (50 sess) | < 200ms | > 99% | Create/Read/Delete |
| Session | moderate (200 sess) | < 250ms | > 98% | Resource limits |
| API Endpoint | light (50 req/s) | < 500ms | > 99% | With auth/RBAC |
| API Endpoint | moderate (200 req/s) | < 600ms | > 98% | Auth overhead |
| Failover | light (10 VUS) | < 2s | > 85% during window | RTO goal: < 5s |
| Failover | moderate (50 VUS) | < 2s | > 80% during window | With moderate load |

## Next Steps

1. **Run dry-run tests** to validate setup:
   ```bash
   DRY_RUN=1 ./run-comprehensive-load-tests.sh
   ```

2. **Establish baseline** with light load:
   ```bash
   DRY_RUN=0 SCENARIO=light ./run-comprehensive-load-tests.sh
   ```

3. **Review results** and metrics:
   ```bash
   cat artifacts/load-test-results/*/LOAD-TEST-REPORT.md
   ```

4. **Escalate testing** as infrastructure stabilizes:
   ```bash
   DRY_RUN=0 SCENARIO=moderate ./run-comprehensive-load-tests.sh
   DRY_RUN=0 SCENARIO=stress ./run-comprehensive-load-tests.sh
   ```

5. **Integrate into CI/CD** for continuous validation

## Additional Resources

- [k6 Documentation](https://k6.io/docs/)
- [k6 Script Examples](https://k6.io/docs/javascript-api/examples/)
- [Performance Testing Best Practices](https://k6.io/docs/testing-guides/running-large-tests/)
- [Thresholds & Acceptance Criteria](https://k6.io/docs/results-output/web-dashboard/#thresholds)

## Support

For issues or enhancements, create an issue in the GitHub repository with:
- Test scenario used (light/moderate/stress)
- Base URL tested
- Error logs from `artifacts/load-test-*-<timestamp>.log`
- Environment details (OS, k6 version, network)
