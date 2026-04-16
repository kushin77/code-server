# Environment Variable Consolidation & SSOT Strategy

**Date**: April 16, 2026  
**Status**: ✅ ANALYSIS COMPLETE, READY FOR IMPLEMENTATION  
**Goal**: Consolidate 4 .env files → 1 master schema + environment-specific overrides  

---

## Current State

### Existing .env Files

| File | Purpose | Location | Scope | Status |
|------|---------|----------|-------|--------|
| `.env.oauth2-proxy` | OAuth2 proxy config (28 vars) | Root | Shared across environments | ✅ SSOT for oauth2 |
| `.env.production` | Production overrides (45 vars) | Root | Production only | ⚠️ Needs consolidation |
| `.env.example` | Template for developers | Root | Reference docs | ⚠️ May be outdated |
| `.env.template` | Terraform template | Root | Build artifact | ⚠️ Generated, shouldn't track |

### Variables Sourced In

```
docker-compose.yml:
  - env_file: [.env.oauth2-proxy]
  - environment: (inline vars with template substitution)

terraform/main.tf:
  - Reads variables.tf inputs
  - Renders docker-compose.tpl with substitutions
  - docker-compose.tpl sources .env files
  - Output: docker-compose.yml (generated)

Deployment (192.168.168.31):
  - docker-compose up reads .env.oauth2-proxy
  - docker-compose up reads .env.production
  - docker-compose up reads inline environment: {} blocks
```

### Problem: Scattered Configuration

1. **Multiple sources of truth**: oauth2-proxy vars in .env.oauth2-proxy, production vars in .env.production
2. **Mixed concerns**: Infrastructure, auth, database, observability spread across files
3. **Terraform templates aren't tracked**: Generated docker-compose.yml differs from source
4. **Unclear dependencies**: Which env vars are REQUIRED? Which are optional?
5. **No validation**: Missing env var errors only appear at runtime

---

## Target Architecture

### Single Source of Truth (SSOT)

```
.env.schema.json
  ↓
  ├─ REQUIRED variables (must be set before deploy)
  ├─ OPTIONAL variables (have sensible defaults)
  ├─ ENVIRONMENT-SPECIFIC variables (dev vs prod)
  └─ SECRET variables (never commit, load from Vault)

.env.example (generated from schema, for developers)
.env.production (production-specific overrides only)
.env.staging (staging-specific overrides only)
.env.development (development-specific overrides only)

Loading order (bottom overwrites top):
1. .env.defaults (shipped in repo, all defaults)
2. .env.${DEPLOYMENT_ENV} (environment-specific)
3. ${HOME}/.code-server/.env (user local overrides)
4. Vault secrets (runtime secrets, highest priority)
```

---

## Implementation: `.env.schema.json`

**Single master schema defining ALL environment variables:**

