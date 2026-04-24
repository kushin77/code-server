# VPN-Gated E2E Testing Framework

**Purpose**: VPN-Gated E2E Testing Framework runbook — operational procedure for vpn gated e2e testing response.

---
title: VPN-Gated E2E Testing Framework
description: Architecture, setup, and execution guide for VPN-gated Playwright E2E tests
owner: qa-infra
last_review_date: 2026-04-20
status: active
related_issues:
  - 985
  - 982
  - 986
  - 987
  - 988
---

# VPN-Gated E2E Testing Framework

## Overview

This document describes the E2E testing infrastructure that gates all tests behind VPN connectivity checks. The framework ensures tests only run when on-prem resources (IDE, Appsmith, PostgreSQL) are reachable.

## Architecture

### Components

1. **VPN Preflight Check** (`scripts/ci/check-vpn-connectivity.sh`)
   - Verifies VPN connectivity before test execution
   - Uses ICMP ping + HTTP fallback
   - Configurable target host/URL
   - Fail-open or fail-closed mode (via `REQUIRE_VPN`)

2. **Test Workflow** (`.github/workflows/e2e-tests.yml`)
   - VPN preflight job gates all downstream tests
   - Parallel test execution (sharded across workers)
   - Artifact collection and consolidated reporting

3. **Playwright Configuration** (`playwright.config.ts`)
   - VPN connectivity requirement
   - Multi-browser testing (Chrome, Firefox, WebKit, Mobile)
   - Screenshot + video on failure
   - Automatic retry (2x in CI)
   - Test result reporting (HTML, JSON, JUnit, GitHub)

4. **Test Fixtures** (`tests/e2e/fixtures.ts`)
   - VPN connectivity verification
   - Google OAuth authentication
   - Session caching (optional)
   - Common test helpers

### VPN Connectivity Check Flow

```
┌─────────────────────────────────────────────┐
│ GitHub Actions Workflow Triggered           │
└─────────────────┬───────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────┐
│ vpn-preflight Job                           │
│ ┌─────────────────────────────────────────┐ │
│ │ 1. ICMP Ping to 192.168.168.31          │ │
│ │    (if available; may be blocked)       │ │
│ │                                          │ │
│ │ 2. HTTP check to https://ide.kushnir... │ │
│ │    (fallback if ICMP blocked)           │ │
│ └─────────────────────────────────────────┘ │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
    Success          Failure
       │                │
       ▼                ▼
  Continue        Skip/Fail Tests
  (vpn_ready=    (vpn_ready=
   true)         false)
       │                │
       ▼                ▼
  Test Jobs       Conditional Skip
  Execute        (if REQUIRE_VPN=1)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REQUIRE_VPN` | `1` | Enforce VPN check (1=required, 0=optional) |
| `VPN_CHECK_HOST` | `192.168.168.31` | Primary host for ICMP ping |
| `VPN_CHECK_TIMEOUT` | `5` | Timeout in seconds for checks |
| `VPN_CHECK_URL` | `https://ide.kushnir.cloud` | HTTP endpoint for fallback check |
| `E2E_USER_EMAIL` | `qa@kushnir.cloud` | QA user email for authentication |
| `E2E_USER_PASSWORD` | (required) | QA user password (from secrets) |
| `E2E_USER_OAUTH_TOKEN` | (optional) | Cached OAuth token (optional, for faster auth) |
| `BASE_URL` | `https://kushnir.cloud` | Portal base URL |
| `IDE_BASE_URL` | `https://ide.kushnir.cloud` | IDE base URL |

### GitHub Actions Secrets

Add to repository settings (Settings → Secrets and variables → Actions):

```
E2E_USER_EMAIL        = qa@kushnir.cloud
E2E_USER_PASSWORD     = <password_from_gsm_qa-user-password>
E2E_USER_OAUTH_TOKEN  = (optional, cached token)
```

## Usage

### Local Development

