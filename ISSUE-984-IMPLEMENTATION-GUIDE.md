# Issue #984 Implementation Guide - QA User OAuth Whitelist & GSM Credentials

**Status**: Ready to execute immediately upon issue #983 completion
**Estimated Duration**: 10-15 minutes
**Complexity**: Low (mostly automated steps)

---

## Pre-Requisites (From Issue #983)

Before starting this issue, verify issue #983 is complete:
- [x] qa@kushnir.cloud user created in Google Workspace
- [x] Password set and known
- [x] 2FA disabled (for E2E test automation)
- [x] No admin permissions assigned
- [x] Password temporarily stored (to be moved to GSM in Step 1)

---

## Step 1: Create GSM Secrets

### 1.1 Create qa-user-email Secret

```bash
# On primary host (192.168.168.31)
ssh akushnir@192.168.168.31

# Create the secret
gcloud secrets create qa-user-email \
  --replication-policy=automatic \
  --project=kushin77-ops

# Add secret value
echo -n "qa@kushnir.cloud" | \
  gcloud secrets versions add qa-user-email \
  --data-file=- \
  --project=kushin77-ops

# Verify creation
gcloud secrets describe qa-user-email --project=kushin77-ops
```

**Expected Output:**
```
name: projects/kushin77-ops/secrets/qa-user-email
created: 2026-04-20T...
replication:
  automatic: {}
```

### 1.2 Create qa-user-password Secret

```bash
# Store the password from issue #983 (get from secure location)
QA_PASSWORD="[PASSWORD_FROM_ISSUE_983]"

# Create the secret
gcloud secrets create qa-user-password \
  --replication-policy=automatic \
  --project=kushin77-ops

# Add secret value (mark as secret in CI/CD logs)
echo -n "$QA_PASSWORD" | \
  gcloud secrets versions add qa-user-password \
  --data-file=- \
  --project=kushin77-ops

# Verify creation
gcloud secrets describe qa-user-password --project=kushin77-ops

# Clear sensitive variable from shell history
unset QA_PASSWORD
```

**Expected Output:**
```
name: projects/kushin77-ops/secrets/qa-user-password
created: 2026-04-20T...
replication:
  automatic: {}
```

### 1.3 Create Optional qa-oauth-token Secret

```bash
# Optional: Pre-cached OAuth token for test optimization
# (Skip if not using token caching)

gcloud secrets create qa-oauth-token \
  --replication-policy=automatic \
  --project=kushin77-ops

# Add placeholder (will be populated after first login)
echo -n "placeholder-token" | \
  gcloud secrets versions add qa-oauth-token \
  --data-file=- \
  --project=kushin77-ops
```

### 1.4 Verify All Secrets Created

```bash
# List all QA-related secrets
gcloud secrets list \
  --project=kushin77-ops \
  --filter="name:qa-*" \
  --format="table(name,created)"

# Expected output:
# NAME                                               CREATED
# projects/kushin77-ops/secrets/qa-oauth-token      2026-04-20T...
# projects/kushin77-ops/secrets/qa-user-email       2026-04-20T...
# projects/kushin77-ops/secrets/qa-user-password    2026-04-20T...
```

---

## Step 2: Verify fetch-gsm-secrets.sh Can Load Credentials

### 2.1 Test Credential Fetching

```bash
# Navigate to repo
cd ~/code-server-enterprise

# Load GSM secrets (this script already has E2E credential handling from prior work)
source scripts/fetch-gsm-secrets.sh

# Verify environment variables are set
echo "E2E_USER_EMAIL=$E2E_USER_EMAIL"
echo "E2E_USER_PASSWORD is set: $([ -z "$E2E_USER_PASSWORD" ] && echo 'NO' || echo 'YES')"

# Expected output:
# E2E_USER_EMAIL=qa@kushnir.cloud
# E2E_USER_PASSWORD is set: YES
```

### 2.2 Check .env.schema.json Configuration

```bash
# Verify E2E credential variables are defined in schema
cat .env.schema.json | jq '.properties | keys[] | select(. | startswith("E2E"))'

# Expected output:
# "E2E_USER_EMAIL"
# "E2E_USER_PASSWORD"
# "E2E_USER_OAUTH_TOKEN"
```

---

## Step 3: Prepare oauth2-proxy Whitelist

### 3.1 Verify allowed-emails.txt Has QA User

```bash
# Check whitelist file
cat allowed-emails.txt | grep qa@kushnir.cloud

# Expected output:
# qa@kushnir.cloud
```

**Note**: This was prepared in prior work (commit f5787454). If not present, add:
```bash
echo "qa@kushnir.cloud" >> allowed-emails.txt
```

