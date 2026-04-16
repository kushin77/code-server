# Secrets Management Policy

**Date**: April 15, 2026  
**Effective**: Immediately  
**Owner**: Security Team  
**Review**: Quarterly  

---

## Policy Statement

No credentials, API keys, tokens, passwords, or sensitive data shall be committed to version control. All secrets must be stored in GitHub Secrets, HashiCorp Vault, or secure key management systems.

---

## Scope

This policy applies to:
- All code repositories under kushin77/ organization
- All GitHub Actions workflows
- All configuration files (.env, .conf, .yml)
- All test fixtures and mocks
- All documentation and examples

---

## Prohibited Secret Types

| Type | Examples | Risk Level |
|------|----------|------------|
| Passwords | Database, OAuth, Admin | CRITICAL |
| API Keys | GitHub, AWS, GCP, Stripe | CRITICAL |
| Tokens | JWT, OAuth tokens, session tokens | CRITICAL |
| Credentials | SSH keys, signing certificates | CRITICAL |
| Configuration | Connection strings, OAuth secrets | HIGH |
| Test Data | Hardcoded test user credentials | MEDIUM |

---

## Secret Storage Requirements

### GitHub Secrets (Recommended for CI/CD)

**Setup**:
```bash
# Add secret
gh secret set SECRET_NAME < secret-value.txt

# Verify
gh secret list

# Delete
gh secret delete SECRET_NAME
```

**Naming Convention**:
- UPPERCASE_WITH_UNDERSCORES
- Prefix with service name: `OAUTH_CLIENT_ID`, `DB_PASSWORD`, `AWS_ACCESS_KEY`
- Never use: `PASS`, `KEY`, `SECRET` alone (too ambiguous)

**Examples**:
```
✓ WIREGUARD_CONFIG
✓ OAUTH_CLIENT_ID
✓ OAUTH_CLIENT_SECRET
✓ GRAFANA_ADMIN_PASSWORD
✓ DATABASE_CONNECTION_STRING
✗ SECRET
✗ PASSWORD
✗ KEY
```

### HashiCorp Vault (For Server-Side Secrets)

Used for:
- Database credentials (auto-rotated)
- OAuth provider secrets
- Encryption keys

**Access**:
```bash
# Authenticate
vault login -method=oidc

# Store secret
vault kv put secret/code-server/postgres password=value

# Retrieve
vault kv get secret/code-server/postgres
```

### .env Files (Local Development Only)

**Rules**:
- NEVER commit `.env` file
- Add `.env` to `.gitignore`
- Provide `.env.example` with placeholder values
- Require manual setup during onboarding

**Example .env.example**:
```bash
# OAuth Configuration
OAUTH_CLIENT_ID=your-client-id-here
OAUTH_CLIENT_SECRET=your-client-secret-here

# Database
DB_HOST=localhost
DB_USER=codeserver
DB_PASSWORD=change-me-in-local-env

# Grafana
GRAFANA_ADMIN_PASSWORD=admin  # This is the default, change in production
```

---

## Adding New Secrets

### Step 1: Identify Secret Type

Is this secret needed for:
- [ ] GitHub Actions CI/CD → Use `gh secret set`
- [ ] Runtime configuration → Use environment variable injection
- [ ] Encryption key → Use Vault
- [ ] Test fixture → Use mock/fixture factory

### Step 2: Add to GitHub Secrets

```bash
# Generate secure secret (if applicable)
openssl rand -hex 32 > /tmp/new-secret.txt

# Add to GitHub
gh secret set NEW_SECRET_NAME < /tmp/new-secret.txt

# Verify
gh secret list | grep NEW_SECRET

# Cleanup
shred -vfz /tmp/new-secret.txt
```

### Step 3: Document in Workflow

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - name: Use secret
        env:
          # Required secrets for this workflow:
          MY_SECRET: ${{ secrets.MY_SECRET }}
        run: echo "Using secret"
```

### Step 4: Update This Document

Add entry to "Managed Secrets Inventory" section below.

---

## Managed Secrets Inventory

| Secret Name | Purpose | Rotation | Owner |
|-------------|---------|----------|-------|
| WIREGUARD_CONFIG | VPN configuration | 90 days | DevOps |
| OAUTH_CLIENT_ID | Google OAuth | 180 days | Security |
| OAUTH_CLIENT_SECRET | Google OAuth | 180 days | Security |
| GRAFANA_ADMIN_PASSWORD | Grafana access | 90 days | DevOps |
| DATABASE_PASSWORD | PostgreSQL | 90 days | DevOps |
| SLACK_WEBHOOK_URL | Notifications | 180 days | Platform |

---

## Secret Rotation Procedures

### Automated Rotation (Recommended)

Secrets managed by systems that auto-rotate:
- Database passwords (AWS RDS, CloudSQL)
- OAuth tokens (OAuth providers)
- API keys (SaaS providers)

### Manual Rotation

For static secrets:

```bash
# 1. Generate new secret
NEW_VALUE=$(openssl rand -hex 32)

