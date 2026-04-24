# Copilot Instructions for kushin77/code-server — ENHANCED April 19, 2026
## Elite Production-Ready Code Governance Rules (Copilot Enforcement)

**SCOPE:** This workspace ONLY. Last updated: April 19, 2026.  
**STATUS:** Production-Ready Enforcement (No exceptions without P0 justification + exec approval)  
**EFFECTIVE DATE:** April 22, 2026 (all new commits must comply)

---

## CRITICAL RULES (Non-Negotiable)

### Rule 0 — SECURITY FIRST
**No hardcoded secrets in any file ever.** Period.

❌ **FORBIDDEN:**
```bash
# NEVER DO THIS
export GOOGLE_CLIENT_SECRET=\"GOCSPX-abc...\"
export GITHUB_TOKEN=\"ghp_\" + \"abc...\"
export DATABASE_PASSWORD=\"password123\"
```

✅ **REQUIRED:**
```bash
# Load from Vault/GSM at runtime
source scripts/fetch-gsm-secrets.sh
export GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"  # From Vault
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # From Vault
export DATABASE_PASSWORD="${DATABASE_PASSWORD:-}"  # From Vault

# .env must NEVER contain real secrets (use .env.template with descriptions)
```

**Implementation:**
- All secrets in `.env.template` documented with `<vault:path>` markers
- Pre-commit hook blocks any commit containing `password=`, `secret=`, `token=` with values
- Use `scripts/bootstrap-vault-secrets.sh` to generate `.env` at runtime
- Vault/GSM configuration required (see Rule 8)

---

### Rule 1 — Configuration SSOT (Single Source of Truth)
**Every configuration item has ONE authoritative source.** No conflicts allowed.

**Hierarchy (highest to lowest precedence):**
```
1. Environment Variables (runtime override)
   ↓
2. terraform.tfvars or terraform/*.tfvars (IaC deployment params)
   ↓
3. terraform/variables.tf defaults (canonical IaC definitions)
   ↓
4. .env.${ENV} files (environment-specific)
   ↓
5. .env.template (template with descriptions, NO VALUES)
   ↓
6. Code defaults (last resort, must be documented)
```

**Critical Config Items (SSOT locations):**

| Item | SSOT Location | Override Via | Example |
|------|---------------|-------------|---------|
| `DOMAIN` | `terraform/variables.tf` | `.env`, env var | `ide.kushnir.cloud` |
| `PRIMARY_HOST` | `terraform/network-variables.tf` | env var | `192.168.168.31` |
| `REPLICA_HOST` | `terraform/network-variables.tf` | env var | `192.168.168.42` |
| `NAS_PRIMARY` | `terraform/network-variables.tf` | env var | `192.168.168.56` |
| `DATABASE_NAME` | `terraform/variables.tf` | None (canonical!) | `code_server` |
| `POSTGRES_PASSWORD` | Vault secret (key: `db_password`) | N/A | Use Vault |
| `GOOGLE_CLIENT_SECRET` | Vault secret (key: `google_secret`) | N/A | Use Vault |
| `GITHUB_TOKEN` | Vault secret (key: `github_token`) | N/A | Use Vault |
| `OLLAMA_MODELS` | `terraform/variables.tf` | env var | `["llama2:70b-q4_K_M"]` |

**Validation:**
```bash
# Check for conflicts
grep -r "DATABASE_NAME\|code_server\|ide_production" . --include="*.tf" --include="*.env*" --include="*.yml"

# Should return ONLY terraform/variables.tf (SSOT location)
# If elsewhere, it's a conflict and must be removed
```

**Enforcement:**
- CI/CD will scan for duplicate configuration definitions
- Any conflict blocks merge to main
- Copilot will flag configurations defined in multiple places

---

### Rule 2 — Image Version Pinning (Immutability)
**All container images must be pinned to specific versions.** No `:latest` tags allowed.