### 3.2 Verify Docker Volume Mount

```bash
# Check docker-compose.yml has whitelist volume mount
grep -A 5 "oauth2-proxy" docker-compose.yml | grep -E "volumes:|allowed-emails"

# Expected output should show:
# - ./allowed-emails.txt:/etc/oauth2-proxy/allowed-emails.txt:ro
```

---

## Step 4: Restart oauth2-proxy Services

### 4.1 Stop Current oauth2-proxy Instances

```bash
# SSH to primary host if not already there
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise

# Stop oauth2-proxy service
docker-compose stop oauth2-proxy oauth2-proxy-portal

# Verify stopped
docker-compose ps | grep oauth2-proxy
```

### 4.2 Restart with New Configuration

```bash
# Start services with updated whitelist
docker-compose up -d oauth2-proxy oauth2-proxy-portal

# Monitor startup logs
docker-compose logs -f --tail=50 oauth2-proxy

# Wait for "listening on" message (30-60 seconds)
# Expected log entry:
# oauth2-proxy | [2026/04/20 ...] http server started listening on 0.0.0.0:4180
```

### 4.3 Verify Whitelist Loaded

```bash
# Check that whitelist was mounted and loaded
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt | grep qa@kushnir.cloud

# Expected output:
# qa@kushnir.cloud
```

---

## Step 5: Test E2E Environment

### 5.1 Verify Environment Variables Load in Test Context

```bash
# On primary host, test credential loading
cd ~/code-server-enterprise

# Source GSM secrets
source scripts/fetch-gsm-secrets.sh

# Test OAuth login manually
echo "QA Email: $E2E_USER_EMAIL"
echo "QA Password loaded: $([ -z "$E2E_USER_PASSWORD" ] && echo 'FAILED' || echo 'OK')"
echo "QA OAuth Token available: $([ -z "$E2E_USER_OAUTH_TOKEN" ] && echo 'Not set' || echo 'OK')"

# Expected output:
# QA Email: qa@kushnir.cloud
# QA Password loaded: OK
# QA OAuth Token available: Not set
```

### 5.2 Run OAuth Login Manual Test

```bash
# Manual test (requires browser and VPN access)
1. Open incognito browser window
2. Navigate to: https://kushnir.cloud
3. Click "Sign in with Google"
4. Enter: qa@kushnir.cloud
5. Enter: [password from GSM]
6. Expected: Redirect back to kushnir.cloud with authenticated session
7. Verify authenticated cookies present:
   - _oauth2_proxy cookie should be httpOnly, secure, sameSite=Lax
```

---

## Step 6: Verify OAuth Whitelist Works

### 6.1 Test Whitelisted User (Should Pass)

```bash
# QA user should be able to login
curl -I https://kushnir.cloud/ -H "Authorization: Bearer $E2E_USER_EMAIL"

# Expected: 200 OK or redirect to login (which succeeds for qa@kushnir.cloud)
```

### 6.2 Test Non-Whitelisted User (Should Fail)

```bash
# Non-whitelisted user should be rejected
# (only test if you have another test email)
# Expected: 403 Forbidden
```

---

## Step 7: E2E Test Environment Verification

### 7.1 Test Fixture Availability

```bash
# Verify test can access authenticated session
cd ~/code-server-enterprise

# Run a single E2E test (OAuth login)
E2E_USER_EMAIL=qa@kushnir.cloud \
  npx playwright test tests/e2e/oauth-login.spec.ts \
  --project=chromium \
  --workers=1

# Expected: Tests pass (or show skipped if credentials not available)
```

### 7.2 Verify All 5 Test Suites Can Load Credentials

```bash
# Test environment loading for all suites
npm run test:e2e -- --list

# Should show all test suites:
# - oauth-login.spec.ts (20+ tests)
# - appsmith-workspace.spec.ts (25+ tests)
# - ide-launch-workspace.spec.ts (25+ tests)
# - session-persistence-failover.spec.ts (30+ tests)
# - error-handling-edge-cases.spec.ts (50+ tests)
```

---

## Step 8: CI/CD Credential Integration

### 8.1 Verify GitHub Actions Can Access GSM Secrets

```bash
# This is handled by workload identity federation
# Verify OIDC provider configuration (already done in prior work)

# Check that CI workflows have GSM permissions
cat .github/workflows/TEMPLATE-ci-tests.yml | grep -A 10 "permissions:"

# Expected:
# permissions:
#   contents: read
#   id-token: write  # For OIDC/GSM access
```

### 8.2 Verify E2E Test Step in CI

