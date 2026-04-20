# QUICK REFERENCE: CONFIG CONFLICTS & FIXES
## Action Items for kushin77/code-server-enterprise

---

## 🔴 P0 BLOCKING ISSUES (Fix First — 4-6 Hours)

### 1. Database Name Mismatch

**Problem**: Three different DB names across config files
- `.env.template`: `codeserver`
- `.env.production`: `ide_production`
- `.env.defaults`: `code_server`

**Impact**: Docker will create one DB, but connection string uses another → **Connection fails**

**Quick Fix**:
```bash
# Replace in .env.template and .env.production:
POSTGRES_DB=code_server

# In terraform/on-prem.tfvars, add:
postgres_db = "code_server"
```

**Files to Change**: 2 `.env` files + 1 terraform file

---

### 2. Missing Terraform Database Password Variable

**Problem**: `POSTGRES_PASSWORD` is in `.env.production` as `${VAULT_POSTGRES_PASSWORD}`, but `terraform/variables.tf` has **NO variable** for it

**Impact**: Docker-compose generation fails (`docker-compose.yml` can't populate postgres password)

**Quick Fix**:
```terraform
# Add to terraform/variables.tf:
variable "postgres_password" {
  description = "PostgreSQL password (from Vault: secret/postgresql/password)"
  type        = string
  sensitive   = true
  default     = ""
  validation {
    condition     = length(var.postgres_password) >= 12
    error_message = "postgres_password must be 12+ characters"
  }
}
```

**Files to Change**: 1 file (terraform/variables.tf)

---

### 3. Missing Terraform Redis Password Variable

**Problem**: `REDIS_PASSWORD` in `.env.production` but NO terraform variable

**Impact**: Same as #2 — docker-compose generation fails

**Quick Fix**:
```terraform
# Add to terraform/variables.tf:
variable "redis_password" {
  description = "Redis authentication password (from Vault: secret/redis/password)"
  type        = string
  sensitive   = true
  default     = ""
  validation {
    condition     = length(var.redis_password) >= 8
    error_message = "redis_password must be 8+ characters"
  }
}
```

**Files to Change**: 1 file

---

### 4. Test Credentials in Git (Security Vulnerability)

**Problem**: `terraform/on-prem.tfvars` contains hardcoded test passwords:
```
grafana_admin_password = "test-password-change-in-production"
kong_database_password = "test-password-change-in-production"
```

**Impact**: 🚨 Security risk — credentials in version control

**Quick Fix**:
```bash
# REMOVE these lines from on-prem.tfvars:
# grafana_admin_password = "..."
# kong_database_password = "..."

# Use Vault only:
# .env.production: GRAFANA_PASSWORD=${VAULT_GRAFANA_PASSWORD}

# For local testing, create .tfvars.local (gitignored):
# cat terraform/.gitignore
# *.tfvars.local
```

**Files to Change**: 2 (on-prem.tfvars, .gitignore)

---

### 5. Ollama Version Mismatch

**Problem**: `docker-compose.yml` hardcodes `ollama/ollama:0.1.27` but `.env.defaults` says `OLLAMA_VERSION=latest`

**Impact**: Version mismatch → unexpected bugs, model incompatibilities

**Quick Fix**:
```bash
# Option A (recommended): Align to 0.1.27 in .env.defaults:
OLLAMA_VERSION=0.1.27

# Option B: Add terraform variable:
# variable "ollama_version" {
#   description = "Ollama version"
#   type        = string
#   default     = "0.1.27"
# }
```

**Files to Change**: 1-2 files

---

### 6. OAuth Redirect URLs Hardcoded (Will Break in Staging)

**Problem**: `.env.production` hardcodes:
```
OAUTH2_PROXY_IDE_REDIRECT_URL=https://ide.kushnir.cloud/oauth2/callback
OAUTH2_PROXY_PORTAL_REDIRECT_URL=https://kushnir.cloud/oauth2/callback
```

If you deploy to **staging.kushnir.cloud**, these URLs won't match Google OAuth config → **Auth fails**

**Impact**: Can't deploy to staging or multi-tenant environments

**Quick Fix**:
```bash
# In .env.template:
OAUTH2_PROXY_IDE_REDIRECT_URL=https://ide.${APEX_DOMAIN}/oauth2/callback
OAUTH2_PROXY_PORTAL_REDIRECT_URL=https://${APEX_DOMAIN}/oauth2/callback

# In docker-compose.tpl, replace hardcoded URLs with env var references
```

**Files to Change**: 2-3 files (.env files, docker-compose.tpl)

---

## 🟠 P1 HIGH PRIORITY (Next 6-8 Hours)

### 1. Primary/Replica Host IPs Can Diverge

| Source | Value |
|--------|-------|
| `.env.template` | `DEPLOY_HOST=192.168.168.31` |
| `terraform/network-variables.tf` | `default = "192.168.168.31"` |
| `terraform/on-prem.tfvars` | `primary_ip = "192.168.168.31"` |
| scripts | Hardcoded 192.168.168.31, 192.168.168.42 |

**Risk**: If terraform.tfvars differs from .env, failover scripts target wrong IP

**Fix**: 
```terraform
# terraform/network-variables.tf should read from .env:
variable "primary_host" {
  type    = string
  default = "192.168.168.31"  # Match .env.template
}
```

**Files to Change**: 1 terraform file (clarify dependency)

---

### 2. Missing Parameters in .env.template

**Add to `.env.template`**:
```bash
# NAS Configuration (currently missing)
NAS_HOST=192.168.168.56
NAS_EXPORT_PATH=/export/code-server

# Ollama Model (currently missing)
OLLAMA_DEFAULT_MODEL=llama2:7b-chat
OLLAMA_KEEP_ALIVE=30m

# Memory/CPU Limits (hardcoded in docker-compose)
CODE_SERVER_MEMORY_LIMIT=8g
CODE_SERVER_CPU_LIMIT=4.0
OLLAMA_MEMORY_LIMIT=32g

# Caddy Admin Port (only in .env.phase3.template)
CADDY_ADMIN_PORT=2019

# TLS Configuration
TLS_MIN_VERSION=1.3
TLS_CIPHER_SUITES=TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256
```

**Files to Change**: 1 (.env.template)

---

### 3. Hard-coded Domains in Scripts (40+ References)

| Hardcoded Value | Should Be |
|-----------------|-----------|
| `kushnir.cloud` | `${APEX_DOMAIN}` |
| `ide.kushnir.cloud` | `ide.${APEX_DOMAIN}` |
| `admin.kushnir.cloud` | `admin.${APEX_DOMAIN}` |

**Impact**: Scripts fail when APEX_DOMAIN ≠ kushnir.cloud

**Example Fixes**:
```bash
# BEFORE (in scripts/automated-certificate-management.sh):
DOMAIN="${DOMAIN:-ide.kushnir.cloud}"

# AFTER:
DOMAIN="${DOMAIN:-ide.${APEX_DOMAIN}}"
```

**Files to Change**: 15+ scripts (use automated replacement)

**Command**:
```bash
find scripts -name "*.sh" -type f -exec sed -i \
  's/ide\.kushnir\.cloud/${IDE_DOMAIN:-ide.${APEX_DOMAIN}}/g' \
  {} \;
```

---

### 4. Inconsistent ACME Email

| Source | Value |
|--------|-------|
| `.env.template` | `ops@kushnir.cloud` |
| `.env.production` | `security-team@example.com` |
| Scripts | `admin@kushnir.cloud` |
| Caddyfile | `admin@kushnir.cloud` (default) |

**Fix**: Use `.env.template` as SSOT:
```bash
# .env.template:
ACME_EMAIL=ops@kushnir.cloud

# .env.production:
ACME_EMAIL=security-team@example.com
```

---

### 5. Grafana Version Mismatch

| Source | Version |
|--------|---------|
| `terraform/module-variables.tf` | 10.2.3 |
| `.env.defaults` | 10.2.0 |

**Fix**: Align to 10.2.3 in `.env.defaults`

---

## 🟡 P2 MEDIUM PRIORITY (8-12 Hours)

- [ ] Add PROMETHEUS_VERSION, ALERTMANAGER_VERSION to .env.defaults
- [ ] Add GRAFANA_VERSION to .env.defaults (align to 10.2.3)
- [ ] Parameterize ACME_CA in Caddyfile (for staging ACME)
- [ ] Add DOCKER_CONTEXT to .env.template (standardize variable naming)
- [ ] Parameterize memory/CPU limits in .env
- [ ] Validate .env.defaults against .env.schema.json in CI/CD

---

## SUMMARY TABLE

| Issue | Severity | Fix Time | Files | Action |
|-------|----------|----------|-------|--------|
| DB name mismatch | P0 | 15 min | 3 | Align to `code_server` |
| Missing POSTGRES_PASSWORD tf var | P0 | 10 min | 1 | Add variable |
| Missing REDIS_PASSWORD tf var | P0 | 10 min | 1 | Add variable |
| Test credentials in git | P0 | 20 min | 2 | Remove from tfvars |
| Ollama version mismatch | P0 | 10 min | 1-2 | Align to 0.1.27 |
| OAuth URLs hardcoded | P0 | 30 min | 2-3 | Derive from APEX_DOMAIN |
| Primary/replica IP divergence | P1 | 30 min | 1 | Clarify dependency |
| Missing .env.template params | P1 | 20 min | 1 | Add NAS, Ollama, resource limits |
| Hard-coded domains in scripts | P1 | 60 min | 15+ | Use env var substitution |
| ACME email inconsistency | P1 | 10 min | 4 | Use .env.template SSOT |
| Grafana version mismatch | P1 | 5 min | 1 | Align to 10.2.3 |
| **TOTAL P0** | **🔴** | **4-6 hours** | **6** | **BLOCKING** |
| **TOTAL P1** | **🟠** | **6-8 hours** | **30+** | **OPERATIONAL** |
| **TOTAL P2** | **🟡** | **8-12 hours** | **10** | **IMPROVEMENT** |

---

## TESTING CHECKLIST

After fixes, verify:

- [ ] `terraform plan` generates docker-compose.yml with all vars populated
- [ ] `docker compose up -d` starts all services without version mismatches
- [ ] `terraform apply` can be re-run idempotently
- [ ] `.env.defaults` matches `.env.schema.json`
- [ ] OAuth redirects match Google Console settings
- [ ] Database connection string resolves to correct host/db/user
- [ ] Redis connection authenticates with password
- [ ] Ollama model loads without version conflicts
- [ ] Failover scripts target correct IP from .env
- [ ] CI/CD validates .env against schema before deploying

---

## IMPLEMENTATION ORDER

1. **Fix P0 blocking issues** (4-6 hrs) → Allows deployment
2. **Fix P1 operational issues** (6-8 hrs) → Allows multi-environment
3. **Add P2 improvements** (8-12 hrs) → Polish and maintainability

---

## RELATED DOCUMENTATION

- Main analysis: [CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md](CONFIGURATION-SSOT-ANALYSIS-APRIL-2026.md)
- Schema source of truth: [.env.schema.json](.env.schema.json)
- Environment templates: `.env.template`, `.env.defaults`, `.env.production`
- Terraform sources: `terraform/variables.tf`, `terraform/module-variables.tf`, `terraform/network-variables.tf`

---

**Generated**: April 19, 2026  
**Status**: Ready for Phase 1 implementation
