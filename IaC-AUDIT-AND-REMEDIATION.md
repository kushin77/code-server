# 🔍 Infrastructure as Code Audit & Hardening Report

## Executive Summary

Your infrastructure has **PARTIAL IaC coverage with several gaps**. This report identifies what's declarative (good ✅) vs imperative (problematic ❌) and provides a remediation plan for full IaC automation with immutability and idempotency guarantees.

---

## Current State Analysis

### ✅ What IS Infrastructure as Code

| Component | Tool | Status | Idempotent? | Immutable? |
|-----------|------|--------|-------------|-----------|
| Docker services | docker-compose.yml | ✅ IaC | ✅ Yes | ⚠️ Images rebuilding |
| Container orchestration | Terraform docker provider | ✅ IaC | ✅ Yes | ⚠️ Depends on images |
| Networking | Docker networks (compose) | ✅ IaC | ✅ Yes | ✅ Yes |
| Volume management | Docker volumes (compose) | ✅ IaC | ✅ Yes | ✅ Yes |
| Configuration validation | scripts/validate.sh | ✅ IaC adjacent | ✅ Yes | ✅ Yes |
| TLS certificates | Caddy auto-renewal | ✅ IaC managed | ✅ Yes | ⚠️ Auto-rotates |
| OAuth2 config | docker-compose env vars | ✅ IaC | ✅ Yes | ⚠️ Via .env file |

### ❌ What IS NOT Infrastructure as Code

| Component | Current Approach | Problem | Risk Level |
|-----------|---------|---------|------------|
| **User allowlist** | allowed-emails.txt (file) | Manual file edits, no version control enforcement | 🟡 Medium |
| **Role settings** | config/role-settings/*.json | Manual JSON management | 🟡 Medium |
| **User workspaces** | config/user-settings/*.json | Manual creation | 🟡 Medium |
| **Secrets management** | .env file (manual) | Secrets in files, not secrets manager | 🔴 High |
| **Deployment scripts** | Bash/PowerShell imperative | Shell scripts do things instead of declaring state | 🟡 Medium |
| **DNS management** | scripts/set-godaddy-dns.sh (manual) | Manual script execution, not terraform | 🟡 Medium |
| **GitHub branch protection** | BRANCH_PROTECTION_SETUP.ps1 (manual) | Policy as script, not IaC | 🟡 Medium |
| **Audit logging setup** | Manual directory creation | No IaC enforcement | 🟡 Medium |
| **Certificate renewal** | Caddy internal | Not explicitly managed by Terraform | ⚠️ Low |

---

## Problems with Current Approach

### 1. Imperative Scripts (❌ Bad for IaC)

**Files:**
- `deploy-iac.sh` - Downloads Terraform, runs init/apply (imperative)
- `deploy-iac.ps1` - PowerShell version (imperative)
- `scripts/deploy-kushnir-cloud.sh` - Manual orchestration
- `scripts/set-godaddy-dns.sh` - Manual DNS updates
- `scripts/fetch-gsm-secrets.sh` - Manual secret retrieval

**Problem:**
```
Imperative: "Do this, then that, then check the result"
Declarative: "Here's the desired state, make it so"

Shell scripts = imperative
Terraform = declarative
```

**Impact:**
- ❌ Not idempotent (running twice can break things)
- ❌ State lives in script logic, not tracked
- ❌ Hard to audit what "should" be vs what "is"
- ❌ Manual intervention required for troubleshooting
- ❌ No state file to recover from failures

### 2. Manual Configuration Files (❌ Not Tracked Properly)

**Files:**
- `.env` - Secrets not version controlled (good for security, bad for IaC)
- `allowed-emails.txt` - User list, manually edited
- `config/role-settings/*.json` - Role definitions, manually created
- `config/user-settings/*/*.json` - Per-user settings, manually created

**Problem:**
- No single source of truth
- Can diverge from version control
- Manual changes bypass review process
- Difficult to reproduce state
- No rollback capability

### 3. Secrets Management (🔴 Security Issue)

**Current:**
- GSM fetch script writes to `.env` file
- `.env` file contains secrets in plain text (even if gitignored)
- If `.env` is compromised, all secrets are exposed

**Better approach:** Use Terraform data sources to fetch secrets at apply time, never write to files.

### 4. Missing IaC Coverage

**Things that should be IaC but aren't:**
1. User provisioning (allowed-emails.txt should be Terraform variable/resource)
2. Role definitions (should be Terraform locals or modules)
3. Audit log setup (directories should be Terraform-managed)
4. DNS records (GoDaddy should use Terraform provider)
5. GitHub branch protection (should use Terraform)
6. Security policies (should be Terraform modules)

---

## What Idempotency Means (and Current Gaps)

### ✅ Idempotent (Safe to Run 100x)
```bash
# These are safe to run multiple times:
terraform init              # Always safe
terraform apply             # Safe (won't recreate unchanged resources)
docker-compose up -d        # Safe (won't restart if already running)
```

### ❌ NOT Idempotent (Breaks on Repeat)
```bash
# These BREAK if run twice:
bash scripts/set-godaddy-dns.sh           # May set DNS twice, race conditions
bash scripts/fetch-gsm-secrets.sh         # Creates .env multiple times
bash deploy-iac.sh                        # Downloads, extracts, overwrites
```

### Problem Example:
```bash
# Run 1: Works fine
scripts/deploy-kushnir-cloud.sh
# ✅ Sets DNS, builds images, starts containers

