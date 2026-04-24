# QA User Creation Runbook - Issue #983

**Objective**: Create `qa@kushnir.cloud` Google Workspace user and configure GSM credentials to unblock E2E testing

**Owner**: @kushnir  
**Blockers**: None (manual admin task)  
**Time Estimate**: 30-40 minutes total  
**Dependencies**: Google Workspace admin access + GCP project admin access

---

## Phase 1: Service Account Setup (GCP Console) - 15 minutes

### Step 1.1: Create Service Account

1. Go to: [GCP Console - Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Click: "Create Service Account"
3. Fill in:
   - **Service Account Name**: `qa-user-creator`
   - **Service Account ID**: `qa-user-creator@gcp-eiq.iam.gserviceaccount.com`
   - **Description**: "Creates QA user in Workspace for E2E testing"
4. Click: "Create and Continue"

### Step 1.2: Grant Permissions (Skip this step, will use domain-wide delegation instead)

Click: "Continue" (we'll grant domain-wide delegation)

### Step 1.3: Create JSON Key

1. Click: "Create Key"
2. Select: "JSON"
3. Click: "Create"
4. **Important**: Save the JSON file securely
   - Save to: `~/service-account-qa-creator.json` or similar
   - **Never commit to git**
   - Keep secure - this grants Workspace admin access

---

## Phase 2: Enable Domain-Wide Delegation - 10 minutes

### Step 2.1: Enable Domain-Wide Delegation

1. Go back to [Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Click the service account: `qa-user-creator`
3. Go to: "Security" > "Show Domain-wide delegation"
4. Check: "Enable domain-wide delegation"
5. Copy the **OAuth 2.0 Client ID** (looks like: `123456789...`)
6. Click: "Save"

### Step 2.2: Authorize Service Account in Workspace

1. Go to: [Google Workspace Admin Console](https://admin.google.com/)
2. Navigate: **Security** > **API controls** > **Domain-wide delegation**
3. Click: "Add new"
4. Paste: The OAuth 2.0 Client ID from Step 2.1
5. In **OAuth scopes** field, enter:
   ```
   https://www.googleapis.com/auth/admin.directory.user
   ```
   (This grants permission to create/manage users only)
6. Click: "Authorize"

✅ **Domain-wide delegation is now configured**

---

## Phase 3: Create QA User via Admin SDK Script - 10 minutes

### Step 3.1: Set Up Local Environment

```bash
# Navigate to repository
cd /path/to/code-server-enterprise

# Set environment variable to JSON key file
export GOOGLE_APPLICATION_CREDENTIALS=~/service-account-qa-creator.json

# Verify Python environment (if running locally)
python3 --version  # Should be 3.7+

# Install required Python packages
pip install google-auth google-auth-httplib2 google-api-python-client
```

### Step 3.2: Update Script Admin Email (CRITICAL)

Before running, edit the script to use correct admin email:

```bash
# Edit the script
nano scripts/ops/create-qa-user-admin-sdk.py

# Find this line (around line 95):
admin_email = "admin@kushnir.cloud"

# Change it to the actual Workspace admin email that has permission to create users
# For example: "akushnir@kushnir.cloud" or "admin@kushnir.cloud"
admin_email = "YOUR_WORKSPACE_ADMIN_EMAIL"

# Save: Ctrl+X, then Y, then Enter
```

### Step 3.3: Run the Script

```bash
# Execute the QA user creation script
python3 scripts/ops/create-qa-user-admin-sdk.py
```

**Expected Output**:
```
======================================================================
Google Workspace QA User Creation via Admin SDK
======================================================================

Using service account: /path/to/service-account-qa-creator.json

Generated Password: [LONG_SECURE_PASSWORD]

Creating Google Workspace user...
----------------------------------------------------------------------
Creating user: qa@kushnir.cloud
✓ User created successfully!
  Email: qa@kushnir.cloud
  Name: QA Testing
  Status: False (not suspended)

----------------------------------------------------------------------
Creating GSM secrets...
----------------------------------------------------------------------
✓ Created GSM secret: qa-user-email
✓ Created GSM secret: qa-user-password

======================================================================
✓ QA User Creation Complete!
======================================================================

Next Steps:
----------------------------------------------------------------------
1. Restart oauth2-proxy to load updated whitelist:
   ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal'

2. Verify credentials in GSM:
   gcloud secrets versions access latest --secret='qa-user-email'
   gcloud secrets versions access latest --secret='qa-user-password'

3. Test E2E authentication:
   source scripts/fetch-gsm-secrets.sh
   echo $E2E_USER_EMAIL

4. Run E2E tests:
   npx playwright test tests/e2e/oauth-login.spec.ts
```

---

## Phase 4: Verify Setup - 5 minutes

### Step 4.1: Verify User in Workspace

1. Go to: [Workspace Admin Users](https://admin.google.com/ac/users)
2. Search: `qa@kushnir.cloud`
3. Verify: User exists and is **not suspended**

### Step 4.2: Verify GSM Secrets

```bash
# Check that credentials were stored in GSM
gcloud secrets versions access latest --secret='qa-user-email'
# Should output: qa@kushnir.cloud

gcloud secrets versions access latest --secret='qa-user-password'
# Should output: [long secure password]
```

### Step 4.3: Restart oauth2-proxy

```bash
# SSH to production host and restart oauth2-proxy
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal'

# Wait 10 seconds for restart
sleep 10

# Verify it's running
ssh akushnir@192.168.168.31 'docker-compose ps oauth2-proxy'
# Should show: oauth2-proxy | Up
```

### Step 4.4: Test E2E Setup

```bash
# Fetch credentials from GSM
source scripts/fetch-gsm-secrets.sh

# Verify they're loaded
echo "Email: $E2E_USER_EMAIL"
# Should output: Email: qa@kushnir.cloud

# Run a single E2E test
npx playwright test tests/e2e/oauth-login.spec.ts --headed --workers=1
```

---

## Phase 5: Run Full E2E Test Suite - 10 minutes

Once verification passes:

```bash
# Run all E2E tests (will take ~10-15 minutes)
E2E_USER_EMAIL=qa@kushnir.cloud \
E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret='qa-user-password') \
PORTAL_BASE_URL=https://kushnir.cloud \
IDE_BASE_URL=https://ide.kushnir.cloud \
npx playwright test tests/e2e/
```

**Success Criteria**:
- ✅ All 150+ E2E tests pass
- ✅ No secrets logged to console
- ✅ All test artifacts saved to `playwright-report/`

---

## Troubleshooting

### Error: "Domain-wide delegation not enabled"

**Solution**: Go to GCP Console > Service Accounts > Select account > Security > Enable Domain-wide delegation

### Error: "The caller does not have permission"

**Possible Causes**:
1. Admin email in script is incorrect
2. Service account scope not authorized in Workspace
3. Service account not granted domain-wide delegation

**Solution**: Verify steps in Phase 2 completed correctly

### Error: "qa-user-cloud user already exists"

**Solution**: The user already exists. Skip user creation, verify GSM secrets exist:
```bash
gcloud secrets list | grep qa-user
```

### OAuth login fails with "user not in whitelist"

**Solution**: oauth2-proxy might not have reloaded the whitelist:
```bash
# Check current whitelist
ssh akushnir@192.168.168.31 'docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt | grep qa@'

# Force restart
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal'

# Wait 15 seconds
sleep 15

# Retry
```

---

## Timeline Summary

| Phase | Step | Time |
|-------|------|------|
| 1 | Create Service Account | 5 min |
| 2 | Enable Domain-Wide Delegation | 10 min |
| 3 | Run Admin SDK Script | 5 min |
| 4 | Verify Setup | 5 min |
| 5 | Run E2E Tests | 10 min |
| **Total** | | **35 minutes** |

---

## Rollback / Cleanup

If needed to undo:

```bash
# Delete the QA user (requires Workspace admin)
gcloud identity users delete qa@kushnir.cloud

# Delete GSM secrets
gcloud secrets delete qa-user-email
gcloud secrets delete qa-user-password

# Delete service account (optional)
gcloud iam service-accounts delete qa-user-creator@gcp-eiq.iam.gserviceaccount.com
```

---

## Success Indicators

✅ **User Created**:
- `qa@kushnir.cloud` appears in Workspace Admin Console
- User is **not suspended**
- User can log in with the generated password

✅ **GSM Secrets Created**:
- `gcloud secrets list` shows `qa-user-email` and `qa-user-password`

✅ **E2E Tests Ready**:
- `npm test` in E2E suite passes
- `$E2E_USER_EMAIL` environment variable resolves

✅ **Production Ready**:
- All 150+ E2E tests passing
- oauth2-proxy accepts `qa@kushnir.cloud` login
- Matrix collaboration features verified

---

## Contact

**Issues**: Open GitHub issue with `[QA User Setup]` prefix  
**Questions**: Review the related documentation:
- `scripts/ops/create-qa-user-admin-sdk.py` - Full script source
- `.env.schema.json` - E2E environment variable definitions
- `PRODUCTION-DEPLOYMENT-VERIFICATION-CHECKLIST.md` - Full deployment guide

---

**Last Updated**: April 20, 2026  
**Script Version**: 1.0  
**Status**: Ready for execution  
**Unblocks**: Issues #984, #986-990, #1000  
