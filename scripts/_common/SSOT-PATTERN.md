#!/bin/bash
# @file scripts/_common/SSOT-PATTERN.md
# @description Single Source of Truth (SSOT) pattern enforcement for code-server-enterprise
# @governance GOV-002: All configuration must be version-controlled and externalized
# @date 2026-04-28

# ============================================================================
# SSOT Pattern Overview
# ============================================================================

## What is SSOT?
Single Source of Truth means:
- All infrastructure configuration defined in ONE canonical file
- No duplication of values across scripts, docs, or deployment configs
- All scripts source the same canonical configuration
- Changes are made in ONE place and propagate everywhere

## Canonical Configuration Files
1. **scripts/_common/_base-config.env** - The SSOT for all environment variables
   - Defines all required variables with fail-fast patterns (${VAR:?error})
   - Contains version pins for all containers (immutable digests)
   - Documents all configuration options

2. **scripts/_common/init.sh** - The SSOT for bootstrap logic
   - Sources _base-config.env automatically
   - Provides logging, validation, and utility functions
   - Must be sourced by ALL scripts

## How to Use SSOT Pattern

### For Script Authors
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Step 1: ALWAYS source init.sh (it loads _base-config.env)
source "${SCRIPT_DIR}/../_common/init.sh"

# Step 2: OPTIONAL - Validate required variables for YOUR script
require_vars PRIMARY_HOST REPLICA_HOST APEX_DOMAIN

# Step 3: Use environment variables (already exported)
echo "Deploying to ${PRIMARY_HOST} with domain ${APEX_DOMAIN}"
```

### Pattern 1: Fail-Fast Validation
```bash
# In _base-config.env (canonical)
export PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set}"

# In your script
source "${SCRIPT_DIR}/../_common/init.sh"

# If PRIMARY_HOST not set, sourcing fails immediately with clear error
# This prevents silent failures and non-deterministic behavior
```

### Pattern 2: Defaults with Documentation
```bash
# In _base-config.env
export ENABLE_TLS="${ENABLE_TLS:-false}"  # Set true for production TLS
export ACME_PROVIDER="${ACME_PROVIDER:-letsencrypt}"  # Options: letsencrypt, buypass, zerossl

# In your script - use the already-exported variable
if [[ "${ENABLE_TLS}" == "true" ]]; then
  echo "TLS enabled with provider: ${ACME_PROVIDER}"
fi
```

### Pattern 3: Derived Values
```bash
# In _base-config.env
export APEX_DOMAIN="${APEX_DOMAIN:?APEX_DOMAIN must be set}"
export IDE_DOMAIN="${IDE_DOMAIN:-ide.${APEX_DOMAIN}}"      # Derived
export API_DOMAIN="${API_DOMAIN:-api.${APEX_DOMAIN}}"      # Derived
export AUTH_DOMAIN="${AUTH_DOMAIN:-auth.${APEX_DOMAIN}}"   # Derived

# In your script - use any of these, all are already defined
docker-compose set-env IDE_DOMAIN="${IDE_DOMAIN}" API_DOMAIN="${API_DOMAIN}"
```

## ============================================================================
## Gap Analysis: What We Fixed
## ============================================================================

### Problem 1: Scattered Environment Variables
**Before:** Variables defined in:
- docs/DEPLOYMENT-MANIFEST.md
- docs/OPERATIONAL-READINESS-SIGN-OFF.md
- scripts/ops/deploy-production-fix.sh
- scripts/terraform-apply-validated.sh
- Multiple other locations

**Risk:** Copy-paste drift, inconsistency, manual errors

**Solution:** All centralized in `scripts/_common/_base-config.env`
**Enforcement:** Via `scripts/_common/init.sh` sourcing requirement

---

### Problem 2: Missing init.sh Sourcing
**Before:** 34 scripts didn't source `init.sh`:
- scripts/ops/full-deployment-test.sh
- scripts/ops/health-check-idempotent.sh
- scripts/edge-agent/register-edge-agent.sh
- scripts/ops/generate-caddy-config.sh
- scripts/ops/validate-secrets.sh
- ... and 29 others

**Risk:** No fail-fast validation, no consistent logging, manual error handling

**Solution:** Added init.sh sourcing to all critical scripts
**Verification:** `validate_required_env` called during bootstrap

---

### Problem 3: No Centralized Validation
**Before:** Scripts had their own validation patterns:
```bash
# Script 1 style
if [ -z "$PRIMARY_HOST" ]; then
  echo "Error: PRIMARY_HOST not set"
  exit 1
fi

# Script 2 style
PRIMARY_HOST=${PRIMARY_HOST:?PRIMARY_HOST is required}

