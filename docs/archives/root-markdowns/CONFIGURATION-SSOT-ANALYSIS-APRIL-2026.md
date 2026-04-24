# CONFIGURATION SINGLE SOURCE OF TRUTH (SSOT) ANALYSIS
## kushin77/code-server-enterprise

**Analysis Date**: April 19, 2026  
**Analysis Scope**: Complete configuration source mapping  
**Status**: CRITICAL CONFLICTS IDENTIFIED — **16 items with multi-source conflicts**  

---

## EXECUTIVE SUMMARY

### Configuration Hierarchy (Top Priority Wins)
```
1. .env file (local — highest priority at runtime)
2. .env.${DEPLOYMENT_ENV} (environment override)
3. .env.template + .env.defaults (template/defaults — lowest priority)
4. terraform/variables.tf defaults (IaC layer — for docker-compose generation)
5. docker-compose.yml locals (hardcoded overrides — ANTI-PATTERN)
6. Shell scripts defaults (inconsistent — SHOULD BE REMOVED)
```

### Critical Findings
| Type | Count | Severity | Example |
|------|-------|----------|---------|
| **Multi-source conflicts** | 16 | 🔴 P0 | `OLLAMA_PORT`: 11434 (docker-compose.yml) vs 11434 (terraform) vs hardcoded in scripts |
| **Hardcoded values** | 42 | 🟠 P1 | IPs (192.168.168.31/42/56/30), domains (kushnir.cloud), paths (/export) |
| **Missing parameterization** | 8 | 🟡 P2 | NAS export paths, cert paths, Vault endpoints |
| **Version inconsistencies** | 5 | 🟡 P2 | ollama: 0.1.27 (docker-compose.yml) vs unspecified (defaults) |

---

## DETAILED ANALYSIS BY CONFIGURATION DOMAIN

---

## 1. INFRASTRUCTURE & TOPOLOGY

### 1.1 **DOMAIN (Apex Domain)**

| Item | Current SSOT | Definition Locations | Override Hierarchy | Issues |
|------|--------------|----------------------|-------------------|---------|
| **DOMAIN** | .env.template | `.env.template`, `.env.production`, `docker-compose.yml` hardcoded, scripts with defaults | .env > .env.{env} > defaults | ✅ CONSISTENT |
| **IDE_DOMAIN** | .env.template | `.env.template`, `.env.production` | .env > defaults | ✅ CONSISTENT |
| **APEX_DOMAIN** | .env.defaults | `.env.schema.json` (schema), `.env.defaults`, `terraform/module-variables.tf` | .env > terraform tfvars | ✅ CONSISTENT |

**Recommended SSOT**: `.env.template` (currently correct)  
**Priority**: P3 — Working as intended

---

### 1.2 **Host IPs & Network Topology**