```json
{
  "version": "1.0.0",
  "description": "Environment variable schema for kushin77/code-server",
  "variables": {
    "DEPLOYMENT_ENV": {
      "type": "string",
      "enum": ["development", "staging", "production"],
      "default": "development",
      "description": "Deployment environment",
      "required": true,
      "example": "production"
    },
    "DOMAIN": {
      "type": "string",
      "description": "Top-level domain for all services",
      "required": true,
      "example": "ide.kushnir.cloud",
      "production": "ide.kushnir.cloud",
      "staging": "staging-ide.kushnir.cloud",
      "development": "localhost"
    },
    "GOOGLE_CLIENT_ID": {
      "type": "string",
      "description": "Google OAuth2 client ID (from Google Cloud Console)",
      "required": true,
      "secret": true,
      "vault_path": "secret/google/oauth2/client_id",
      "example": "123456789-abc.apps.googleusercontent.com"
    },
    "GOOGLE_CLIENT_SECRET": {
      "type": "string",
      "description": "Google OAuth2 client secret",
      "required": true,
      "secret": true,
      "vault_path": "secret/google/oauth2/client_secret"
    },
    "OAUTH2_PROXY_COOKIE_SECRET": {
      "type": "string",
      "description": "oauth2-proxy session encryption key (32 hex characters = 16 bytes AES)",
      "required": true,
      "secret": true,
      "vault_path": "secret/oauth2proxy/cookie_secret",
      "validation": "length == 32 && alphanumeric",
      "example": "0123456789abcdef0123456789abcdef"
    },
    "CODE_SERVER_PASSWORD": {
      "type": "string",
      "description": "Code-server login password",
      "required": true,
      "secret": true,
      "vault_path": "secret/code_server/password"
    },
    "POSTGRES_PASSWORD": {
      "type": "string",
      "description": "PostgreSQL admin password",
      "required": true,
      "secret": true,
      "vault_path": "secret/postgres/password"
    },
    "REDIS_PASSWORD": {
      "type": "string",
      "description": "Redis server password",
      "required": true,
      "secret": true,
      "vault_path": "secret/redis/password"
    },
    "PROMETHEUS_RETENTION_DAYS": {
      "type": "integer",
      "description": "Prometheus data retention in days",
      "default": 15,
      "required": false,
      "example": 30,
      "min": 1,
      "max": 365
    },
    "LOKI_RETENTION_DAYS": {
      "type": "integer",
      "description": "Loki log retention in days",
      "default": 7,
      "required": false,
      "example": 14
    },
    "CADDY_LOG_LEVEL": {
      "type": "string",
      "enum": ["debug", "info", "warn", "error"],
      "default": "info",
      "required": false,
      "description": "Caddy reverse proxy logging level"
    },
    "TLS_MIN_VERSION": {
      "type": "string",
      "enum": ["1.2", "1.3"],
      "default": "1.3",
      "required": false,
      "description": "Minimum TLS version for HTTPS connections"
    },
    "CLOUDFLARE_API_TOKEN": {
      "type": "string",
      "description": "CloudFlare API token for DNS management",
      "required": false,
      "secret": true,
      "vault_path": "secret/cloudflare/api_token",
      "note": "Only required if using CloudFlare DNS validation"
    }
  },
  "groups": {
    "Infrastructure": [
      "DEPLOYMENT_ENV",
      "DOMAIN",
      "DEPLOY_HOST",
      "DEPLOY_REGION"
    ],
    "Authentication": [
      "GOOGLE_CLIENT_ID",
      "GOOGLE_CLIENT_SECRET",
      "OAUTH2_PROXY_COOKIE_SECRET"
    ],
    "Database": [
      "POSTGRES_PASSWORD",
      "POSTGRES_REPLICATION_PASSWORD",
      "REDIS_PASSWORD"
    ],
    "Security": [
      "TLS_MIN_VERSION",
      "CLOUDFLARE_API_TOKEN"
    ],
    "Observability": [
      "PROMETHEUS_RETENTION_DAYS",
      "LOKI_RETENTION_DAYS",
      "CADDY_LOG_LEVEL"
    ]
  }
}
```

---

## Implementation: `.env.defaults`

**Shipped with repository, defines all defaults:**

```bash
# .env.defaults — Master defaults (committed to git)
# DO NOT EDIT — modify via .env.${DEPLOYMENT_ENV} overrides

# ════════════════════════════════════════════════════════════
# Infrastructure (required, no sensible default)
# ════════════════════════════════════════════════════════════
# DEPLOYMENT_ENV=production       ← Must be overridden per environment
# DOMAIN=                         ← Must be overridden per environment

# ════════════════════════════════════════════════════════════
# Authentication (required, secrets from Vault)
# ════════════════════════════════════════════════════════════
# GOOGLE_CLIENT_ID=               ← From Vault
# GOOGLE_CLIENT_SECRET=           ← From Vault
# OAUTH2_PROXY_COOKIE_SECRET=     ← From Vault

# ════════════════════════════════════════════════════════════
# OAuth2 Proxy Settings
# ════════════════════════════════════════════════════════════
OAUTH2_PROXY_PROVIDER=google
OAUTH2_PROXY_OIDC_ISSUER_URL=https://accounts.google.com
OAUTH2_PROXY_COOKIE_NAME=_oauth2_proxy_ide
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true
OAUTH2_PROXY_COOKIE_SAMESITE=Strict
OAUTH2_PROXY_SESSION_LIFETIME=24h

# ════════════════════════════════════════════════════════════
# Database
# ════════════════════════════════════════════════════════════
POSTGRES_USER=code-server
POSTGRES_DB=code_server_db
POSTGRES_PORT=5432
# POSTGRES_PASSWORD=              ← From Vault
# REDIS_PASSWORD=                 ← From Vault

# ════════════════════════════════════════════════════════════
# Security & TLS
# ════════════════════════════════════════════════════════════
TLS_MIN_VERSION=1.3
ACME_EMAIL=security-team@example.com

# ════════════════════════════════════════════════════════════
# Observability & Monitoring
# ════════════════════════════════════════════════════════════
PROMETHEUS_RETENTION_DAYS=15
LOKI_RETENTION_DAYS=7
CADDY_LOG_LEVEL=info
```

