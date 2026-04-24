# P3-1676 SSO Validation - Test Execution Guide

## Overview

This document describes how to run the P3-1676 SSO validation Playwright test suite with automatic retry logic for flaky test handling.

## Prerequisites

```bash
# Install Node.js 20+
node --version  # Should be v20 or higher

# Install dependencies
npm install @playwright/test

# Install Playwright browsers
npx playwright install chromium
```

## Configuration

Test configuration is defined in two files:

### 1. playwright.config.ts
- **Test timeout:** 30 seconds per test (configurable via PLAYWRIGHT_TIMEOUT)
- **Retries:** 3 automatic retries on failure (configurable via PLAYWRIGHT_RETRIES)
- **Reporting:** HTML, JSON, JUnit formats
- **Traces:** Captured on first retry for debugging
- **Screenshots:** Only on failure
- **Videos:** Captured on failure

### 2. .env.test
Environment variables for test execution:
```bash
TEST_BASE_URL=https://ide.kushnir.cloud
PORTAL_BASE_URL=https://kushnir.cloud
PLAYWRIGHT_TIMEOUT=30000      # 30 seconds
PLAYWRIGHT_RETRIES=3          # 3 retry attempts
REQUIRE_VPN=0                 # Optional VPN tests
REQUIRE_SINGLE_LOGIN=1        # Enforce single-session mode
```

## Running Tests

### Option 1: GitHub Actions (Recommended)

Automatically runs daily at 2 AM UTC:

```bash
# Manual trigger via GitHub CLI
gh workflow run p3-1676-sso-validation.yml \
  --ref main \
  -f environment=production
```

### Option 2: Local Execution

```bash
# Load test environment
source .env.test

# Run all tests with retry logic
npx playwright test tests/e2e/sso-flows.spec.ts

# Run specific flow
npx playwright test tests/e2e/sso-flows.spec.ts -g "Flow 1:"

# Run with verbose output
npx playwright test tests/e2e/sso-flows.spec.ts --reporter=list

# Run with debug mode
DEBUG=pw:api npx playwright test tests/e2e/sso-flows.spec.ts
```

### Option 3: With Custom Configuration

```bash
# Override retry count
PLAYWRIGHT_RETRIES=5 npx playwright test tests/e2e/sso-flows.spec.ts

# Override timeout
PLAYWRIGHT_TIMEOUT=60000 npx playwright test tests/e2e/sso-flows.spec.ts

# Skip VPN tests
REQUIRE_VPN=0 npx playwright test tests/e2e/sso-flows.spec.ts

# Enable VPN tests
REQUIRE_VPN=1 npx playwright test tests/e2e/sso-flows.spec.ts
```

## Test Output

### HTML Report
```bash
# Opens in browser after test completion
npx playwright test tests/e2e/sso-flows.spec.ts
npx playwright show-report
```

### Results Files
```
playwright-report/          # HTML report
test-results/results.json   # JSON results
test-results/junit.xml      # JUnit XML (CI integration)
```

## Retry Logic

### How It Works

1. **Test Runs:** Each test runs once initially
2. **Failure Detection:** If test fails, Playwright captures:
   - Full page trace (for debugging)
   - Screenshot (PNG)
   - Video recording (MP4)
3. **Retry:** Automatically retries up to 3 times
4. **Pass/Fail:** Test passes if any retry succeeds

### Configuration

```typescript
// playwright.config.ts
retries: retryCount,  // Default: 3, override via PLAYWRIGHT_RETRIES env var
timeout: timeout,     // Default: 30000ms, override via PLAYWRIGHT_TIMEOUT env var
```

### Example Retry Scenarios

```
Flow 1: New User Onboarding
├─ Attempt 1: Flaky network → FAIL
├─ Attempt 2: Retry from failed point → FAIL
├─ Attempt 3: Clean retry → PASS ✅
└─ Result: PASSED (took 3 attempts)

Flow 2: Returning User
├─ Attempt 1: oauth2-proxy timeout → FAIL
├─ Attempt 2: Clean retry → PASS ✅
└─ Result: PASSED (took 2 attempts)
```

## Continuous Integration

### GitHub Actions Workflow

File: `.github/workflows/p3-1676-sso-validation.yml`

**Schedule:** Daily at 2 AM UTC  
**Manual Trigger:** Yes (via workflow_dispatch)  
**Notifications:** Slack webhooks (success/failure/start)  
**Artifacts:** 30-day retention  
**Archived Results:** 90-day retention

### Workflow Execution Flow

```
1. Checkout code
2. Setup Node.js (v20)
3. Install npm dependencies
4. Install Playwright browsers (chromium)
5. Run tests (with retries)
6. Upload test results
7. Parse results for notifications
8. Send Slack notification
9. Archive results
10. Post to issue (if provided)
```

## Troubleshooting

### Tests Timing Out

```bash
# Increase timeout
PLAYWRIGHT_TIMEOUT=60000 npx playwright test tests/e2e/sso-flows.spec.ts
```

### Flaky Tests Still Failing

```bash
# Increase retry attempts
PLAYWRIGHT_RETRIES=5 npx playwright test tests/e2e/sso-flows.spec.ts
```

### Debug Failed Test

```bash
# View detailed trace
npx playwright show-trace test-results/trace.zip

# Re-run specific flow with debug
DEBUG=pw:api npx playwright test tests/e2e/sso-flows.spec.ts -g "Flow 3:"
```

### VPN Tests Skipped

VPN tests are optional and skipped by default. Enable with:

```bash
REQUIRE_VPN=1 npx playwright test tests/e2e/sso-flows.spec.ts
```

## Performance Metrics

### Test Execution Times
- **Flow 1 (New User):** ~5-8 seconds
- **Flow 2 (Returning User):** ~3-5 seconds  
- **Flow 3 (VPN):** ~2-4 seconds (optional)
- **Flow 4 (Session Expiry):** ~4-6 seconds
- **Integration Test:** ~5-7 seconds
- **Smoke Test:** ~3-5 seconds
- **Total Suite:** ~25-35 seconds (without retries)

## Test Coverage

| Flow | Tests | Assertions | Coverage |
|------|-------|-----------|----------|
| Flow 1 | 1 | 5 | New user oauth2-proxy integration |
| Flow 2 | 1 | 5 | Session persistence |
| Flow 3 | 1 | 5 | VPN/Access control (optional) |
| Flow 4 | 1 | 6 | Token expiry & refresh |
| Integration | 1 | 4 | All flows sequential |
| Smoke | 1 | 5 | Infrastructure health |
| **TOTAL** | **6** | **30** | **Complete SSO stack** |

## Support & Escalation

### Issue: Tests consistently failing
1. Check if services are HEALTHY: `curl https://ide.kushnir.cloud/health`
2. Review playwright-report HTML for specific failures
3. Check GitHub Actions logs for environment issues
4. File issue in GitHub with test results

### Contact
- **Slack:** #infrastructure-automation
- **GitHub Issues:** kushin77/code-server
- **Wiki:** P3-1676 SSO Validation (in progress)

## References

- [Playwright Documentation](https://playwright.dev)
- [Playwright Config Options](https://playwright.dev/docs/test-configuration)
- [Retry Logic](https://playwright.dev/docs/test-retries)
- [GitHub Actions Workflows](https://docs.github.com/en/actions/using-workflows)