```bash
# Run all E2E tests (requires VPN + QA user credentials)
pnpm exec playwright test

# Run specific test suite
pnpm exec playwright test tests/e2e/specs/oauth-login.spec.ts

# Run with debug mode (opens inspector)
pnpm exec playwright test --debug

# Run with specific browser
pnpm exec playwright test --project=chromium

# Run with tracing (for debugging failures)
pnpm exec playwright test --trace=on

# View test results in HTML report
pnpm exec playwright show-report
```

### Environment Setup for Local Testing

```bash
# Set up environment variables
export E2E_USER_EMAIL="qa@kushnir.cloud"
export E2E_USER_PASSWORD="$(gcloud secrets versions access latest --secret=qa-user-password)"
export BASE_URL="https://kushnir.cloud"
export IDE_BASE_URL="https://ide.kushnir.cloud"
export REQUIRE_VPN="1"  # Enforce VPN check locally

# Verify VPN is working
bash scripts/ci/check-vpn-connectivity.sh

# Run tests
pnpm exec playwright test
```

### CI/CD Execution

The workflow runs automatically on:
- Push to `main` (if code/tests changed)
- Pull requests (if code/tests changed)
- Daily schedule (2 AM UTC)
- Manual trigger (`workflow_dispatch`)

**VPN Requirement**: The workflow requires `[self-hosted, vpn-connected]` runners. If you don't have a VPN-connected self-hosted runner, tests will be skipped with an informational message.

### Manual Test Execution via Workflow Dispatch

```bash
# Trigger E2E tests manually
gh workflow run e2e-tests.yml \
  --repo kushin77/code-server \
  -f require_vpn=true

# Trigger without VPN requirement (for testing without VPN)
gh workflow run e2e-tests.yml \
  --repo kushin77/code-server \
  -f require_vpn=false
```

## Test Structure

### OAuth Login Tests (`tests/e2e/specs/oauth-login.spec.ts`)

Target: 20+ tests

- Login flow validation
- OAuth scope verification
- Token refresh
- Logout flow
- Error handling (invalid credentials, timeout)
- Multi-session management

### Appsmith Portal Tests (`tests/e2e/specs/appsmith-portal.spec.ts`)

Target: 30+ tests

- Portal navigation
- Application CRUD operations
- Data source connectivity
- Query execution
- UI editor functionality
- Error handling

### IDE Launch Tests (`tests/e2e/specs/ide-launch.spec.ts`)

Target: 25+ tests

- IDE startup performance
- Workspace loading
- File operations
- Terminal functionality
- Extension loading
- Error recovery

### Session/Failover Tests (Planned)

Target: 15+ tests

- Session persistence across failover
- OAuth token refresh during failover
- Cross-host session continuity

### Error Handling Tests (Planned)

Target: 20+ tests

- Network timeouts
- Invalid credentials
- VPN disconnection recovery
- Rate limiting
- Error page rendering

## Test Execution Strategy

### Sharding (Parallel Execution)

Tests are sharded across workers to reduce execution time:

```
Job                    Shards
─────────────────────────────────
oauth-login-tests      [1/2, 2/2]     (2 workers)
appsmith-portal-tests  [1/3, 2/3, 3/3] (3 workers)
ide-launch-tests       [1/2, 2/2]     (2 workers)
```

Total execution time: ~45 minutes (parallel) vs ~2 hours (sequential)

### Retry Strategy

- **Local**: No retries (fail fast for debugging)
- **CI**: 2 retries per test (transient failure recovery)

Retries help with:
- Network timeouts
- Race conditions (timing-sensitive UI)
- Browser startup delays
- Server temporary unavailability

### Artifact Collection

Test results collected:

- `playwright-report/` - HTML report with traces, screenshots, videos
- `test-results/results.json` - Machine-readable results (JSONL)
- `test-results/results.xml` - JUnit format (for CI integration)
- GitHub Actions check run (linked to PR/commit)

Retention: **30 days**

## VPN Connectivity Check Details