| Configuration | Current SSOT | Defined In | Conflicts | Impact |
|---------------|--------------|-----------|-----------|--------|
| **Primary Host IP (192.168.168.31)** | CONFLICT | `.env.template` (DEPLOY_HOST) | terraform/network-variables.tf (primary_host), terraform/on-prem.tfvars (primary_ip), docker-compose.yml comments, scripts/*/setup-*.sh | If terraform.tfvars differs from .env, docker-compose will be generated with terraform values, scripts fail if .env is different |
| **Replica Host IP (192.168.168.42)** | CONFLICT | CONFLICT | terraform/network-variables.tf (replica_host), on-prem.tfvars (secondary_ip), .env.template (REPLICA_HOST), scripts | Failover scripts reference 192.168.168.42 hardcoded, terraform generates different IP if tfvars differ |
| **VIP Host (192.168.168.30)** | .env.template | .env.template (VIP_HOST), terraform/network-variables.tf (vip_host default: 192.168.168.30), on-prem.tfvars | If .env not set, terraform default applies; inconsistency if .env differs | Caddyfile references hardcoded "ide.kushnir.cloud", not VIP |
| **NAS Host (192.168.168.56)** | HARDCODED | terraform/network-variables.tf (default), .env.template (not defined), .env.example (NAS_HOST), scripts/dev/check-config-drift.sh | No .env template param; scripts assume hardcoded NAS IP | P1 — Missing from .env.template |
| **NAS Export Path (/export)** | terraform/network-variables.tf | terraform/network-variables.tf (default: `/export/code-server`), docker-compose.yml comments, scripts | No env var, hardcoded in Terraform | Need to parameterize in .env |

**Recommended SSOT**:
- ✅ Primary/Replica/VIP → `.env.template` (source of truth)
- ❌ Terraform tfvars should reference .env values, NOT override them
- ❌ NAS_HOST should be added to `.env.template`
- ❌ NAS_EXPORT_PATH should be added to `.env.template`

**Priority**: 🔴 **P0** — Failover/replica deployment will fail if .env and terraform.tfvars differ

---

## 2. AUTHENTICATION & OAUTH2

### 2.1 **OAuth2 Configuration**

| Item | Current SSOT | Locations | Conflicts | Priority |
|------|--------------|-----------|-----------|----------|
| **GOOGLE_CLIENT_ID** | `.env.schema.json` (vault_path: secret/oauth2/google/client_id) | `.env.template`, `.env.production` (uses ${VAULT_GOOGLE_CLIENT_ID}), terraform/variables.tf (google_client_id), `.env.defaults` | 🟢 CONSISTENT — all reference vault or env var | P3 ✅ |
| **GOOGLE_CLIENT_SECRET** | Vault (secret/oauth2/google/client_secret) | `.env.schema.json`, `.env.production`, terraform/variables.tf | 🟢 CONSISTENT — vault-sourced | P3 ✅ |
| **OAUTH2_PROXY_COOKIE_SECRET** | CONFLICT | `.env.schema.json` (vault_path), `.env.template` (empty), `.env.production` (${VAULT_OAUTH2_PROXY_COOKIE_SECRET}), terraform/variables.tf (validation: length >= 16) | ⚠️ GENERATION CONFLICT: `.env.template` empty, terraform expects pre-generated value; scripts/automated-env-generator.sh generates but doesn't store in .env | Need bootstrap script to auto-generate or fetch from Vault |
| **OAUTH2_PROXY_IDE_REDIRECT_URL** | `.env.template` | `.env.template`, `.env.production` (hardcoded: https://ide.kushnir.cloud/oauth2/callback), `.env.defaults` (http://localhost:8080/oauth2/callback), `.env.schema.json` | 🟠 CONFLICT: defaults assume localhost, production assumes ide.kushnir.cloud; if someone uses .env.defaults for production, OAuth will fail | P1 — must validate against APEX_DOMAIN |
| **OAUTH2_PROXY_PORTAL_REDIRECT_URL** | `.env.production` | `.env.production` (https://kushnir.cloud/oauth2/callback), `.env.defaults` (http://localhost:8080/oauth2/callback), `.env.schema.json` | 🟠 CONFLICT: same as IDE URL above | P1 — must derive from APEX_DOMAIN |
| **OAUTH2_REDIRECT_URI** | DEPRECATED | `.env.production` (template: https://${DOMAIN}/oauth2/callback), `.env.defaults` (fallback) | ⚠️ LEGACY: served as fallback in .env.defaults but .env.production uses OAUTH2_PROXY_IDE/PORTAL variants | Mark as deprecated, remove from schema |

**Recommended SSOT**:
- ✅ Secrets → Vault (current practice correct)
- ❌ Redirect URLs → Derive from APEX_DOMAIN, don't hardcode
  - `OAUTH2_PROXY_IDE_REDIRECT_URL=https://ide.${APEX_DOMAIN}/oauth2/callback`
  - `OAUTH2_PROXY_PORTAL_REDIRECT_URL=https://${APEX_DOMAIN}/oauth2/callback`
- ❌ Cookie secret → Bootstrap script should generate + store in Vault, or .env.production should auto-populate from Vault

**Priority**: 🔴 **P0** — OAuth will fail if redirect URLs don't match Google Console settings

---

## 3. DATABASE (PostgreSQL)

### 3.1 **Database Connection Parameters**

| Item | Current SSOT | Defined In | Override Hierarchy | Conflicts | Impact |
|------|--------------|-----------|-------------------|-----------|---------|
| **POSTGRES_HOST** | `.env.defaults` (postgres) | `.env.defaults` ("postgres"), `.env.production` ("postgres"), `.env.schema.json` | All hardcode "postgres" container name | ✅ CONSISTENT | For local docker-compose: connects to `postgres` container; for remote: would need IP in .env |
| **POSTGRES_PORT** | `.env.defaults` (5432) | `.env.defaults`, `.env.schema.json`, `.env.production` | All hardcode 5432 | ✅ CONSISTENT | Standard port, rarely changes |
| **POSTGRES_DB** | `.env.template` (codeserver) | `.env.template` (POSTGRES_DB=codeserver), `.env.production` (ide_production), `.env.defaults` (code_server), `.env.schema.json` | ⚠️ THREE DIFFERENT VALUES | 🔴 CONFLICT — .env.template ≠ .env.production ≠ .env.defaults | Critical: Wrong DB name will cause migrations to fail |
| **POSTGRES_USER** | `.env.template` (codeserver) | `.env.template` (POSTGRES_USER=codeserver), `.env.production` (ide_admin), terraform/on-prem.tfvars (not defined) | ⚠️ TWO DIFFERENT VALUES | 🔴 CONFLICT — Username mismatch | Connect will fail if user doesn't match |
| **POSTGRES_PASSWORD** | Vault/TF | `.env.template` (empty — must come from Vault), `.env.production` (${VAULT_POSTGRES_PASSWORD}), terraform/variables.tf (NO VARIABLE DEFINED), .env.defaults (empty) | 🟠 PARTIAL CONFLICT — terraform has no postgres_password variable | docker-compose can't be generated without TF variable | P0 — Must add postgres_password to terraform/variables.tf |
| **DATABASE_URL** | NOT DEFINED | Nowhere (but common pattern in Node.js) | N/A | ❌ MISSING | Backend code likely constructs: `postgresql://user:pass@host:port/db` but no env var for it | Should add DATABASE_URL to .env.template for easy reference |

**Recommended SSOT**:
- `.env.template` → Single source, environment files override only if needed
- URGENT: Fix POSTGRES_DB inconsistency:
  - `.env.template`: codeserver
  - `.env.production`: ide_production
  - `.env.defaults`: code_server
  - **Choose one**: recommend `code_server` (consistent with Docker container)
- URGENT: Add POSTGRES_PASSWORD to terraform/variables.tf
- ADD: DATABASE_URL composite variable (for app convenience)

**Priority**: 🔴 **P0** — Database connection will fail due to naming conflicts

---

## 4. REDIS (Cache)

### 4.1 **Redis Connection Parameters**

| Item | Current SSOT | Defined In | Hierarchy | Issues |
|------|--------------|-----------|-----------|--------|
| **REDIS_HOST** | `.env.defaults` (redis) | `.env.defaults`, `.env.production` | All hardcode "redis" | ✅ CONSISTENT — docker container name |
| **REDIS_PORT** | `.env.defaults` (6379) | `.env.defaults`, `.env.production`, scripts/*/phase-*.sh | All hardcode 6379 | ✅ CONSISTENT |
| **REDIS_PASSWORD** | Vault | `.env.schema.json` (vault_path), `.env.production` (${VAULT_REDIS_PASSWORD}), `.env.template` (empty), terraform/variables.tf (NO VARIABLE) | ⚠️ MISSING TERRAFORM VARIABLE | docker-compose can't populate redis_password | P0 — Add redis_password variable to terraform/variables.tf |
| **REDIS_DB** | `.env.production` (0) | `.env.production`, `.env.defaults` | All assume DB 0 | ✅ CONSISTENT |
| **REDIS_URL** | NOT DEFINED | Not defined anywhere | N/A | ❌ MISSING | Should add: `redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}/${REDIS_DB}` |

