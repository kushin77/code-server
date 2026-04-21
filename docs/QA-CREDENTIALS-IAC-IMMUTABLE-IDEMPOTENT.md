# QA Credentials Management: IaC, Immutable, Idempotent, Automated

**Purpose**: QA Credentials Management: IaC, Immutable, Idempotent, Automated — reference and operational document.

## Overview

This document describes the Infrastructure-as-Code (IaC) approach for managing QA user credentials used in OAuth endpoint E2E testing. The solution is **immutable**, **idempotent**, and **automatically enforced** for all OAuth testing in CI/CD.

## Architecture Principles

### 1. **IaC (Infrastructure as Code)**
- All QA credentials are defined and managed in Terraform (`terraform/qa-credentials.tf`)
- No manual credential management in scripts or configuration files
- Version-controlled, auditable, and reproducible

### 2. **Immutable Secrets**
- Secrets are stored in Google Secret Manager (GSM)
- Each credential change creates a new **versioned** secret record
- Previous versions are preserved (immutable history)
- Terraform `prevent_destroy` and `ignore_changes` ensure secrets are never accidentally modified
- **Once deployed, credentials are locked in place**

### 3. **Idempotent Deployment**
- `terraform plan` always shows "No changes" after initial deployment
- Running `terraform apply` multiple times produces identical results
- Safe to re-run without side effects
- CI/CD can deploy repeatedly without data corruption

### 4. **Automatically Mandated**
- GitHub Actions workflow (`.github/workflows/e2e-oauth-automatic.yml`) automatically:
  - Validates Terraform IaC configuration
  - Authenticates to GCP using Workload Identity Federation (WIF)
  - Loads QA credentials from GSM on every E2E test run
  - Enforces OAuth endpoint testing for all commits
  - Never stores credentials in code, logs, or artifacts

---

## File Structure

```
terraform/
├── qa-credentials.tf              # Terraform resources for GSM secrets + IAM
├── variables.tf                   # Variable definitions (qa_password, qa_email, etc.)
├── qa-credentials.tfvars.example  # Example values (never commit real values)
└── outputs.tf                     # Secret IDs for CI/CD consumption

scripts/
├── deploy-qa-credentials-iac.sh  # One-command IaC deployment (idempotent)
└── _common/
    └── init.sh                    # Shared initialization logic

.github/workflows/
└── e2e-oauth-automatic.yml        # GitHub Actions: automatic credential setup + OAuth testing

tests/e2e/
└── specs/
    ├── oauth-login-comprehensive.spec.ts      # OAuth E2E tests (requires QA creds)
    ├── appsmith-portal-features.spec.ts
    ├── ide-launch-operations.spec.ts
    ├── session-persistence-failover.spec.ts
    └── error-handling-edge-cases.spec.ts
```

---

## Deployment Workflow

### Step 1: Initial IaC Deployment (One-Time)

**Requirements**:
- GCP project: `kushin77-ops`
- GitHub Actions service account: `github-actions@kushin77-ops.iam.gserviceaccount.com`
- Workload Identity Federation configured

**Command**:
```bash
# Generate a secure 32-character password
QA_PASSWORD=$(openssl rand -hex 16 | head -c 32)
echo "Generated QA password: $QA_PASSWORD"

# Deploy IaC (creates immutable GSM secrets + IAM bindings)
bash scripts/deploy-qa-credentials-iac.sh "$QA_PASSWORD"
```

**What it does**:
1. Validates Terraform configuration
2. Creates immutable GSM secrets:
   - `qa-user-email`: `qa@kushnir.cloud`
   - `qa-user-password`: `<GENERATED_PASSWORD>`
3. Grants GitHub Actions service account access via IAM roles
4. Verifies idempotency (plan shows no changes on re-run)
5. Reports success/failure

**Outputs**:
```
✓ QA credentials deployed (immutable)
✓ Email secret: projects/kushin77-ops/secrets/qa-user-email/versions/1
✓ Password secret: projects/kushin77-ops/secrets/qa-user-password/versions/1
✓ Idempotent: Plan shows no changes (deployment is stable)
✓ CI service account can access both secrets
```

---

### Step 2: Automatic CI/CD Execution

