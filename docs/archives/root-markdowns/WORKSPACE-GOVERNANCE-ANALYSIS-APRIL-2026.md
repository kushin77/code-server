# Workspace Governance Analysis — code-server-enterprise
**Date:** April 19, 2026  
**Scope:** Duplicated code, stale code, IaC issues, environment variables, documentation, monorepo structure, secrets, NAS usage  
**Status:** Comprehensive audit complete — P0/P1/P2/P3 findings documented

---

## Executive Summary

The code-server-enterprise workspace is **Phase 14 operationally mature** with strong governance patterns emerging. However, **10 P0/P1 issues** require immediate attention before Phase 15+ development.

| Priority | Count | Category | Risk Level |
|----------|-------|----------|-----------|
| **P0** 🔴 | 5 | Security, Hardcoding, Credentials | Critical |
| **P1** 🟠 | 5 | Deduplication, Migration Debt | High |
| **P2** 🟡 | 8 | Documentation, Headers | Medium |
| **P3** 🟢 | 6 | Tech Debt, Structure | Low |

---

## P0 CRITICAL FINDINGS 🔴

### 1. **Hardcoded Domain Names in Production Configs**

**Risk:** Domain changes require manual updates across multiple files; breaks env separation

**Location & Details:**
```yaml
# docker-compose.yml (line 175, 187-188, 222, 240-250, 262-263, 360)
OAUTH2_PROXY_REDIRECT_URL: https://ide.kushnir.cloud/oauth2/callback   # ❌ HARDCODED
OAUTH2_PROXY_COOKIE_DOMAINS: ide.kushnir.cloud,.ide.kushnir.cloud      # ❌ HARDCODED
DOMAIN: kushnir.cloud                                                     # ❌ HARDCODED
ACME_EMAIL: ops@kushnir.cloud                                           # ❌ HARDCODED

# terraform/variables.tf (line 24)
default = "ide.kushnir.cloud"                                           # ❌ HARDCODED DEFAULT

# Dockerfile.caddy (implicit via config templates)
# docker-compose.yml oauth2-proxy-portal service (line 250)
OAUTH2_PROXY_REDIRECT_URL: "https://kushnir.cloud/oauth2/callback"    # ❌ HARDCODED
```

**Impact:**
- Cannot deploy to different domains without code changes
- Test/staging deploys must use same domain or modify configs
- Production and dev environments mixed in version control

**Remediation:**
```bash
# ✅ CORRECT: Use environment variables for ALL domains
# docker-compose.yml
OAUTH2_PROXY_REDIRECT_URL: "${OAUTH2_PROXY_IDE_REDIRECT_URL:-https://ide.${DOMAIN}/oauth2/callback}"
OAUTH2_PROXY_COOKIE_DOMAINS: "ide.${DOMAIN},.ide.${DOMAIN}"
DOMAIN: "${DOMAIN:-kushnir.cloud}"

# terraform/variables.tf
default = "ide.${var.domain}"  # or explicitly: var.ide_domain
```

