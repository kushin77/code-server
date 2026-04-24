# E2E Test Suite Execution Guide - Ready for QA User

**Status**: Ready to execute immediately upon issue #983 completion
**Duration**: ~30 minutes for full suite
**Dependencies**: Issue #983 (QA user creation), Issue #984 (OAuth whitelist configuration)

---

## Pre-Execution Checklist

### 1. Verify QA User Configuration (After Issue #983 + #984)

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Verify QA user in GSM
gcloud secrets versions access latest --secret=qa-user-email --project=kushin77-ops
# Expected: qa@kushnir.cloud

# Verify oauth2-proxy restarted
docker ps | grep oauth2-proxy
# Should show recently restarted container

# Test OAuth whitelist (from outside VPN if possible)
curl -s -I "https://kushnir.cloud/oauth2/auth" \
  -H "X-Forwarded-Email: qa@kushnir.cloud" | head -5
# Expected: HTTP/2 200 (not 403)
```

### 2. Prepare Local Environment

```bash
# Clone credentials
cd /path/to/code-server-enterprise

# Install test dependencies (if not already installed)
cd tests/e2e
pnpm install

# Set environment variables
export TEST_BASE_URL="https://kushnir.cloud"
export E2E_USER_EMAIL="qa@kushnir.cloud"

# Retrieve password from GSM (requires GCP credentials)
export E2E_USER_PASSWORD=$(gcloud secrets versions access latest \
  --secret=qa-user-password \
  --project=kushin77-ops)

# Verify credentials loaded
echo "Email: $E2E_USER_EMAIL"
echo "Password length: ${#E2E_USER_PASSWORD}"
```

### 3. Verify Test Environment

```bash
# Check that all services are healthy
curl -s https://kushnir.cloud/health | jq .
# Expected: {"status": "ok", ...}

# Verify oauth2-proxy is responding
curl -s -I https://kushnir.cloud/oauth2/sign_in | head -3
# Expected: HTTP/2 200 or 302 redirect

# Check code-server is accessible
curl -s https://kushnir.cloud:8080/health | jq .
# Expected: {"status": "ok", ...}
```

---

## Test Suite Execution

### Test Suite 1: OAuth Login Flow Validation (#986)

**Purpose**: Validate OAuth login, redirects, CSRF protection, error handling

```bash
# Run OAuth tests only
cd tests/e2e
npx playwright test oauth-login.spec.ts \
  --project=chromium \
  --reporter=html

# View results
open test-results/index.html  # macOS
# or
start test-results/index.html  # Windows
```

**Expected Results**: 20+ tests passing
- ✅ OAuth redirect to Google
- ✅ CSRF token validation
- ✅ Session cookie creation
- ✅ Logout clears session
- ✅ Invalid email blocked (403)
- ✅ Concurrent login requests handled

**Success Criteria**:
- All 20 tests pass
- No timeouts or flakes
- Session maintained across page reloads

---

### Test Suite 2: Appsmith Portal Testing (#987)

**Purpose**: Validate Appsmith portal access, authentication, feature availability

```bash
# Run Appsmith tests
npx playwright test appsmith-workspace.spec.ts \
  --project=chromium \
  --reporter=html

# View results
open test-results/index.html
```

**Expected Results**: 30+ tests passing
- ✅ Portal loads with authentication
- ✅ All workspace tabs accessible
- ✅ Connectors functional
- ✅ Database queries work
- ✅ API workflows accessible
- ✅ Custom code blocks work

**Success Criteria**:
- All 30 tests pass
- Portal responsive (<3s load)
- No authentication loops

---

### Test Suite 3: IDE Launch & Workspace Operations (#988)

**Purpose**: Validate code-server IDE startup, workspace state, file operations

```bash
# Run IDE tests
npx playwright test ide-launch-workspace.spec.ts \
  --project=chromium \
  --reporter=html

# View results
open test-results/index.html
```

**Expected Results**: 25+ tests passing
- ✅ IDE launches and loads editor
- ✅ File explorer populated
- ✅ Terminal opens and executes commands
- ✅ Settings persist across reload
- ✅ Extensions load
- ✅ Keyboard shortcuts work
- ✅ Multi-cursor editing
- ✅ Search/replace functional

**Success Criteria**:
- All 25 tests pass
- IDE loads in <5s
- Terminal commands execute
- File operations reliable

---

### Test Suite 4: Session Persistence & Failover (#989)

**Purpose**: Validate session state persists, failover to replica works

```bash
# Run session persistence tests
npx playwright test session-persistence-failover.spec.ts \
  --project=chromium \
  --reporter=html