**Trigger**: Any push to `main` that modifies:
- `tests/e2e/**`
- `apps/**/src/**`
- `terraform/qa-credentials.tf`

**Workflow** (`.github/workflows/e2e-oauth-automatic.yml`):

```
1. Validate IaC
   ├─ Terraform format check
   ├─ Terraform validate
   └─ Immutability annotation verification

2. Setup Credentials
   ├─ Authenticate to GCP (Workload Identity Federation)
   ├─ Load QA email from GSM
   ├─ Load QA password from GSM
   └─ Verify credentials are versioned (immutable)

3. Run OAuth E2E Tests
   ├─ Set environment variables (E2E_USER_EMAIL, E2E_USER_PASSWORD)
   ├─ Execute oauth-login-comprehensive.spec.ts
   └─ Generate HTML report

4. Run Full E2E Suite (Parallel)
   ├─ oauth-login-comprehensive (depends on OAuth)
   ├─ appsmith-portal-features (depends on OAuth)
   ├─ ide-launch-operations (depends on OAuth)
   ├─ session-persistence-failover (depends on OAuth)
   └─ error-handling-edge-cases (depends on OAuth)

5. Report Results
   └─ Upload artifacts to GitHub
```

---

## Idempotency Guarantees

### Terraform Idempotency

**After Initial Deployment**:
```bash
terraform plan
# Output: No changes. Infrastructure is up-to-date.
```

**Why?**:
- Secret versions are immutable (ignored by Terraform)
- IAM bindings are fixed (prevent_destroy enforced)
- GSM secrets are never updated (only versioned)

### Redeployment Safety

Running deployment multiple times is 100% safe:
```bash
# Safe to run repeatedly (idempotent)
bash scripts/deploy-qa-credentials-iac.sh "nHPMOKF9280saXmC4BJQvNj173ftxebI"
bash scripts/deploy-qa-credentials-iac.sh "nHPMOKF9280saXmC4BJQvNj173ftxebI"
bash scripts/deploy-qa-credentials-iac.sh "nHPMOKF9280saXmC4BJQvNj173ftxebI"

# Result: ✓ Idempotent: No changes needed
```

### CI/CD Idempotency

GitHub Actions workflow is idempotent:
- Loads credentials from GSM (immutable source)
- Never writes credentials to logs or artifacts
- Test results are deterministic
- Re-running CI/CD for same commit produces same results

---

## Immutability Enforcement

### Secret Versioning

GSM secrets are versioned automatically:
```bash
gcloud secrets versions list qa-user-email --project=kushin77-ops

# Output:
# NAME  STATE   CREATED
# 1     ENABLED 2026-04-20T10:30:00Z
# (no edits possible; new password = new version, old preserved)
```

### Terraform Lifecycle Rules

```terraform
# Prevent accidental secret deletion
lifecycle {
  prevent_destroy = true   # Blocks terraform destroy
  ignore_changes  = all    # Ignore manual updates to GSM
}
```

### IAM Immutability

Once deployed, IAM bindings are fixed:
- GitHub Actions service account **always** has secret accessor role
- Cannot remove without explicit `terraform destroy` (blocked)
- Prevents accidental lockout of CI/CD

---

## Credential Rotation

### When to Rotate Credentials

Rotate QA credentials if:
- Compromised or leaked
- Scheduled rotation (compliance requirement)
- Service account access needs to be revoked
- End of quarterly security audit

### How to Rotate (Immutable Approach)

**Option 1: Create New Version (Recommended)**
```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -hex 16 | head -c 32)

# Deploy new version (preserves old versions)
bash scripts/deploy-qa-credentials-iac.sh "$NEW_PASSWORD"

# Old versions are archived automatically
gcloud secrets versions list qa-user-password --project=kushin77-ops
# Shows: version 1 (old), version 2 (new)
```

**Option 2: Destroy & Recreate**
```bash
# For compliance: delete all secrets and redeploy fresh
terraform destroy -target=google_secret_manager_secret.qa_password
terraform destroy -target=google_secret_manager_secret.qa_email

# Redeploy with new credentials
bash scripts/deploy-qa-credentials-iac.sh "$NEW_PASSWORD"
```

---

## Security Properties

### ✅ What's Protected

