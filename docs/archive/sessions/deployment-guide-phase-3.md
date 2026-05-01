# Deployment Guide - Phase 3 Environment Variable Consolidation

## Quick Start: Using Consolidated Environment Variables

### For Local Development

```bash
# Load development environment (defaults to private)
export ENVIRONMENT=private
source scripts/_common/init.sh

# Now use any variable
echo "Deploying to: $API_HOST"
echo "Domain: $APEX_DOMAIN"
```

### For Air-Gapped Deployment

```bash
# Load air-gapped environment configuration
export ENVIRONMENT=air-gapped
source scripts/_common/init.sh

# Variables are now set for internal deployment
echo "Internal registry: $REGISTRY_URL"
echo "Internal domain: $APEX_DOMAIN"
```

### For CI/CD Pipelines

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy Private Environment
        env:
          ENVIRONMENT: private
        run: |
          source scripts/_common/init.sh
          terraform plan \
            -var-file=../_common/terraform.tfvars \
            -var-file=terraform.tfvars
          docker-compose -f docker-compose.enterprise.yml up -d
      
      - name: Deploy Air-Gapped Environment
        env:
          ENVIRONMENT: air-gapped
        run: |
          source scripts/_common/init.sh
          terraform plan \
            -var-file=../_common/terraform.tfvars \
            -var-file=terraform.tfvars
          docker-compose -f docker-compose.enterprise.yml up -d
```

## Understanding Environment Variable Resolution

### Variable Hierarchy

```
┌─────────────────────────────────────────────┐
│ .env/_common/defaults                       │
│ (41 shared variables - SSOT)                │
└──────────────┬──────────────────────────────┘
               │
               ├─ ENVIRONMENT=private
               │  └─ Load .env/private/overrides
               │
               ├─ ENVIRONMENT=air-gapped
               │  └─ Load .env/air-gapped/overrides
               │
               └─ (default - use SSOT values only)
```

### Key Variables

**Domain Configuration (SSOT):**
- `APEX_DOMAIN` - Primary domain (source of truth)
- Derived: `AUTH_DOMAIN`, `API_DOMAIN`, `REGISTRY_DOMAIN`, etc.

**Infrastructure (Environment-Specific):**
- `PRIMARY_HOST` - Changes per environment
- `API_HOST` - Changes per environment
- `REGISTRY_URL` - Changes per environment

**Credentials (Environment-Specific):**
- `DB_PASSWORD` - Stored in environment overrides
- `REDIS_PASSWORD` - Stored in environment overrides
- Never stored in `.env/_common/defaults`

## Deployment Procedures

### Private Deployment

```bash
# 1. Set environment
export ENVIRONMENT=private

# 2. Run deployment (sources .env automatically)
bash scripts/ops/deploy-enterprise-idempotent.sh

# 3. Verify
curl http://192.168.168.31:8080/health
```

### Air-Gapped Deployment

```bash
# 1. Set environment
export ENVIRONMENT=air-gapped

# 2. Ensure local registry is available
# (registry.internal:5000 must be accessible)

# 3. Run deployment
bash scripts/ops/deploy-enterprise-idempotent.sh

# 4. Verify
curl https://internal.local:8443/health
```

### CI/CD Integration

All deployment scripts automatically load the correct environment when `ENVIRONMENT` is set:

```bash
# GitHub Actions
- name: Deploy
  env:
    ENVIRONMENT: private
  run: bash scripts/ops/deploy-enterprise-idempotent.sh

# GitLab CI
deploy:
  variables:
    ENVIRONMENT: private
  script:
    - bash scripts/ops/deploy-enterprise-idempotent.sh
```

## Adding New Environment Variables

### 1. For Shared Variables (used in all environments)

Edit `.env/_common/defaults`:
```bash
export NEW_VAR=${NEW_VAR:-default_value}
```

### 2. For Environment-Specific Variables

Edit `.env/private/overrides` or `.env/air-gapped/overrides`:
```bash
export NEW_VAR=environment_specific_value
```

### 3. Test

```bash
export ENVIRONMENT=private
source .env/_common/defaults
source .env/private/overrides
echo $NEW_VAR
```

## Troubleshooting

### Variables Not Loading

```bash
# Check if .env files exist
ls -la .env/_common/defaults .env/private/overrides

# Test loading manually
ENVIRONMENT=private
source .env/_common/defaults
source .env/private/overrides
env | grep APEX_DOMAIN
```

### Wrong Environment Loaded

```bash
# Check ENVIRONMENT variable
echo $ENVIRONMENT

# Should be: private, air-gapped, or unset (default)
# If unset, will use SSOT values only
```

### Missing Credentials

```bash
# Verify credentials are in environment overrides
grep DB_PASSWORD .env/private/overrides
grep REDIS_PASSWORD .env/air-gapped/overrides

# Credentials should NEVER be in .env/_common/defaults
```

## Migration from Legacy .env Files

### Old Structure (Legacy)
```
.env.base
.env.production
.env.cluster
.env.deployment
```

### New Structure (Phase 3)
```
.env/_common/defaults        # Replaces .env.base
.env/private/overrides       # Replaces .env.production + .env.cluster
.env/air-gapped/overrides    # New for air-gapped environments
```

### Migration Checklist

- ✅ All deployment scripts updated to use `scripts/_common/init.sh`
- ✅ CI/CD pipelines passing `ENVIRONMENT` variable
- ✅ Environment variables verified in both deployments
- ✅ Legacy .env.base archived
- ⏳ Legacy .env.production/cluster scheduled for deprecation

## Phase 3 Features

- ✅ Single Source of Truth (SSOT) for 41 environment variables
- ✅ Automatic environment loading via `scripts/_common/init.sh`
- ✅ Clear separation: shared vs environment-specific values
- ✅ Support for multiple environments (private, air-gapped, future)
- ✅ Backward compatibility with legacy scripts
- ✅ Tested and verified for both deployments

---

**For detailed information:** See `.env/_common/README.md`  
**For configuration details:** See `IaC_CONSOLIDATION_COMPLETE.md`  
**For phase status:** See `PHASE_3_COMPLETION_FINAL.md`