# 2. Update GitHub Secret
gh secret set SECRET_NAME <<< "$NEW_VALUE"

# 3. Log rotation event
echo "Rotated SECRET_NAME on $(date)" >> /tmp/secret-rotation.log

# 4. Verify new value works
# (run dependent systems/tests)

# 5. Document in changelog
echo "- Rotated SECRET_NAME (reason: scheduled rotation)" >> CHANGELOG.md

# 6. Commit and push
git add CHANGELOG.md && git commit -m "chore: update changelog for secret rotation"
```

---

## Secret Detection & Prevention

### Pre-Commit Hook (Mandatory)

File: `.git/hooks/pre-commit`

```bash
#!/bin/bash
set -e

echo "Running secret detection..."

# Check staged files
THIS_COMMIT=$(git rev-parse --verify HEAD 2>/dev/null || echo "")
if git diff --cached --name-only | xargs truffleHog filesystem 2>/dev/null; then
  echo "❌ COMMIT BLOCKED: Potential secrets detected"
  echo "Please remove secrets and try again"
  exit 1
fi

echo "✓ No secrets detected"
exit 0
```

Install:
```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### CI/CD Scanning (Enforced)

Every PR requires:
1. TruffleHog scan (blocks if secrets found)
2. Semgrep SAST scan (blocks if hardcoded secrets pattern)
3. Manual review of suspicious strings

---

## Incident Response

If a secret is accidentally committed:

### Immediate Actions (Within 1 Hour)

1. **Alert Security Team**
   ```bash
   # Email: security@kushnir.cloud
   # Subject: SECRET EXPOSED - [Secret Name]
   ```

2. **Rotate Exposed Secret**
   ```bash
   # Immediately generate new value
   gh secret set EXPOSED_SECRET < new-secure-value.txt
   ```

3. **Revoke Old Value**
   - OAuth provider: revoke access tokens
   - Database: change password
   - API provider: revoke key

4. **Check Impact**
   ```bash
   # Did anyone clone with the old secret?
   git log --all --oneline | grep -i "exposed"
   ```

### Follow-Up Actions (Within 24 Hours)

5. **Remove from History**
   ```bash
   # Use BFG Repo-Cleaner (safe for shared repos)
   bfg --replace-text passwords.txt
   git reflog expire --expire=now --all && git gc --prune=now --aggressive
   ```

6. **Force Push** (with team approval)
   ```bash
   git push --force-with-lease
   # Notify all developers to re-clone
   ```

7. **Post-Mortem**
   - Document what happened
   - Update detection rules
   - Improve team training

---

## Developer Onboarding

### Required Setup

1. Install pre-commit hook:
   ```bash
   cp .git-hooks/* .git/hooks/
   chmod +x .git/hooks/*
   ```

2. Create local .env:
   ```bash
   cp .env.example .env
   # Edit .env with your local values
   ```

3. Install TruffleHog:
   ```bash
   pip install truffleHog
   ```

4. Test secret detection:
   ```bash
   echo "password=exposed" >> /tmp/test.txt
   truffleHog filesystem /tmp/test.txt
   # Should detect the secret
   ```

### Training

- Never paste credentials into code
- Always check .gitignore before committing
- Use placeholders in examples
- Report suspicious activity to security team

---

## Audit & Compliance

### Monthly Audit

```bash
#!/bin/bash
# scripts/audit-secrets.sh

echo "=== Secret Audit Report ==="
echo ""
echo "GitHub Secrets:"
gh secret list

echo ""
echo "Recent commits with secret keywords:"
git log --all -p -S 'password\|secret\|api_key' --oneline | head -20

echo ""
echo "Secrets in git history:"
truffleHog git file://. --json 2>/dev/null | jq '.sourceFile' | sort -u || echo "No secrets found"
```

Run monthly:
```bash
bash scripts/audit-secrets.sh > /tmp/audit-$(date +%Y-%m).log
# Review and archive log
```

---

## References

- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [TruffleHog Documentation](https://github.com/trufflesecurity/truffleHog)

---

**Policy Version**: 1.0  
**Last Updated**: April 15, 2026  
**Next Review**: July 15, 2026