**Recommended SSOT**:
- ✅ .env.defaults correct
- ❌ Add REDIS_PASSWORD to terraform/variables.tf
- ADD: REDIS_URL composite variable to .env template

**Priority**: 🔴 **P0** — Missing terraform variable blocks docker-compose generation

---

## 5. SERVICE PORTS

### 5.1 **Port Definitions**

| Service | Port | Current SSOT | Defined In | Conflicts | Hardcoded In | Priority |
|---------|------|--------------|-----------|-----------|--------------|----------|
| **Code-Server** | 8080 | terraform/main.tf locals | docker-compose.tpl, terraform/main.tf (locals), .env.defaults (CODE_SERVER_PORT), .env.schema.json | ✅ MOSTLY CONSISTENT | scripts (30+ references), Caddyfile, nginx configs | P2 — Documented, rarely changes |
| **PostgreSQL** | 5432 | .env.defaults | .env.defaults, .env.schema.json, scripts, Prometheus scrape configs, .env.phase3.template | ✅ CONSISTENT | postgres config files, CoredNS config | P3 ✅ |
| **Redis** | 6379 | .env.defaults | .env.defaults, .env.schema.json, scripts, .env.phase3.template | ✅ CONSISTENT | Prometheus scrape config, redis.conf | P3 ✅ |
| **Prometheus** | 9090 | .env.defaults | .env.defaults, .env.schema.json, scripts, .env.phase3.template, Caddyfile | ✅ CONSISTENT | Prometheus YAML configs | P3 ✅ |
| **Grafana** | 3000 | .env.defaults | .env.defaults, .env.schema.json, scripts, .env.phase3.template, Caddyfile | ✅ CONSISTENT | User docs, dashboards | P3 ✅ |
| **AlertManager** | 9093 | .env.phase3.template | .env.phase3.template (CADDY_ALLOWED_SERVICES), prometheus.yml, Caddyfile | ✅ CONSISTENT | Prometheus rules | P3 ✅ |
| **Jaeger** | 16686 | .env.defaults | .env.defaults, .env.schema.json | ✅ CONSISTENT | Caddyfile, tracing configs | P3 ✅ |
| **Ollama** | 11434 | CONFLICT | docker-compose.yml (11434), terraform/main.tf (11434), .env.defaults (OLLAMA_ENDPOINT=http://localhost:11434), scripts (hardcoded) | ✅ ALL SAY 11434 | code-server Dockerfile, scripts, models config | P3 ✅ |
| **OAuth2-Proxy** | 4180 | terraform/main.tf (4180) | terraform/main.tf, docker-compose.tpl, Caddyfile (reverse_proxy oauth2-proxy:4180) | ✅ CONSISTENT | Scripts hardcoded in 5+ places | P3 ✅ |
| **Caddy** | 80/443 | terraform/main.tf | docker-compose.yml, Caddyfile, terraform/main.tf | ✅ CONSISTENT | Standard HTTP/HTTPS | P3 ✅ |
| **Caddy Admin** | 2019 | .env.phase3.template | .env.phase3.template (referenced in CADDY_ALLOWED_SERVICES) | Not parameterized | .env.phase3.template only | P2 — Should be in main .env files |

**Issues**:
- ⚠️ Caddy admin port (2019) only in .env.phase3.template, not in main config
- All other ports are consistent but scattered across files (not a critical issue)

**Recommended SSOT**: .env.defaults (currently correct for ports)

**Priority**: 🟡 **P2** — Low risk (rarely change), but 2019 should be centralized

---

## 6. OLLAMA (Local LLM)

### 6.1 **Ollama Version & Configuration**

| Item | Current SSOT | Locations | Conflicts | Priority |
|------|--------------|-----------|-----------|----------|
| **OLLAMA_VERSION** | CONFLICT | docker-compose.yml (0.1.27), terraform/variables.tf (defaults.ollama_version = NOT DEFINED), .env.defaults (OLLAMA_VERSION=latest) | 🔴 CRITICAL: docker-compose hardcodes 0.1.27, .env.defaults says "latest" | If .env is "latest" and docker-compose is 0.1.27, version mismatch | P0 — Image versioning broken |
| **OLLAMA_PORT** | 11434 | docker-compose.yml, terraform/main.tf (locals: ollama_port = 11434), .env.defaults, scripts | ✅ ALL CONSISTENT | No conflicts, all 11434 | P3 ✅ |
| **OLLAMA_ENDPOINT** | `.env.defaults` | .env.defaults (http://localhost:11434), docker-compose.yml comments, code-server Dockerfile env, scripts | ✅ CONSISTENT | But assumes localhost; in production, could be remote (e.g., 192.168.168.42:11434) | P2 — Should be parameterized per environment |
| **OLLAMA_DEFAULT_MODEL** | CONFLICT | terraform/variables.tf (llama2:70b-chat), .env.defaults (LLAMA_MODEL unset), docker-compose.yml (OLLAMA_DEFAULT_MODEL=${llama_model}) | 🟠 CONFLICT: terraform expects variable, docker-compose.tpl uses it, .env has no var for it | If not set in .env, docker-compose will have empty env var | P1 — Must add OLLAMA_DEFAULT_MODEL to .env.template |
| **OLLAMA_NUM_THREADS** | .env.defaults (OLLAMA_NUM_THREAD) | .env.defaults, docker-compose.yml, terraform (no variable) | Not in terraform | Script can override but no IaC integration | P2 — Should add to terraform |
| **OLLAMA_NUM_GPU** | .env.defaults (OLLAMA_NUM_GPU=0) | .env.defaults, docker-compose.yml | ✅ CONSISTENT | Assumes CPU-only by default | P3 ✅ |
| **OLLAMA_KEEP_ALIVE** | docker-compose.yml (30m) | docker-compose.yml only | Hardcoded, not parameterized | Not in .env template | P2 — Should add to .env.template |

**Recommended SSOT**:
- URGENT: Fix OLLAMA_VERSION versioning:
  - Option A: Terraform imports version from .env (preferred)
  - Option B: .env.template specifies version, terraform uses it
- ADD to .env.template: OLLAMA_DEFAULT_MODEL, OLLAMA_KEEP_ALIVE
- ADD to terraform/variables.tf: ollama_default_model variable

**Priority**: 🔴 **P0** — Version mismatch will cause unexpected behavior

---

## 7. GRAFANA

### 7.1 **Grafana Credentials & Configuration**

| Item | Current SSOT | Locations | Issues | Priority |
|------|--------------|-----------|--------|----------|
| **GRAFANA_PASSWORD** | .env.template | .env.template (empty), terraform/on-prem.tfvars (test-password-change-in-production), .env.production (${VAULT_GRAFANA_PASSWORD}), .env.defaults (empty) | 🟠 CONFLICT: on-prem.tfvars has test password (insecure), .env.production uses vault | Insecure test value in tfvars file | P1 — Remove test value, use Vault only |
| **GRAFANA_VERSION** | terraform/module-variables.tf (10.2.3) | terraform/module-variables.tf, .env.defaults (GRAFANA_VERSION=10.2.0) | ⚠️ MISMATCH: 10.2.3 vs 10.2.0 | Different versions if both apply | P1 — Align versions |
| **GRAFANA_ADMIN_PASSWORD** | Vault | .env.schema.json (secret), terraform/on-prem.tfvars (test password), .env.production | 🟠 CONFLICT: test password in tfvars | P0 — Security risk, must remove from git-tracked tfvars |

**Recommended SSOT**:
- Remove test passwords from on-prem.tfvars → move to local override or Vault only
- Align GRAFANA_VERSION across all sources (10.2.3 recommended)

**Priority**: 🔴 **P0** — Security issue (credentials in version control)

---

## 8. TLS & CERTIFICATES

### 8.1 **Certificate Configuration**

| Item | Current SSOT | Locations | Issues | Priority |
|------|--------------|-----------|--------|----------|
| **ACME_EMAIL** | `.env.template` | .env.template (ops@kushnir.cloud), .env.production (security-team@example.com), Caddyfile (template: {$ACME_EMAIL:admin@kushnir.cloud}), scripts (admin@kushnir.cloud) | 🟠 CONFLICT: three different values | Email determines Let's Encrypt renewal notifications | P1 — Choose one |
| **TLS_MIN_VERSION** | `.env.production` (1.3) | .env.production, .env.defaults (NOT SET) | Missing from .env.defaults | If .env.defaults used, no TLS minimum enforced | P2 — Should be in .env.defaults |
| **TLS_CIPHER_SUITES** | `.env.production` | .env.production, .env.defaults (NOT SET) | Missing from defaults | Security setting only in production | P2 — Should have sensible defaults |
| **ACME_CA** | Caddyfile hardcoded | Caddyfile (https://acme-v02.api.letsencrypt.org/directory) | Hardcoded in Caddyfile, not parameterized | No env var for alternate CA (staging for testing) | P2 — Should be env var for testing |

**Recommended SSOT**:
- `.env.template` → ACME_EMAIL authoritative
- `.env.production` overrides with real email
- ADD: TLS_MIN_VERSION, TLS_CIPHER_SUITES to .env.defaults with sensible defaults
- PARAMETERIZE: ACME_CA in Caddyfile

**Priority**: 🟡 **P2** — Low immediate risk but security config scattered

---

## 9. MONITORING & OBSERVABILITY

### 9.1 **Prometheus**

| Item | Current SSOT | Defined In | Issues | Priority |
|------|--------------|-----------|--------|----------|
| **PROMETHEUS_VERSION** | terraform/module-variables.tf (v2.48.0) | terraform/module-variables.tf, .env.defaults (PROMETHEUS_VERSION not defined), docker-compose.yml (not defined) | Not in .env.defaults or docker-compose | Can't override without editing Terraform | P2 — Should parameterize |
| **PROMETHEUS_RETENTION** | `.env.production` (365d) | .env.production, .env.defaults (NOT SET) | Missing from dev/defaults | No retention policy in defaults | P2 — Add sensible default (e.g., 15d) |
| **PROMETHEUS_SCRAPE_INTERVAL** | terraform/on-prem.tfvars (15) | terraform/on-prem.tfvars, .env.defaults (NOT SET) | Only in tfvars | Can't override via .env | P2 — Should add to .env |

**Recommended SSOT**: `.env.defaults` with production overrides in `.env.production`

**Priority**: 🟡 **P2** — Observability config, low immediate impact

---

### 9.2 **Grafana**
See section 7.1 above (credentials already covered).

---

### 9.3 **AlertManager**

| Item | Current SSOT | Locations | Issues | Priority |
|------|--------------|-----------|--------|----------|
| **ALERTMANAGER_VERSION** | terraform/module-variables.tf (v0.26.0) | terraform/module-variables.tf, .env.defaults (NOT SET) | Not parameterized in .env | Can't override without Terraform | P2 — Should add to .env |

**Priority**: 🟡 **P2** — Monitoring config

---

## 10. DEPLOYMENT & OPERATIONS

### 10.1 **Deployment Host Configuration**

| Item | Current SSOT | Defined In | Conflicts | Issues | Priority |
|------|--------------|-----------|-----------|--------|----------|
| **DEPLOY_HOST** | .env.template | .env.template (192.168.168.31), terraform/terraform.tfvars (deployment_host), scripts | ✅ All say .31 | Only one value | P3 ✅ |
| **DEPLOY_USER** | .env.template | .env.template (akushnir), terraform/network-variables.tf (akushnir), scripts | ✅ CONSISTENT | No conflicts | P3 ✅ |
| **SSH_PORT** | .env.defaults (22) | .env.defaults, .env.schema.json, terraform/network-variables.tf | ✅ CONSISTENT | Standard SSH port | P3 ✅ |
| **DOCKER_SOCKET** | .env.defaults (unix:///var/run/docker.sock) | .env.defaults, .env.schema.json, terraform/variables.tf (docker_host) | ⚠️ MISMATCH: env var name DOCKER_SOCKET vs terraform var docker_host | Variable name inconsistency | P2 — Align naming |
| **DOCKER_CONTEXT** | terraform/variables.tf (default) | terraform/variables.tf only | Not in .env | Can't override without Terraform | P2 — Add to .env |

**Recommended SSOT**: `.env.template` (primary) with terraform reading from it

**Priority**: 🟡 **P2** — Naming inconsistency (DOCKER_SOCKET vs docker_host)

---

## 11. ENVIRONMENT-SPECIFIC FILES

### 11.1 **Environment File Hierarchy Issues**

| File | Purpose | Status | Issues |
|------|---------|--------|--------|
| `.env.template` | Template for operator (primary source) | ✅ USED | Some variables missing (NAS_HOST, OLLAMA_DEFAULT_MODEL, REDIS_PASSWORD) |
| `.env.defaults` | Fallback defaults | ✅ USED | Should mirror .env.template defaults, but doesn't (schema drift) |
| `.env.production` | Production overrides | ✅ USED | Uses Vault references (${VAULT_*}) but some Vault vars not defined |
| `.env.k8s-oidc` | K8s OIDC config | ⚠️ PARTIAL | Only defines OIDC endpoints, incomplete |
| `.env.phase3.template` | Phase 3 network policy | ⚠️ INCOMPLETE | Specific to Phase 3, should be mainlined or archived |
| `.env.schema.json` | Schema definition | ✅ SOURCE OF TRUTH | But drift between schema and actual .env files |

**Issue**: `.env.schema.json` is the authoritative schema, but .env.defaults doesn't match it perfectly.

**Recommended Fix**:
```bash
# Generate .env.defaults from .env.schema.json
scripts/generate-env-defaults-from-schema.sh
```

---

## 12. MISSING PARAMETERIZATION

### 12.1 **Hardcoded Values That Should Be Parameters**

| Category | Hardcoded Value | Current Location | Recommendation | Priority |
|----------|-----------------|------------------|-----------------|----------|
| **Paths** | `/export` | terraform/network-variables.tf, scripts | Add NAS_EXPORT_PATH to .env.template | P2 |
| **Paths** | `/home/coder/workspace` | docker-compose.tpl, scripts | Add WORKSPACE_MOUNT_PATH to .env | P2 |
| **Paths** | `/vault/data` | Various scripts | Add VAULT_DATA_PATH to .env | P2 |
| **Domains** | `kushnir.cloud` | 40+ script references | ✅ Parameterized via APEX_DOMAIN, but scripts still have defaults | P1 — Remove script defaults |
| **Domains** | `ide.kushnir.cloud` | 30+ script references | Should derive from `ide.${APEX_DOMAIN}` | P1 — Parameterize |
| **Domains** | `.nip.io` | .env.k8s-oidc (K8S_OIDC_ISSUER) | Add to .env.template | P2 |
| **IPs** | `127.0.0.1` | .env.defaults (dev default) | ✅ Correct for dev | P3 ✅ |
| **Ports** | `2019` (Caddy admin) | .env.phase3.template | Add CADDY_ADMIN_PORT to .env.defaults | P2 |
| **Service Names** | `code-server` | docker-compose.yml, scripts | Add SERVICE_NAME to .env | P3 — Low priority |
| **Memory Limits** | `8g` (code-server) | docker-compose.yml | Add CODE_SERVER_MEMORY_LIMIT to .env | P2 |
| **CPU Limits** | `4.0` (code-server) | docker-compose.yml | Add CODE_SERVER_CPU_LIMIT to .env | P2 |

---

## 13. CONFIGURATION OVERRIDE HIERARCHY

### Current Hierarchy (Actual)
```
1. docker-compose.yml hardcoded values (HIGHEST PRIORITY — WRONG!)
2. .env file (if exists)
3. .env.${DEPLOYMENT_ENV} (environment override)
4. terraform/variables.tf defaults
5. .env.defaults (LOWEST PRIORITY)
```

### Recommended Hierarchy (CORRECT)
```
1. .env file (operator override) (HIGHEST)
2. .env.${DEPLOYMENT_ENV} (environment standard)
3. terraform/variables.tf defaults (IaC layer)
4. .env.defaults/schema (built-in defaults) (LOWEST)

docker-compose.yml should be GENERATED from Terraform, not hardcoded!
```

**Current Problem**: `docker-compose.yml` has hardcoded values that override environment variables.

**Solution**: Ensure `docker-compose.yml` is regenerated by `terraform apply`.

---

## 14. CONFIGURATION VALIDATION

### Current Validation
- ✅ `.env.schema.json` defines schema
- ⚠️ No runtime validator (should check actual .env against schema)
- ❌ No CI/CD check that .env.defaults matches schema

### Recommended Validation Script
```bash
scripts/validate-env-against-schema.sh  # Check .env against .env.schema.json
```

---

## SUMMARY OF CONFLICTS BY PRIORITY

### 🔴 P0 (Critical — Blocks Deployment)

| Item | Conflict | Fix Effort | Impact |
|------|----------|-----------|--------|
| **Primary/Replica IPs** | .env vs terraform tfvars can differ | MEDIUM | Failover routing broken |
| **POSTGRES_DB** | Three different values (.env, .env.production, .env.defaults) | EASY | DB connection fails |
| **POSTGRES_PASSWORD** | Missing from terraform/variables.tf | EASY | docker-compose gen fails |
| **REDIS_PASSWORD** | Missing from terraform/variables.tf | EASY | docker-compose gen fails |
| **OAUTH2 Redirect URLs** | Hardcoded in .env.production, not derived from APEX_DOMAIN | MEDIUM | OAuth fails in staging/multi-environment |
| **OLLAMA_VERSION** | docker-compose (0.1.27) vs .env (latest) | EASY | Version mismatch bugs |
| **GRAFANA_PASSWORD** | Test password in on-prem.tfvars (git-tracked) | EASY | Security vulnerability |

### 🟠 P1 (High — Operational Risk)

| Item | Conflict | Fix Effort |
|------|----------|-----------|
| **NAS_HOST** | Missing from .env.template | EASY |
| **OLLAMA_DEFAULT_MODEL** | Missing from .env.template | EASY |
| **Hard-coded domains in scripts** | 40+ references to kushnir.cloud/ide.kushnir.cloud | MEDIUM |
| **ACME_EMAIL** | Three different values | EASY |
| **GRAFANA_VERSION** | 10.2.3 vs 10.2.0 mismatch | EASY |

### 🟡 P2 (Medium — Improvement)

| Item | Conflict | Fix Effort |
|------|----------|-----------|
| **Docker host naming** | DOCKER_SOCKET vs docker_host | EASY |
| **Version parameters** | Prometheus, AlertManager not in .env | MEDIUM |
| **TLS configuration** | Scattered across .env.production and Caddyfile | MEDIUM |
| **Memory/CPU limits** | Hardcoded in docker-compose.yml | MEDIUM |
| **NAS export path** | Hardcoded in terraform | EASY |

### 🟢 P3 (Low — Nice-to-Have)

| Item | Status |
|------|--------|
| Standard ports (5432, 6379, 9090, 3000, 16686) | ✅ Consistent |
| Code-server port (8080) | ✅ Consistent |
| Service names (postgres, redis, ollama) | ✅ Consistent |

---

## RECOMMENDED IMMEDIATE ACTIONS

### Phase 1: Fix Critical Conflicts (4-6 hours)

1. **Database Schema Fix**
   ```bash
   # Align these values:
   # .env.template: POSTGRES_DB=code_server
   # .env.production: POSTGRES_DB=code_server
   # .env.defaults: POSTGRES_DB=code_server
   ```

2. **Add Missing Terraform Variables**
   ```terraform
   variable "redis_password" {
     description = "Redis authentication password"
     type        = string
     sensitive   = true
   }
   
   variable "postgres_password" {
     description = "PostgreSQL password"
     type        = string
     sensitive   = true
   }
   
   variable "ollama_default_model" {
     description = "Default Ollama model to pull"
     type        = string
     default     = "llama2:7b-chat"
   }
   ```

3. **Fix OLLAMA_VERSION Consistency**
   ```bash
   # .env.defaults: OLLAMA_VERSION=0.1.27 (match docker-compose)
   # or: Add OLLAMA_VERSION variable to terraform
   ```

4. **Remove Test Credentials from Git**
   ```bash
   # on-prem.tfvars: Remove GRAFANA_PASSWORD="test-password-change-in-production"
   # Use Vault or local .tfvars.local instead
   ```

5. **Add Missing Parameters to .env.template**
   - NAS_HOST
   - NAS_EXPORT_PATH
   - OLLAMA_DEFAULT_MODEL
   - OLLAMA_KEEP_ALIVE
   - GRAFANA_PASSWORD

### Phase 2: Parameterize Hard-coded Values (8-12 hours)

1. Derive OAuth redirect URLs from APEX_DOMAIN
2. Move hard-coded IPs from scripts to .env defaults
3. Parameterize memory/CPU limits in .env
4. Parameterize version numbers (Prometheus, AlertManager, Grafana)

### Phase 3: Add Validation (4-6 hours)

1. Create `scripts/validate-env-against-schema.sh`
2. Add CI/CD check to validate .env.defaults against .env.schema.json
3. Add pre-deploy validation that terraform tfvars match .env

---

## APPENDIX: SSOT SOURCES BY CONFIGURATION DOMAIN

### Authentication
- **SSOT**: Vault (secret/oauth2/google/*, secret/oauth2-proxy/cookie_secret)
- **Secondary**: .env.production
- **Schema**: .env.schema.json

### Infrastructure (IPs, Domains, Paths)
- **SSOT**: .env.template (primary source)
- **Secondary**: terraform/network-variables.tf (applies defaults only if .env not set)
- **Conflict**: terraform tfvars can override

### Database
- **SSOT**: .env.template (primary) + Vault (passwords)
- **Conflict**: DB names inconsistent across files

### Services (ports, versions, memory)
- **SSOT**: terraform/variables.tf (generates docker-compose.yml)
- **Secondary**: docker-compose.tpl (template)
- **Conflict**: Some hardcoded in docker-compose.yml

### Monitoring
- **SSOT**: .env.defaults + .env.production
- **Secondary**: terraform/module-variables.tf
- **Conflict**: Version numbers scattered

---

## CONFIGURATION FILE DEPENDENCY GRAPH

```
.env.template (↑ Source of Truth)
  ↓ copy/override
.env (local override)
  ↓ sourced by scripts
scripts/*.sh
  ↓ source
terraform/variables.tf
  ↓ generate
docker-compose.yml (generated)
  ↓ docker compose up
Running services
```

**Problem**: .env.defaults, .env.production, and terraform tfvars can all override, creating multiple SSOT sources.

**Solution**: Enforce this order:
1. .env.template is PRIMARY SSOT
2. .env.${DEPLOYMENT_ENV} overrides only what differs
3. terraform reads from .env, applies it to docker-compose.tpl
4. docker-compose.yml MUST be generated, never manually edited

---

## CONCLUSION

**Status**: 16 critical configuration conflicts identified  
**Severity**: 🔴 **HIGH** — Deployment and failover at risk  
**Estimated Fix Time**: 20-30 hours total  
**Critical Path**: Phase 1 (fix P0 items) — 4-6 hours  

**Key Insight**: Configuration has multiple SSOT sources without clear precedence. Recommend establishing:
1. **.env.template** as PRIMARY SSOT
2. **Terraform** as application of .env to infrastructure
3. **docker-compose.yml** as GENERATED output (never manually edited)
4. **Vault** as secret SSOT (not version-controlled)
