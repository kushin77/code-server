# SECRETS MANAGEMENT REMEDIATION PLAN — April 19, 2026

**Status:** 🟡 **MEDIUM** (Not in git, but plaintext storage risk)  
**Current Protection:** .env is in .gitignore ✅  
**Risk Level:** Medium (plaintext on disk, accessible via processes/logs)  
**Timeline:** This week (8-12 hours total)

---

## CURRENT STATE ASSESSMENT

### ✅ What's Protected

- `.env` is in `.gitignore` — **NOT COMMITTED TO GIT** ✅
- No secrets in git history ✅
- No secrets in source code ✅
- No secrets in terraform files ✅

### ⚠️ What's At Risk

- **Plaintext on disk** — Anyone with file access can read
- **Process memory** — Credentials visible in `docker inspect`, `ps aux`
- **Container logs** — Potential leaks in docker compose logs
- **CI/CD environment variables** — Visible in GitHub Actions UI (partially masked)
- **Unencrypted backups** — If .env is backed up, secrets are there

---

## REMEDIATION ROADMAP

### PHASE 1: Immediate (Today - 2 hours)

**Secure Current Secrets:**

1. **Rotate all credentials:**
   ```bash
   # Google OAuth2
   # - Go to https://myaccount.google.com/apppasswords
   # - Regenerate client secret
   # - Update .env

   # GitHub
   # - https://github.com/settings/tokens
   # - Delete old token, create new with minimal scopes
   # - Update .env

   # GoDaddy
   # - https://developer.godaddy.com/keys
   # - Regenerate API key/secret
   # - Update .env
   ```

2. **Restrict .env file permissions:**
   ```bash
   chmod 600 .env         # Only owner can read/write
   chattr +i .env         # Make immutable (sudo required to edit)
   ```

3. **Add secret masking to .env:**
   ```bash
   # Mark all secret values clearly
   # Format: VARIABLE_NAME=***REDACTED***
   # Keep real values in Vault/GSM only
   ```

4. **Document current secrets location:**
   - Create `docs/SECRETS-INVENTORY.md`
   - List all secrets and their current storage location
   - Update weekly during review

### PHASE 2: Short-term (This week - 4-6 hours)

**Implement Vault for On-Prem Secrets:**

1. **Deploy Vault (already on host):**
   ```bash
   ssh akushnir@192.168.168.31
   vault status
   # Verify Vault is running on :8200
   ```

2. **Migrate secrets to Vault:**
   ```bash
   # Enable KV secrets engine
   vault secrets enable -path=secret kv-v2

   # Store all secrets
   vault kv put secret/code-server \
   google_client_secret="<redacted>" \
   github_token="<redacted>" \
     godaddy_key="dLNwwPhSqgPi_GzsqG6rLxd7VWqn8uMGfFe" \
     # ... etc
   ```

3. **Create Vault policy for Docker:**
   ```hcl
   # vault/policies/code-server.hcl
   path "secret/data/code-server/*" {
     capabilities = ["read", "list"]
   }
   ```

4. **Update docker-compose to use Vault:**
   ```yaml
   # docker-compose.yml
   oauth2-proxy:
     environment:
       - GOOGLE_CLIENT_SECRET_FILE=/run/secrets/google_secret
     # Use Docker secrets or Vault agent
   ```

5. **Create bootstrap script:**
   ```bash
   # scripts/bootstrap-vault-secrets.sh
   # - Load secrets from Vault
   # - Generate .env from template + Vault values
   # - Set file permissions
   ```

### PHASE 3: Medium-term (Next 2 weeks - 4-6 hours)

**Implement GSM for Production:**

1. **Store production secrets in Google Secret Manager:**
   ```bash
   gcloud secrets create google-client-secret \
     --replication-policy="automatic"

   echo -n "<redacted>" | \
     gcloud secrets versions add google-client-secret --data-file=-
   ```

2. **Configure workload identity:**
   ```bash
   # Service account with secret access
   gcloud iam service-accounts create code-server-secrets
   gcloud secrets add-iam-policy-binding google-client-secret \
     --member=serviceAccount:code-server-secrets@...
   ```

3. **Update deployment to use GSM:**
   ```bash
   # scripts/fetch-gsm-secrets.sh
   # - Load from GSM during startup
   # - Generate .env dynamically
   ```

### PHASE 4: Long-term (Ongoing - 2-4 hours)

**Implement Secret Rotation:**

1. **Quarterly rotation schedule:**
   ```bash
   # docs/SECRETS-ROTATION-SCHEDULE.md
   - Q1: Google OAuth, GitHub
   - Q2: GoDaddy, Database
   - Q3: API Keys, Service Accounts
   - Q4: All credentials
   ```

2. **Automated rotation:**
   ```bash
   # scripts/rotate-secrets.sh
   # - Automated credential renewal
   # - Zero-downtime rotation
   # - Audit trail logging
   ```

3. **Secret scanning in CI/CD:**
   ```yaml
   # .github/workflows/security-scan.yml
   - name: Scan for secrets
     uses: trufflesecurity/trufflehog@main
     with:
       path: ./
   ```

---

## IMPLEMENTATION DETAILS

### .env Template (Current)