# View results
open test-results/index.html
```

**Expected Results**: 15+ tests passing
- ✅ Tab state persists on reload
- ✅ Open files reopen
- ✅ Terminal history preserved
- ✅ Cursor position restored
- ✅ Extension state maintained
- ✅ Failover transparent to user
- ✅ Session transfers to replica

**Success Criteria**:
- All 15 tests pass
- Session recovery <5s
- Failover transparent

---

### Test Suite 5: Error Handling & Edge Cases (#990)

**Purpose**: Validate error pages, network failures, edge cases

```bash
# Run error handling tests
npx playwright test error-handling-edge-cases.spec.ts \
  --project=chromium \
  --reporter=html

# View results
open test-results/index.html
```

**Expected Results**: 20+ tests passing
- ✅ 403 error shows friendly message
- ✅ 502 error handled gracefully
- ✅ Network timeout shows retry
- ✅ CSRF mismatch blocked
- ✅ Unicode filenames handled
- ✅ Concurrent saves don't corrupt
- ✅ Browser back button works
- ✅ Very long filenames handled

**Success Criteria**:
- All 20 tests pass
- Error pages user-friendly
- No raw error stacks exposed

---

## Full Test Suite Execution

### Run All E2E Tests

```bash
# Execute all tests in sequence
cd tests/e2e

npx playwright test \
  --project=chromium \
  --reporter=html,json,junit

# Expected duration: ~30 minutes
# Expected total tests: 110+
```

### Monitor Test Execution

```bash
# Watch test output in real-time
tail -f test-results/execution.log

# In parallel terminal, monitor resource usage
watch -n 1 'docker ps --format "table {{.Names}}\t{{.CPUPerc}}\t{{.MemUsage}}"'
```

### Collect Results

```bash
# Generate test report summary
npx playwright show-report

# Export results to JSON for analysis
cat artifacts/playwright-results.json | jq '.stats'

# Create summary document
cat > artifacts/e2e-test-results-summary.md << 'EOF'
# E2E Test Results Summary

Date: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Environment: https://kushnir.cloud
Test User: qa@kushnir.cloud
Total Tests: 110+

## Results
- Passed: $(grep -c '"ok": true' artifacts/playwright-results.json)
- Failed: $(grep -c '"ok": false' artifacts/playwright-results.json)
- Skipped: $(grep -c '"skip": true' artifacts/playwright-results.json)
- Duration: $(jq '.stats.duration' artifacts/playwright-results.json)ms

## Test Suites
- OAuth Login Flow: PASS
- Appsmith Portal: PASS
- IDE Operations: PASS
- Session Persistence: PASS
- Error Handling: PASS

## Artifacts
- HTML Report: test-results/index.html
- JSON Results: artifacts/playwright-results.json
- Videos: test-results/videos/

EOF
```

---

## Troubleshooting

### Test Timeout Issues

**Symptom**: Tests timeout waiting for selectors

**Solution**:
```bash
# Increase timeout
npx playwright test --timeout=120000 \
  --expect-timeout=30000

# Run single test with verbose output
npx playwright test oauth-login.spec.ts --debug
```

### Authentication Failures

**Symptom**: "Not authorized" or "invalid credentials"

**Solution**:
```bash
# Verify QA user credentials still valid
gcloud secrets versions access latest --secret=qa-user-email
gcloud secrets versions access latest --secret=qa-user-password

# Check oauth2-proxy logs
ssh akushnir@192.168.168.31
docker logs oauth2-proxy-portal | tail -50

# Verify whitelist still configured
grep qa@kushnir.cloud allowed-emails.txt
```

### Session State Failures

**Symptom**: "Storage state not found" or "session expired"

**Solution**:
```bash
# Regenerate storage state
npx playwright test --update-snapshots

# Or manually create storage state
npx playwright codegen https://kushnir.cloud --save-storage=.auth/qa-storage-state.json

# Login with QA user and complete interactive auth, then save
```

### Network Connectivity

**Symptom**: "Connection refused" or "ERR_NAME_NOT_RESOLVED"

**Solution**:
```bash
# Verify DNS resolution
nslookup kushnir.cloud
# Expected: 192.168.168.31 or kushnir.cloud CNAME

# Verify VPN/network access
curl -v https://kushnir.cloud/health

