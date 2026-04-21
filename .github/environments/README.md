# E2E Testing Environment Configuration (Kushnir.cloud / KC)

This directory contains GitHub Actions environment setup for E2E testing.

## Environment: e2e-testing

The `e2e-testing` GitHub Actions environment is configured for running end-to-end tests against the production-like infrastructure.

### Required Secrets

The following secrets must be configured in the GitHub repository settings under **Settings → Environments → e2e-testing**:

| Secret Name | Description | Source |
|------------|-------------|--------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Workload Identity Provider URI | GCP Console (project settings) |
| `GCP_SERVICE_ACCOUNT` | Service account email | GCP Console (service accounts) |
| `GCP_PROJECT_ID` | Google Cloud Project ID | GCP Console |

### GCP Configuration

The E2E test workflow uses **Workload Identity Federation** to authenticate to Google Cloud without storing service account keys in the repository.

**Minimal required permissions for the service account:**
```
roles/secretmanager.secretAccessor (for qa-user-email, qa-user-password secrets)
```

### GSM Secrets Required

The workflow fetches QA credentials from Google Secret Manager. These secrets must be created once Issue #983 (QA user creation) completes:

```bash
# Issue #983 provides the password; Issue #984 creates these secrets:
gcloud secrets create qa-user-email --replication-policy=automatic
gcloud secrets create qa-user-password --replication-policy=automatic

# Add values (replace [PASSWORD] with actual QA user password)
echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-
echo -n "[PASSWORD]" | gcloud secrets versions add qa-user-password --data-file=-

# Grant service account access
gcloud secrets add-iam-policy-binding qa-user-email \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding qa-user-password \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"
```

### Workflow Execution

Once all prerequisites are in place, the E2E workflow (`e2e-oauth-tests.yml`) can be triggered:

1. **Manually**: Via GitHub Actions UI (workflow_dispatch)
2. **Scheduled**: Nightly at 2 AM UTC
3. **On PR**: When changes are made to tests or application code

### Test Execution Flow

```
oauth-login-e2e (20+ tests)
    ↓ (success)
appsmith-portal-e2e (30+ tests)
    ↓ (success)
ide-operations-e2e (25+ tests)
    ↓
summary (overall pass/fail)
```

### Artifact Output

Test results are uploaded as GitHub Actions artifacts:

- `oauth-login-test-report/` - Playwright test results
- `oauth-login-playwright-report/` - Interactive HTML report
- `appsmith-portal-test-report/` - Playwright test results
- `ide-operations-test-report/` - Playwright test results

Each artifact is retained for 30 days.

### PR Integration

When the workflow runs on a pull request, a test summary comment is posted automatically with:
- Number of tests passed/failed/skipped
- Total execution time
- Link to full test report

### Troubleshooting

**Workflow fails with "secret not found"**
- Verify GSM secrets `qa-user-email` and `qa-user-password` are created
- Verify service account has `secretmanager.secretAccessor` permission

**Workflow fails with "authentication failed"**
- Verify `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` secrets are correct
- Check Workload Identity Federation configuration in GCP Console

**Tests timeout or fail intermittently**
- Increase timeout in playwright.config.ts if needed
- Check `https://kushnir.cloud` and `https://ide.kushnir.cloud` are accessible

### Security Best Practices

✅ **What this workflow does right:**
- Uses Workload Identity Federation (no service account keys in git)
- Masks sensitive values in logs
- Fetches credentials at runtime from GSM
- Uses specific service account (not default)
- Limits artifact retention to 30 days
- All secrets stored in GitHub, not in code

❌ **What NOT to do:**
- Don't commit service account keys
- Don't hardcode credentials in workflow files
- Don't use "latest" versions of actions
- Don't store passwords in code or PR comments

---

**Last updated**: April 24, 2026  
**Status**: Ready (awaiting Issue #984 to complete)  
**Related**: Issues #983, #984, #986-990