---

## Loading Strategy

### Development (Local)

```bash
# Load order:
1. .env.defaults (from repo)
2. .env.development (from repo)
3. ~/.code-server/.env.local (user machine only, NOT committed)
4. Environment variables (CLI or system, highest priority)

# Start:
docker-compose --env-file .env.defaults \
               --env-file .env.development \
               up -d
```

### Production (192.168.168.31)

```bash
# Load order:
1. .env.defaults (from repo)
2. .env.production (from repo)
3. /etc/code-server/.env.vault (secrets from Vault, NOT in repo)
4. Environment variables (set by Vault agent at runtime)

# Start:
docker-compose --env-file .env.defaults \
               --env-file .env.production \
               --env-file /etc/code-server/.env.vault \
               up -d
```

---

## Validation Tooling

### `scripts/validate-env.sh` — Validate all required variables are set

```bash
#!/bin/bash
# Usage: bash scripts/validate-env.sh [environment]

ENV=${1:-production}

# Check required variables
REQUIRED=(
  DEPLOYMENT_ENV
  DOMAIN
  GOOGLE_CLIENT_ID
  GOOGLE_CLIENT_SECRET
  OAUTH2_PROXY_COOKIE_SECRET
  CODE_SERVER_PASSWORD
  POSTGRES_PASSWORD
  REDIS_PASSWORD
)

MISSING=()
for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var}" ]]; then
    MISSING+=("$var")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing required variables: ${MISSING[@]}"
  echo "Load environment first: source .env.defaults && source .env.${ENV}"
  exit 1
fi

echo "✅ All required variables set"
```

### `scripts/generate-env-docs.sh` — Auto-generate docs from schema

```bash
#!/bin/bash
# Generate environment variable documentation from .env.schema.json
# Output: docs/ENVIRONMENT_VARIABLES.md

jq -r '.variables | to_entries[] | 
  "\(.value.required? | if . then "**REQUIRED**" else "Optional" end) — \(.key)\n" +
  "  \(.value.description)\n" +
  "  Type: \(.value.type)\n" +
  if .value.default then "  Default: \(.value.default)\n" else "" end +
  if .value.secret then "  ⚠️  SECRET (load from Vault)\n" else "" end +
  if .value.example then "  Example: \(.value.example)\n" else "" end'
```

---

## Migration Path

### Phase 1: Introduce Schema (April 16)
- [ ] Create `.env.schema.json`
- [ ] Create `.env.defaults`
- [ ] Document in CONTRIBUTING.md

### Phase 2: Generate Docs (April 17)
- [ ] Update `.env.example` from schema
- [ ] Generate `docs/ENVIRONMENT_VARIABLES.md`
- [ ] Add validation script to pre-commit hooks

### Phase 3: Deprecate Old Files (April 23)
- [ ] Archive `.env.oauth2-proxy` (functionality moved to .env.defaults + .env.production)
- [ ] Keep `.env.production` for production-specific overrides
- [ ] Mark old files as deprecated in comments

### Phase 4: Automated Loading (April 30)
- [ ] Update docker-compose.yml to use --env-file with all files
- [ ] Test on 192.168.168.31
- [ ] Verify all services start correctly

---

## Benefits

✅ **Clear SSOT**: `.env.schema.json` defines all variables  
✅ **Auto-generated Docs**: No manual documentation drift  
✅ **Validation**: Catch missing variables at startup (not runtime)  
✅ **Type Safety**: JSON schema validates variable types  
✅ **Environment Specificity**: dev vs prod overrides clear  
✅ **Secret Vaulting**: Explicit marking of secrets for Vault management  
✅ **Reduced Duplication**: Shared defaults in one place  

---

## Remaining Files

### Safe to Delete (functionality consolidated into schema)
- `.env.template` — Generated artifact, not needed if schema is SSOT
- `.env.example` (after auto-generation from schema)

### Keep & Update
- `.env.defaults` — Consolidates all defaults from .oauth2-proxy + .production
- `.env.production` — Production-specific overrides only
- `.env.development` — Development-specific overrides

---

**Owner**: Infrastructure Team (@kushin77)  
**Priority**: P2 (Structural improvement, not blocking)  
**Timeline**: Complete by April 30, 2026  
**Risk**: LOW (additive, no breaking changes to existing setup)