✅ **CORRECT:**
```yaml
# docker-compose.yml
services:
  code-server:
    image: codercom/code-server:4.23.0  # ✅ Specific version
  
  ollama:
    image: ollama/ollama:0.1.33  # ✅ Pinned version
  
  postgres:
    image: postgres:15.4-alpine  # ✅ Specific version with digest
    # OR (even better — with digest):
    # image: postgres@sha256:abc123def456...  # ✅ Immutable digest
```

❌ **FORBIDDEN:**
```yaml
image: ollama/ollama:latest  # ❌ FORBIDDEN
image: mistral:latest        # ❌ FORBIDDEN  
image: postgres               # ❌ FORBIDDEN (defaults to latest)
```

**Implementation:**
1. Pin all images in `docker-compose.yml`
2. Pin all images in Terraform (AMI versions, container registries)
3. Include SHA256 digests when possible
4. Document the version in a version matrix

**Version Matrix (maintain in version-pinning-policy.md):**
```yaml
images:
  codercom-code-server: 4.23.0
  ollama: 0.1.33
  postgres: 15.4
  redis: 7.2
  prometheus: v2.48.0
  grafana: 10.2.3
  oauth2-proxy: v7.5.1
```

**CI/CD Enforcement:**
- All `:latest` tags trigger build failure
- Missing versions trigger build failure
- Floating tags (e.g., `v7.*`) trigger warning

---

### Rule 3 — IaC Idempotency & Immutability

**All terraform, docker-compose, and kubernetes manifests must be:**
1. **Idempotent** — Safe to run 10 times (no drift, no errors)
2. **Immutable** — Version-pinned, reproducible, no mutations
3. **Validated** — Input types, ranges, formats enforced
4. **Tested** — Terraform validate, docker-compose config, helm lint

✅ **IDEMPOTENT:**
```hcl
# terraform/main.tf

# ✅ Creating resource if NOT exists
resource "docker_container" "code_server" {
  name  = "code-server-primary"
  image = docker_image.code_server.image_id
  
  # Safe to re-run — will attach to existing container if present
  restart_policy {
    condition = "unless-stopped"
  }
  
  # Explicit resource management
  lifecycle {
    prevent_destroy = false  # Allow deliberate destruction
    ignore_changes = [
      command,  # Allow container restart with new command
    ]
  }
}

# ✅ Database initialization is idempotent
resource "null_resource" "db_init" {
  provisioner "remote-exec" {
    inline = [
      "docker exec postgres_db psql -U postgres -c 'SELECT 1'",  # Check exists
      "[ $? -eq 0 ] && echo 'DB exists' || docker exec postgres_db < /schema.sql"
    ]
  }
}
```

❌ **NOT IDEMPOTENT:**
```hcl
# ❌ Creates new container every run
resource "docker_container" "code_server" {
  name  = "code-server-${timestamp()}"  # Different name each time!
  # ...
}

# ❌ Script creates files without checking
provisioner "remote-exec" {
  inline = [
    "echo 'data' > /var/lib/data.txt"  # Overwrites every time
  ]
}
```

**Implementation Checklist:**
- [ ] Resource naming is deterministic (no timestamps, random IDs)
- [ ] All state is tracked in terraform.tfstate
- [ ] No `depends_on` implicit ordering (use explicit depends_on)
- [ ] All provisioners are scripted and idempotent
- [ ] Error handling for partially-failed runs
- [ ] Rollback is tested

**Validation:**
```bash
# Run terraform multiple times — should always be plan: no changes
terraform init
terraform plan  # Should show: Plan: 0 to add, 0 to change, 0 to destroy
terraform apply
terraform plan  # Again: no changes expected
terraform apply
terraform plan  # Again: no changes expected
```

---

### Rule 4 — Secrets Management (Vault/GSM)
**All secrets MUST be stored in Vault (on-prem) or GSM (production).** Never in code.

**Vault Setup (On-Prem):**
```bash
# 1. Verify Vault is running
vault status

# 2. Store secrets
vault kv put secret/code-server \
  google_client_secret=\"GOCSPX-...\" \
  github_token=\"ghp_\" + \"...\" \
  db_password=\"...\" \
  cookie_secret=\"...\"

# 3. Verify stored
vault kv get secret/code-server
```

