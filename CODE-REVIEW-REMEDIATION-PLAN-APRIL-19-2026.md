# Code Review & Governance Remediation Plan
**Date:** April 19, 2026  
**Scope:** Comprehensive code review covering duplicates, IaC immutability, environment variables, secrets, monorepo structure, documentation, and branch management  
**Status:** Action plan created — ready for implementation

---

## Overview: 10 P0/P1 Issues + Branch Sprawl

| Category | Count | Issues | Priority |
|----------|-------|--------|----------|
| **Security & Hardcoding** | 3 | Hardcoded domains, IPs, secrets | 🔴 P0 |
| **IaC Immutability** | 2 | Floating image tags, version inconsistency | 🔴 P0 |
| **Deduplication & Migration** | 5 | Deprecated libs, missing headers, non-standard init | 🟠 P1 |
| **Documentation** | 8 | Missing docstrings, GOV-002 headers, monorepo structure | 🟡 P2 |
| **Branch Sprawl** | 1 | 137 branches, 13 merged but not deleted | 🔴 P0 |
| **Tech Debt** | 6 | Legacy patterns, TODOs, stale configs | 🟢 P3 |

**Total Issues:** 25  
**Effort Estimate:** 48 hours (6 business days)  
**Critical Path (P0 only):** 6 hours

---

## CRITICAL P0 ISSUES (Blocking)

### P0.1: Hardcoded Domains Prevent Multi-Environment Deployment 🔴

