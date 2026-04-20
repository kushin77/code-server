# SECURITY INCIDENT REPORT — April 19, 2026
## Hardcoded Secrets Exposure in Git History

**SEVERITY:** 🔴 **CRITICAL**  
**STATUS:** Requires Immediate Action  
**Affected Systems:** Production credentials in plaintext  
**Timeline to Fix:** Today (4-6 hours)

---

## EXPOSED SECRETS INVENTORY

### 🔴 CRITICAL SECRETS (Production/API Access)

| Secret Type | File | Line | Exposure | Severity | Action |
|-------------|------|------|----------|----------|--------|
| Google OAuth2 Client Secret | .env | L4 | Git history + possible CI logs | CRITICAL | **REVOKE IMMEDIATELY** |
| GitHub Personal Access Token | .env | L16 | Git history + possible CI logs | CRITICAL | **REVOKE IMMEDIATELY** |
| oauth2-proxy Cookie Secret | .env | L5 | Git history + possible CI logs | CRITICAL | **REVOKE IMMEDIATELY** |
| GoDaddy API Key | .env | L11-14 | Git history (DUPLICATED 2x!) | CRITICAL | **REVOKE IMMEDIATELY** |
| GoDaddy API Secret | .env | L11-14 | Git history (DUPLICATED 2x!) | CRITICAL | **REVOKE IMMEDIATELY** |

### 🟠 HIGH SECRETS (Database/Service Access)

| Secret Type | File | Line | Exposure | Severity | Action |
|-------------|------|------|----------|----------|--------|
| Code-Server Admin Password | .env | L6 | Git history | HIGH | Rotate |
| Appsmith Admin Password | .env | L9 | Git history | HIGH | Rotate |
| PostgreSQL Admin Password | .env.defaults | L95 | Git history | HIGH | Rotate |
| MinIO Access Key | .env.defaults | L158 | Git history | HIGH | Rotate |
| MinIO Secret Key | .env.defaults | L161 | Git history | HIGH | Rotate |

---

## REMEDIATION CHECKLIST

### PHASE 1: IMMEDIATE (Today - 30 minutes)

- [ ] **STOP:** No commits until .env removed from git
- [ ] **REVOKE:** All secrets in external systems
  - [ ] Google OAuth2 (disable current client secret)
  - [ ] GitHub Personal Access Token (delete from GitHub)
  - [ ] GoDaddy API Key (rotate in GoDaddy console)
  - [ ] All other production credentials
- [ ] **NOTIFY:** Team about credential compromise
- [ ] **BACKUP:** Screenshot current .env values before deletion

### PHASE 2: GIT CLEANUP (Today - 1 hour)

- [ ] Remove `.env` from git history
  ```bash
  git filter-branch --tree-filter 'rm -f .env' -- --all
  # OR use git-filter-repo (preferred)
  pip install git-filter-repo
  git filter-repo --path .env --invert-paths
  ```
- [ ] Force push to all branches
  ```bash
  git push --force-with-lease origin main
  git push --force-with-lease origin --all
  ```
- [ ] Verify .env is not in history:
  ```bash
  git log --full-history -- .env
  # Should return nothing
  ```

### PHASE 3: REGENERATE SECRETS (Today - 2 hours)

- [ ] **Google OAuth2:**
  - Login to Google Cloud Console
  - Rotate client secret
  - Update .env with new secret
  
- [ ] **GitHub PAT:**
  - Login to GitHub
  - Delete old token
  - Create new token with minimal scopes
  - Update .env

- [ ] **GoDaddy API:**
  - Login to GoDaddy console
  - Rotate API key/secret
  - Update .env (note: previously duplicated — consolidate)

- [ ] **Vault/GSM Integration:**
  - Store all secrets in Vault (on-prem)
  - Configure GSM bootstrap (production)
  - Update .env to reference Vault/GSM instead

- [ ] **Database Passwords:**
  - Rotate PostgreSQL admin password
  - Rotate MinIO credentials
  - Store in Vault/GSM

### PHASE 4: CI/CD AUDIT (Today - 1 hour)

- [ ] Check GitHub Actions logs for secret exposure
  ```bash
  # View GitHub Actions logs (do NOT paste credentials!)
  gh workflow view <workflow-name>
  ```
- [ ] Check CI/CD logs for credential leaks
- [ ] Disable log retention for logs containing secrets
- [ ] Enable masking for all secrets in CI/CD:
  ```yaml
  # .github/workflows/example.yml
  env:
    GOOGLE_CLIENT_SECRET: ${{ secrets.GOOGLE_CLIENT_SECRET }}
  ```

### PHASE 5: DEPLOYMENT (Today - 2 hours)

- [ ] Update `.env.template` with descriptions (no values)
- [ ] Update docker-compose to use env vars for all secrets
- [ ] Update terraform to use Vault/GSM for secrets
- [ ] Regenerate `.env` from template with new secrets
- [ ] Deploy to 192.168.168.31:
  ```bash
  ssh akushnir@192.168.168.31
  cd code-server-enterprise
  # Pull changes with forced rebase
  git pull --force-with-lease origin main
  # Regenerate .env with new secrets
  cp .env.template .env
  # Fill in new secret values (from Vault/GSM)
  docker compose down
  docker compose pull
  docker compose up -d
  docker compose logs -f
  ```