**GSM Setup (Production):**
```bash
# 1. Create secrets in Google Secret Manager
gcloud secrets create google-client-secret --replication-policy=automatic
echo "GOCSPX-..." | gcloud secrets versions add google-client-secret --data-file=-

# 2. Grant workload identity access
gcloud secrets add-iam-policy-binding google-client-secret \
  --member=serviceAccount:code-server@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor

# 3. Load in scripts
source scripts/fetch-gsm-secrets.sh
```

**Bootstrap Script:**
```bash
# scripts/bootstrap-vault-secrets.sh
#!/usr/bin/env bash
# Load secrets from Vault and generate .env

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat /root/.vault-token)}"

# Function to fetch secret
get_secret() {
    curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/code-server/$1" | \
        jq -r '.data.data.value'
}

# Generate .env from template
cp .env.template .env

# Populate from Vault
sed -i "s|<vault:google_secret>|$(get_secret google_client_secret)|g" .env
sed -i "s|<vault:github_token>|$(get_secret github_token)|g" .env
sed -i "s|<vault:db_password>|$(get_secret db_password)|g" .env

# Secure permissions
chmod 600 .env
```

**Usage in Scripts:**
```bash
#!/usr/bin/env bash
# All scripts must load secrets from Vault/GSM, NOT hardcode

source "$SCRIPT_DIR/../scripts/bootstrap-vault-secrets.sh"

# Secrets are now in environment
curl -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user
```

**Rotation Schedule:**
- Quarterly (every 3 months) for all credentials
- Immediately if compromised
- Document rotation in [docs/SECRETS-ROTATION-SCHEDULE.md](docs/SECRETS-ROTATION-SCHEDULE.md)

---

### Rule 5 — No Duplication (Code Consolidation)

Before writing ANY function, check these canonical locations:

**Bash/Shell:**
- `scripts/_common/init.sh` — Canonical initialization
- `scripts/_common/logging.sh` — Log functions (log_info, log_warn, log_error, log_fatal, log_debug)
- `scripts/_common/utils.sh` — Generic utilities (retry, confirm, die, etc.)
- `scripts/_common/config.sh` — Config loading
- `scripts/_common/error-handler.sh` — Error handling
- `scripts/lib/nas.sh` — NAS mount helpers
- `scripts/lib/` — Other shared libraries

**Terraform:**
- `terraform/modules/` — Reusable modules (networking, security, compute, storage)
- `terraform/variables.tf` — Centralized variables
- `terraform/network-variables.tf` — Network topology variables

**Docker:**
- `Dockerfile` — Base container
- `Dockerfile.${SERVICE}` — Service-specific additions
- `.dockerignore` — Build optimization

**Deduplication Checklist:**
- [ ] Function doesn't already exist in canonical location
- [ ] Variable isn't already in terraform/variables.tf
- [ ] Module can't be reused from terraform/modules/
- [ ] Logging uses `log_*` from logging.sh
- [ ] Scripts source init.sh (not multiple partial sources)
- [ ] Error handling uses error-handler.sh patterns

**Enforce with:**
```bash
# Search for duplicates
grep -r "function log_" scripts/ | grep -v scripts/_common/logging.sh  # ❌ Duplicate
grep -r "log_info " scripts/ | wc -l  # Check usage

# Search for hardcoded values
grep -r "192.168.168" terraform/ --include="*.tf" | grep -v "network-variables.tf"  # ❌ Duplicate
```

---

## STRUCTURAL RULES

### Rule 6 — Metadata Headers (GOV-002)
**Every new bash/python/go script requires metadata headers.**

**Bash Scripts:**
```bash
#!/usr/bin/env bash
# @file        scripts/operations/backup.sh
# @module      operations/backup
# @description Backup PostgreSQL database to NAS
# @owner       devops-team
# @status      active
#
# Usage: ./scripts/operations/backup.sh [--dry-run]
# Exit Codes: 0=success, 1=error, 2=usage
#

set -euo pipefail  # Strict mode

source "$SCRIPT_DIR/../_common/init.sh"  # Load shared libs

main() {
  log_info "Starting database backup..."
  # ...
}

main "$@"
```

