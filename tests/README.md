# End-to-End Test Suite: Cloudflare → Code-Server

## Overview

This comprehensive test suite validates the complete production path from Cloudflare Tunnel edge ingress all the way through to the Code-Server IDE backend. Tests cover all 6 layers of the infrastructure stack, plus integration, load, resilience, and security scenarios.

## Architecture Tested

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: DNS & Connectivity (Public Internet)                  │
│         └─→ Resolving ide.kushnir.cloud                        │
└─────────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 2: Cloudflare Tunnel                                      │
│         ├─ cloudflared daemon (connection to Cloudflare edge)  │
│         └─ Tunnel token authentication                          │
└─────────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Caddy (TLS/WAF)                                        │
│         ├─ TLS termination (internal certificates)              │
│         ├─ Reverse proxy routing                                │
│         └─ Security headers & WAF rules                         │
└─────────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 4: OAuth2-Proxy (Identity)                               │
│         ├─ Authentication gateway                               │
│         ├─ Session cookie management                            │
│         └─ Upstream to Code-Server:8080                         │
└─────────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 5: Code-Server (IDE)                                      │
│         ├─ Backend application (port 8080)                      │
│         ├─ Workspace files & extensions                         │
│         └─ Interactive development environment                  │
└─────────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ Layer 6: Infrastructure (Observability)                        │
│         ├─ PostgreSQL (data persistence)                        │
│         ├─ Redis (caching & sessions)                           │
│         ├─ Prometheus (metrics)                                 │
│         ├─ Grafana (dashboards)                                 │
│         ├─ Jaeger (distributed tracing)                         │
│         └─ AlertManager (alerting)                              │
└─────────────────────────────────────────────────────────────────┘
```

## Test Files

### 1. `e2e-cloudflare-to-code.sh`
Comprehensive end-to-end test covering all layers with detailed diagnostics.

**What it tests:**
- DNS resolution
- Cloudflare Tunnel connectivity
- Caddy TLS configuration
- OAuth2-Proxy health
- Code-Server accessibility
- Infrastructure services
- Inter-service networking
- Load resilience
- Security posture

**Usage:**
```bash
# Run with defaults (192.168.168.31)
bash tests/e2e-cloudflare-to-code.sh

# Run with verbose output
bash tests/e2e-cloudflare-to-code.sh --verbose

# Run with debug logging
bash tests/e2e-cloudflare-to-code.sh --verbose --debug

# Run against specific host/domain
bash tests/e2e-cloudflare-to-code.sh --host 192.168.168.31 --domain ide.kushnir.cloud
```

### 2. `orchestrate-e2e.sh`
Test orchestrator that runs full path validation with latency measurements and failure injection.

**What it tests:**
- Full path latency (Cloudflare → Code-Server)
- Failure modes (Caddy/OAuth2/Code-Server restart)
- Recovery times
- Path continuity validation
- Security headers
- Observability (Prometheus, Jaeger)

**Usage:**
```bash
# Run full orchestration
bash tests/orchestrate-e2e.sh

# Run specific test suite
bash tests/orchestrate-e2e.sh --suite resilience
bash tests/orchestrate-e2e.sh --suite security
bash tests/orchestrate-e2e.sh --suite latency
```

### 3. `ci-runner.sh`
CI/CD-integrated test runner with GitHub Actions formatting.

**What it tests:**
- All 6 infrastructure layers
- Integration validations
- Path latency measurements
- CI-friendly output formatting

**Usage (Local):**
```bash
# Run locally (auto-detects non-CI environment)
bash tests/ci-runner.sh

# Set production host
PROD_HOST=192.168.168.31 bash tests/ci-runner.sh
```

**Usage (GitHub Actions):**
```yaml
- name: Run E2E Tests
  run: |
    bash tests/ci-runner.sh
  env:
    PROD_HOST: ${{ secrets.PROD_HOST }}
    PROD_USER: akushnir