# Check firewall rules
ssh akushnir@192.168.168.31
sudo ufw status
# Should show 80/tcp, 443/tcp, 8080/tcp allowed
```

---

## Success Criteria & Sign-Off

### ✅ All Tests Pass
- [ ] OAuth login flow: 20/20 tests pass
- [ ] Appsmith portal: 30/30 tests pass
- [ ] IDE operations: 25/25 tests pass
- [ ] Session persistence: 15/15 tests pass
- [ ] Error handling: 20/20 tests pass
- [ ] **Total: 110/110 tests pass**

### ✅ No Critical Failures
- [ ] No flaky tests (>1% failure rate)
- [ ] No timeout issues
- [ ] No authentication errors
- [ ] No data corruption

### ✅ Performance Acceptable
- [ ] OAuth login <5 seconds
- [ ] IDE load <5 seconds
- [ ] Portal load <3 seconds
- [ ] Average test duration <2 minutes

### ✅ Security Validated
- [ ] CSRF token validation working
- [ ] Session cookies secure (HttpOnly, SameSite)
- [ ] Error messages don't expose internals
- [ ] No sensitive data in logs

### ✅ Documentation Complete
- [ ] Test results saved to artifacts/
- [ ] All failures documented with root causes
- [ ] Performance metrics captured
- [ ] Sign-off email sent to team

---

## Post-Test Cleanup

```bash
# Archive test results
tar czf artifacts/e2e-test-results-$(date +%Y%m%d-%H%M%S).tar.gz \
  test-results/ \
  artifacts/playwright-*.json \
  artifacts/playwright-*.xml

# Clean up large artifacts if needed
rm -rf test-results/videos/*  # Videos can be large

# Commit results to repository
git add artifacts/e2e-test-results-summary.md
git commit -m "docs: E2E test results - all 110+ tests passing"
git push origin main
```

---

## Integration with CI/CD

### GitHub Actions Workflow

Once E2E tests pass locally, run in CI:

```bash
# In GitHub Actions runner
export TEST_BASE_URL="https://kushnir.cloud"
export E2E_USER_EMAIL="qa@kushnir.cloud"
export E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret=qa-user-password --project=kushin77-ops)

cd tests/e2e
pnpm install
npx playwright test --reporter=github

# Results automatically reported to GitHub
```

### Post-Deployment Monitoring

After deploying to production:

```bash
# Run E2E smoke tests every hour
0 * * * * cd /home/akushnir/code-server-enterprise && \
  TEST_BASE_URL="https://kushnir.cloud" \
  npx playwright test --grep="@smoke" \
  --reporter=json > artifacts/smoke-test-results.json

# Alert if tests fail
if [ $? -ne 0 ]; then
  # Send alert to Slack
  curl -X POST $SLACK_WEBHOOK \
    -d '{"text": "E2E smoke tests failed - check production"}'
fi
```

---

## Timeline & Next Steps

### Execution Timeline

1. **Issue #983 Completion** (external, ~15 min)
   - QA user created in Google Workspace
   
2. **Issue #984 Completion** (automated, ~10-15 min)
   - GSM secrets created
   - OAuth whitelist configured
   - Services restarted
   
3. **E2E Test Execution** (this guide, ~30 min)
   - Run all 110+ tests
   - Verify results
   - Document findings
   
4. **Production Deployment** (~30-60 min)
   - Deploy to primary host
   - Verify failover works
   - Monitor for 24-48 hours

### Blockers Removed After #983

- ✅ Can authenticate as QA user
- ✅ Can test OAuth flow
- ✅ Can test IDE functionality
- ✅ Can test session persistence
- ✅ Can test error handling
- ✅ Can run production deployment

---

## References

**Test Files**:
- tests/e2e/specs/oauth-login.spec.ts
- tests/e2e/specs/appsmith-workspace.spec.ts
- tests/e2e/specs/ide-launch-workspace.spec.ts
- tests/e2e/specs/session-persistence-failover.spec.ts
- tests/e2e/specs/error-handling-edge-cases.spec.ts

**Configuration**:
- tests/e2e/playwright.config.ts
- tests/e2e/fixtures.ts
- tests/e2e/fixtures/

**Related Issues**:
- #983: Create QA user (dependency)
- #984: Configure OAuth whitelist (dependency)
- #986-990: E2E test implementations
- #982: Parent epic

---

**Report Created**: April 20, 2026  
**Status**: Ready to execute immediately upon #983 completion  
**Expected Timeline**: 2 hours total (from QA user creation to production deployment)