**Python Scripts:**
```python
#!/usr/bin/env python3
# @file        scripts/monitoring/check_health.py
# @module      monitoring/health
# @description Check system health via API endpoints
# @owner       platform-team
# @status      active
#
"""
Health check script that validates all system components.

Usage:
    python3 check_health.py [--verbose] [--json]

Exit Codes:
    0: All systems healthy
    1: One or more components degraded
    2: Critical failure
"""

import sys
import logging

# ... rest of script ...
```

**Validation:**
```bash
# Auto-fix missing headers
./scripts/fix-metadata-headers.sh

# Check compliance
./scripts/fix-metadata-headers.sh --check --fail-on-missing
```

---

### Rule 7 — Configuration Separation
**Infrastructure config (environment-specific) vs Logic config (function-specific).**

**Infrastructure Config (Environment Variables):**
```bash
# These come from .env or terraform.tfvars
export DOMAIN="ide.kushnir.cloud"
export PRIMARY_HOST="192.168.168.31"
export POSTGRES_PASSWORD="<from-vault>"
export OLLAMA_MODELS='["llama2:70b-q4_K_M"]'
```

**Logic Config (Function Parameters/Local):**
```bash
function retry_with_backoff() {
    local max_attempts="${1:-3}"
    local timeout="${2:-10}"
    local cmd="${@:3}"
    
    # Logic uses parameters, not env vars
    for attempt in $(seq 1 "$max_attempts"); do
        if eval "$cmd"; then
            return 0
        fi
        if [ "$attempt" -lt "$max_attempts" ]; then
            sleep $((timeout * 2 ** (attempt - 1)))
        fi
    done
    return 1
}
```

**Rules:**
- ❌ No hardcoded URLs, IPs, passwords, API keys, ports
- ✅ All "tuning" values as parameters or env vars
- ✅ All secrets from Vault/GSM
- ✅ All environment-specific values from .env.template

---

### Rule 8 — Testing Requirements
**All code changes require tests. No exceptions.**

**Test Types Required:**

| Code Type | Test Type | Location | Tool | Coverage |
|-----------|-----------|----------|------|----------|
| Shell Scripts | Integration | `tests/sh/` | bats | All functions |
| Terraform | Validation | `tests/terraform/` | terraform test | All modules |
| Docker Compose | Config | `tests/docker/` | docker-compose config | All services |
| APIs | E2E | `tests/e2e/` | Playwright | All endpoints |
| Frontend | Unit+E2E | `frontend/tests/` | Jest + Playwright | 80%+ coverage |
| Backend | Unit+Integration | `backend/tests/` | pytest/jest | 80%+ coverage |

**Minimum Requirements:**
- [ ] Code compiles/lints without warnings
- [ ] New code has unit tests (if applicable)
- [ ] Integration tests passing
- [ ] E2E tests passing (for user-facing features)
- [ ] No performance regression (benchmarks)
- [ ] No security issues (secrets scan, SAST, dependency check)

**Test Execution:**
```bash
# Run all tests before commit
npm test
pytest
terraform validate
docker-compose config

# Run E2E tests (requires VPN + QA account)
npm run test:e2e -- --headed  # See browser
npm run test:e2e              # Headless

# Coverage report
npm run test:coverage
```

---

### Rule 9 — Git Workflow (Branches, Commits, PRs)

**Branch Naming Convention:**
```
{type}/{issue-number}-{description}

Types:
  feat/     — New feature
  fix/      — Bug fix
  refactor/ — Code refactoring (no behavior change)
  docs/     — Documentation only
  chore/    — Build, dependencies, tooling
  ci/       — CI/CD pipeline changes
  test/     — Adding/fixing tests

Examples:
  feat/762-iac-immutable-failclosed
  fix/691-oauth-cookie-secret
  docs/add-nas-topology-guide
```

