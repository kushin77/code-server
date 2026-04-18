# E2E Account Provisioning Runbook (#750)

**Objective**: Provision E2E test account credentials and capture authenticated Playwright storage state for non-interactive failover continuity tests (#733).

**Status**: BLOCKING #733 (authenticated session continuity), requires manual E2E account setup

**Timeline**: ~2-4 hours total (account creation + credentials capture + secret storage)

---

## Prerequisites

1. **Google OAuth Access**: Ability to create/configure test users in your Google Workspace or OAuth provider
2. **Access to ide.kushnir.cloud**: E2E account must be able to authenticate and access the IDE
3. **Node.js + Playwright**: Local environment with Node.js 18+ and Playwright installed
4. **GitHub CLI**: `gh` command available for setting repository secrets
5. **Bash**: For running capture and preparation scripts

---

## Phase 1: E2E Account Creation (30-60 min)

### Option A: Google Workspace Account (Recommended)

If you manage a Google Workspace domain (e.g., bioenergystrategies.com):

1. **Create Test User in Google Admin**:
   ```
   - Admin URL: https://admin.google.com/
   - Navigate: Users and accounts → Users
   - Click "+ Create user"
   - Email: e2e-test@yourdomain.com
   - First name: E2E
   - Last name: Test
   - Password: [generate strong password]
   - Require password change on login: OFF (we need static password)
   - Create
   ```

2. **Configure OAuth Consent Screen** (if not already done):
   ```
   - Go to: https://console.cloud.google.com/apis/credentials/consent
   - Select your project
   - Edit app:
     - App name: code-server-e2e
     - User support email: your-email@domain.com
     - Authorized domains: [add your domain]
   - Save
   ```

3. **Verify Test User Can Access IDE**:
   ```bash
   # From a browser:
   # 1. Open https://ide.kushnir.cloud/
   # 2. Click "Sign in with Google" or similar OAuth button
   # 3. Enter: e2e-test@yourdomain.com + password
   # 4. Confirm auth succeeds and you reach code-server dashboard
   ```

### Option B: Local/Custom Authentication

If using local authentication without Google OAuth:

1. **Create local user account** on your authentication system
   - Username: e2e-test
   - Email: e2e-test@kushnir.cloud (or equivalent)
   - Password: [strong, static password]

2. **Verify test user can authenticate** to ide.kushnir.cloud

---

## Phase 2: Prepare Local Environment (15 min)

### Step 1: Install Node.js and Playwright

```bash
# Check Node.js version
node --version
# Expect: v18.0.0 or higher

# If needed, install Node.js from https://nodejs.org/
```

### Step 2: Setup Playwright Kit

```bash
# From repository root
cd ~/code-server-enterprise  # or wherever repo is cloned

# Install Playwright dependencies
bash scripts/ci/setup-e2e-playwright.sh

# Validate kit is ready
bash scripts/ci/validate-e2e-playwright-kit.sh
```

---

## Phase 3: Capture Storage State (30-45 min)

### Step 1: Run Capture Script

This script will authenticate to ide.kushnir.cloud and save the browser context (cookies, tokens, etc.):

```bash
#!/bin/bash

# Set your E2E credentials
export E2E_USER_EMAIL="e2e-test@yourdomain.com"
export E2E_USER_PASSWORD="your-password-here"
export TARGET_URL="https://ide.kushnir.cloud"
export OUTPUT_FILE="/tmp/playwright-storage-state.json"

# Run capture script
bash scripts/ci/capture-playwright-storage-state.sh
```

**Expected Output**:
```
[2026-04-18T...] [INFO] Setting up Playwright kit for storage state capture
[2026-04-18T...] [INFO] Generating Playwright capture script
[2026-04-18T...] [capture] Navigating to https://ide.kushnir.cloud/oauth2/start?rd=/
[2026-04-18T...] [capture] Current URL: https://ide.kushnir.cloud/...
[2026-04-18T...] [capture] Authenticating with email: e2e-test@yourdomain.com
[2026-04-18T...] [capture] Successfully captured storage state
[2026-04-18T...] [INFO] Storage state saved to /tmp/playwright-storage-state.json
```

### Step 2: Validate Captured State

```bash
# Check file exists and is valid JSON
test -f /tmp/playwright-storage-state.json && \
  cat /tmp/playwright-storage-state.json | jq . > /dev/null && \
  echo "✓ Storage state is valid JSON"

# Check for expected keys (cookies, localStorage, sessionStorage)
cat /tmp/playwright-storage-state.json | jq 'keys' 
# Expected: ["cookies", "localStorage", "origins", "sessionStorage"]
```

---

## Phase 4: Encode to Base64 for GitHub Secret (10 min)

### Step 1: Prepare Single-Line Base64

```bash
# Encode storage state to base64 (single line, no newlines)
bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json

# Output: [very long base64 string]
# Copy this entire string
```

### Step 2: Set as GitHub Repository Secret

```bash
# Option A: Using gh CLI (recommended)
STORAGE_STATE_B64=$(bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json)

gh secret set PLAYWRIGHT_STORAGE_STATE_B64 --body "$STORAGE_STATE_B64"
# Output: ✓ Set secret PLAYWRIGHT_STORAGE_STATE_B64 for kushin77/code-server

# Option B: Manual GitHub UI
# 1. Go to: https://github.com/kushin77/code-server/settings/secrets/actions
# 2. Click "New repository secret"
# 3. Name: PLAYWRIGHT_STORAGE_STATE_B64
# 4. Value: [paste the base64 string from above]
# 5. Click "Add secret"
```

### Step 3: Verify Secret is Set

```bash
# List repository secrets (values not shown)
gh secret list

# Expected output includes:
# PLAYWRIGHT_STORAGE_STATE_B64    Updated 2026-04-18T...
```

---

## Phase 5: Test Integration (20-30 min)

### Step 1: Dispatch E2E Workflow

```bash
# Dispatch the authenticated failover continuity workflow
gh workflow run e2e-authenticated-failover-continuity.yml \
  --ref main \
  -f failover_wait_ms=45000

# Example output:
# ✓ Created workflow_dispatch event for e2e-authenticated-failover-continuity.yml on main
# 
# To see runs for this workflow, try: gh run list --workflow=e2e-authenticated-failover-continuity.yml
```

### Step 2: Monitor Workflow Execution

```bash
# List recent runs
gh run list --workflow e2e-authenticated-failover-continuity.yml --limit 5

# Watch specific run
gh run watch <RUN_ID>

# Get full details
gh run view <RUN_ID> --log
```

### Step 3: Validate Results

Successful run should produce:
- ✅ Authenticated session established to ide.kushnir.cloud
- ✅ Playwright tests execute with storage state (no interactive auth)
- ✅ Failover continuity validated (session survives VIP movement)
- ✅ Artifacts uploaded (playwright report, test results)

---

## Troubleshooting

### Issue: "Storage state capture script fails with auth error"

**Cause**: OAuth credentials incorrect or provider configuration missing

**Solution**:
```bash
# Test credentials manually first
curl -X POST https://ide.kushnir.cloud/oauth2/start \
  -d "email=e2e-test@yourdomain.com&password=your-password"

# Verify OAuth provider is configured correctly
# - Check Caddyfile routing to oauth2-proxy
# - Verify Google OAuth app credentials in environment
# - Check oauth2-proxy logs: docker logs oauth2-proxy
```

### Issue: "Playwright capture hangs during authentication"

**Cause**: Page selectors don't match actual OAuth form, or network timeout

**Solution**:
```bash
# Run with debug output and headless=false to see browser UI
HEADLESS=false bash scripts/ci/capture-playwright-storage-state.sh

# Adjust selectors in capture-playwright-storage-state.sh if needed
# - Edit PLAYWRIGHT_SCRIPT section
# - Update page.fill() and selector timing to match actual form
```

### Issue: "Base64 secret decoding fails in workflow"

**Cause**: Secret value corrupted or truncated

**Solution**:
```bash
# Verify secret in GitHub
gh secret view PLAYWRIGHT_STORAGE_STATE_B64 | head -20

# Recapture and reset if needed
bash scripts/ci/capture-playwright-storage-state.sh
STORAGE_STATE_B64=$(bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json)
gh secret set PLAYWRIGHT_STORAGE_STATE_B64 --body "$STORAGE_STATE_B64"
```

### Issue: "Workflow runs but tests timeout"

**Cause**: Failover event not triggered or test environment issues

**Solution**:
```bash
# Run with explicit failover trigger
gh workflow run e2e-authenticated-failover-continuity.yml \
  -f failover_wait_ms=60000 \
  -f failover_trigger_cmd="bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action trigger"

# Check test logs for timeout details
gh run view <RUN_ID> --log | grep -i "timeout\|failover\|error"
```

---

## Maintenance & Rotation

### Refresh Storage State (Monthly or After Password Changes)

If E2E account password changes or session expires:

```bash
# Recapture storage state with updated credentials
E2E_USER_EMAIL="e2e-test@yourdomain.com" \
E2E_USER_PASSWORD="new-password" \
bash scripts/ci/capture-playwright-storage-state.sh

# Re-encode and update GitHub secret
STORAGE_STATE_B64=$(bash scripts/ci/prepare-playwright-storage-state.sh /tmp/playwright-storage-state.json)
gh secret set PLAYWRIGHT_STORAGE_STATE_B64 --body "$STORAGE_STATE_B64"
```

### Secure Credential Storage

The E2E account credentials should be stored securely:

```bash
# Option A: Google Secret Manager (Recommended for production)
gcloud secrets create e2e-account-email --data-file=- <<< "e2e-test@yourdomain.com"
gcloud secrets create e2e-account-password --data-file=- <<< "your-password"

# Option B: Pass credential file (for local automation)
cat > ~/.e2e-credentials <<EOF
export E2E_USER_EMAIL="e2e-test@yourdomain.com"
export E2E_USER_PASSWORD="your-password"
EOF
chmod 600 ~/.e2e-credentials

# Option C: Environment variable in CI/CD secrets (already done with PLAYWRIGHT_STORAGE_STATE_B64)
```

---

## Related Issues & Documentation

| Issue | Title | Status |
|-------|-------|--------|
| #750 | Provision non-interactive Playwright storage state | BLOCKED (this runbook) |
| #733 | Validate authenticated session continuity with failover | BLOCKED on #750 |
| #710 | P0 EPIC Stateful failover | In progress |
| [PLAYWRIGHT-STORAGE-STATE-PROVISIONING-750.md](PLAYWRIGHT-STORAGE-STATE-PROVISIONING-750.md) | Architecture & technical specs | Available |
| [AUTHENTICATED-FAILOVER-CONTINUITY-733.md](AUTHENTICATED-FAILOVER-CONTINUITY-733.md) | Test execution guide | Available |

---

## Success Criteria

- [x] This runbook is comprehensive and actionable
- [ ] E2E account created with access to ide.kushnir.cloud
- [ ] `scripts/ci/capture-playwright-storage-state.sh` runs successfully
- [ ] Storage state JSON file is created and valid
- [ ] Base64 encoding completed
- [ ] `PLAYWRIGHT_STORAGE_STATE_B64` secret set in GitHub
- [ ] Workflow `e2e-authenticated-failover-continuity.yml` dispatched
- [ ] Workflow runs successfully and produces test results
- [ ] #733 marked as ready for automated continuity testing

---

## Estimated Timeline

| Phase | Task | Time | Status |
|-------|------|------|--------|
| 1 | Create E2E account (Google Workspace or local) | 30-60 min | MANUAL |
| 2 | Setup Playwright locally | 15 min | AUTOMATED |
| 3 | Capture storage state | 30-45 min | AUTOMATED (needs creds) |
| 4 | Encode and set GitHub secret | 10 min | AUTOMATED |
| 5 | Test workflow execution | 20-30 min | AUTOMATED |
| **Total** | **End-to-end provisioning** | **2-4 hours** | **READY** |

**Next Step**: Start Phase 1 (E2E account creation), then follow phases 2-5 in order.

Once complete, issue #750 can be closed and #733 workflow will execute in fully non-interactive mode.
