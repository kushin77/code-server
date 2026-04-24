# P2-1695: OPS Scripts Hardening & Governance Compliance

**Issue**: #1695 - Automated hardening of ops scripts for cluster parity  
**Status**: In Progress  
**Date**: April 24, 2026  

## Summary

Comprehensive GOV-002 compliance standards and hardening for all operational scripts in `scripts/ops/`. This ensures IaC (Infrastructure as Code), immutable, and idempotent patterns across cluster deployment automation.

## Governance Standards (GOV-002)

All operational scripts MUST follow these standards:

### 1. Metadata Headers (REQUIRED)

Every bash script must start with:
```bash
#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/<filename>.sh
# @module      ops/<category>
# @description <one-line purpose>
# @owner       platform
# @status      active
#
# USAGE
#   bash scripts/ops/<filename>.sh [OPTIONS]
#
# OPTIONS
#   Description of command-line options
#
# EXIT CODES
#   0 - Success
#   1 - General failure
#   2 - Configuration error
#
################################################################################
```

**Verification**: Check for `@file`, `@module`, `@description` on lines 2-4.

### 2. Canonical Initialization (REQUIRED)

Every script must initialize via the shared library:
```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"
```

**Why**: Ensures consistent error handling, logging, and configuration loading across all scripts.

**Location**: Must appear after metadata headers and before main logic.

### 3. Configuration Separation (REQUIRED)

- **Infrastructure config**: Use environment variables from `scripts/_common/_base-config.env`
  - Example: `$DEPLOY_HOST`, `$REPLICA_1_IP`, `$REPLICA_2_IP`, `$SSH_USER`
  - Loaded globally via `source scripts/_common/config.sh`
- **Logic config**: Use function parameters or local variables
  - Example: function argument `$1`, timeout `TIMEOUT=30`

**Violation Example**:
```bash
# ❌ WRONG - Hardcoded IP
REPLICA_IP="192.168.168.31"

# ✅ CORRECT - Environment variable
REPLICA_IP="${REPLICA_1_IP}"  # Loaded from config.sh
```

### 4. Logging via Canonical Functions (REQUIRED)

Use ONLY these logging functions from `scripts/_common/logging.sh`:
```bash
log_info "Message"       # Informational
log_warn "Message"       # Warning
log_error "Message"      # Error (non-fatal)
log_fatal "Message"      # Error (fatal, exits)
log_debug "Message"      # Debug (if DEBUG=1)
```

**Violations**:
- ❌ `echo "ERROR: ..."`
- ❌ `echo "INFO: ..."`
- ❌ Custom `die()`, `write_error()` functions
- ❌ `printf`, `>&2`, raw stderr redirection

### 5. Error Handling Patterns (REQUIRED)

Every script must have robust error handling:
```bash
set -euo pipefail                    # Exit on error, undefined vars, pipe failures
trap 'log_fatal "Script failed"' ERR # Catch errors
trap 'cleanup' EXIT                  # Cleanup on exit
```

**Verification**: Check for `set -euo pipefail` and `trap` statements.

### 6. No Hardcoded Values (IMMUTABILITY)

**Violations**:
- ❌ IP addresses: `192.168.168.31`, `10.0.0.1`
- ❌ Domain names: `kushnir.cloud`, `ide.kushnir.cloud`
- ❌ API keys, tokens, credentials
- ❌ Absolute file paths (except `/bin`, `/usr`, `/etc`)
- ❌ Service ports (except well-known: 80, 443, 22)

**Correct Approach**:
```bash
# Load from environment/config
REPLICA_1_IP="${REPLICA_1_IP:?REPLICA_1_IP not set}"
APEX_DOMAIN="${APEX_DOMAIN:?APEX_DOMAIN not set}"
API_KEY=$(load_secret "api_key_gsm" || log_fatal "Missing API key")
```

### 7. Linux-Native Only (NON-NEGOTIABLE)