```

### 4. `lib/test-utils.sh`
Shared utilities library for all test suites.

**Provides:**
- Assertion functions (equals, not_empty, contains, http_status)
- SSH helpers (docker ps, inspect, logs)
- HTTP helpers (get, head, status, latency)
- Service health checks
- Metrics measurement (latency, throughput)
- Report generation
- CI/CD integration

## Test Coverage

| Layer | Component | Test | Coverage |
|-------|-----------|------|----------|
| 1 | DNS | Resolution | ✅ |
| 2 | Cloudflare Tunnel | Connection, Logs | ✅ |
| 2 | Cloudflare Tunnel | In-flight metrics | ⚠ (requires integration) |
| 3 | Caddy | TLS Certificate | ✅ |
| 3 | Caddy | Reverse Proxy | ✅ |
| 3 | Caddy | Container Health | ✅ |
| 4 | OAuth2-Proxy | Container Health | ✅ |
| 4 | OAuth2-Proxy | Port 4180 | ✅ |
| 4 | OAuth2-Proxy | Configuration | ✅ |
| 5 | Code-Server | Container Health | ✅ |
| 5 | Code-Server | Port 8080 | ✅ |
| 5 | Code-Server | Login Interface | ✅ |
| 6 | PostgreSQL | Container Health | ✅ |
| 6 | Redis | Container Health | ✅ |
| 6 | Prometheus | Metrics | ✅ |
| 6 | Grafana | UI Accessibility | ✅ |
| 6 | Jaeger | Tracing Backend | ✅ |
| - | Docker Network | Connectivity | ✅ |
| - | Volumes | Mounts | ✅ |
| - | Load | Concurrent Requests | ✅ |
| - | Resilience | Failover Recovery | ✅ |
| - | Security | TLS Version | ✅ |
| - | Security | Secret Exposure | ✅ |

## Running Tests

### Quick Start
```bash
# Navigate to project root
cd code-server-enterprise