**Commit Messages (Conventional Commits):**
```
{type}({scope}): {message}

type: feat|fix|refactor|docs|chore|ci|test|security
scope: module/component affected
message: imperative, present tense

Examples:
  feat(oauth): add MFA support for QA accounts
  fix(nas): resolve mount path hardcoding
  refactor(terraform): consolidate network variables
  docs(CONTRIBUTING): add branch cleanup policy
```

**PR Requirements:**
1. Create issue first (or use existing)
2. Create PR with `Fixes #N` in description
3. PR must pass all CI/CD checks:
   - [ ] Code lint (eslint, shellcheck, terraform fmt)
   - [ ] Tests passing (unit + integration)
   - [ ] No hardcoded secrets (git-secrets, trufflehog)
   - [ ] Security scanning (SAST, dependency check)
   - [ ] Documentation updated
   - [ ] Performance benchmarks OK
4. Require at least 1 approving review (security/ops for prod changes)
5. Merge to main
6. CI/CD auto-deploys to replica + production

**Branch Cleanup:**
```bash
# After merge to main:
git branch -d feature-branch       # Delete local
git push origin --delete feature-branch  # Delete remote

# Monthly audit
git branch -a --merged main | grep -v main | xargs -I {} git push origin --delete {}
```

---

### Rule 10 — Documentation Requirements
**All code changes require documentation.**

**Documentation Checklist:**
- [ ] README.md updated (if behavior changed)
- [ ] API documentation (if new endpoints)
- [ ] Deployment guide updated
- [ ] Configuration changes documented
- [ ] Breaking changes highlighted
- [ ] Examples provided
- [ ] Architecture diagram updated (if topology changed)

**Documentation Files:**
- [README.md](README.md) — Project overview
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to contribute
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — Deployment guide
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — System architecture
- [docs/NAS-ARCHITECTURE.md](docs/NAS-ARCHITECTURE.md) — NAS topology
- [docs/SECRETS-ROTATION-SCHEDULE.md](docs/SECRETS-ROTATION-SCHEDULE.md) — Secret rotation
- [docs/ERROR-CODES.md](docs/ERROR-CODES.md) — API error codes (to create)
- [docs/API.md](docs/API.md) — API specification (to create)

---

## ENFORCEMENT & AUTOMATION

### Pre-Commit Hooks
```bash
#!/usr/bin/env bash
# .githooks/pre-commit

set -euo pipefail

# 1. Check for secrets
if git diff --cached | grep -iE 'password|secret|token|key|credential' | grep -vE 'placeholder|example|<vault>|changeme'; then
    echo "ERROR: Possible secret detected in staged changes"
    exit 1
fi

# 2. Check for :latest tags
if git diff --cached docker-compose.yml | grep ':latest'; then
    echo "ERROR: :latest tag found (use specific versions)"
    exit 1
fi

# 3. Check metadata headers
if git diff --cached --name-only | grep -E 'scripts/.*\.(sh|py)$'; then
    ./scripts/fix-metadata-headers.sh --check --fail-on-missing
fi

# 4. Lint/format checks
npm run lint -- --staged
terraform fmt -check terraform/

echo "✅ Pre-commit checks passed"
```

**Install:**
```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

### CI/CD Checks (GitHub Actions)
```yaml
# .github/workflows/quality-gates.yml
name: Quality Gates

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run lint
      - run: terraform fmt -check
      - run: shellcheck scripts/**/*.sh

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test -- --coverage
      - run: pytest backend/tests
      - uses: codecov/codecov-action@v3

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: trufflesecurity/trufflehog@main
      - uses: aquasecurity/trivy-action@master
      - run: ./scripts/check-hardcoded-secrets.sh

  iac-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: terraform init && terraform validate
      - run: docker-compose config

  e2e-test:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - run: npm install
      - run: npm run test:e2e
      - uses: actions/upload-artifact@v3
        if: failure()
        with:
          name: test-report
          path: test-results/
```

---

## COPILOT TRIGGER PATTERNS

When you need Copilot assistance, use these patterns:

### Governance Standards
```
@copilot, apply governance standards to {file}:
  - Deduplication: check _common/ for existing functions
  - Headers: add GOV-002 metadata block
  - Config: use env vars, NOT hardcoded values
  - Secrets: load from Vault/GSM, NOT in code
  - Tests: ensure unit + integration coverage
  - Docs: update README and appropriate guides