---

## RISK ASSESSMENT

### Current Risk Level: 🔴 **CRITICAL**

**What an attacker can do:**
- ✅ Access Google OAuth2 (impersonate users, steal credentials)
- ✅ Access GitHub (modify code, access private repos)
- ✅ Access GoDaddy (modify DNS, domain hijacking)
- ✅ Access Code-server (execute code on production)
- ✅ Access PostgreSQL (steal/modify data)
- ✅ Access MinIO (steal/modify backups)

**Time window:** Immediate (GitHub stores forever, git history is public)

**Impact:** Complete infrastructure compromise

---

## PREVENTION (Going Forward)

### Add Pre-Commit Hook

Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Prevent secrets in git
PATTERN='(password|secret|token|key|credential).*=.*[a-zA-Z0-9]{20,}'
if git diff --cached | grep -iE "$PATTERN"; then
    echo "ERROR: Possible secret detected in staged changes"
    exit 1
fi
```

### Add .gitignore

```
# .gitignore
.env
.env.local
.env.*.local
terraform.tfvars
terraform.tfvars.json
*.key
*.pem
.vault-token
```

### Add GitHub Secret Scanning

```yaml
# .github/settings.yml
repo:
  secret_scanning: true
  secret_scanning_push_protection: true
```

### Use Vault/GSM for All Secrets

**Vault (On-Prem):**
```bash
# Store secrets
vault kv put secret/code-server google_client_secret=<value>

# Retrieve in script
source scripts/fetch-vault-secrets.sh
```

**GSM (Production):**
```bash
# Already in fetch-gsm-secrets.sh
source scripts/fetch-gsm-secrets.sh
```

### Update .env.template

```bash
# .env.template
# DO NOT add real values here!
# All secrets should be loaded from Vault/GSM

# Google OAuth2
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=   # ← Use Vault or GSM

# GitHub
GITHUB_TOKEN=           # ← Use Vault or GSM

# GoDaddy
GODADDY_API_KEY=        # ← Use Vault or GSM
GODADDY_API_SECRET=     # ← Use Vault or GSM

# Database
POSTGRES_PASSWORD=      # ← Use Vault or GSM
```

---

## COMPLIANCE & AUDITING

### Document This Incident

```bash
# Create incident log
echo "2026-04-19: Hardcoded secrets found in .env, revoked and regenerated" >> docs/security/INCIDENT-LOG.md
```

### Update Security Policy

Add to [docs/SECURITY-POLICY.md](docs/SECURITY-POLICY.md):
```markdown
## Secret Management

1. **All secrets must be stored in Vault or GSM**
2. **.env must not be committed to git**
3. **.env.template documents available env vars (NO VALUES)**
4. **Pre-commit hook scans for secrets**
5. **GitHub secret scanning enabled**
6. **Quarterly rotation of all credentials**
```

### Monitor for Future Leaks

```bash
# Monitor GitHub for exposed tokens
# https://github.com/settings/tokens → Token scanning

# Monitor git history
git log -p | grep -i "password\|secret\|token" || echo "No secrets found"
```

---

## ROLLBACK PLAN (If Something Goes Wrong)

If the force push causes issues:

```bash
# Restore backed-up branch
git reset --hard <backed-up-commit>
git push --force origin main

# Restore backed-up servers
ssh akushnir@192.168.168.31
docker compose down
# Restore from backup database/config
docker compose up -d
```

---

## SIGN-OFF CHECKLIST

- [ ] All secrets revoked in external systems
- [ ] .env removed from git history
- [ ] Force push completed to all remotes
- [ ] Verified .env is not in git log
- [ ] All secrets regenerated
- [ ] Vault/GSM configured
- [ ] Pre-commit hook deployed
- [ ] .gitignore updated
- [ ] GitHub secret scanning enabled
- [ ] Deployment to 192.168.168.31 successful
- [ ] All services operational post-deployment
- [ ] Incident documented
- [ ] Security policy updated
- [ ] Team notified

---

## TIMELINE

| Task | Start | Duration | End | Owner |
|------|-------|----------|-----|-------|
| Revoke secrets | 14:45 | 30m | 15:15 | Copilot |
| Git cleanup | 15:15 | 1h | 16:15 | Copilot |
| Regenerate secrets | 16:15 | 1h | 17:15 | Copilot + Team |
| CI/CD audit | 17:15 | 1h | 18:15 | Copilot |
| Deployment | 18:15 | 2h | 20:15 | Team |
| Verification | 20:15 | 1h | 21:15 | Team |
| **TOTAL** | | **6.5h** | | |

---

## REFERENCES

- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [git-filter-repo](https://github.com/newren/git-filter-repo)
- [OWASP: Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [Google Secret Manager](https://cloud.google.com/secret-manager)

---

**Report Generated:** 2026-04-19T15:00:00Z  
**Status:** ⏳ Awaiting Action  
**Next Review:** Hourly until remediated  
**Escalation Contact:** Security Team