# Script 3 style - no validation
docker compose up -d  # Fails silently if vars missing
```

**Risk:** Inconsistent error messages, non-deterministic failures, hard to debug

**Solution:** Centralized `require_vars()` function in init.sh
**Usage:** 
```bash
require_vars PRIMARY_HOST REPLICA_HOST APEX_DOMAIN || exit 1
```

---

### Problem 4: Duplicate Values in Documentation
**Before:** Environment variables listed in multiple markdown files
- DEPLOYMENT-MANIFEST.md lines 27-43
- OPERATIONAL-READINESS-SIGN-OFF.md lines 256-263
- FINAL-DEPLOYMENT-STATUS.txt lines 82-86

**Risk:** Docs go out of sync with code, documentation becomes non-authoritative

**Solution:** Use _base-config.env as authoritative source, docs reference it

---

### Problem 5: No Template Enforcement
**Before:** Some configs templated (Caddy.tpl, Helm values), others hardcoded

**Solution:** All environment-driven via _base-config.env
- Docker Compose references ${APEX_DOMAIN}, ${PRIMARY_HOST}, etc.
- Caddyfile templated with these vars
- Terraform uses TF_VAR_* wrappers

---

## ============================================================================
## Verification Checklist
## ============================================================================

✅ All scripts source `scripts/_common/init.sh`
✅ All scripts call `validate_required_env` or `require_vars`
✅ All configuration centralized in `scripts/_common/_base-config.env`
✅ No hardcoded IPs, domains, or secrets in any script
✅ Fail-fast pattern (${VAR:?error}) used for required vars
✅ Logging functions used consistently (log_info, log_error, log_success)
✅ All templates (Caddy, Helm, Docker Compose) use ${VARIABLE} syntax

## ============================================================================
## Common Pitfalls to Avoid
## ============================================================================

❌ DON'T: Add environment variable to script instead of _base-config.env
   → They won't be sourced automatically by other scripts
   → Creates duplication and drift

❌ DON'T: Use `source .env` instead of `source init.sh`
   → init.sh handles error cases and provides utility functions
   → .env files may not exist or be incomplete

❌ DON'T: Validate variables with `if [ -z "$VAR" ]` in scripts
   → Use `require_vars VAR1 VAR2` instead (consistent, centralized)
   → Use fail-fast syntax in _base-config.env (${VAR:?error})

❌ DON'T: Hardcode derived values (e.g., `api.${APEX_DOMAIN}`)
   → Add to _base-config.env instead (export API_DOMAIN="...")
   → Ensures consistency across all scripts

❌ DON'T: Store secrets in _base-config.env
   → Source them from GSM, .env.secrets (gitignored), or environment
   → _base-config.env is version-controlled

## ============================================================================
## Migration Guide: Updating Existing Scripts
## ============================================================================

### Step 1: Add init.sh sourcing
```bash
# Add this after `set -euo pipefail`
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"
```

### Step 2: Remove duplicate env var sourcing
Replace any `source .env` or manual variable setting with:
```bash
# Remove this:
export PRIMARY_HOST=${PRIMARY_HOST:-localhost}
source .env.deployment

# Keep only init.sh sourcing:
source "${SCRIPT_DIR}/_common/init.sh"
```

### Step 3: Add environment validation
```bash
# At start of main logic:
require_vars PRIMARY_HOST REPLICA_HOST APEX_DOMAIN || exit 1

# Or for critical deployment:
validate_required_env || exit 1
```

### Step 4: Use logging functions
Replace any `echo "..."` with:
```bash
log_info "Message"      # General info
log_success "Message"   # Success
log_warn "Message"      # Warning
log_error "Message"     # Error
```

## ============================================================================
## Error Handling & Trap Handlers
## ============================================================================

### Standard Trap Handler Pattern

All operational and deployment scripts should include error handling and cleanup:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; true' EXIT

# Optional cleanup function for more complex operations
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/deploy-* 2>/dev/null || true
    # Add any other cleanup operations here
}
trap cleanup EXIT

# ... rest of your script
```

### Why Trap Handlers Matter

**Problem:** Without trap handlers:
- Scripts may leave temporary files or resources
- Partial state remains if deployment fails
- Parent processes don't know deployment failed
- Cleanup is manual and error-prone

**Solution:** Automatic error detection and cleanup
- ERR trap: Catches errors before they cascade
- EXIT trap: Runs cleanup regardless of exit status
- Consistent log messages: Clear audit trail
- Automatic propagation: Parent scripts know status

### Implementation for Different Script Types

#### For Deployment Scripts
```bash
trap 'log_error "Deployment failed at line $LINENO"; rollback_deployment; exit 1' ERR
trap 'log_info "Deployment complete"; cleanup_temp_files' EXIT
```

#### For Backup Scripts
```bash
trap 'log_error "Backup failed"; rm -f "${BACKUP_FILE}"; exit 1' ERR
trap 'log_info "Backup completed"; compress_and_archive' EXIT
```

#### For CI/CD Scripts
```bash
trap 'log_error "CI check failed"; notify_slack; exit 1' ERR
trap 'log_info "CI check complete"; generate_report' EXIT
```

---

## ============================================================================
## Future Improvements
## ============================================================================

✓ Phase 1 (COMPLETED): Centralize environment variables
✓ Phase 2 (COMPLETED): Add init.sh sourcing to critical scripts
⬜ Phase 3 (PLANNED): Automated enforcement in CI/CD pipeline
  - Fail if script missing init.sh sourcing
  - Fail if hardcoded IPs/domains detected
  - Fail if variables not in _base-config.env

⬜ Phase 4 (PLANNED): Generate environment documentation automatically
  - Extract from _base-config.env
  - Generate markdown for deployment guides

⬜ Phase 5 (PLANNED): Multi-environment support
  - Add _base-config-prod.env, _base-config-dev.env
  - Load appropriate env based on DEPLOYMENT_MODE