# Make test scripts executable
chmod +x tests/*.sh tests/lib/*.sh

# Run complete end-to-end test
bash tests/e2e-cloudflare-to-code.sh --verbose
```

### Expected Output (Success)
```
═══════════════════════════════════════════════
  End-to-End Test Suite: Cloudflare → Code-Server
═══════════════════════════════════════════════

► LAYER 1: DNS RESOLUTION
✓ DNS resolved ide.kushnir.cloud → 192.168.168.31

► LAYER 2: CLOUDFLARE TUNNEL
✓ Cloudflare tunnel container running
✓ Cloudflare tunnel token configured

► LAYER 3: CADDY (TLS/WAF)
✓ Caddy TLS responding (status: 200)
✓ Caddy configured to reverse_proxy code-server:8080
✓ Caddy configured with internal TLS
✓ Caddy container running

► LAYER 4: OAUTH2-PROXY (IDENTITY)
✓ OAuth2-Proxy container running
✓ OAuth2-Proxy responding on port 4180
✓ OAuth2-Proxy upstream configured to code-server:8080
✓ OAuth2-Proxy listening on 0.0.0.0:4180
✓ OAuth2-Proxy cookie-secret configured

► LAYER 5: CODE-SERVER (IDE)
✓ Code-Server container running
✓ Code-Server responding on port 8080
✓ Code-Server login interface detected

► LAYER 6: INFRASTRUCTURE (OBSERVABILITY)
✓ Prometheus responding (status: 200)
✓ Grafana accessible (status: 200)
✓ Jaeger UI accessible (status: 200)

► INTEGRATION TESTS
✓ Core services healthy (11/11)
✓ Docker network 'enterprise' exists
✓ Data volumes mounted: 4/4
✓ Code-Server → PostgreSQL: time=0.8 ms

► LOAD TESTS
✓ Code-Server load test: 10/10 requests successful
✓ OAuth2-Proxy load test: 5/5 requests successful

► SECURITY TESTS
✓ Modern TLS version: Protocol  : TLSv1.3
✓ No secrets found in logs

╔════════════════════════════════════════════════╗
║         END-TO-END TEST SUMMARY                ║
╠════════════════════════════════════════════════╣
║ Total Tests:    19
║ Passed:         19
║ Failed:         0
║ Success Rate:   100%
╚════════════════════════════════════════════════╝

Test execution log: test-results/e2e-20260414_234530.log
```

## Troubleshooting Failed Tests

### SSH Connection Issues
```bash
# Test SSH connectivity first
ssh -v akushnir@192.168.168.31 "echo ok"

# Add to ~/.ssh/config if needed
Host prod
  HostName 192.168.168.31
  User akushnir
  StrictHostKeyChecking no
```

### Docker Connection Issues
```bash
# Verify docker daemon on production host
ssh akushnir@192.168.168.31 "docker ps"

# Check docker-compose file
ssh akushnir@192.168.168.31 "cat /home/akushnir/code-server-enterprise/docker-compose.yml"
```

### Cloudflare Tunnel Issues
```bash
# Check tunnel token configuration
ssh akushnir@192.168.168.31 "grep CLOUDFLARE_TUNNEL_TOKEN /home/akushnir/code-server-enterprise/.env"

# View tunnel logs
ssh akushnir@192.168.168.31 "docker logs code-server-enterprise-cloudflared-1 --tail 20"
```

### OAuth2-Proxy Authorization Issues
```bash
# Check OAuth2 configuration
ssh akushnir@192.168.168.31 "docker logs code-server-enterprise-oauth2-proxy-1 --tail 20"

# Verify cookie secret (should be 32 bytes)
ssh akushnir@192.168.168.31 "grep OAUTH2 /home/akushnir/code-server-enterprise/.env"
```

## CI/CD Integration

### GitHub Actions
Add to `.github/workflows/e2e-tests.yml`:

```yaml
name: End-to-End Tests

on:
  push:
    branches: [main, develop]
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run E2E Tests
        run: bash tests/ci-runner.sh
        env:
          PROD_HOST: ${{ secrets.PROD_HOST }}
          PROD_USER: akushnir
```

### GitLab CI
Add to `.gitlab-ci.yml`:

```yaml
e2e-tests:
  script:
    - bash tests/ci-runner.sh
  environment:
    name: production
  only:
    - main
```

## Performance Baselines

Target metrics for production deployment:

| Metric | Target | Status |
|--------|--------|--------|
| DNS Resolution | <100ms | ✅ |
| TLS Handshake | <200ms | ✅ |
| OAuth2 Auth | <300ms | ✅ |
| Code-Server Response | <500ms | ✅ |
| Full Path (Cloudflare → Code) | <1000ms | ✅ |
| Service Recovery (Failover) | <5s | ✅ |
| Container Startup | <10s | ✅ |

## Best Practices

1. **Run tests regularly**: Schedule hourly or daily
2. **Capture diagnostics**: Use `capture_diagnostics()` on failures
3. **Monitor trends**: Track latency metrics over time
4. **Alert on failures**: Set up notifications for test failures
5. **Document results**: Archive test reports for compliance
6. **Load test frequently**: Ensure system scales under traffic

## Contributing

When adding new tests:

1. Add test function to appropriate layer in main script
2. Use assertion helpers from `test-utils.sh`
3. Follow naming convention: `test_<layer>_<component>`
4. Include descriptive output with `print_*` functions
5. Update this README with new coverage

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Caddy Reverse Proxy](https://caddyserver.com/docs/)
- [OAuth2-Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Code-Server Self-Hosted](https://coder.com/docs/code-server/latest)
- [docker-compose Reference](https://docs.docker.com/compose/compose-file/)

---

**Last Updated**: April 14, 2026  
**Test Suite Version**: 1.0  
**Compatible With**: code-server-enterprise Phase 26+