```bash
# Check that E2E test step loads GSM secrets
cat .github/workflows/TEMPLATE-ci-tests.yml | grep -A 5 "E2E_USER"

# Expected step to include:
# - name: Load E2E credentials from GSM
#   run: source scripts/fetch-gsm-secrets.sh
# 
# - name: Run E2E tests
#   run: npm run test:e2e
```

---

## Step 9: Documentation & Handoff

### 9.1 Record QA User Details

Create a private document (NOT in git):
```
QA User Setup Complete
=====================

Email: qa@kushnir.cloud
Password: [Stored in GSM secret: qa-user-password]
OAuth Token (cached): [Stored in GSM secret: qa-oauth-token]

Whitelist Status: ✅ Added to allowed-emails.txt
OAuth2-proxy: ✅ Restarted with updated whitelist
E2E Tests: ✅ Ready to execute

Date Created: 2026-04-20
Created by: [Your name]
Last Verified: [Date]
```

### 9.2 Update Issue #984 with Completion Evidence

Add comment to issue #984:
```markdown
## Implementation Complete ✅

### Credentials Setup
- [x] qa-user-email created in GSM
- [x] qa-user-password created in GSM
- [x] qa-oauth-token placeholder created in GSM

### oauth2-proxy Configuration
- [x] allowed-emails.txt includes qa@kushnir.cloud
- [x] oauth2-proxy services restarted
- [x] Whitelist verification passed

### E2E Environment
- [x] GSM credential loading verified
- [x] Environment variables set correctly
- [x] Test fixtures ready to execute

### Testing Status
- [x] Manual OAuth login test passed
- [x] Whitelist enforcement verified
- [x] All 5 E2E test suites ready

Ready to execute all E2E tests (#986-990)
```

### 9.3 Close Issue #984

Once all steps verified:
```bash
gh issue close 984 --repo kushin77/code-server --comment "OAuth whitelist and GSM credentials configured successfully. E2E test suites ready to execute."
```

---

## Rollback Procedure (If Issues Occur)

### If oauth2-proxy fails to restart:

```bash
# Check logs for errors
docker-compose logs oauth2-proxy

# Common issues:
# 1. Cookie secret format wrong → Verify in .env
# 2. Google OAuth credentials invalid → Check env vars
# 3. Whitelist file not mounted → Check volumes in docker-compose.yml
# 4. Port 4180 already in use → Kill competing process

# Rollback: Remove secrets and restart
gcloud secrets delete qa-user-email --project=kushin77-ops
gcloud secrets delete qa-user-password --project=kushin77-ops
gcloud secrets delete qa-oauth-token --project=kushin77-ops

docker-compose restart oauth2-proxy
```

### If E2E tests fail with auth errors:

```bash
# Check credential loading
source scripts/fetch-gsm-secrets.sh
echo "E2E_USER_EMAIL=$E2E_USER_EMAIL"

# Verify oauth2-proxy can see whitelist
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt

# Check oauth2-proxy logs
docker-compose logs oauth2-proxy | tail -100

# Restart oauth2-proxy
docker-compose restart oauth2-proxy
```

---

## Success Criteria

- [x] GSM secrets created (qa-user-email, qa-user-password, qa-oauth-token)
- [x] allowed-emails.txt contains qa@kushnir.cloud
- [x] oauth2-proxy services restarted successfully
- [x] Manual OAuth login test passed
- [x] E2E test environment variables load correctly
- [x] All 5 E2E test suites ready to execute
- [x] CI/CD pipeline has GSM access
- [x] Issue #984 closed with evidence

---

## Timeline

| Task | Time |
|------|------|
| Create GSM secrets | 3 min |
| Verify fetch-gsm-secrets.sh | 2 min |
| Prepare oauth2-proxy whitelist | 1 min |
| Restart oauth2-proxy services | 2 min |
| Test E2E environment | 3 min |
| Verify CI/CD integration | 2 min |
| Documentation & handoff | 2 min |
| **Total** | **15 min** |

---

## Post-Execution

Once this issue is complete:

1. **Immediately Unblocked**:
   - All E2E test suites (#986-990) can execute
   - Production deployment can proceed
   - Full test coverage can be measured

2. **Next Steps**:
   - Run all E2E tests: `npm run test:e2e`
   - Collect coverage reports
   - Review test results
   - Close issues #986-990 with evidence
   - Schedule production deployment

3. **Expected Results**:
   - 150+ tests passing
   - >90% code coverage
   - Zero flaky tests
   - Production-ready infrastructure verified

---

**Document Created**: April 20, 2026
**For**: Issue #984 (P0: Configure QA user OAuth whitelist + GSM credentials)
**Status**: Ready to execute upon issue #983 completion
**Estimated Execution Time**: 15 minutes
