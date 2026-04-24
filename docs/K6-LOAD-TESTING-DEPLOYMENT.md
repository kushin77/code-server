# K6 Load Testing Installation & Deployment Guide

## Current Status
- ✅ k6 test scripts written and merged (scripts/loadtest/)
- ✅ k6 installation script created (scripts/ops/install-k6-on-hosts.sh)
- ❌ **BLOCKED**: k6 CLI not installed on production hosts (192.168.168.31, 192.168.168.42)

## Installation Steps

### Option 1: Install on Local Machine (for testing)
```bash
# Linux
bash scripts/ops/install-k6-on-hosts.sh --local

# Or manually for Ubuntu:
curl -sSL https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz | tar xz
sudo mv k6 /usr/local/bin/
```

### Option 2: Install on Production Replicas (Recommended)
```bash
# Install on all production hosts (requires SSH access)
bash scripts/ops/install-k6-on-hosts.sh --all-replicas

# Or install on specific host
bash scripts/ops/install-k6-on-hosts.sh --host 192.168.168.31 --host 192.168.168.42

# Dry-run to verify before executing
bash scripts/ops/install-k6-on-hosts.sh --all-replicas --dry-run
```

### Option 3: Manual Installation on Production Host
On 192.168.168.31 or 192.168.168.42:
```bash
# Create temp directory
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# Download k6
curl -sSL 'https://github.com/grafana/k6/releases/download/v0.50.0/k6-v0.50.0-linux-amd64.tar.gz' | tar xz

# Install (may require sudo)
sudo mv k6 /usr/local/bin/k6
sudo chmod +x /usr/local/bin/k6

# Verify
k6 version

# Cleanup
cd /tmp && rm -rf $TEMP_DIR
```

## Verify Installation
```bash
k6 version
# Expected output: k6 v0.50.0 (...)
```

## Run Load Tests

### After k6 is installed, execute performance tests:

```bash
# Full load testing campaign (baseline + spike + sustained)
cd /path/to/code-server-enterprise
bash scripts/loadtest/run-performance-tests.sh

# Or with custom base URL (for remote testing)
BASE_URL=http://192.168.168.31:8080 bash scripts/loadtest/run-performance-tests.sh

# Individual tests:
k6 run scripts/loadtest/k6-baseline.js
k6 run scripts/loadtest/k6-spike.js
k6 run scripts/loadtest/k6-sustained.js
```

## Test Scenarios

### 1. Baseline Load Test (k6-baseline.js)
- **Virtual Users**: 100
- **Duration**: 10 minutes
- **Ramp-up**: Linear over 2 minutes
- **Success Criteria**:
  - Response time (p95): < 5 seconds
  - Error rate: < 0.1%
  - CPU utilization: < 70%

### 2. Spike Load Test (k6-spike.js)
- **Virtual Users**: 1000 (immediate spike)
- **Duration**: 5 minutes
- **Success Criteria**:
  - Graceful degradation (no crashes)
  - Recovery time: < 2 minutes
  - Error rate: < 1% during spike

### 3. Sustained Load Test (k6-sustained.js)
- **Virtual Users**: 500 continuous
- **Duration**: 30 minutes
- **Success Criteria**:
  - Memory stability (no leaks)
  - No connection pool exhaustion
  - Error rate: < 0.1%

## Environment Variables

```bash
# Override base URL (default: http://localhost:8080)
BASE_URL=http://192.168.168.31:8080

# Override virtual user counts
BASELINE_VUS=50      # Instead of 100
SPIKE_VUS=500        # Instead of 1000
SUSTAINED_VUS=200    # Instead of 500

# Override durations
BASELINE_DURATION=5m   # Instead of 10m
SPIKE_DURATION=2m      # Instead of 5m
SUSTAINED_DURATION=10m # Instead of 30m

# Run tests with custom environment
BASE_URL=http://192.168.168.31:8080 \
BASELINE_VUS=50 \
bash scripts/loadtest/run-performance-tests.sh
```

## Results

Performance test results are saved to:
```
artifacts/performance/
├── baseline-<timestamp>.json
├── spike-<timestamp>.json
├── sustained-<timestamp>.json
├── <timestamp>.log
└── performance-summary.md
```

## Troubleshooting

### k6 not found
```bash
# Check if k6 is in PATH
which k6

# If not found, install it:
bash scripts/ops/install-k6-on-hosts.sh --local
```

### SSH access issues to production hosts
```bash
# Test SSH connection
ssh -v akushnir@192.168.168.31

# If key-based auth fails, check:
# 1. SSH key permissions (should be 600)
# 2. SSH public key is in authorized_keys on remote
# 3. firewall allows SSH (port 22)
```

### Tests fail with connection errors
```bash
# Verify target is accessible
curl -I http://192.168.168.31:8080

# Check if services are running
docker ps -a | grep code-server
docker ps -a | grep caddy
docker ps -a | grep oauth2-proxy
```

## Performance Testing Timeline

### Phase 1: Installation (1-2 hours)
1. Install k6 on all production hosts
2. Verify installation and k6 version
3. Verify test script availability

### Phase 2: Baseline Testing (30 minutes)
1. Run baseline load test (100 VUs, 10 min)
2. Collect metrics and validate against success criteria
3. Document baseline performance

### Phase 3: Spike Testing (30 minutes)
1. Run spike load test (1000 VUs, 5 min)
2. Measure recovery time and error rates
3. Validate graceful degradation

### Phase 4: Sustained Testing (1.5 hours)
1. Run sustained load test (500 VUs, 30 min)
2. Monitor for memory leaks and stability
3. Validate long-running reliability

### Phase 5: Analysis & Reporting (2 hours)
1. Aggregate all test results
2. Compare against success criteria
3. Generate performance report
4. Document recommendations

## Success Criteria Checklist

- [ ] k6 installed on 192.168.168.31
- [ ] k6 installed on 192.168.168.42
- [ ] Baseline test passes (p95 < 5s, error < 0.1%)
- [ ] Spike test passes (graceful degradation, recovery < 2m)
- [ ] Sustained test passes (memory stable, error < 0.1%)
- [ ] All metrics documented in artifacts/performance/
- [ ] Performance report generated
- [ ] Issue #1517 closed with verification evidence

## Related Issues
- #1517 - P2: Production Load Testing & Performance Validation
- #1468 - P0: Production Deployment - ASAP (waiting on load test results)
- #1467 - P1: GO/NO-GO Decision (blocked by load testing)
- #1466 - P1: Staging Deployment Validation

## Commands for Production Deployment Path

Once load testing completes successfully:

```bash
# 1. Document results in issue #1517
# 2. Collect team sign-offs for issue #1464
# 3. Obtain GO/NO-GO decision for issue #1467
# 4. Execute production deployment for issue #1468

# Execute deployment:
bash scripts/ops/redeploy.sh --all-replicas --validate-health-checks
```

---

**Created**: April 23, 2026
**Last Updated**: April 23, 2026
**Status**: Ready for k6 installation on production hosts