**Files Affected:**
- [docker-compose.yml](docker-compose.yml#L175,L250)
- [terraform/variables.tf](terraform/variables.tf#L24)
- [.env.template](.env.template#L2-L3)

**Current State:**
```yaml
# ❌ WRONG: Hardcoded domains scattered across configs
OAUTH2_PROXY_REDIRECT_URL: "https://ide.kushnir.cloud/oauth2/callback"
OAUTH2_PROXY_COOKIE_DOMAINS: "ide.kushnir.cloud,.ide.kushnir.cloud"
DOMAIN: "kushnir.cloud"
ACME_EMAIL: "ops@kushnir.cloud"
```

**Remediation:**
```yaml
# ✅ CORRECT: All domains parameterized via environment
OAUTH2_PROXY_REDIRECT_URL: "https://${IDE_DOMAIN}/oauth2/callback"
OAUTH2_PROXY_COOKIE_DOMAINS: "${IDE_DOMAIN},${COOKIE_DOMAIN}"
DOMAIN: "${DOMAIN:-kushnir.cloud}"
ACME_EMAIL: "${ACME_EMAIL:-ops@kushnir.cloud}"

# Variables with defaults in .env.template:
DOMAIN=kushnir.cloud
IDE_DOMAIN=ide.kushnir.cloud
COOKIE_DOMAIN=.kushnir.cloud
ACME_EMAIL=ops@kushnir.cloud
```

**Implementation:** Update docker-compose.yml, docker-compose.tpl, .env.template  
**Effort:** 1.5 hours | **Impact:** P0-blocking

---

### P0.2: Hardcoded IP Addresses Break Network Topology Changes 🔴

**Files Affected:**
- [terraform/main.tf](terraform/main.tf#L87,L394,L401,L417,L422,L429)
- [terraform/variables.tf](terraform/variables.tf#L175)
- [terraform/module-variables.tf](terraform/module-variables.tf#L59,L65)

**Current State:**
```hcl
# ❌ WRONG: IPs hardcoded in terraform code
nas_host = "192.168.168.56"
primary_host = "192.168.168.31"
replica_host = "192.168.168.42"
vip_host = "192.168.168.30"
```

**Remediation:** Create `terraform/network-variables.tf` with all network parameters:
```hcl
# ✅ CORRECT: All IPs as variables
variable "vip_host" {
  description = "Virtual IP for failover"
  default = "192.168.168.30"
  type = string
}

variable "primary_host" {
  description = "Primary deployment host (production)"
  default = "192.168.168.31"
  type = string
}

variable "replica_host" {
  description = "Replica/failover host (standby)"
  default = "192.168.168.42"
  type = string
}

variable "nas_host" {
  description = "NAS primary IP (backup: 192.168.168.50)"
  default = "192.168.168.56"
  type = string
}

# Usage in main.tf:
nas_host = var.nas_host
primary_host = var.primary_host
```

**Implementation:** Extract all IPs to variables.tf with clear documentation  
**Effort:** 2 hours | **Impact:** P0-blocking

---

### P0.3: Floating Image Tags (`:latest`) Break Reproducibility 🔴

**Files Affected:**
- [terraform/192.168.168.31/variables.tf](terraform/192.168.168.31/variables.tf#L216)
- [docker-compose.tpl](docker-compose.tpl#L81,L121)

**Current State:**
```hcl
# ❌ WRONG: :latest models float (non-deterministic)
ollama_models = ["llama2:70b-chat", "codegemma:latest", "mistral:latest"]
```

**Remediation:**
```hcl
# ✅ CORRECT: Pin specific model versions
variable "ollama_models" {
  description = "Ollama models to pull (pinned for reproducibility)"
  default = [
    "llama2:70b-chat-q4_K_M",      # Quantized version for performance
    "codegemma:7b-instruct-q4_K_M",
    "mistral:7b-instruct-q4_K_M"
  ]
}
```

**Implementation:** Update variables.tf and document model selection process  
**Effort:** 1 hour | **Impact:** P0-blocking

---

### P0.4: Vault Token Hardcoded in Terraform (Security Breach Risk) 🔴

**Files Affected:**
- [terraform/modules/security/main.tf](terraform/modules/security/main.tf#L56)

**Current State:**
```hcl
# ❌ CRITICAL: Hardcoded secret token!
vault_token = "dev-root-token"
vault_url = "http://vault:8200"
```

**Remediation:**
```hcl
# ✅ CORRECT: Load from environment or GSM
variable "vault_token" {
  description = "Vault authentication token (load from GSM in prod)"
  type = string
  sensitive = true
  default = ""  # Require explicit override
}

# In terraform: --var="vault_token=$VAULT_TOKEN" (from environment)
# Or use: TF_VAR_vault_token from GSM
```

**Implementation:** Remove hardcoded token; document GSM bootstrap process  
**Effort:** 1 hour | **Impact:** P0-blocking (security)

---

### P0.5: Branch Sprawl: 137 Branches (13 Merged, Unpruned) 🔴

**Current State:**
- **Total branches:** 137 (local + remote)
- **Merged, unpruned:** 13
- **Stale (>30 days):** ~40+ estimated

**Sample Stale Branches:**
```
feat/332-session-schema-versioning         (merged/old)
feat/334-broadcast-multitab-sync           (merged/old)
feat/357-opa-conftest-baseline             (active in feat/376)
feat/381-phase-4-sla-gate                  (replaced by feat/618)
deploy/tier2-3-infrastructure-hardening    (Phase 14 complete)
docs/failover-runbook                      (merged, unpruned)
feature/comprehensive-p1-p2-execution-april-16   (old)
feature/final-session-completion-april-22       (old)
```

**Remediation Plan:**

**Step 1: Clean Merged Branches Locally**
```bash
# Delete 13 merged local branches
git branch --merged main | grep -v "main\|develop" | xargs -I {} git branch -d {}

# Verify cleanup
git branch | wc -l  # Should reduce from ~70 to ~57
```

**Step 2: Delete Stale Remote Branches**
```bash
# Delete obviously old/obsolete:
git push origin --delete feat/332-session-schema-versioning
git push origin --delete feat/334-broadcast-multitab-sync
git push origin --delete deploy/tier2-3-infrastructure-hardening
git push origin --delete docs/failover-runbook
git push origin --delete feature/comprehensive-p1-p2-execution-april-16
git push origin --delete feature/final-session-completion-april-22
git push origin --delete feature/gov-002-metadata-headers
# ... (~15 total to delete)
```

**Step 3: Establish Branch Policy**
```
✅ KEEP:
  - main, develop (permanent)
  - feat/376-root-zero-sprawl-guardrails (active governance)
  - feat/618-enterprise-policy-pack (in progress)
  - feature/p1-388-* (active implementation)
  - feature/p2-* (planned sprints)

❌ DELETE:
  - Phase-complete branches (deploy/tier2-3, feat/phase-*, feat/readiness-*)
  - >30-day-old branches without PRs
  - Branches merged to main (automatic after PR merge)
```

**Implementation:** Execute cleanup; document policy in CONTRIBUTING.md  
**Effort:** 0.5 hours execution + 1 hour policy documentation | **Impact:** P0-blocking (DevOps)

---

## P1 HIGH PRIORITY ISSUES (Within Sprint)

### P1.1: Scripts Missing GOV-002 Metadata Headers 🟠

**Affected Scripts:** ~15 files without proper headers
- scripts/ci/validate-epic-ac-overlap.sh
- scripts/ci/validate-governance-issue-ac-text-overlap.sh
- scripts/governance/export-policy-decision-log.sh
- scripts/governance/generate-waiver-inventory.sh
- scripts/setup-cloudflare-access.sh
- ... (10 more)

**Fix:** Run `scripts/fix-metadata-headers.sh`  
**Effort:** 0.25 hours | **Impact:** Governance compliance

---

### P1.2: Scripts Not Using Canonical `init.sh` Entry Point 🟠

**Affected Scripts:** ~8 scripts source individual modules instead of unified init.sh
```bash
# ❌ WRONG: Inline sourcing (duplicates init.sh logic)
source "$SCRIPT_DIR/_common/config.sh"
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/utils.sh"

# ✅ CORRECT: Single canonical entry point
source "$SCRIPT_DIR/_common/init.sh"
```

**Fix:** Add init.sh sourcing to: setup-cloudflare-access.sh, generate-waiver-inventory.sh, export-policy-decision-log.sh  
**Effort:** 2 hours | **Impact:** Deduplication, maintainability

---

### P1.3: Deprecated `common-functions.sh` Still Exists 🟠

**File:** scripts/common-functions.sh (deprecated in Rule 6)

**Status:** Marked for deletion; verify no active sourcing  
**Fix:** Grep for sourcing; migrate to _common/, delete file  
**Effort:** 1 hour | **Impact:** Code cleanup

---

### P1.4: Hardcoded Email Addresses in Docker-Compose 🟠

**Files:** docker-compose.yml, docker-compose.yml.remote

**Current:**
```yaml
OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE: "/etc/oauth2-proxy/allowed-emails.txt"
# File path hardcoded; should be variable
```

**Fix:** Add `OAUTH_EMAILS_FILE` variable; use in config  
**Effort:** 0.5 hours | **Impact:** Env var consistency

---

### P1.5: Terraform Validation Gaps (Password Policies) 🟠

**Issue:** No validation of PostgreSQL password requirements in terraform

**Fix:** Add password validation:
```hcl
variable "postgres_password" {
  validation {
    condition = length(var.postgres_password) >= 16 && can(regex("[A-Z]", var.postgres_password))
    error_message = "PostgreSQL password must be ≥16 chars with uppercase"
  }
}
```

**Effort:** 1.5 hours | **Impact:** Security policy enforcement

---

## P2 MEDIUM PRIORITY (Documentation & Structure)

### P2.1: pnpm Monorepo Structure Undocumented 🟡

**Issue:** pnpm-workspace.yaml exists, but no MONOREPO.md explaining workspace structure

**Files:** pnpm-workspace.yaml, package.json (root)

**Deliverable:** Create [MONOREPO.md](docs/MONOREPO.md) with:
- Workspace topology (apps/, packages/, services/)
- Package isolation rules
- Dependency management (pnpm freeze, lock)
- Build order and script execution
- Cross-package import rules (no hardcoded paths)

**Effort:** 3 hours | **Impact:** Onboarding, governance

---

### P2.2: Code Documentation Missing in TypeScript Services 🟡

**Issue:** New opa-policy-service lacks JSDoc comments

**Files:** src/services/opa-policy-service/*.ts

**Fix:** Add JSDoc for all exported functions:
```typescript
/**
 * Load and parse OPA policy bundle catalog
 * @param catalogPath - Path to bundle-catalog.json
 * @returns {Promise<PolicyCatalog>} Loaded catalog with version info
 * @throws {Error} If catalog is invalid or file not found
 */
export async function LoadCatalog(catalogPath: string): Promise<PolicyCatalog>
```

**Effort:** 2 hours | **Impact:** Developer experience, IDE support

---

### P2.3: NAS Volume Configuration Undocumented 🟡

**Issue:** docker-compose.tpl uses NAS volumes but no explanation of mount topology

**Fix:** Add comments to docker-compose.tpl:
```yaml
volumes:
  # NAS-backed volumes (shared between .31 and .42 via NFS v4)
  # Mount point: /mnt/nas/code-server/profile on docker host
  # Fail-over: If .31 down, .42 can mount same path
  data-volume:
    driver: local
    driver_opts:
      type: nfs
      device: ":${nas_export_path}/code-server/profile"
```

**Effort:** 1 hour | **Impact:** Operations runbook

---

## Effort Summary & Timeline

| Phase | Duration | Tasks | Priority |
|-------|----------|-------|----------|
| **Phase 1: Security & IaC** | 6 hours | P0.1-P0.5 hardcoding, branch cleanup | 🔴 P0 |
| **Phase 2: Migration Debt** | 8 hours | P1.1-P1.5 deduplication, headers, validation | 🟠 P1 |
| **Phase 3: Documentation** | 10 hours | P2.1-P2.3 docstrings, monorepo guide | 🟡 P2 |
| **Phase 4: Tech Debt** | 6 hours | P3 stale configs, legacy patterns | 🟢 P3 |
| **TOTAL** | 30 hours | All issues | - |

**Recommended Sequence:**
1. Week 1 (Mon-Tue): Phase 1 (P0) — 6 hours
2. Week 1 (Wed-Thu): Phase 2 (P1) — 8 hours
3. Week 2: Phase 3 (P2) + Phase 4 (P3) — 16 hours

---

## Success Criteria

✅ All P0 issues resolved before deploying Phase 15 infrastructure  
✅ No hardcoded domains, IPs, or secrets in version control  
✅ All scripts have GOV-002 headers and use canonical init.sh  
✅ Git branch count < 50 (down from 137)  
✅ All new code has JSDoc/docstrings  
✅ Terraform validation enforces security policies  
✅ NAS and monorepo patterns documented  

---

## Next Actions

**Immediate (Today):**
1. Execute branch cleanup (30 min)
2. Create variables for hardcoded domains & IPs (2 hours)
3. Fix Vault token hardcoding (1 hour)

**This Week:**
4. Pin Ollama model versions (1 hour)
5. Run metadata header fixer (0.25 hours)
6. Add init.sh to remaining scripts (2 hours)

**Next Week:**
7. Create MONOREPO.md (3 hours)
8. Add JSDoc to opa-policy-service (2 hours)
9. Document NAS topology (1 hour)

---

**Report Generated:** 2026-04-19  
**Review Status:** ✅ Ready for implementation  
**Approval Gate:** Address all P0 issues before next commit to main
