## Configure QA User OAuth Whitelist + GSM Credentials

### Objective
Add qa@kushnir.cloud to the OAuth2 whitelist and store credentials securely in Google Secret Manager.

### Part 1: OAuth Whitelist Configuration

**File**: `allowed-emails.txt`

**Current State**:
```
akushnir@bioenergystrategies.com
kushin77@gmail.com
```

**Target State**:
```
akushnir@bioenergystrategies.com
kushin77@gmail.com
qa@kushnir.cloud
```

**Deployment**:
```bash
# 1. Update allowed-emails.txt
echo "qa@kushnir.cloud" >> allowed-emails.txt

# 2. Redeploy oauth2-proxy to pick up new whitelist
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal"

# 3. Verify whitelist loaded
ssh akushnir@192.168.168.31 "docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt"
```

### Part 2: GSM Credentials Storage

**Secrets to Create**:

| Secret Name | Description | Source |
|-------------|-------------|--------|
| `qa-user-email` | QA account email | `qa@kushnir.cloud` |
| `qa-user-password` | QA account password | Generated during user creation |
| `qa-oauth-refresh-token` | OAuth refresh token (optional) | OAuth flow capture |

**GSM Commands**:
```bash
# Create secrets in Google Secret Manager
gcloud secrets create qa-user-email --replication-policy=automatic
gcloud secrets create qa-user-password --replication-policy=automatic

# Add values
echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-
echo -n "[ACTUAL_PASSWORD]" | gcloud secrets versions add qa-user-password --data-file=-

# Grant access to CI service account
gcloud secrets add-iam-policy-binding qa-user-email \
  --member="serviceAccount:github-actions@PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding qa-user-password \
  --member="serviceAccount:github-actions@PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Part 3: CI Environment Configuration

**GitHub Actions Secrets** (retrieved from GSM at runtime):

```yaml
# .github/workflows/e2e-tests.yml
env:
  E2E_USER_EMAIL: ${{ steps.gsm.outputs.qa-user-email }}
  E2E_USER_PASSWORD: ${{ steps.gsm.outputs.qa-user-password }}
```

**Local Development** (via scripts/fetch-gsm-secrets.sh):

```bash
# Add to fetch-gsm-secrets.sh
export E2E_USER_EMAIL=$(gcloud secrets versions access latest --secret=qa-user-email)
export E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret=qa-user-password)
```

### Part 4: Environment Schema Update

**Update `.env.schema.json`**:
```json
{
  "E2E_USER_EMAIL": {
    "description": "QA service account email for E2E testing",
    "required": false,
    "source": "gsm:qa-user-email"
  },
  "E2E_USER_PASSWORD": {
    "description": "QA service account password for E2E testing",
    "required": false,
    "source": "gsm:qa-user-password",
    "sensitive": true
  }
}
```

### Validation Commands

```bash
# Test GSM access
gcloud secrets versions access latest --secret=qa-user-email

# Test oauth2-proxy whitelist
curl -s https://kushnir.cloud/oauth2/auth -H "X-Forwarded-Email: qa@kushnir.cloud" | head

# Test full login flow (requires browser or Playwright)
E2E_USER_EMAIL=qa@kushnir.cloud E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret=qa-user-password) \
  npx playwright test tests/e2e/specs/oauth-login.spec.ts
```

### Security Checklist

- [ ] Password NEVER appears in git history
- [ ] Password NEVER appears in CI logs (masked)
- [ ] GSM access restricted to necessary service accounts only
- [ ] Rotation policy documented (quarterly recommended)

### Definition of Done

- [ ] qa@kushnir.cloud added to allowed-emails.txt
- [ ] oauth2-proxy restarted and whitelist verified
- [ ] GSM secrets created: qa-user-email, qa-user-password
- [ ] CI service account has GSM access
- [ ] .env.schema.json updated with new variables
- [ ] E2E test can authenticate as QA user
- [ ] No credentials in plaintext anywhere

Parent: #982
Depends on: #983 (QA user must exist first)