# Run 2: BREAKS
scripts/deploy-kushnir-cloud.sh
# ❌ DNS API calls race
# ❌ Images rebuilt from scratch (slow)
# ❌ Containers may be inconsistent
# ❌ State lost between runs
```

---

## What Immutability Means (and Current Gaps)

### ✅ Immutable (Infrastructure Doesn't Drift)
```
Goal: Once deployed, infrastructure stays in known state
Problem: Infrastructure can be modified outside IaC (manual changes)
Solution: Enforce IaC as single source of truth, disallow manual changes
```

### ❌ Currently NOT Immutable
1. **Manual edits possible:** `vi allowed-emails.txt` bypasses review
2. **Container images rebuild:** No digest pinning (can change unexpectedly)
3. **Configuration untracj:** Role settings not in git with commit history
4. **No enforcement:** Nothing prevents someone from manually editing `/etc/caddy/Caddyfile`
5. **Drift possible:** State can diverge from IaC definitions

### Current Immutability Issues:

| Component | Current State | Immutability Gap | Fix |
|-----------|---------------|------------------|-----|
| Images | `image: codercom/code-server:latest` | ❌ "latest" is mutable | 📌 Pin digest: `image: codercom/code-server:4.115.0@sha256:abcd...` |
| User list | Manual file edits | ❌ No version control | 📌 Terraform tfvars + git + PR enforcement |
| Secrets | .env file | ❌ Can be edited manually | 📌 Use GCP Secret Manager data source |
| Configuration | Docker Compose + manual | ❌ Can diverge | 📌 All config in Terraform, one source of truth |
| Deployments | Shell scripts | ❌ State in script logic | 📌 Terraform manages all state |

---

## Remediation Plan

### Phase 1: Eliminate Imperative Scripts (2 hours)

**Goal:** Convert all shell scripts to Terraform or Makefile targets

**Current Imperative Scripts:**
```
deploy-iac.sh              → CONVERT to Makefile wrapper
deploy-iac.ps1             → CONVERT to Makefile wrapper  
deploy-kushnir-cloud.sh    → REPLACE with docker-compose + pre-checks
set-godaddy-dns.sh         → REPLACE with Terraform (godaddy provider)
fetch-gsm-secrets.sh       → REPLACE with Terraform data sources
```

**Action:** Create wrapper Makefile that calls Terraform (declarative), not custom scripts.

---

### Phase 2: Consolidate Configuration Source (2 hours)

**Goal:** Single source of truth for all configuration

**Current Fragmentation:**
```
main.tf (Terraform)        ← Primary
docker-compose.yml         ← Secondary
.env file                  ← Secrets (manual)
config/*.json              ← Tertiary
scripts/*.sh               ← Embedded config
Caddyfile                  ← Static config
```

**Desired State:**
```
terraform/
  ├── main.tf              ← PRIMARY: Services, networks, volumes
  ├── variables.tf         ← PRIMARY: All inputs
  ├── outputs.tf           ← PRIMARY: All outputs
  ├── locals.tf            ← PRIMARY: Computed values
  ├── secrets.tf           ← PRIMARY: GCP Secrets Manager data sources
  ├── users.tf             ← PRIMARY: User management
  ├── docker-compose.yml   ← GENERATED: From Terraform
  └── config/              ← Generated from Terraform
```

---

### Phase 3: Version Control Everything (1 hour)

**Goal:** All infrastructure state in git with review process

**Add to Git:**
```bash
terraform/
├── *.tf              ← Version controlled
├── .tfvars           ← NEVER (contains inputs)
├── terraform.tfstate ← NEVER (sensitive)
└── ...
```

**Protect with:**
- Require PR review before merge to main
- Terraform plan runs on every PR
- Only merge after plan human review

---

### Phase 4: Fix Idempotency (2 hours)

**Goal:** All operations can run 100x safely

**Audit Each Script:**
```
For each bash/ps1/python script:
1. Does it check if already done?
2. Does it create output files each time (cumulative)?
3. Does it have race conditions (concurrent runs)?
4. Does it leave partial state if interrupted?
5. Can you recover by re-running?

If any are ❌, convert to Terraform or add idempotency checks
```

**Key Fixes:**
- ✅ Terraform: Already idempotent
- ✅ docker-compose: Already idempotent  
- ❌ Scripts: Need refactoring to be idempotent

---

### Phase 5: Fix Immutability (2 hours)

**Goal:** Infrastructure matches IaC exactly, can't drift

**1. Image Pinning**
```hcl
# ❌ Current (mutable - could change daily)
resource "docker_image" "code_server" {
  name = "codercom/code-server:latest"
}

# ✅ Fixed (immutable - exact version)
resource "docker_image" "code_server" {
  name = "codercom/code-server:4.115.0@sha256:abc123..."
}
```

**2. Configuration Management**
```hcl
# ❌ Current (manual file edits)
resource "local_file" "allowed_emails" {
  filename = "allowed-emails.txt"
  # ← user manually
 edits this
}

# ✅ Fixed (Terraform-managed)
resource "local_file" "allowed_emails" {
  filename = "allowed-emails.txt"
  content = jsonencode(var.allowed_users)  # ← From tfvars/Terraform
}
```

**3. No Manual Changes**
```hcl
# ✅ Add to all file resources:
resource "local_file" "config" {
  filename             = "config.json"
  content              = jsonencode(local.config)
  file_permission      = "0644"
  directory_permission = "0755"
  
  # Prevent drift - warn if file edited outside Terraform
  lifecycle {
    ignore_changes = []  # Don't ignore - detect drift
  }
}
```

---

## Recommended IaC Architecture

### New Structure:

```
code-server-enterprise/
├── terraform/                          # ← ALL IaC HERE
│   ├── main.tf                        # Core configuration
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   ├── locals.tf                      # Computed values
│   ├── docker.tf                      # Docker resources
│   ├── secrets.tf                     # GCP Secrets Manager
│   ├── users.tf                       # User management
│   ├── dns.tf                         # GoDaddy DNS (TBD)
│   ├── github.tf                      # GitHub branch protection (TBD)
│   ├── versions.tf                    # Provider versions
│   ├── terraform.tfvars.example       # Example values
│   ├── modules/
│   │   ├── code-server/               # Code-server module
│   │   ├── oauth2/                    # OAuth2 proxy module
│   │   └── caddy/                     # Caddy reverse proxy module
│   └── environments/
│       ├── dev.tfvars                 # Dev values
│       ├── staging.tfvars             # Staging values
│       └── prod.tfvars                # Prod values
│
├── docker-compose.yml                 # Generated from Terraform
├── Dockerfile*                        # DO NOT CHANGE MANUALLY
├── Caddyfile                         # Generated from Terraform
├── config/                           # Generated from Terraform
├── scripts/                          # Helpers only (no core logic)
│   ├── validate.sh                   # KEEP: Pre-commit checks
│   ├── pre-commit.sh                 # KEEP: Git hooks
│   └── [deployments moved to Terraform]
│
├── Makefile                          # ← Simplified: just calls terraform
├── .gitignore                        # ← Updated
├── .github/workflows/
│   ├── iac-validate.yml              # ← NEW: PR checks
│   ├── iac-plan.yml                  # ← NEW: Plan on PR
│   └── iac-deploy.yml                # ← NEW: Apply on merge
└── docs/
    ├── IaC-ARCHITECTURE.md           # ← NEW
    ├── IaC-IDEMPOTENCY.md            # ← NEW
    ├── IaC-IMMUTABILITY.md           # ← NEW
    └── [existing docs]
```

---

## Specific Code Issues & Fixes

### Issue 1: Mutable Image Tags

**File:** `docker-compose.yml`

**Current (BAD):**
```yaml
code-server:
  image: codercom/code-server:latest  # ❌ Mutable - can change daily
  
caddy:
  image: caddy:latest                 # ❌ Mutable
  
oauth2-proxy:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1  # ✅ Mostly good (but no digest)
```

**Fixed (GOOD):**
```yaml
code-server:
  image: codercom/code-server:4.115.0@sha256:abcd1234...  # ✅ Immutable + digest

caddy:
  image: caddy:latest@sha256:def5678...  # ✅ Better (but should pin major.minor)

oauth2-proxy:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1@sha256:ghi9012...  # ✅ Full version + digest
```

**Implementation:**
```bash
# Find digest for image:
docker pull codercom/code-server:4.115.0
docker inspect codercom/code-server:4.115.0 | grep -i digest

# Update docker-compose.yml with digest
docker-compose up -d  # Now uses exact image, won't auto-upgrade
```

---

### Issue 2: Manual Secret Management

**File:** `.env` (currently created by fetch-gsm-secrets.sh)

**Current (BAD - Secrets in Files):**
```bash
# scripts/fetch-gsm-secrets.sh
gcloud secrets versions access latest --secret="google-client-id" > .env  # ❌ Writes secrets to file
export GOOGLE_CLIENT_ID=$(cat .env | ...)                                 # ❌ In plaintext
```

**Fixed (GOOD - Secrets Manager):**
```hcl
# terraform/secrets.tf
data "google_secret_manager_secret_version" "google_client_id" {
  secret = "google-client-id"
  version = "latest"
}

# Use in docker-compose generation
resource "local_file" "env_file" {
  sensitive_content = <<-EOT
GOOGLE_CLIENT_ID=${data.google_secret_manager_secret_version.google_client_id.secret_data}
GOOGLE_CLIENT_SECRET=${data.google_secret_manager_secret_version.google_client_secret.secret_data}
  EOT
  filename = ".env"
  
  # .env not in git (it's generated)
}
```

**.gitignore adjustment:**
```bash
# ✅ Keep these out of git:
.env
.env.local
terraform.tfstate
terraform.tfstate.*
tfplan*

# ✅ Put these IN git:
terraform/
Makefile
.github/workflows/
```

---

### Issue 3: Manual User Management

**Files:** `allowed-emails.txt`, `config/user-settings/`, `config/role-settings/`

**Current (BAD - Manual Files):**
```bash
# ❌ Users edited by: vi allowed-emails.txt
# ❌ No version control
# ❌ No review process
# ❌ Can't rollback

./scripts/manage-users.sh add-user "email@company.com" "developer"
# → Creates files manually
```

**Fixed (GOOD - IaC-Managed):**
```hcl
# terraform/users.tf
variable "allowed_users" {
  description = "Allowlist of users"
  type = map(object({
    email    = string
    role     = string
    disabled = bool
  }))

  default = {
    user1 = {
      email    = "alice@company.com"
      role     = "developer"
      disabled = false
    }
    user2 = {
      email    = "bob@company.com"
      role     = "viewer"
      disabled = false
    }
  }
}

# Generate allowed-emails.txt from Terraform
resource "local_file" "allowed_emails" {
  filename = "allowed-emails.txt"
  content = join("\n", [
    for user in var.allowed_users : user.email
    if !user.disabled
  ])
}

# Generate per-user settings from Terraform
resource "local_file" "user_settings" {
  for_each = var.allowed_users

  filename = "config/user-settings/${each.key}/user-metadata.json"
  content = jsonencode({
    email    = each.value.email
    role     = each.value.role
    created  = filesha256("...")
  })
}
```

**Usage:**
```bash
# Edit: terraform/environments/prod.tfvars
allowed_users = {
  alice = {
    email    = "alice@company.com"
    role     = "developer"
    disabled = false
  }
  new_user = {
    email    = "newuser@company.com"
    role     = "viewer"
    disabled = false
  }
}

# Deploy:
terraform apply -var-file="environments/prod.tfvars"
# ✅ Generates all files from single source
# ✅ Can rollback with git revert
# ✅ PR review before applying
```

---

### Issue 4: Deployment Scripts Are Imperative

**Files:** `deploy-iac.sh`, `deploy-iac.ps1`

**Current (BAD):**
```bash
#!/bin/bash
# ❌ Imperative: step 1, 2, 3...
check_prerequisites()       # Do this
install_terraform()         # Then this
init_terraform()           # Then this
plan_deployment()          # Then this
apply_deployment()         # Then this
```

**Fixed (GOOD - Declarative):**
```makefile
# Makefile
.PHONY: deploy plan destroy

deploy: validate plan
	terraform apply tfplan
	docker compose restart oauth2-proxy

plan: validate
	terraform plan -out=tfplan

destroy: 
	terraform destroy -auto-approve

validate:
	terraform validate
	terraform fmt -check -recursive

# ✅ Idempotent (can run 100x)
# ✅ Declarative (targets = state goals)
# ✅ Follows terraform patterns
```

**Usage:**
```bash
make plan    # Show what will change
make deploy  # Apply changes (safe, declarative)
make destroy # Remove everything

# No need for custom scripts!
```

---

## GitHub Actions CI/CD for IaC

**Create:** `.github/workflows/iac-validate.yml`

```yaml
name: IaC Validation

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/iac-*.yml'
  push:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Initialize Terraform
        run: terraform -chdir=terraform init -backend=false
      
      - name: Format Check
        run: terraform -chdir=terraform fmt -check -recursive
      
      - name: Validate
        run: terraform -chdir=terraform validate
      
      - name: Plan (PR only)
        if: github.event_name == 'pull_request'
        run: terraform -chdir=terraform plan -out=tfplan
      
      - name: Upload Plan
        if: github.event_name == 'pull_request'
        uses: actions/upload-artifact@v3
        with:
          name: tfplan
          path: terraform/tfplan
```

**Create:** `.github/workflows/iac-deploy.yml`

```yaml
name: IaC Deploy

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.6.0
      
      - name: Initialize
        run: terraform -chdir=terraform init
      
      - name: Validate
        run: terraform -chdir=terraform validate
      
      - name: Plan
        run: terraform -chdir=terraform plan
      
      - name: Apply
        run: terraform -chdir=terraform apply -auto-approve
```

---

## Idempotency Verification Checklist

### ✅ Test Each Component:

```bash
# 1. Terraform idempotency
terraform plan
terraform apply -auto-approve
terraform plan  # Should show "No changes"

# 2. Docker Compose idempotency
docker compose up -d
docker compose up -d  # Should show "already running"

# 3. File generation idempotency
terraform apply -auto-approve
terraform apply -auto-approve  # Should show "No changes"

# 4. User provisioning idempotency
terraform apply -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars  # Should be unchanged
```

---

## Immutability Verification Checklist

### ✅ Verify No Drift:

```bash
# 1. Check state matches reality
terraform plan  # Should show "No changes"

# 2. Verify image digests
docker inspect code-server | grep -i digest
# Should show: sha256:abc123...@sha256:def456...

# 3. Verify config files

 are generated
git status | grep "config/"
# Should show these are NOT in git (generated from .tf)

# 4. Verify no manual edits possible
vi allowed-emails.txt  # Edit and save
terraform plan         # Should detect change
terraform apply        # Should revert to IaC version
```

---

## Implementation Roadmap

| Phase | Time | Deliverable | Priority |
|-------|------|-------------|----------|
| Phase 1 | 2h | Convert scripts to Makefile | 🔴 Critical |
| Phase 2 | 2h | Consolidate config in Terraform | 🔴 Critical |
| Phase 3 | 1h | Git + review process | 🔴 Critical |
| Phase 4 | 2h | Fix all idempotency issues | 🟠 High |
| Phase 5 | 2h | Pin image digests, enable immutability | 🟠 High |
| Phase 6 | 2h | GitHub Actions CI/CD for IaC | 🟠 High |
| Phase 7 | 1h | Documentation + team training | 🟡 Medium |

**Total: ~12 hours**

---

## Success Criteria

- [ ] All infrastructure defined in Terraform (no manual steps)
- [ ] All operations idempotent (can run 100x safely)
- [ ] All config in git with PR review
- [ ] No mutable image tags (all digests pinned)
- [ ] Secrets in GCP Secrets Manager (not .env)
- [ ] CI/CD validates every PR  
- [ ] No drift: `terraform plan` always shows "No changes"
- [ ] Team training complete: everyone knows IaC process

---

**Status:** Architecture Review Complete  
**Recommendation:** Proceed with Phase 1-3 immediately (5 hours)  
**Risk if Deferred:** Configuration drift, deployment failures, reduced auditability