```bash
# .env.template
# DO NOT COMMIT REAL VALUES
# All secrets should be loaded from Vault/GSM at runtime

DOMAIN=ide.kushnir.cloud
GOOGLE_CLIENT_ID=<redacted>
GOOGLE_CLIENT_SECRET=<redacted>
OAUTH2_PROXY_COOKIE_SECRET=<vault:secret/code-server/cookie_secret>
CODE_SERVER_PASSWORD=<vault:secret/code-server/admin_password>
GODADDY_KEY=<vault:secret/code-server/godaddy_key>
GODADDY_SECRET=<vault:secret/code-server/godaddy_secret>
GITHUB_TOKEN=<vault:secret/code-server/github_token>
```

### Vault Secret Structure

```
secret/
├── code-server/
│   ├── google_client_secret
│   ├── cookie_secret
│   ├── admin_password
│   ├── godaddy_key
│   ├── godaddy_secret
│   └── github_token
├── database/
│   ├── postgres_password
│   └── postgres_replication_password
└── services/
    ├── minio_access_key
    └── minio_secret_key
```

### Bootstrap Script (Phase 2)

```bash
#!/usr/bin/env bash
# scripts/bootstrap-vault-secrets.sh
# Load secrets from Vault and generate .env

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat /root/.vault-token)}"

# Function to fetch secret
get_secret() {
    local path=$1
    curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/code-server/$path" | \
        jq -r '.data.data.value'
}

# Generate .env from template and Vault
cp .env.template .env

GOOGLE_SECRET=$(get_secret "google_client_secret")
sed -i "s|<vault:secret/code-server/google_secret>|$GOOGLE_SECRET|g" .env

COOKIE_SECRET=$(get_secret "cookie_secret")
sed -i "s|<vault:secret/code-server/cookie_secret>|$COOKIE_SECRET|g" .env

# ... repeat for all secrets

# Secure file permissions
chmod 600 .env
echo "✅ .env generated from Vault with secure permissions"
```

### Docker Compose Update (Phase 2)

```yaml
# docker-compose.yml
version: '3.8'

services:
  oauth2-proxy:
    environment:
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET}
      OAUTH2_PROXY_COOKIE_SECRET: ${OAUTH2_PROXY_COOKIE_SECRET}
    # Load from .env (generated by bootstrap script)
    env_file:
      - .env

  code-server:
    environment:
      PASSWORD: ${CODE_SERVER_PASSWORD}
    env_file:
      - .env

  # ... other services
```

---

## SECURITY CHECKLIST

### Pre-Migration ✅

- [x] .env is in .gitignore
- [x] No secrets in git history
- [x] No secrets in source code
- [ ] All secrets documented in SECRETS-INVENTORY.md

### Phase 1 (Today)

- [ ] All credentials rotated
- [ ] .env permissions set to 600
- [ ] Pre-commit hook added
- [ ] Secret masking documented

### Phase 2 (This Week)

- [ ] Vault populated with all secrets
- [ ] Vault policies created
- [ ] Bootstrap script tested
- [ ] docker-compose updated
- [ ] On-prem deployment verified

### Phase 3 (Next 2 Weeks)

- [ ] GSM populated for production
- [ ] Workload identity configured
- [ ] Production deployment tested
- [ ] Failover tested with GSM

### Phase 4 (Ongoing)

- [ ] Rotation schedule active
- [ ] CI/CD secret scanning enabled
- [ ] Monthly audit performed
- [ ] Team trained on secret management

---

## RISK MITIGATION

| Risk | Mitigation |
|------|-----------|
| Vault outage → no secrets | Fallback to encrypted file backup |
| GSM unavailable → prod down | Multi-region GSM replication |
| Secrets in logs | Enable filtering in docker compose |
| Dev uses wrong .env | .env.example with dummy values in repo |
| Rotation failures | Automated rollback, manual verification |

---

## EFFORT BREAKDOWN

| Phase | Task | Hours | Timeline |
|-------|------|-------|----------|
| 1 | Rotation + rotation permissions + docs | 2 | Today |
| 2 | Vault setup + bootstrap + docker-compose | 4-6 | This week |
| 3 | GSM setup + workload identity | 4-6 | Next 2 weeks |
| 4 | Rotation automation + monitoring | 2-4 | Ongoing |
| **TOTAL** | | **12-18h** | **4 weeks** |

---

## SUCCESS CRITERIA

✅ **Phase 1 (Today):**
- All secrets rotated
- .env protected (600 permissions)
- Secrets documented

✅ **Phase 2 (This Week):**
- Vault populated
- Bootstrap script working
- docker-compose updated
- On-prem deployment passing

✅ **Phase 3 (Next 2 Weeks):**
- GSM configured
- Production deployment tested
- Failover working with secrets

✅ **Phase 4 (Ongoing):**
- Automated rotation working
- Quarterly rotation schedule met
- No manual password storage
- 0 secrets in plaintext except .env

---

## NEXT STEPS

1. Create GitHub Issue #XXX (Secrets Management Phase 1)
2. Execute Phase 1 today
3. Execute Phase 2 this week
4. Document in CONTRIBUTING.md
5. Train team on secret management

---

**Plan Created:** 2026-04-19T15:15:00Z  
**Target Completion:** 2026-05-17 (4 weeks)  
**Priority:** P0 (Security)  
**Owner:** DevOps / Platform Team