**Prohibited**:
- ❌ PowerShell syntax (`.ps1` files, `pwsh` calls)
- ❌ Windows paths (`C:\`, `%APPDATA%`, `$LOCALAPPDATA`)
- ❌ Windows executables (`.exe`, `.bat`, `.cmd`)
- ❌ WSL paths (`/mnt/c/`)
- ❌ macOS-specific code (`$HOME/Library`, `darwin` checks)

**Required**:
- ✅ `#!/usr/bin/env bash` shebang
- ✅ Linux standard paths (`/home`, `/opt`, `/var`, `/etc`)
- ✅ Standard utilities: `bash`, `python3`, `curl`, `git`, `docker`, `ssh`, `jq`
- ✅ `/bin/bash` hardcoded in Node.js `spawn()` calls

### 8. Idempotent Operations Only

All scripts must be safe to run multiple times without side effects:

**Violations**:
- ❌ `rm -rf` (destructive)
- ❌ `DROP TABLE` (destructive)
- ❌ `force-push` to git
- ❌ `--no-cache` Docker builds with new pins
- ❌ Database migrations without rollback

**Correct Patterns**:
```bash
# ✅ Idempotent delete with backup
backup_file "$config_file"
rm -f "$config_file"

# ✅ Idempotent update with check
if ! grep -q "pattern" "$file"; then
    echo "pattern" >> "$file"
fi

# ✅ Idempotent docker-compose (no volume destruction)
docker-compose up -d  # Safe - doesn't delete volumes
# ✅ NOT this: docker-compose down -v  # Would delete volumes
```

### 9. Shared Library Adoption

**MANDATORY USAGE**:

| Library | Location | Functions |
|---------|----------|-----------|
| Init | `scripts/_common/init.sh` | Sets SCRIPT_DIR, sources logging, config |
| Logging | `scripts/_common/logging.sh` | `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_debug` |
| Config | `scripts/_common/config.sh` | `load_env <file>`, `export_vars <vars>` |
| Utils | `scripts/_common/utils.sh` | `retry`, `confirm`, `die`, `validate_*` |

**Usage**:
```bash
source "$REPO_ROOT/scripts/_common/init.sh"  # Sources all dependencies
```

## Compliance Checklist

For every new/modified ops script:

- [ ] **Headers**: @file, @module, @description present
- [ ] **Shebang**: `#!/usr/bin/env bash`
- [ ] **Initialization**: `source "$REPO_ROOT/scripts/_common/init.sh"`
- [ ] **Error Handling**: `set -euo pipefail`, `trap` statements
- [ ] **Logging**: Uses `log_*` functions only (no `echo` for errors)
- [ ] **No Hardcoding**: All config via env vars or parameters
- [ ] **Linux-Native**: No Windows/PowerShell/WSL artifacts
- [ ] **Idempotent**: Safe to run multiple times
- [ ] **Shared Libraries**: Uses canonical locations (no duplication)
- [ ] **Documentation**: USAGE section with examples

## Non-Compliant Patterns to Fix

### Pattern 1: Missing Metadata Headers
```bash
# ❌ WRONG
#!/usr/bin/env bash
set -e
# ... rest of script
```

Fix: Add GOV-002 headers before `set -e`.

### Pattern 2: Direct Initialization (not via init.sh)
```bash
# ❌ WRONG
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/config.sh"

# ✅ CORRECT
source "$REPO_ROOT/scripts/_common/init.sh"  # Loads all dependencies
```

### Pattern 3: Hardcoded Values
```bash
# ❌ WRONG
REPLICA_IP="192.168.168.31"
curl "https://kushnir.cloud/health"

# ✅ CORRECT
REPLICA_IP="${REPLICA_1_IP:?REPLICA_1_IP not set}"
curl "https://${APEX_DOMAIN}/health"
```

### Pattern 4: Echo for Logging
```bash
# ❌ WRONG
echo "ERROR: Failed to deploy"
echo "INFO: Starting deployment"

# ✅ CORRECT
log_error "Failed to deploy"
log_info "Starting deployment"
```

### Pattern 5: No Error Handling
```bash
# ❌ WRONG
#!/usr/bin/env bash
docker-compose up -d
# ... if first command fails, script continues

# ✅ CORRECT
#!/usr/bin/env bash
set -euo pipefail
trap 'log_fatal "Deployment failed"' ERR
docker-compose up -d
```

## Automated Validation

### Pre-Commit Hook
All scripts are validated before commit:
```bash
bash scripts/ci/validate-ops-scripts-compliance.sh
```

### GitHub Actions
Workflow validates on every PR:
- GoV-002 headers present
- Canonical initialization
- No hardcoded values
- No Windows artifacts

### Manual Validation
```bash
# Analyze compliance
bash scripts/ops/P2-1695-HARDEN-OPS-SCRIPTS.sh --analyze

# Validate cluster parity (example of compliant script)
bash scripts/ops/validate-cluster-parity-all-replicas.sh
```

## Status: Implemented Artifacts

### 1. New Compliant Script: `validate-cluster-parity-all-replicas.sh`
- **Purpose**: Validates multi-replica deployment parity
- **Compliance**: Full GOV-002 adherence, IaC/immutable/idempotent
- **Location**: `scripts/ops/validate-cluster-parity-all-replicas.sh`
- **Status**: ✅ Created and ready for testing

### 2. Compliance Reference Document
- **Purpose**: This document - canonical governance standards for ops scripts
- **Location**: `docs/OPS-SCRIPTS-GOVERNANCE-GOV-002.md` (created)
- **Usage**: Reference for all ops script development

### 3. Automated Analysis Script
- **Purpose**: Scan all ops scripts for compliance violations
- **Location**: `scripts/ops/P2-1695-HARDEN-OPS-SCRIPTS.sh`
- **Status**: Created with analysis/fixing modes

## Compliance Rollout

### Phase 1 (Immediate)
- ✅ Create reference documentation (this file)
- ✅ Create example compliant scripts
- ✅ Add CI pre-commit validation

### Phase 2 (Next Sprint)
- Automated remediation of non-compliant scripts
- Team review of large/critical scripts
- Testing of refactored scripts on staging

### Phase 3 (Optional)
- Full automated fix application to all scripts
- Code review and testing
- Deployment to production

## References

- **Governance Rules**: `.github/copilot-instructions.md` (Rules 1-7)
- **Script Writing Guide**: `docs/SCRIPT-WRITING-GUIDE.md`
- **Related Issues**: #1692, #1693, #1665, #1664, #1663, #1662
- **Shared Libraries**: `scripts/_common/`

## Next Steps

1. Review this compliance guide with team
2. Run compliance analysis: `bash scripts/ops/P2-1695-HARDEN-OPS-SCRIPTS.sh --analyze`
3. Test compliant script: `bash scripts/ops/validate-cluster-parity-all-replicas.sh --dry-run`
4. Merge changes to main
5. Begin Phase 2 remediation

---

**Issue**: kushin77/code-server#1695  
**Last Updated**: April 24, 2026
