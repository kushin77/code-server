# Secrets Management & Rotation Guide

## Overview

This document outlines how secrets are managed, rotated, and protected in the Kushnir.cloud infrastructure.

**Principle**: Secrets should be rotated regularly, stored securely, and never committed to git.

---

## Secret Storage Architecture

### Primary: Google Secret Manager (GSM)

**Location**: `gcp-kc` project  
**Bootstrap**: `scripts/fetch-gsm-secrets.sh`

Secrets are stored as versioned entries in GSM and fetched at deployment time.

```bash
# Bootstrap secrets from GSM
source scripts/fetch-gsm-secrets.sh

# Verify secrets loaded
env | grep VAULT_
```

### Fallback: .env Files (Local Development Only)

- **File**: `.env`, `.env.local`, `.env.template`
- **Scope**: Local testing and development
- **Safety**: Never commit files with real secrets
- **Git Protection**: Patterns in `.gitignore` and pre-commit hooks

---

## Secrets Categories

| Type | Storage | Rotation | Examples |
|------|---------|----------|----------|
| **Database Credentials** | GSM + .env | Quarterly | POSTGRES_PASSWORD, REDIS_PASSWORD |
| **OAuth2/API Keys** | GSM only | Semi-annually | GOOGLE_CLIENT_SECRET, GITHUB_TOKEN |
| **TLS/mTLS Certificates** | HashiCorp Vault | Annually | TLS_CERT_FILE, TLS_KEY_FILE |
| **Service Accounts** | GSM (JSON keys) | Annually | GCP service account keys |
| **Signing Keys** | Vault | Annually | VAULT_ROOT_TOKEN, Code-signing keys |

---

## Rotation Procedures

### 1. Database Passwords

```bash
# Generate new password
NEW_PASSWD=$(openssl rand -base64 32)

# 1. Create new secret version in GSM
gcloud secrets versions add POSTGRES_PASSWORD --data="$NEW_PASSWD"

# 2. Update docker-compose environment
docker-compose down
export POSTGRES_PASSWORD="$NEW_PASSWD"
docker-compose up -d postgres

# 3. Verify database connection
docker exec postgres psql -U code_server -c "SELECT 1"

# 4. Restart dependent services
docker restart pgbouncer code-server-session-broker

# 5. Document rotation in changelog
echo "ROTATION: POSTGRES_PASSWORD rotated on $(date)" >> docs/ROTATION-LOG.md
```

### 2. Redis Credentials

```bash
# Generate new password (must be valid for Redis)
NEW_PASSWD=$(openssl rand -base64 24 | tr -d '/' | head -c 32)

# 1. Update GSM
gcloud secrets versions add REDIS_PASSWORD --data="$NEW_PASSWD"

# 2. Update .env on deployed hosts
SSH_HOSTS=("akushnir@192.168.168.31" "akushnir@192.168.168.42")
for host in "${SSH_HOSTS[@]}"; do
  ssh "$host" "echo REDIS_PASSWORD=$NEW_PASSWD >> /home/akushnir/code-server-enterprise/.env"
done

# 3. Restart Redis (causes brief downtime ~5 seconds)
for host in "${SSH_HOSTS[@]}"; do
  ssh "$host" "docker restart redis redis-sentinel-1 redis-sentinel-arbiter"
done

# 4. Verify sentinel sees master healthy
docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL masters
```

### 3. OAuth2 Client Secrets

**Note**: Changing OAuth2 secrets requires coordination with OAuth2 provider.

```bash
# For Google OAuth2:
# 1. Go to https://console.cloud.google.com/apis/credentials
# 2. Rotate the service account client secret
# 3. Update GSM:
gcloud secrets versions add GOOGLE_CLIENT_SECRET --data="<new_secret>"

# 4. Restart OAuth2 proxy services
docker restart oauth2-proxy oauth2-proxy-portal

# 5. Verify OAuth2 flow works
curl -k https://ide.kushnir.cloud/oauth2/start
```

### 4. TLS Certificates

```bash
# Generate new certificate
certbot renew --force-renewal

# 1. Update Caddy configuration with new paths
sed -i "s|/etc/letsencrypt/live/old.cert|/etc/letsencrypt/live/new.cert|" Caddyfile

# 2. Reload Caddy
docker exec caddy caddy reload

# 3. Verify HTTPS is working
curl -v https://kushnir.cloud/health
```

---

## Secret Scanning & Prevention

### Pre-Commit Hook

Prevent accidental secret commits locally:

```bash
# Install pre-commit framework
pip install pre-commit

# Install hooks (one-time)
pre-commit install

# Hooks will run automatically on `git commit`
# To bypass (emergency only): git commit --no-verify
```

### CI/CD Secret Scanning

All PRs and pushes to `main` are scanned:

- **Tool**: TruffleHog v3.76.3
- **Scope**: Verified secrets only (high confidence)
- **Failure**: Blocks merge if secrets detected
- **Workflow**: `.github/workflows/security.yml`

```bash
# Scan locally before committing
trufflehog filesystem . --only-verified
```

---

## Incident Response: Compromised Secret

**If a secret is accidentally committed:**

1. **Immediately revoke** the secret (e.g., delete GSM version, rotate password)
2. **Audit access logs** to check if secret was used maliciously
3. **Force rotate** all dependent credentials
4. **Remove from git history**:
   ```bash
   git filter-branch --force --tree-filter '
     find . -name ".env" -delete
   ' HEAD
   git push origin --force-with-lease
   ```
5. **Post-incident review**: Document root cause and preventive measures

---

## Monitoring & Alerts

- **Rotation Expiry**: Alerts 30 days before rotation due
- **Suspect Activity**: Auto-revoke credentials on suspicious access patterns
- **Failed Auth**: Alert on repeated auth failures (potential brute force)

**Alert Channel**: Slack `#security-alerts`

---

## Documentation & Governance

- **SSOT**: Secrets list maintained in `GSM project=gcp-kc`
- **Audit Trail**: All GSM operations logged to Cloud Audit Logs
- **Access Control**: Only ops/security team can access GSM
- **Compliance**: Follows SOC 2 Type II requirements for secret management

---

## References

- [Google Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Pre-commit Framework](https://pre-commit.com/)
- [TruffleHog Documentation](https://github.com/trufflesecurity/trufflehog)
- [NIST SP 800-53: AC-2 Account Management](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf)

---

**Last Updated**: April 23, 2026  
**Owner**: Security Team  
**Status**: Active