**Files Affected:** 
- [docker-compose.yml](docker-compose.yml#L175)
- [docker-compose.yml](docker-compose.yml#L250)
- [terraform/variables.tf](terraform/variables.tf#L24)
- [.env.template](.env.template#L2-L3)

**Effort:** 2 hours | **Priority:** P0

---

### 2. **Hardcoded IP Addresses in Infrastructure Code**

**Risk:** Failover and network changes require code modifications; breaks immutability

**Location & Details:**
```bash
# terraform/main.tf (line 87, 394, 401, 417, 422, 429)
nas_host = "192.168.168.56"              # ❌ HARDCODED NAS IP
# Comment: VIP 192.168.168.30 floats between primary (.31) and replica (.42).

# terraform/192.168.168.31/variables.tf (line 10)
default = "192.168.168.31"               # ❌ HARDCODED as DEFAULT

# terraform/module-variables.tf (line 59, 65)
default = "192.168.168.31"               # Primary
default = "192.168.168.42"               # Replica

# terraform/main.tf failover config (line 417, 422, 429)
ip = "192.168.168.30"  # VIP
ip = "192.168.168.31"  # Primary
ip = "192.168.168.42"  # Replica

# terraform/192.168.168.31/outputs.tf (line 166-167)
"192.168.168.31:9100 (node-exporter metrics)"
"192.168.168.31:8080/metrics (code-server if exposed)"
```

**Impact:**
- Cannot change network topology without terraform code changes
- Adds/removes hosts require code PR instead of variables
- Network reconfiguration risk (typographical errors in code)

**Remediation:**
```hcl
# ✅ CORRECT: All IPs as variables with well-documented defaults
variable "vip_host" {
  description = "Virtual IP for failover (floats between primary/.31 and replica/.42)"
  default = "192.168.168.30"
}

variable "nas_host" {
  description = "NAS primary IP address (backup at var.nas_host_backup)"
  default = "192.168.168.56"
}

variable "primary_host" {
  description = "Primary deployment host (192.168.168.31)"
  default = "192.168.168.31"
}

# Use consistently:
nas_host = var.nas_host
```

**Files Affected:**
- [terraform/main.tf](terraform/main.tf#L87)
- [terraform/variables.tf](terraform/variables.tf#L175)
- [terraform/module-variables.tf](terraform/module-variables.tf#L59-L65)
- [terraform/192.168.168.31/variables.tf](terraform/192.168.168.31/variables.tf#L10)

**Effort:** 3 hours | **Priority:** P0

---

### 3. **Floating/Latest Image Tags in Production (Ollama, Mistral)**

**Risk:** Non-reproducible builds; Ollama pulls `:latest` models on every deploy

**Location & Details:**
```hcl
# terraform/192.168.168.31/variables.tf (line 216)
default = ["llama2:70b-chat", "codegemma:latest", "mistral:latest"]  # ❌ :latest IS FLOATING

# docker-compose.tpl (line 81, 121)
image: ollama/ollama:${ollama_version}   # ✅ Version pinned (good!)

# But Ollama models themselves use :latest
# This means each container start may pull different model code
```

**Impact:**
- Ollama containers pull different model versions on restart
- `codegemma:latest` and `mistral:latest` are not guaranteed to be same as last deploy
- Cannot guarantee reproducible AI responses or behavior
- Model changes can silently break workflows

**Remediation:**
```bash
# ✅ CORRECT: Pin ALL Ollama model versions
default = [
  "llama2:70b-chat-q4_K_M",     # Pinned quantization
  "codegemma:7b",               # Pinned version
  "mistral:7b-instruct-q4_K_M"  # Pinned with quantization
]

# In docker-compose.tpl:
ollama pull llama2:70b-chat-q4_K_M   # Not :latest
```

**Files Affected:**
- [terraform/192.168.168.31/variables.tf#L216](terraform/192.168.168.31/variables.tf#L216)
- [docker-compose.tpl](docker-compose.tpl#L81)

**Effort:** 1 hour | **Priority:** P0

---

### 4. **Hardcoded Secrets & Defaults in Code (oauth2-proxy, Postgres, Kong)**

**Risk:** Secret material may be exposed in git history or terraform plans

**Location & Details:**
```hcl
# terraform/modules/security/main.tf (line 271-272)
name  = "VAULT_DEV_ROOT_TOKEN_ID"
value = "dev-root-token"              # ❌ HARDCODED DEV TOKEN (even if marked :dev, unacceptable)

# terraform/modules/networking/main.tf (line 50-51)
name  = "KONG_PG_PASSWORD"
value = var.kong_database_password   # ✅ Variable (good), but var check needed

# terraform/modules/monitoring/main.tf (line 137)
name  = "GF_SECURITY_ADMIN_PASSWORD"
value = var.grafana_admin_password   # ✅ Variable (good)

# docker-compose.yml (line 315)
DATABASE_URL=postgres://${POSTGRES_USER:-codeserver}:${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}
# ✅ Properly enforced with ?:must set

# docker-compose.yml (line 37-47)
PASSWORD: ${CODE_SERVER_PASSWORD:?CODE_SERVER_PASSWORD must be set}  # ✅ Good
GSM_SECRET_NAME: ${GSM_SECRET_NAME:-github-token}                   # ✅ Good (has fallback)
```

**Issues:**
1. **Vault token in code** (albeit marked `:dev`) is unacceptable — use Vault API or variable
2. **Postgres password validation** is ENV-dependent; terraform doesn't validate `var.postgres_password` length/strength
3. **Variable defaults in terraform** don't have validation on:
   - `code_server_password` length ✅ has validation
   - `kong_database_password` ❌ no validation
   - `grafana_admin_password` ❌ no validation

**Remediation:**
```hcl
# ✅ CORRECT: Remove hardcoded secrets, add validation
variable "vault_dev_root_token" {
  description = "Vault dev root token — fetch from Vault API or GSM, never hardcode"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.vault_dev_root_token) > 20
    error_message = "Vault tokens must be fetched from Vault, not hardcoded"
  }
}

variable "postgres_password" {
  description = "PostgreSQL password (from .env or GSM)"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.postgres_password) >= 12
    error_message = "postgres_password must be at least 12 characters"
  }
}

# Never expose in terraform output:
# ✅ DO: Mask in outputs
output "postgres_connection" {
  value     = "postgres://${var.postgres_user}:***@postgres:5432/${var.postgres_db}"
  sensitive = true
}

# ❌ DON'T: Expose password
output "postgres_url" {
  value = "postgres://${var.postgres_user}:${var.postgres_password}@postgres:5432"  # WRONG
}
```

**Files Affected:**
- [terraform/modules/security/main.tf#L271](terraform/modules/security/main.tf#L271)
- [terraform/modules/networking/main.tf#L50](terraform/modules/networking/main.tf#L50)
- [terraform/modules/monitoring/main.tf#L137](terraform/modules/monitoring/main.tf#L137)
- [terraform/variables.tf](terraform/variables.tf#L10-L70)

**Effort:** 4 hours | **Priority:** P0

---

### 5. **Image Version Handling Inconsistency (Some Pinned, Some Floating)**

**Risk:** Mixed immutability levels make version tracking fragile

**Location & Details:**
```dockerfile
# Dockerfile.code-server (GOOD - pinned)
ARG CODE_SERVER_VERSION=4.115.0
ARG GCLOUD_SDK_VERSION=479.0.0
ARG COPILOT_VERSION=1.299.0
ARG COPILOT_CHAT_VERSION=0.43.2026040705

# Dockerfile.caddy (GOOD - pinned)
FROM caddy:2.9.1

# docker/haproxy/Dockerfile (GOOD - pinned)
FROM haproxy:2.8-alpine

# apps/session-broker/Dockerfile (GOOD - pinned)
FROM node:22-slim

# Ollama models (terraform) (BAD - uses :latest)
default = ["llama2:70b-chat", "codegemma:latest", "mistral:latest"]

# docker-compose.tpl uses variables (GOOD)
image: ollama/ollama:${ollama_version}
image: code-server-patched:${code_server_version}
```

**Standard:** All images should have pinned versions in:
- Base image `FROM` statements (✅ mostly good)
- Multi-stage build stages (✅ good)
- Ollama model pulls (❌ uses :latest)
- Package manager installations (⚠️ some use apt without --no-install-recommends)

**Remediation:**
- Pin Ollama models (see P0-3 above)
- Document why certain images cannot be pinned (if any)

---

## P1 HIGH PRIORITY FINDINGS 🟠

### 1. **Deprecated `common-functions.sh` Still in Use / Still Exists**

**Status:** DEPRECATED, but needs active migration

**Location:**
```bash
# scripts/common-functions.sh (line 1-30)
# ⚠️  DEPRECATED — Use scripts/_common/init.sh instead.
# Status: DEPRECATED
# Deprecated-By: scripts/_common/utils.sh + scripts/_common/error-handler.sh
```

**Current Situation:**
- ✅ `common-functions.sh` has deprecation warning
- ✅ Most new scripts use `_common/init.sh`
- ❌ Some old scripts still source it (shim pattern working but fragile)
- ❌ File provides fallback impl — won't cause failures but masking debt

**Scripts Still Potentially Using Old Pattern:**
- Should audit all scripts for patterns like:
  - `source ./scripts/common-functions.sh`
  - Custom logging functions (`write_error`, `write_info`, etc.)
  - Inline `die`, `error_exit` functions

**Remediation Plan:**
```bash
# Phase 1: Audit (1 hour)
grep -r "write_error\|write_success\|write_warning\|die\|error_exit" \
  scripts/*.sh scripts/**/*.sh | grep -v "_common/" | grep -v "common-functions.sh"

# Phase 2: Migrate (4 hours)
# For each script found, replace with _common/init.sh pattern

# Phase 3: Archive (1 hour)
# Move common-functions.sh to _archive/
# Add migration guide to scripts/_common/README.md
```

**Files Affected:**
- [scripts/common-functions.sh](scripts/common-functions.sh) (entire file)
- All scripts with inline log functions

**Effort:** 6 hours | **Priority:** P1

---

### 2. **Scripts Not Using Canonical init.sh Pattern**

**Risk:** Unmigrated scripts don't have standardized logging, error handling

**Patterns to Find:**
```bash
# ❌ BAD: Direct sourcing of individual files
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/utils.sh"
source "$SCRIPT_DIR/_common/config.sh"

# ✅ CORRECT: Single canonical entry point
source "$SCRIPT_DIR/_common/init.sh"
```

**Known Cases:**
- [scripts/ci/validate-dedup-registry.sh#L15](scripts/ci/validate-dedup-registry.sh#L15)
  ```bash
  source "$SCRIPT_DIR/../_common/logging.sh"  # ❌ Should use init.sh
  ```

- Some validation scripts may have inline helper functions (write_info, etc.)
  - [scripts/validate-host-31.sh](scripts/validate-host-31.sh) (custom log functions)
  - [scripts/dev/onboard-dev.sh](scripts/dev/onboard-dev.sh#L36) (inline helpers: log, success, warning, error)

**Migration Script Exists:**
```bash
./scripts/dev/refactor-phase2-task1.sh  # References migration (line 59-87)
```

**Effort:** 4 hours | **Priority:** P1

---

### 3. **Missing GOV-002 Metadata Headers on ~15 Scripts**

**Status:** Partial compliance — many scripts have headers, some don't

**Standard Header Format (GOV-002):**
```bash
#!/usr/bin/env bash
# @file        scripts/<path>/<filename>.sh
# @module      <category/subcategory>
# @description <one-line purpose>
# @owner       <team>
# @status      <active|deprecated|archived>
```

**Affected Scripts (sample):**
- [scripts/validate-host-31.sh](scripts/validate-host-31.sh) — no @file/@module/@description
- [scripts/dev/onboard-dev.sh](scripts/dev/onboard-dev.sh) — no metadata
- [scripts/validate-env.sh](scripts/validate-env.sh) — no metadata
- [scripts/post-deployment-validation.sh](scripts/post-deployment-validation.sh) — no metadata
- [scripts/dev/check-config-drift.sh](scripts/dev/check-config-drift.sh) — no metadata

**Tool Available:**
```bash
./scripts/fix-metadata-headers.sh  # Auto-fix script exists
```

**Effort:** 1 hour (automated) | **Priority:** P1

---

### 4. **Environment Variable Hardcoding in Docker-Compose**

**Status:** Mostly good, but some patterns are inconsistent

**Good Patterns Found:**
```yaml
PASSWORD: ${CODE_SERVER_PASSWORD:?must be set}           # ✅ Enforced
GSM_SECRET_NAME: ${GSM_SECRET_NAME:-github-token}        # ✅ Has default
DATABASE_URL: postgres://${POSTGRES_USER:-codeserver}... # ✅ Variable with default
```

**Issues Found:**
```yaml
# docker-compose.yml (line 187-188)
OAUTH2_PROXY_COOKIE_DOMAINS: "ide.kushnir.cloud,.ide.kushnir.cloud"  # ❌ Hardcoded
OAUTH2_PROXY_WHITELIST_DOMAINS: "ide.kushnir.cloud,.ide.kushnir.cloud"  # ❌ Hardcoded

# Better:
OAUTH2_PROXY_COOKIE_DOMAINS: "${OAUTH2_PROXY_COOKIE_DOMAINS:-ide.${DOMAIN},.ide.${DOMAIN}}"
OAUTH2_PROXY_WHITELIST_DOMAINS: "${OAUTH2_PROXY_WHITELIST_DOMAINS:-ide.${DOMAIN},.ide.${DOMAIN}}"
```

**Files Affected:**
- [docker-compose.yml](docker-compose.yml#L187-L188)
- [docker-compose.tpl](docker-compose.tpl#L164-L165)

**Effort:** 1 hour | **Priority:** P1

---

### 5. **Terraform Variables Not Fully Documented/Validated**

**Status:** Good baseline, but validation gaps exist

**Good Examples:**
```hcl
variable "code_server_password" {
  validation {
    condition     = length(var.code_server_password) >= 8
    error_message = "code_server_password must be at least 8 characters."
  }
}
```

**Missing Validation:**
```hcl
# terraform/variables.tf
variable "google_client_id" {
  description = "Google OAuth2 Client ID"
  type        = string
  # ❌ No validation (should check non-empty)
}

variable "google_client_secret" {
  description = "Google OAuth2 Client Secret"
  type        = string
  sensitive   = true
  # ❌ No validation
}

variable "kong_database_password" {
  description = "Kong PostgreSQL password"
  type        = string
  sensitive   = true
  # ❌ No validation (should be >= 12 chars)
}
```

**Remediation:**
```hcl
variable "google_client_id" {
  type      = string
  sensitive = true
  
  validation {
    condition     = length(var.google_client_id) > 0 && try(regex("^[a-zA-Z0-9._-]+$", var.google_client_id), null) != null
    error_message = "google_client_id must be non-empty and valid OAuth format"
  }
}
```

**Files Affected:**
- [terraform/variables.tf](terraform/variables.tf#L38-L70)
- [terraform/modules/*/variables.tf](terraform/modules/)

**Effort:** 2 hours | **Priority:** P1

---

## P2 MEDIUM PRIORITY FINDINGS 🟡

### 1. **Missing Python/TypeScript Docstrings & JSDoc**

**Status:** Inconsistent — some files well-documented, others sparse

**Examples:**
- [apps/backend/package.json](apps/backend/package.json) — no docstrings in code (needs audit)
- [apps/frontend/src/](apps/frontend/src/) — no JSDoc on React components (needs audit)
- [apps/extensions/agent-farm/src/](apps/extensions/agent-farm/src/) — some files have docs, others don't

**Standard Expected:**
```typescript
/**
 * Initializes the code agent with project context
 * @param context Project code context
 * @returns Initialized agent instance
 */
export function initCodeAgent(context: CodeContext): Agent { ... }
```

**Effort:** 8 hours (content audit + fixes) | **Priority:** P2

---

### 2. **NAS Mount Configuration Not Fully Centralized**

**Status:** Partially configured, but documentation sparse

**Found Configs:**
```hcl
# terraform/main.tf (line 87)
nas_host = "192.168.168.56"

# terraform/192.168.168.31/variables.tf (line 54, 78)
nas_host_primary = "192.168.168.50"      # NOTE: Config vs actual conflict!
nas_backup_host = "192.168.168.51"
```

**Issues:**
- NAS IPs appear in multiple places with different values
- No clear single source of truth for NAS topology
- Mount paths not documented in central location

**Expected Centralization:**
```hcl
# terraform/nas-config.tf (NEW)
variable "nas_hosts" {
  type = object({
    primary = string
    backup  = string
  })
  default = {
    primary = "192.168.168.50"
    backup  = "192.168.168.51"
  }
}

# Use consistently:
locals {
  nas = var.nas_hosts
}
```

**Effort:** 2 hours | **Priority:** P2

---

### 3. **Legacy Files in scripts/_archive/ Not Documented**

**Status:** Present but undocumented

**Found:**
- [scripts/_archive/phase-history/](scripts/_archive/phase-history/) — ~15 phase validation scripts
- [scripts/_archive/historical/](scripts/_archive/historical/) — older deployment scripts
- No README or index for archive

**Recommendation:**
```markdown
# scripts/_archive/README.md
## Archive Index

### phase-history/
- phase-13-validation-checklist.sh — Phase 13 deployment checks (DEPRECATED - use current CI)
- phase-13-orchestrator.sh — Phase 13 task orchestration (ARCHIVED)
- ...

### historical/
- tier-3-deployment-validation.sh — Pre-Phase-13 validation (DEPRECATED)
- ...

## Migration Guide
See ../fix-metadata-headers.sh for updating headers
See ../dev/refactor-phase2-task1.sh for canonical logging migration
```

**Effort:** 1 hour | **Priority:** P2

---

### 4. **TODO/FIXME Comments Not Tracked**

**Status:** Found in code, no systematic tracking

**Found Examples:**
```bash
# scripts/code-server-entrypoint.sh (line 41)
echo "[entrypoint] WARNING: GSM_GITHUB_TOKEN_SECRET is deprecated..."

# scripts/configure-rbac-enforcement-phase3.sh (line 83)
# Placeholder: caddy-security jwt <key> <audience> <issuer>

# apps/extensions/agent-farm/src/agents/CodeAgent.ts (line 29-33)
// Check for TODO/FIXME comments
const todoRegex = /(TODO|FIXME):/gi;
const todos = Array.from(content.matchAll(todoRegex));
if (todos.length > 0) {
  recommendations.push(`Found ${todos.length} TODO/FIXME comments`);
}
```

**Recommendation:**
- Create GitHub issues for each TODO/FIXME
- Use consistent format: `// TODO(#NNN): description`
- Remove when issues closed

**Effort:** 2 hours | **Priority:** P2

---

### 5. **pnpm Workspace Structure Not Well Documented**

**Status:** Configured but undocumented

**Current Structure:**
```yaml
# pnpm-workspace.yaml
packages:
  - apps/backend
  - apps/frontend
  - apps/extensions/*
```

**Missing Documentation:**
- How to add new packages
- Dependency isolation rules
- Version management strategy
- Cross-package import patterns (allowed/disallowed)

**Recommendation:**
```markdown
# docs/monorepo-structure.md
## pnpm Workspace Configuration

### Packages
- `apps/backend` — Node.js backend services
- `apps/frontend` — React UI (RBAC Dashboard)
- `apps/extensions/*` — VS Code extensions and agent framework

### Dependency Isolation
- Each package has isolated node_modules (pnpm)
- Cross-package imports: Use absolute paths via workspace alias
- ✅ ALLOWED: `import { logger } from '@code-server/utils'`
- ❌ DISALLOWED: `import { logger } from '../../../utils'` (relative paths)

### Adding New Packages
1. Create folder in `apps/`
2. Add `package.json` with `"name": "@code-server/my-package"`
3. Add to `pnpm-workspace.yaml`
4. Run `pnpm install`
```

**Effort:** 1 hour | **Priority:** P2

---

### 6. **Docker-Compose Syntax Issues**

**Status:** Mix of template and deployed versions

**Found:**
- `docker-compose.yml` — Active deployment config
- `docker-compose.tpl` — Template (good!)
- `docker-compose.socket-override.yml` — Alternative config
- `docker-compose.yml.remote` — Alternate remote format
- `docker/docker-compose.yml` — Deprecated local copy (CI guard exists)

**Issues:**
```yaml
# docker-compose.yml (line 360)
DOMAIN=kushnir.cloud  # Should be DOMAIN=${DOMAIN:?required}

# Some services use expose vs ports inconsistently
# See scripts/dev/fix-onprem.sh (line 17-35) — has patches for this!
```

**Effort:** 1 hour | **Priority:** P2

---

### 7. **Extension Versions Not All Pinned**

**Status:** Mostly pinned, but some floating in Dockerfile caching logic

**Found:**
```dockerfile
# Dockerfile.code-server (line 93-101)
# Optional cache paths use hardcoded old versions:
curl -fL -o /tmp/github-copilot.vsix.gz \
  "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/1.295.0/vspackage"
  # ^^ This is DIFFERENT from ARG COPILOT_VERSION=1.299.0 (should match)
```

**Issues:**
- Cached versions don't match build args
- If cache fails, entrypoint re-installs with `$COPILOT_VERSION`
- Inconsistent source of truth

**Remediation:**
```dockerfile
ARG COPILOT_VERSION=1.299.0
...
curl -fL -o /tmp/github-copilot.vsix.gz \
  "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot/${COPILOT_VERSION}/vspackage"
  # Use variable instead of hardcoded version
```

**Effort:** 1 hour | **Priority:** P2

---

### 8. **Configuration Separation Not Consistent**

**Status:** Good pattern, but not applied everywhere

**Pattern Found (Good):**
```bash
# scripts/_common/config.sh loads from .env
# docker-compose.yml references ${VAR} from .env
# terraform passes variables from terraform.tfvars
```

**Gaps:**
```bash
# scripts/p0-operations-deployment-validation.sh (line 28-32)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # ❌ DUPLICATE ASSIGNMENT
source "$SCRIPT_DIR/_common/init.sh"

# Fallback color codes defined locally (should use logging.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
```

**Effort:** 1 hour | **Priority:** P2

---

## P3 LOW PRIORITY FINDINGS 🟢

### 1. **Duplicate Color Code Definitions**

Multiple scripts define their own color codes instead of using canonical ones from logging.sh.

**Files:** [scripts/validate-host-31.sh](scripts/validate-host-31.sh#L30), [scripts/dev/onboard-dev.sh](scripts/dev/onboard-dev.sh#L36), [scripts/p0-operations-deployment-validation.sh](scripts/p0-operations-deployment-validation.sh#L28)

**Effort:** 1 hour | **Priority:** P3

---

### 2. **Test Data with Hardcoded Values**

**Example:**
```typescript
// apps/extensions/agent-farm/src/phases/phase6/PullRequestValidator.test.ts (line 88)
patch: '+  password: "hardcoded123"',  // ❌ Test uses real-looking secret
```

Should use placeholder like `password: "PLACEHOLDER_SECRET"` or sanitized test value.

**Effort:** 1 hour | **Priority:** P3

---

### 3. **Inline Helper Functions in Dev Scripts**

Scripts like [scripts/dev/onboard-dev.sh](scripts/dev/onboard-dev.sh#L36) define custom `log()`, `success()`, `warning()`, `error()` functions instead of using canonical ones.

**Effort:** 2 hours | **Priority:** P3

---

### 4. **Validation Logic Spread Across Multiple Files**

Validation patterns repeated in:
- [scripts/validate-env.sh](scripts/validate-env.sh)
- [scripts/validate-host-31.sh](scripts/validate-host-31.sh)
- [scripts/validate.sh](scripts/validate.sh)
- [scripts/ci/enforce-global-dedup.sh](scripts/ci/enforce-global-dedup.sh)

Could benefit from shared validation library in `scripts/_common/validation.sh`.

**Effort:** 3 hours | **Priority:** P3

---

### 5. **Architecture Documentation Gaps**

**Missing from [docs/](docs/):**
- `architecture-monorepo.md` — How pnpm workspace works
- `image-versioning-policy.md` — Rules for pinning versions
- `secrets-management.md` — Where credentials come from (GSM/Vault/.env)
- `network-topology.md` — IP/hostname assignments (VIP, primary, replica, NAS)

**Effort:** 4 hours | **Priority:** P3

---

### 6. **Logging Configuration Spread Across Files**

Logging setup appears in:
- [scripts/_common/logging.sh](scripts/_common/logging.sh) (canonical)
- [scripts/logging.sh](scripts/logging.sh) (old, should be deprecated)
- [scripts/dev/onboard-dev.sh](scripts/dev/onboard-dev.sh) (inline)

**Effort:** 1 hour | **Priority:** P3

---

## Summary Table: All Issues

| ID | Category | Issue | File(s) | P | Effort | Status |
|----|----------|-------|---------|---|--------|--------|
| 1 | Secrets | Hardcoded domains | docker-compose.yml, terraform/variables.tf | P0 | 2h | Open |
| 2 | IaC | Hardcoded IPs | terraform/main.tf, variables.tf | P0 | 3h | Open |
| 3 | Immutability | Floating image tags (:latest) | terraform/192.168.168.31/variables.tf | P0 | 1h | Open |
| 4 | Secrets | Hardcoded tokens in code | terraform/modules/security/main.tf | P0 | 4h | Open |
| 5 | Versions | Inconsistent version pinning | Dockerfile.code-server, docker-compose.tpl | P0 | 2h | Open |
| 6 | Migration | Deprecated common-functions.sh | scripts/common-functions.sh | P1 | 6h | Open |
| 7 | Migration | Scripts not using init.sh | scripts/ci/validate-dedup-registry.sh, others | P1 | 4h | Open |
| 8 | Documentation | Missing metadata headers (GOV-002) | ~15 scripts | P1 | 1h | Open |
| 9 | Config | Hardcoded env vars in docker-compose | docker-compose.yml#L187 | P1 | 1h | Open |
| 10 | Validation | Terraform variables lack validation | terraform/variables.tf | P1 | 2h | Open |
| 11 | Docs | Missing Python/TypeScript docstrings | apps/ (entire tree) | P2 | 8h | Open |
| 12 | Ops | NAS config not centralized | terraform/main.tf, 192.168.168.31/ | P2 | 2h | Open |
| 13 | Docs | Archive scripts not documented | scripts/_archive/ | P2 | 1h | Open |
| 14 | Tracking | TODO/FIXME comments not tracked | scattered | P2 | 2h | Open |
| 15 | Docs | pnpm workspace undocumented | pnpm-workspace.yaml | P2 | 1h | Open |
| 16 | Config | docker-compose syntax issues | docker-compose.yml | P2 | 1h | Open |
| 17 | Versions | Extension caching version mismatch | Dockerfile.code-server | P2 | 1h | Open |
| 18 | Config | Duplicate SCRIPT_DIR assignments | p0-operations-deployment-validation.sh | P2 | 1h | Open |
| 19 | Code | Duplicate color definitions | 3+ scripts | P3 | 1h | Open |
| 20 | Testing | Test data with hardcoded secrets | apps/extensions/agent-farm/tests | P3 | 1h | Open |
| 21 | Code | Inline helpers in dev scripts | scripts/dev/onboard-dev.sh | P3 | 2h | Open |
| 22 | Code | Validation logic duplication | scripts/validate*.sh | P3 | 3h | Open |
| 23 | Docs | Architecture docs gaps | docs/ | P3 | 4h | Open |
| 24 | Code | Logging setup spread across files | scripts/logging.sh, scripts/_common/logging.sh | P3 | 1h | Open |

---

## Recommendations by Governance Rule

### Applying Copilot-Instructions Rules

Reference: [.github/copilot-instructions.md](.github/copilot-instructions.md)

**Rule 1 — No Duplication:**
- ✅ Shared libraries in `scripts/_common/` are well-established
- ❌ Some scripts still have inline helpers instead of using canonical ones
- ❌ Validation logic duplicated across files (see issue #22)
- **Action:** Migrate remaining scripts to `_common/init.sh`; create `_common/validation.sh`

**Rule 2 — Metadata Headers (GOV-002):**
- ⚠️ Partially compliant; ~15 scripts missing headers
- ✅ Tool exists: `./scripts/fix-metadata-headers.sh`
- **Action:** Run automation tool, verify output, commit

**Rule 3 — Configuration Separation:**
- ✅ Good: `.env.template` documents required vars
- ⚠️ Issue: Hardcoded domains/IPs in docker-compose and terraform
- **Action:** Move all hardcoded values to variable defaults with `${VAR}` substitution

**Rule 4 — Shared Library Adoption:**
- ✅ Most scripts use `_common/init.sh`
- ❌ Some use partial sourcing (logging.sh only)
- **Action:** Audit remaining scripts, migrate to init.sh pattern

**Rule 5 — Script Template:**
- ✅ Template exists: `scripts/_template.sh`
- **Action:** Use for all new scripts; document in CONTRIBUTING.md

**Rule 6 — Deduplication Enforcement:**
- ⚠️ Status: Common-functions.sh deprecated but not removed
- ⚠️ Status: Some scripts still have custom log functions
- **Action:** Complete migration in Phase 15 planning

**Rule 7 — Copilot Trigger Pattern:**
```bash
@workspace, apply governance standards: 
- deduplication: migrate scripts/dev/onboard-dev.sh, validate-*.sh
- headers: run fix-metadata-headers.sh
- config: externalize hardcoded domains/IPs
- shared libs: complete init.sh migration
```

---

## Immediate Action Items (Next Sprint)

### Week 1: P0 Critical (5 issues)
1. ✅ Extract hardcoded domains to variables (2h)
2. ✅ Extract hardcoded IPs to variables (3h)
3. ✅ Pin Ollama model versions (1h)
4. ✅ Add validation to terraform password variables (4h)
5. ✅ Document secret handling policy (1h)

**Total:** 11 hours

### Week 2-3: P1 High (5 issues)
1. ✅ Migrate `common-functions.sh` references (6h)
2. ✅ Audit and migrate scripts not using init.sh (4h)
3. ✅ Fix metadata headers with tool (1h)
4. ✅ Update docker-compose env vars (1h)
5. ✅ Add terraform variable validation (2h)

**Total:** 14 hours

### Week 4: P2 Medium (8 issues)
- Audit Python/TypeScript docstrings (8h)
- Centralize NAS config (2h)
- Document archives (1h)
- Create GitHub issues for TODOs (2h)
- Document monorepo structure (1h)
- Fix docker-compose syntax (1h)
- Fix extension version caching (1h)
- Dedup config setup code (1h)

**Total:** 17 hours

**Grand Total:** 42 hours (~5 business days, one engineer)

---

## Success Criteria

After remediation:

- [ ] **Zero P0 governance violations** (critical security/immutability)
- [ ] **100% of scripts use `_common/init.sh`** pattern
- [ ] **100% of image versions pinned** (no `:latest`)
- [ ] **All hardcoded secrets extracted** to variables with validation
- [ ] **GOV-002 headers on 100%** of bash scripts
- [ ] **Architecture documented** (monorepo, versioning, secrets, topology)
- [ ] **Archive indexed and deprecated** markers added to old scripts

---

## References

- [Copilot Governance Rules](.github/copilot-instructions.md)
- [Script Writing Guide](docs/SCRIPT-WRITING-GUIDE.md)
- [Deduplication Analysis](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md)
- [Current Production State](/memories/repo/current-production-state.md)
- [Terraform Consolidation Status](/memories/repo/terraform-consolidation-status.md)

---

**Document Version:** 1.0  
**Last Updated:** April 19, 2026  
**Author:** Governance Analysis  
**Next Review:** After P1-P2 remediation (Week 4, 2026)