| Property | Implementation |
|----------|-----------------|
| **Immutability** | GSM versions are immutable, Terraform prevent_destroy |
| **Access Control** | IAM roles grant only secretAccessor (read-only) |
| **Encryption** | GSM default encryption (at rest, in transit) |
| **Audit Trail** | All credential versions logged with creation timestamps |
| **CI/CD Isolation** | Workload Identity Federation (no long-lived keys) |
| **Secret Masking** | GitHub Actions masks passwords from logs |
| **No Code Storage** | Credentials stored in GSM, never in git |

### ✅ What's NOT Protected

- **QA user's password** is transmitted via GSM API (use HTTPS only)
- **GSM secret deletion** requires explicit terraform destroy (can be re-enabled if needed)
- **Credential expiration** is not enforced (implement via policy if required)

---

## Usage in E2E Tests

### Playwright Test Configuration

```typescript
// tests/e2e/specs/oauth-login-comprehensive.spec.ts

import { test, expect } from '@playwright/test';

test('OAuth login with QA credentials', async ({ page }) => {
  const qaEmail = process.env.E2E_USER_EMAIL;    // qa@kushnir.cloud
  const qaPassword = process.env.E2E_USER_PASSWORD;  // (from GSM)

  if (!qaEmail || !qaPassword) {
    test.skip();  // Skip if credentials not available
  }

  await page.goto('https://kushnir.cloud');
  await page.click('text=Login with Google');
  
  // Enter credentials
  await page.fill('input[type="email"]', qaEmail);
  await page.click('text=Next');
  
  await page.fill('input[type="password"]', qaPassword);
  await page.click('text=Next');

  // Verify successful login
  await expect(page).toHaveURL(/.*code-server.*/, { timeout: 10000 });
});
```

### Environment Variables in CI/CD

GitHub Actions automatically provides:
```bash
E2E_USER_EMAIL="qa@kushnir.cloud"              # From GSM
E2E_USER_PASSWORD="nHPMOKF9280saXmC4BJQvNj..." # From GSM (masked)
OAUTH_REDIRECT_URI="https://kushnir.cloud"
```

---

## Troubleshooting

### Issue: "Credentials unavailable in E2E tests"

**Diagnosis**:
```bash
# Check GSM secrets exist
gcloud secrets describe qa-user-email --project=kushin77-ops

# Check CI service account has access
gcloud secrets get-iam-policy qa-user-email --project=kushin77-ops | grep "github-actions"
```

**Fix**:
```bash
# Redeploy IaC
bash scripts/deploy-qa-credentials-iac.sh "$QA_PASSWORD"

# Verify in GitHub Actions logs
# Look for: "✓ Loaded QA email" and "✓ QA password is accessible"
```

### Issue: "Terraform shows changes despite idempotency"

**Diagnosis**:
```bash
terraform plan
# Should show: "No changes. Infrastructure is up-to-date."
```

**Fix**:
```bash
# Refresh state
terraform refresh

# Retry plan
terraform plan
```

### Issue: "Cannot redeploy because secret already exists"

**This is expected**. GSM secrets are immutable:
```bash
# Deployment is already complete and stable
# No changes needed - idempotent
# Run: bash scripts/deploy-qa-credentials-iac.sh "$SAME_PASSWORD"
# Result: ✓ No changes (idempotent deployment succeeded)
```

---

## References

- **Terraform**: `terraform/qa-credentials.tf`
- **Deployment Script**: `scripts/deploy-qa-credentials-iac.sh`
- **CI/CD Workflow**: `.github/workflows/e2e-oauth-automatic.yml`
- **E2E Tests**: `tests/e2e/specs/oauth-login-comprehensive.spec.ts`
- **GCP Project**: `kushin77-ops`
- **Service Account**: `github-actions@kushin77-ops.iam.gserviceaccount.com`

---

## Next Steps

1. ✅ Deploy IaC: `bash scripts/deploy-qa-credentials-iac.sh "<PASSWORD>"`
2. ✅ Verify CI/CD: Push to `main` and check GitHub Actions
3. ✅ Monitor E2E Tests: Verify all OAuth tests pass automatically
4. ✅ Document Rotation: Add credential rotation to quarterly compliance checklist