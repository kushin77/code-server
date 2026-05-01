# GSM Secrets Operations Runbook

**Owner**: Platform Operations  
**Scope**: Google Secret Manager (GSM) for production secrets management  
**Last Updated**: April 29, 2026  

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Secret Categories](#secret-categories)
4. [Common Operations](#common-operations)
5. [Emergency Procedures](#emergency-procedures)
6. [Troubleshooting](#troubleshooting)
7. [Audit and Compliance](#audit-and-compliance)

---

## Overview

This runbook documents operational procedures for managing secrets in Google Secret Manager (GSM) for the code-server platform.

**Key Principles:**
- ✅ All production secrets stored in GSM (never in .env or repo)
- ✅ Dev secrets kept in .gitignored local .env files
- ✅ Automatic fallback from GSM → environment variables in scripts
- ✅ All secret access audited and logged
- ✅ Automatic version management (keep 3 recent versions)

**Secret Hierarchy:**
```
Development:  .env files (local only)
        ↓
Staging:      GSM (automatic replication)
        ↓
Production:   GSM + Vault backup
```

---

## Prerequisites

### Tools

```bash
# Install Google Cloud SDK
curl https://sdk.cloud.google.com | bash

# Authenticate (opens browser)
gcloud init
gcloud auth application-default login

# Verify gcloud is configured
gcloud config list
gcloud config set project YOUR_PROJECT_ID
```

### Permissions

Verify you have these IAM roles:
- **Editor** or **Secret Manager Admin** for full access
- **Secret Manager Secret Accessor** for read-only access

Check your roles:
```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)"
```

### Environment

```bash
# Set project ID for all commands
export GCP_PROJECT_ID="your-project-id"

# Verify credentials
gcloud auth list
```

---

## Secret Categories

Organize secrets by purpose using consistent naming:

### 1. Database Secrets (`postgres-*`, `redis-*`)

```bash
# List database secrets
gcloud secrets list --filter="name:postgres* OR name:redis*"

# Common secrets:
# - postgres-admin-password      (superuser)
# - postgres-user-password       (app user)
# - postgres-replication-password (replication)
# - redis-password              (cache)
```

### 2. API Secrets (`github-*`, `slack-*`)

```bash
# GitHub fine-grained token
gsm_get_secret "github-fine-grained-token"

# GitHub App credentials (for token exchange)
gsm_get_secret "github-app-id"
gsm_get_secret "github-app-secret"

# Slack integration
gsm_get_secret "slack-webhook-url"
gsm_get_secret "slack-bot-token"
```

### 3. OAuth2 Secrets (`oauth2-*`)

```bash
# OAuth2 provider credentials
gsm_get_secret "oauth2-client-id"
gsm_get_secret "oauth2-client-secret"

# Session/cookie secret
gsm_get_secret "oauth2-cookie-secret"

# Redirect URI (usually just metadata)
gsm_get_secret "oauth2-redirect-uri"
```

### 4. TLS/Certificate Secrets (`tls-*`)

```bash
# TLS certificate and key
gsm_get_secret "tls-cert"
gsm_get_secret "tls-key"

# CA certificate for verification
gsm_get_secret "tls-ca-cert"
```

### 5. Application Secrets (`paperclip-*`, `jwt-*`)

```bash
# Encryption master key
gsm_get_secret "paperclip-encryption-master-key"

# Session management
gsm_get_secret "session-secret"

# JWT signing key
gsm_get_secret "jwt-signing-key"
```

---

## Common Operations

### Create a New Secret

```bash
# Option 1: From stdin
echo "secret-value-here" | gcloud secrets create my-secret --data-file=-

# Option 2: From file
gcloud secrets create my-secret --data-file=/path/to/secret.txt

# Option 3: With labels
gcloud secrets create my-secret \
  --replication-policy="automatic" \
  --data-file=- \
  --labels="env=prod,team=platform" <<< "secret-value"
```

### Retrieve a Secret

```bash
# Latest version
gcloud secrets versions access latest --secret="my-secret"

# Specific version
gcloud secrets versions access VERSION_ID --secret="my-secret"

# Using helper function
source scripts/_common/gsm-secrets.sh
TOKEN=$(gsm_get_secret "my-secret")
```

### Rotate a Secret (Add New Version)

```bash
# Generate new secret
NEW_TOKEN=$(gcloud auth print-access-token)

# Store as new version (old versions preserved)
echo "$NEW_TOKEN" | gcloud secrets versions add my-secret --data-file=-

# Verify new version is active
gcloud secrets versions list my-secret --limit=1
```

### List All Secrets

```bash
# All secrets
gcloud secrets list

# Format with timestamps
gcloud secrets list --format="table(name, created, updated, labels)"

# Filter by prefix
gcloud secrets list --filter="name:github*"
gcloud secrets list --filter="name:postgres*"

# Using helper
source scripts/_common/gsm-secrets.sh
gsm_list_secrets "github"  # Lists all github-* secrets
```

### Prune Old Versions

```bash
# Keep only 3 most recent versions of a secret
source scripts/_common/gsm-secrets.sh
gsm_prune_versions "my-secret" 3

# Manual method
gcloud secrets versions list my-secret --format="value(name)" | tail -n +4 | while read v; do
  gcloud secrets versions destroy "$v" --secret="my-secret" --quiet
done
```

### Delete a Secret Completely

```bash
# WARNING: This is permanent (10 day delay exists)
gcloud secrets delete my-secret --quiet

# Check deletion status
gcloud secrets list --filter="name:my-secret"
```

---

## Emergency Procedures

### Secret Leaked/Compromised

1. **Immediate**: Create new secret version
   ```bash
   NEW_VALUE=$(openssl rand -base64 32)
   echo "$NEW_VALUE" | gcloud secrets versions add my-secret --data-file=-
   ```

2. **Update Applications**: Deploy new secret to all services
   ```bash
   # Update environment in docker-compose
   docker-compose down
   docker-compose up -d
   ```

3. **Revoke Old Version**: Destroy compromised version
   ```bash
   gcloud secrets versions list my-secret --format="value(name)" | tail -1 | \
   xargs -I {} gcloud secrets versions destroy {} --secret="my-secret" --quiet
   ```

4. **Audit**: Check who accessed the secret
   ```bash
   # Check Cloud Audit Logs
   gcloud logging read "resource.type=secretmanager.googleapis.com AND \
     protoPayload.request.name=projects/PROJECT/secrets/my-secret" \
     --limit=50 --format=json
   ```

### Cannot Access Secret

```bash
# 1. Verify permission
gcloud secrets get-iam-policy my-secret

# 2. Check if secret exists
gcloud secrets describe my-secret

# 3. Verify authentication
gcloud auth list
gcloud config list

# 4. Check cloud logs for errors
gcloud logging read "severity>=ERROR" --limit=20
```

### Mass Secret Rotation

Script to rotate all GitHub tokens:

```bash
#!/bin/bash
for secret in github-fine-grained-token github-app-secret; do
  echo "Rotating $secret..."
  NEW_VALUE=$(openssl rand -base64 32)
  echo "$NEW_VALUE" | gcloud secrets versions add "$secret" --data-file=-
  gsm_prune_versions "$secret" 3
  echo "  ✓ Rotated $secret"
done
```

---

## Troubleshooting

### Error: "Permission denied" when accessing secret

**Cause**: Insufficient IAM permissions  
**Solution**:
```bash
# Check current permissions
gcloud secrets get-iam-policy my-secret

# Grant access
gcloud secrets add-iam-policy-binding my-secret \
  --member="user:your-email@company.com" \
  --role="roles/secretmanager.secretAccessor"
```

### Error: "Secret not found"

**Cause**: Secret doesn't exist or wrong project  
**Solution**:
```bash
# Verify project
gcloud config get-value project

# List all secrets
gcloud secrets list

# Check secret name spelling
gcloud secrets describe my-secret
```

### Error: "The Secret Manager API is not enabled"

**Cause**: API not enabled in GCP project  
**Solution**:
```bash
gcloud services enable secretmanager.googleapis.com

# Verify
gcloud services list --enabled | grep secret
```

### Script fails with "gcloud: command not found"

**Cause**: gcloud CLI not installed or not in PATH  
**Solution**:
```bash
# Install gcloud
curl https://sdk.cloud.google.com | bash

# Add to PATH
export PATH=/usr/local/google-cloud-sdk/bin:$PATH

# Verify
gcloud --version
```

### Secret retrieval hangs/times out

**Cause**: Network issues or credentials expired  
**Solution**:
```bash
# Refresh credentials
gcloud auth application-default login

# Test connectivity
gcloud secrets list --limit=1

# Check network
ping -c 1 secretmanager.googleapis.com
```

---

## Audit and Compliance

### View All Access to a Secret

```bash
SECRET_NAME="my-secret"
PROJECT_ID=$(gcloud config get-value project)

gcloud logging read \
  "resource.type=secretmanager.googleapis.com AND \
   protoPayload.request.name=projects/$PROJECT_ID/secrets/$SECRET_NAME" \
  --format="table(timestamp, protoPayload.principalEmail, protoPayload.methodName)" \
  --limit=100
```

### Export Audit Logs

```bash
# Export last 7 days of secret access
gcloud logging read \
  "resource.type=secretmanager.googleapis.com AND \
   timestamp>=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --format=json > /tmp/secret-audit-$(date +%Y%m%d).json

# Review exported logs
cat /tmp/secret-audit-*.json | jq '.[] | {user: .protoPayload.principalEmail, action: .protoPayload.methodName, secret: .protoPayload.request.name}'
```

### Compliance Checks

**Daily Secret Inventory:**
```bash
#!/bin/bash
gcloud secrets list --format="table(name, created, updated)" > /tmp/secret-inventory.txt
echo "Secret inventory saved to /tmp/secret-inventory.txt"
```

**Verify No Hardcoded Secrets in Code:**
```bash
# Using TruffleHog
trufflehog git https://github.com/YOUR_REPO --only-verified

# Using git-secrets
git secrets --scan --cached
```

**Verify All Secrets Are Rotated Within 90 Days:**
```bash
#!/bin/bash
CUTOFF=$(date -u -d "90 days ago" +%s)
for secret in $(gcloud secrets list --format="value(name)"); do
  CREATED=$(gcloud secrets describe "$secret" --format="value(created)" | date +%s)
  if (( CREATED < CUTOFF )); then
    echo "⚠️ Secret needs rotation: $secret (created >90 days ago)"
  fi
done
```

---

## Integration with Deployment Pipeline

### Using Secrets in Docker Compose

```bash
# In deployment script
source scripts/_common/gsm-secrets.sh

# Get secrets from GSM
OAUTH_SECRET=$(gsm_get_secret "oauth2-cookie-secret")
DB_PASSWORD=$(gsm_get_secret "postgres-user-password")

# Pass to docker-compose
export OAUTH2_COOKIE_SECRET="$OAUTH_SECRET"
export DATABASE_PASSWORD="$DB_PASSWORD"

# Deploy
docker-compose -f docker-compose.yml up -d
```

### Using Secrets in CI/CD

```yaml
# GitHub Actions example
- name: Deploy with secrets
  run: |
    source scripts/_common/gsm-secrets.sh
    TOKEN=$(gsm_get_secret "github-fine-grained-token")
    # Deploy...
```

### Using Secrets in Terraform

```hcl
# terraform/main.tf
data "google_secret_manager_secret_version" "db_password" {
  secret      = "postgres-user-password"
  version     = "latest"
}

resource "docker_container" "postgres" {
  env = [
    "POSTGRES_PASSWORD=${data.google_secret_manager_secret_version.db_password.secret_data}"
  ]
}
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Get secret | `gcloud secrets versions access latest --secret=NAME` |
| List secrets | `gcloud secrets list` |
| Create secret | `echo VALUE \| gcloud secrets create NAME --data-file=-` |
| Add version | `echo VALUE \| gcloud secrets versions add NAME --data-file=-` |
| Delete secret | `gcloud secrets delete NAME --quiet` |
| Destroy version | `gcloud secrets versions destroy VERSION --secret=NAME --quiet` |
| Check permissions | `gcloud secrets get-iam-policy NAME` |
| View audit logs | `gcloud logging read "resource.type=secretmanager.googleapis.com"` |

---

## Related Documentation

- [Google Cloud Secret Manager Docs](https://cloud.google.com/secret-manager/docs)
- [Security Guide](../docs/security/SECURITY-GUIDE.md)
- [GSM Secrets Helper Module](./scripts/_common/gsm-secrets.sh)
- [Deployment Secrets Checklist](#deployment-secrets-checklist) (below)

---

## Support

**Questions?** Check:
1. [Troubleshooting](#troubleshooting) section above
2. `gcloud secrets --help`
3. Google Cloud documentation
4. Platform team Slack channel

**To report a secret compromise:**
1. Immediately rotate the secret (see [Emergency Procedures](#emergency-procedures))
2. Notify the security team
3. Document incident in post-mortem
