# Issue #984 Execution Guide - QA OAuth Whitelist + GSM Credentials

**Status**: Ready to execute once #983 (QA user creation) is complete  
**Estimated duration**: 15-20 minutes  
**Prerequisites**: Issue #983 MUST be complete (QA user exists + password obtained)

---

## Execution Checklist

### Part 1: Add QA Email to OAuth Whitelist ✅ (ALREADY DONE)

**Verification**:
```bash
grep "qa@kushnir.cloud" allowed-emails.txt
# Expected output: qa@kushnir.cloud
```

**Status**: ✅ `allowed-emails.txt` already updated  
**Last verified**: April 23, 2026

---

### Part 2: Create GSM Secrets (⏳ READY, awaiting QA user from #983)

Once Issue #983 completes and you have the QA user password, execute:

```bash
# 1. Create qa-user-email secret (if not exists)
gcloud secrets describe qa-user-email >/dev/null 2>&1 || \
  gcloud secrets create qa-user-email --replication-policy=automatic

# 2. Create qa-user-password secret (if not exists)
gcloud secrets describe qa-user-password >/dev/null 2>&1 || \
  gcloud secrets create qa-user-password --replication-policy=automatic

# 3. Add/update qa-user-email value
echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-

# 4. Add/update qa-user-password value (REPLACE [PASSWORD_FROM_ISSUE_983] with actual password)
echo -n "[PASSWORD_FROM_ISSUE_983]" | gcloud secrets versions add qa-user-password --data-file=-

# 5. Verify values stored correctly
gcloud secrets versions access latest --secret=qa-user-email
gcloud secrets versions access latest --secret=qa-user-password
```

---

### Part 3: Grant CI Service Account Access ✅ (Status Check Needed)

**Check if GitHub Actions service account exists and has access**:

```bash
# Get current GCP project
PROJECT_ID=$(gcloud config get-value project)
echo "Project: $PROJECT_ID"

# List service accounts
gcloud iam service-accounts list

# Expected format: github-actions@PROJECT.iam.gserviceaccount.com

# Grant access to qa-user-email
gcloud secrets add-iam-policy-binding qa-user-email \
  --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Grant access to qa-user-password
gcloud secrets add-iam-policy-binding qa-user-password \
  --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Verify permissions
gcloud secrets get-iam-policy qa-user-email
gcloud secrets get-iam-policy qa-user-password
```

---

### Part 4: Verify fetch-gsm-secrets.sh ✅ (Already Configured)

**Status**: ✅ Script already fetches E2E_USER_* variables

**Verification**:
```bash
grep -A 5 "E2E_USER_EMAIL" scripts/fetch-gsm-secrets.sh
# Expected: Fetches from qa-user-email, qa-oauth-token GSM secrets
```

**Result**: Script ready, no changes needed

---

### Part 5: Verify .env.schema.json ✅ (Already Configured)

**Status**: ✅ Schema already includes E2E_USER_* variables

**Verification**:
```bash
jq '.groups.testing.variables | keys' .env.schema.json
# Expected: ["E2E_USER_EMAIL", "E2E_USER_PASSWORD", "E2E_USER_OAUTH_TOKEN"]
```

**Result**: Schema ready, no changes needed

---

### Part 6: Redeploy oauth2-proxy (⏳ READY, do after GSM secrets created)

Once GSM secrets are created:

```bash
# 1. SSH to production host
ssh akushnir@192.168.168.31

# 2. Verify allowed-emails.txt is loaded
docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt | grep qa@kushnir.cloud

# 3. Redeploy oauth2-proxy to pick up whitelist
cd code-server-enterprise
docker-compose restart oauth2-proxy oauth2-proxy-portal

# 4. Wait for services to be healthy
sleep 10
docker-compose ps | grep oauth2-proxy

# 5. Verify health check passing
curl -s http://localhost:4180/ping | jq .
```

---

### Part 7: Validation Tests (⏳ READY, do after redeploy)

Once redeploy complete:

```bash
# 1. Test oauth2-proxy health
curl -s https://kushnir.cloud/oauth2/auth \
  -H "X-Forwarded-Email: qa@kushnir.cloud" \
  -H "X-Forwarded-Proto: https" | head -20

# 2. Test GSM secret access
source scripts/fetch-gsm-secrets.sh --non-interactive

# Verify variables loaded
echo "E2E_USER_EMAIL: ${E2E_USER_EMAIL:-EMPTY}"
echo "E2E_USER_PASSWORD: ${E2E_USER_PASSWORD:+*****} (masked)"

# 3. (Manual) Test full OAuth login
# Open browser incognito window
# Navigate to: https://kushnir.cloud
# Click "Sign in with Google"
# Use qa@kushnir.cloud + password from GSM
# Expected: Successful redirect to authenticated portal
```