```

### Code Review
```
@copilot, review {branch} for:
  - Hardcoded secrets or IPs
  - Configuration SSOT violations
  - Image version pinning
  - Test coverage requirements
  - Documentation completeness
  - Performance regressions
```

### Production Readiness
```
@copilot, assess production readiness:
  - Zero P0 issues remaining
  - Governance compliance 100%
  - E2E tests passing with VPN + QA account
  - Deployment pre-flight passing
  - Secret management configured
  - Disaster recovery tested
```

---

## QUICK REFERENCE

### Essential Commands

```bash
# Create new script (with template)
cp scripts/_template.sh scripts/new-script.sh

# Fix metadata headers
./scripts/fix-metadata-headers.sh

# Load Vault secrets
source scripts/bootstrap-vault-secrets.sh

# Validate all changes
npm run lint && npm test && terraform validate && docker-compose config

# Deploy to replica (safe)
ssh akushnir@192.168.168.42 "cd code-server && docker compose pull && docker compose up -d"

# Deploy to production (after replica testing)
ssh akushnir@192.168.168.31 "cd code-server && docker compose pull && docker compose up -d"

# Run E2E tests (requires VPN)
npm run test:e2e -- --headed

# Check for secrets
git diff HEAD^ | grep -iE 'password|secret|token'
```

### Configuration Matrix

| Item | Env Var | Terraform | .env | Vault |
|------|---------|-----------|------|-------|
| DOMAIN | ✅ | ✅ (SSOT) | ✅ | - |
| PRIMARY_HOST | ✅ | ✅ (SSOT) | ✅ | - |
| DATABASE_PASSWORD | - | - | - | ✅ (SSOT) |
| GOOGLE_CLIENT_SECRET | - | - | - | ✅ (SSOT) |
| GITHUB_TOKEN | - | - | - | ✅ (SSOT) |

---

## EXCEPTIONS & APPROVALS

**Exceptions to these rules require:**
1. Written justification (not just "it's faster")
2. Explicit P0 approval (security/devops lead)
3. Documented in issue
4. Time-bound (e.g., "temporary for 2 weeks")
5. Follow-up issue created for proper fix

**Exception Example:**
```
Issue #999: Temporary exception for hardcoded test password
Justification: QA testing on replica needs isolated credentials
Approval: @devops-lead
Expires: 2026-04-30
Follow-up: #1000 (implement proper test secret management)
```

---

## SUCCESS CRITERIA (Production Ready April 22, 2026)

✅ **Code Quality:**
- [ ] 0 hardcoded secrets
- [ ] 0 :latest image tags
- [ ] 0 hardcoded IPs/domains
- [ ] 100% of scripts have metadata headers
- [ ] 100% config uses env vars
- [ ] <5% code duplication
- [ ] All tests passing

✅ **Documentation:**
- [ ] README complete
- [ ] API specification present
- [ ] Deployment guide complete
- [ ] NAS topology documented
- [ ] Secret rotation schedule established
- [ ] Incident response procedures documented

✅ **Security:**
- [ ] Vault configured (on-prem)
- [ ] GSM configured (production)
- [ ] Pre-commit hooks deployed
- [ ] Secret scanning enabled
- [ ] No leaked credentials in history
- [ ] MFA enabled for critical operations

✅ **Operations:**
- [ ] E2E tests passing (with VPN + QA account)
- [ ] Failover tested
- [ ] Backup/restore tested
- [ ] Disaster recovery plan verified
- [ ] SLOs defined
- [ ] Monitoring/alerting active

---

**Last Updated:** 2026-04-19 17:00:00Z  
**Next Review:** 2026-05-17 (monthly)  
**Status:** ✅ ACTIVE - ENFORCE ON ALL NEW COMMITS  
**Exceptions:** Require P0 approval in writing

For questions or clarifications, see linked documentation or create GitHub Issue.
