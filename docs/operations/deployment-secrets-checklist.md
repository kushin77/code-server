# Deployment Secrets Checklist

**Purpose**: Verify all production secrets are properly configured in GSM before deployment.  
**Owner**: Platform Operations / Release Manager  
**Frequency**: Before every production deployment  

---

## Pre-Deployment Verification

### Step 1: Verify GSM Project Configuration

- [ ] GCP project ID is set: `gcloud config get-value project`
- [ ] Secret Manager API is enabled: `gcloud services list --enabled | grep secret`
- [ ] Authentication credentials valid: `gcloud auth list`
- [ ] Current user has appropriate IAM roles:
  ```bash
  gcloud projects get-iam-policy $(gcloud config get-value project) \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:$(gcloud config get-value account)"
  ```

### Step 2: Database Secrets

**Purpose**: PostgreSQL and Redis credentials must be present and valid

```bash
# Check each required secret exists
for secret in postgres-admin-password postgres-user-password postgres-replication-password redis-password; do
  if gcloud secrets describe "$secret" >/dev/null 2>&1; then
    echo "✓ $secret exists"
  else
    echo "✗ MISSING: $secret"
    exit 1
  fi
done
```

Checklist:
- [ ] `postgres-admin-password` exists and non-empty
- [ ] `postgres-user-password` exists and non-empty
- [ ] `postgres-replication-password` exists and non-empty
- [ ] `redis-password` exists and non-empty
- [ ] All database secrets are at least 20 characters
- [ ] None contain default values like "password" or "secret123"

### Step 3: API & Integration Secrets

**Purpose**: Third-party API tokens and webhooks must be present

```bash
for secret in github-fine-grained-token github-app-id github-app-secret slack-webhook-url slack-bot-token; do
  if gcloud secrets describe "$secret" >/dev/null 2>&1; then
    echo "✓ $secret exists"
  else
    echo "⚠ Optional: $secret"
  fi
done
```

Checklist:
- [ ] `github-fine-grained-token` exists (or GITHUB_TOKEN env var set)
- [ ] `github-app-id` exists (if using GitHub App auth)
- [ ] `github-app-secret` exists (if using GitHub App auth)
- [ ] `slack-webhook-url` exists (if Slack integration enabled)
- [ ] `slack-bot-token` exists (if Slack integration enabled)
- [ ] GitHub token starts with `github_pat_` (fine-grained)
- [ ] Slack tokens start with `xoxb-` or `xoxp-`

**Verification Script**:
```bash
#!/bin/bash
set -e

echo "Verifying API secrets..."

# Get GitHub token
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token" 2>/dev/null || true)
if [[ -n "$GITHUB_TOKEN" ]]; then
  # Verify token is valid with GitHub API
  USER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r '.login')
  if [[ -n "$USER" ]]; then
    echo "✓ GitHub token valid for user: $USER"
  else
    echo "✗ GitHub token invalid or expired"
    exit 1
  fi
fi

echo "✓ All API secrets verified"
```

### Step 4: OAuth2 Secrets

**Purpose**: Authentication provider secrets must be configured

Checklist:
- [ ] `oauth2-client-id` exists and non-empty
- [ ] `oauth2-client-secret` exists and non-empty
- [ ] `oauth2-cookie-secret` exists and is at least 32 characters
- [ ] `oauth2-redirect-uri` exists (metadata, can be read from config)
- [ ] OAuth2 secrets not in hardcoded values like "changeme" or "default"

**Verification**:
```bash
source scripts/_common/gsm-secrets.sh

gsm_verify_secret "oauth2-client-id" "not-empty"
gsm_verify_secret "oauth2-client-secret" "not-empty"
gsm_verify_secret "oauth2-cookie-secret" "length:32"

echo "✓ OAuth2 secrets valid"
```

### Step 5: TLS/Certificate Secrets

**Purpose**: HTTPS certificates must be present and valid

Checklist:
- [ ] `tls-cert` exists (if HTTPS enabled)
- [ ] `tls-key` exists (if HTTPS enabled)
- [ ] TLS cert is not self-signed in production
- [ ] TLS cert covers correct domain names
- [ ] TLS cert is not expired:
  ```bash
  CERT=$(gcloud secrets versions access latest --secret="tls-cert")
  echo "$CERT" | openssl x509 -noout -dates
  ```
- [ ] TLS cert and key match:
  ```bash
  CERT=$(gcloud secrets versions access latest --secret="tls-cert")
  KEY=$(gcloud secrets versions access latest --secret="tls-key")
  CERT_MOD=$(echo "$CERT" | openssl x509 -noout -modulus | md5sum)
  KEY_MOD=$(echo "$KEY" | openssl rsa -noout -modulus | md5sum)
  if [ "$CERT_MOD" = "$KEY_MOD" ]; then echo "✓ Match"; else echo "✗ Mismatch"; fi
  ```

### Step 6: Application Secrets

**Purpose**: Internal application encryption and signing keys must be present

Checklist:
- [ ] `paperclip-encryption-master-key` exists and is at least 32 characters
- [ ] `session-secret` exists and is at least 32 characters
- [ ] `jwt-signing-key` exists and is at least 32 characters
- [ ] None are default/placeholder values
- [ ] Keys are properly encoded (base64 or hex)

**Verification**:
```bash
source scripts/_common/gsm-secrets.sh

gsm_verify_secret "paperclip-encryption-master-key" "length:32"
gsm_verify_secret "session-secret" "length:32"
gsm_verify_secret "jwt-signing-key" "length:32"

echo "✓ Application secrets valid"
```