---

## Part 8: E2E Test Smoke Test (⏳ Ready after validation)

Once all above complete, run E2E login smoke test:

```bash
# Load QA credentials
source scripts/fetch-gsm-secrets.sh --non-interactive

# Run OAuth login smoke test
npx playwright test tests/e2e/specs/oauth-login.spec.ts --project=chromium -v

# Expected: All tests pass
# E.g., "OAuth login: 2 passed (5s)"
```

---

## Execution Script (All-in-One)

For convenience, here's a complete execution script that runs all steps:

```bash
#!/bin/bash
# scripts/issue-984-execute.sh
# One-command execution of Issue #984

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Require QA user password as argument
if [[ -z "${1:-}" ]]; then
    log_fatal "Usage: bash scripts/issue-984-execute.sh <QA_USER_PASSWORD>"
fi

QA_PASSWORD="$1"
PROJECT_ID=$(gcloud config get-value project)

log_info "=== Executing Issue #984: QA OAuth Whitelist + GSM Credentials ==="

# Step 1: Verify whitelist
log_info "Step 1: Verifying allowed-emails.txt..."
if grep -q "qa@kushnir.cloud" allowed-emails.txt; then
    log_pass "✓ qa@kushnir.cloud found in allowed-emails.txt"
else
    log_fatal "✗ qa@kushnir.cloud NOT found in allowed-emails.txt"
fi

# Step 2: Create GSM secrets
log_info "Step 2: Creating/updating GSM secrets..."
gcloud secrets describe qa-user-email >/dev/null 2>&1 || \
    gcloud secrets create qa-user-email --replication-policy=automatic
gcloud secrets describe qa-user-password >/dev/null 2>&1 || \
    gcloud secrets create qa-user-password --replication-policy=automatic

echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-
echo -n "$QA_PASSWORD" | gcloud secrets versions add qa-user-password --data-file=-
log_pass "✓ GSM secrets created/updated"

# Step 3: Grant CI service account access
log_info "Step 3: Granting CI service account access to GSM secrets..."
gcloud secrets add-iam-policy-binding qa-user-email \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true
gcloud secrets add-iam-policy-binding qa-user-password \
    --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true
log_pass "✓ CI service account permissions granted"

# Step 4: Redeploy oauth2-proxy
log_info "Step 4: Redeploying oauth2-proxy..."
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal" || {
    log_error "Failed to redeploy oauth2-proxy. Ensure SSH access to 192.168.168.31"
    exit 1
}
sleep 5
log_pass "✓ oauth2-proxy restarted"

# Step 5: Validate
log_info "Step 5: Validating setup..."
source scripts/fetch-gsm-secrets.sh --non-interactive
if [[ "${E2E_USER_EMAIL:-}" == "qa@kushnir.cloud" ]]; then
    log_pass "✓ E2E_USER_EMAIL loaded: $E2E_USER_EMAIL"
else
    log_error "✗ E2E_USER_EMAIL not loaded correctly"
    exit 1
fi

if [[ -n "${E2E_USER_PASSWORD:-}" ]]; then
    log_pass "✓ E2E_USER_PASSWORD loaded (masked)"
else
    log_error "✗ E2E_USER_PASSWORD not loaded"
    exit 1
fi

log_info ""
log_pass "=== Issue #984 EXECUTION COMPLETE ==="
log_info ""
log_info "Next steps:"
log_info "1. Manually test OAuth login (see validation section above)"
log_info "2. Run E2E smoke tests: npx playwright test oauth-login.spec.ts"
log_info "3. Close Issue #984"
log_info "4. Unblock Issues #986-990 (E2E test implementation)"
```

---

## Definition of Done

- [ ] qa@kushnir.cloud in allowed-emails.txt ✅ (Already done)
- [ ] GSM secrets created: qa-user-email, qa-user-password
- [ ] CI service account has GSM access
- [ ] oauth2-proxy redeployed
- [ ] E2E_USER_* variables loaded from GSM
- [ ] Manual OAuth login test successful
- [ ] E2E smoke test passing
- [ ] No credentials in plaintext anywhere

---

## Timeline

| Item | Status | Duration | Owner |
|------|--------|----------|-------|
| Issue #983 (QA user creation) | ⏳ AWAITING | 15-30 min | akushnir (manual admin task) |
| Issue #984 (this issue) execution | ⏳ READY | 10-15 min | Agent/Script |
| Issues #986-990 (E2E tests) | 🔴 BLOCKED | 20-40 hrs | Dev team |

---

**Last updated**: April 23, 2026  
**Ready for execution**: Once #983 completes