### ICMP Ping Check

```bash
ping -c 1 -W 5 192.168.168.31
```

**Pros**: Fast, direct connectivity check  
**Cons**: May be blocked by firewalls/ISPs

### HTTP Fallback Check

```bash
curl -s -o /dev/null -w "%{http_code}" \
  --connect-timeout 5 \
  https://ide.kushnir.cloud
```

**Pros**: Works through most firewalls  
**Cons**: Slightly slower, depends on service availability

### Expected Responses

| Method | Success Codes | Behavior |
|--------|---------------|----------|
| ICMP Ping | 0 (reply) | Sets `VPN_PING_SUCCESS=true` |
| HTTP | 200, 301, 302, 401, 403 | Sets `VPN_HTTP_SUCCESS=true` |
| Either | ✓ (at least one) | `VPN_READY=true` (tests proceed) |
| Both fail | ✗ | `VPN_READY=false` (tests skip if `REQUIRE_VPN=1`) |

## Troubleshooting

### Tests Skip with "VPN Unreachable"

**Cause**: VPN not connected or firewall blocking probes

**Solutions**:
1. Verify VPN connection: `bash scripts/ci/check-vpn-connectivity.sh`
2. Check firewall rules (allow ICMP, 443/HTTPS)
3. Set `REQUIRE_VPN=0` to bypass check (not recommended in CI)
4. Override VPN check host: `VPN_CHECK_HOST=192.168.168.42`

### Tests Timeout

**Cause**: Network latency, browser startup, or test complexity

**Solutions**:
1. Increase timeout: `--timeout=120000` (ms)
2. Run tests locally with `--debug` to identify slow steps
3. Check VPN latency: `ping 192.168.168.31`
4. Verify QA user credentials are correct

### Authentication Fails

**Cause**: QA user password incorrect or expired, or OAuth config mismatch

**Solutions**:
1. Verify password: `echo "$E2E_USER_PASSWORD" | wc -c` (should be non-empty)
2. Check Google OAuth configuration (redirect URIs match)
3. Verify QA user exists and is not locked: `gcloud identity users describe qa@kushnir.cloud`
4. Clear browser storage: `PLAYWRIGHT_BROWSERS_PATH=/tmp/pw-browsers-new`

### Browser Download Fails

**Cause**: Network issues or insufficient disk space

**Solutions**:
1. Pre-download browsers: `pnpm exec playwright install`
2. Use existing downloads: `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`
3. Check disk space: `df -h /tmp`

## Security Considerations

1. **VPN Credentials**: Always use GitHub Actions secrets, never commit credentials
2. **QA User Password**: Store in GSM (Google Secret Manager), rotate quarterly
3. **Self-Hosted Runner**: Keep VPN client updated, restrict network access
4. **OAuth Tokens**: Don't log or expose in test output; mask in CI logs
5. **Test Data**: Use isolated test user (qa@kushnir.cloud), don't share credentials

## Monitoring & Alerts

### CI Workflow Status

Monitor in GitHub Actions:
```
.github/workflows/e2e-tests.yml
```

### Test Result Tracking

- Weekly execution summary sent to team
- Flaky tests identified automatically (retries)
- VPN connectivity baseline tracked

### Known Flaky Tests

None documented yet (placeholder for future issues)

## Next Steps

1. Set up `[self-hosted, vpn-connected]` runner
2. Create QA user and store credentials in GSM
3. Update `.env` with E2E variables
4. Run initial test suite manually: `pnpm exec playwright test --workers=1`
5. Review test results and artifact collection
6. Integrate with PR checks and status reports

## Related Issues

- #982 - QA User & Comprehensive E2E Testing Infrastructure (parent EPIC)
- #983 - Create qa@kushnir.cloud user
- #984 - Configure QA user OAuth whitelist + GSM credentials
- #986 - E2E OAuth login tests
- #987 - E2E Appsmith portal tests
- #988 - E2E IDE launch tests