### Step 7: Environment Variables

**Purpose**: Ensure deployment scripts can access secrets

Checklist:
- [ ] `GCP_PROJECT_ID` is set: `echo $GCP_PROJECT_ID`
- [ ] `GSM_PROJECT_ID` is set: `echo $GSM_PROJECT_ID`
- [ ] gcloud authentication is valid: `gcloud auth list`
- [ ] `.env` file is NOT committed to git (check .gitignore)
- [ ] `.env.production` on remote hosts is NOT committed
- [ ] All env vars use GSM fallback pattern: `${SECRET_NAME:-$(gsm_get_secret "name")}`

### Step 8: Rotation Status

**Purpose**: Verify secrets are rotated regularly (max 90 days old)

```bash
#!/bin/bash
CUTOFF=$(date -u -d "90 days ago" +%s)

for secret in $(gcloud secrets list --format="value(name)"); do
  CREATED=$(gcloud secrets describe "$secret" --format="value(created)" | xargs -I {} date -d {} +%s)
  AGE=$(($(date +%s) - CREATED))
  DAYS=$((AGE / 86400))
  
  if (( DAYS > 90 )); then
    echo "⚠️ Secret needs rotation: $secret ($DAYS days old)"
  fi
done
```

Checklist:
- [ ] No secrets are older than 90 days
- [ ] GitHub token was rotated within 90 days
- [ ] Database passwords were rotated within 180 days
- [ ] Rotation schedule is documented and followed

### Step 9: Access Control

**Purpose**: Verify only authorized users/services can access secrets

Checklist:
- [ ] Review IAM permissions: `gcloud secrets get-iam-policy SECRET_NAME`
- [ ] Only platform team has Admin role
- [ ] Only CI/CD service account has Accessor role
- [ ] No public access (check for `allUsers` or `allAuthenticatedUsers`)
- [ ] Service accounts have only required permissions

**Audit all secrets**:
```bash
for secret in $(gcloud secrets list --format="value(name)"); do
  echo "=== $secret ==="
  gcloud secrets get-iam-policy "$secret"
done
```

### Step 10: Deployment Script Integration

**Purpose**: Verify deployment scripts properly load secrets

- [ ] Deployment script sources `scripts/_common/gsm-secrets.sh`
- [ ] Secrets are retrieved before containers start:
  ```bash
  source scripts/_common/gsm-secrets.sh
  export OAUTH2_COOKIE_SECRET=$(gsm_get_secret "oauth2-cookie-secret")
  ```
- [ ] Secrets are passed to docker-compose via environment
- [ ] No secrets are logged in output (grep for MASKED/REDACTED)
- [ ] Deployment script doesn't fail if optional secrets missing

### Step 11: Post-Deployment Verification

**Purpose**: Verify secrets loaded correctly in running containers

```bash
# For each container that uses secrets
docker exec CONTAINER_NAME env | grep -i secret | head -3

# Verify no plaintext secrets in logs
docker logs CONTAINER_NAME | grep -i "password\|token\|secret" | head -5
```

Checklist:
- [ ] Containers started successfully
- [ ] No "secret not found" errors in logs
- [ ] No plaintext secret values in container logs
- [ ] Application tests pass (verify OAuth2, DB connections work)
- [ ] Health checks pass: `curl -s http://localhost/health`

---

## Pre-Deployment Checklist (Quick Version)

Run this before each production deployment:

```bash
#!/bin/bash
set -e

echo "=== Deployment Secrets Checklist ==="
echo ""

source scripts/_common/gsm-secrets.sh

# Database
echo "Database secrets:"
gsm_secret_exists "postgres-admin-password" && echo "✓ postgres-admin-password" || (echo "✗ MISSING"; exit 1)
gsm_secret_exists "postgres-user-password" && echo "✓ postgres-user-password" || (echo "✗ MISSING"; exit 1)
gsm_secret_exists "redis-password" && echo "✓ redis-password" || (echo "✗ MISSING"; exit 1)

# OAuth2
echo ""
echo "OAuth2 secrets:"
gsm_verify_secret "oauth2-cookie-secret" "not-empty" || exit 1
gsm_verify_secret "oauth2-client-id" "not-empty" || exit 1
gsm_verify_secret "oauth2-client-secret" "not-empty" || exit 1

# API
echo ""
echo "API secrets:"
gsm_secret_exists "github-fine-grained-token" && echo "✓ github-fine-grained-token" || echo "⚠ Optional"

# Application
echo ""
echo "Application secrets:"
gsm_verify_secret "paperclip-encryption-master-key" "length:32" || exit 1
gsm_verify_secret "session-secret" "length:32" || exit 1

echo ""
echo "✓✓✓ All secrets verified! Ready to deploy. ✓✓✓"
```

---

## Troubleshooting

If any checks fail:

1. **Identify missing secret**: Check error message
2. **Create/rotate secret**:
   ```bash
   echo "new-secret-value" | gcloud secrets create SECRET_NAME --data-file=-
   ```
3. **Update deployment script** if needed
4. **Re-run checklist** to verify

---

## Related Documentation

- [GSM Secrets Runbook](GSM_SECRETS_RUNBOOK.md)
- [GSM Secrets Helper Module](../../scripts/_common/gsm-secrets.sh)
- [Security Guide](../../docs/security/SECURITY-GUIDE.md)
