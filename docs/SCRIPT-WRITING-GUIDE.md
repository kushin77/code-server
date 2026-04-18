# Script Writing Guide

**Goal**: Eliminate duplication and ensure all scripts follow canonical patterns (GOV-001, GOV-002, GOV-003).

---

## Quick Start: Template Your Script

Every new script should start with:
```bash
cp scripts/_template.sh scripts/my-new-script.sh
```

The template is pre-configured with:
- ✅ GOV-002 metadata headers (`@file`, `@module`, `@description`)
- ✅ Canonical initialization (`_common/init.sh`)
- ✅ Canonical logging (`log_info`, `log_error`, `log_fatal`)
- ✅ Error handling (ERR trap, stack trace)
- ✅ Cleanup hooks (EXIT trap)

---

## Directory Structure & Rules

```
scripts/
├── _common/              # CANONICAL LIBRARIES (shared)
│   ├── init.sh          # ← Always source this first
│   ├── logging.sh       # ← Use for all output (log_*, NOT echo)
│   ├── config.sh        # ← Config loading from .env
│   ├── utils.sh         # ← Common utilities (retry, require_*, etc)
│   ├── error-handler.sh # ← Stack trace + debug mode
│   ├── docker.sh        # ← Docker helpers (optional)
│   └── ssh.sh           # ← SSH helpers (optional)
├── _template.sh         # ← Copy this for new scripts
├── phase-*.sh           # ← Infrastructure/deployment scripts
├── apply-*.sh           # ← Configuration/policy scripts
├── ci/
│   └── *.sh            # ← CI/CD scripts
├── lib/
│   └── *.sh            # ← Additional libraries
└── dev/
    └── *.sh            # ← Development/testing scripts
```

---

## Pattern 1: Script Initialization (REQUIRED)

❌ **WRONG** (creates 27 copies of the same code):
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/logging.sh" || exit 1
source "$SCRIPT_DIR/_common/config.sh" || exit 1
source "$SCRIPT_DIR/_common/utils.sh" || exit 1
# ... repeat for every script
```

✅ **CORRECT** (one line, loads everything):
```bash
#!/usr/bin/env bash
# @file scripts/my-script.sh
# @module category/subcategory
# @description What this does
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"  # ← That's it!
```

**What `init.sh` provides:**
- `log_info`, `log_error`, `log_fatal` (canonical logging)
- `log_debug` (controlled by LOG_LEVEL)
- `require_command`, `require_var`, `require_file` (validation)
- `retry`, `confirm`, `die` (utilities)
- `set -euo pipefail` (safe defaults)
- `ERR` trap (stack traces on error)

---

## Pattern 2: Logging (REQUIRED)

❌ **WRONG** (27+ scripts, inconsistent):
```bash
echo "ERROR: Something failed"          # Not structured
echo "[ERROR] Something failed"         # Custom format
echo "FATAL: Something failed" >&2      # Manual stderr redirection
log_error "Something failed"            # Wrong function name (was log_err)
```

✅ **CORRECT** (canonical, structured, Loki-ready):
```bash
log_info "Script started"         # → INFO level (green)
log_debug "Debug detail here"     # → DEBUG level (gray, only if LOG_LEVEL=0)
log_warn "Warning message"        # → WARN level (yellow)
log_error "An error occurred"     # → ERROR level (red, exit 1)
log_fatal "Cannot continue"       # → FATAL level (red, exit 1)
```

**Key Features:**
- Colored output in terminals
- JSON format for `LOG_FORMAT=json` (Loki/Grafana)
- Timestamp, level name, script name auto-added
- Redirect to file via `LOG_FILE=/path`
- Control verbosity via `LOG_LEVEL=0-4`

**Examples:**
```bash
# Log with context
log_info "Creating backup" "path=/backup/db.sql"

# Log error and exit
if ! backup_database; then
    log_fatal "Backup failed, cannot continue"
fi

# Log warning but continue
if [[ "$disk_usage" -gt 80 ]]; then
    log_warn "Disk usage high: $disk_usage%"
fi

# Debug-level output (only shown if LOG_LEVEL=0)
log_debug "Internal state: $variable_value"
```

---

## Pattern 3: Configuration Separation (REQUIRED)

❌ **WRONG** (hardcoded values = config spread across 5-6 files):
```bash
DEPLOY_HOST="192.168.168.31"       # ← Hardcoded!
DEPLOY_USER="akushnir"             # ← Hardcoded!
DOMAIN="kushnir.cloud"             # ← Hardcoded!
DEPLOY_TIMEOUT="300"               # ← Hardcoded!
```

✅ **CORRECT** (GSM-first secret flow; `.env` only for local fallback):
```bash
# Secret material comes from GSM via scripts/fetch-gsm-secrets.sh
# Local development may fall back to .env only when explicitly configured
source scripts/fetch-gsm-secrets.sh
DEPLOY_HOST="${DEPLOY_HOST}"       # ← From env / config
DEPLOY_USER="${DEPLOY_USER}"       # ← From env / config
DOMAIN="${DOMAIN}"                 # ← From env / config
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"  # ← Default if missing

# Validate required config exists
require_var "DEPLOY_HOST" "Deployment host required from .env"
require_var "DEPLOY_USER" "SSH user required from .env"
```

**Master Config File**: `.env.template` for non-secret deployment config; GSM for secret material
```bash
# This is the single source of truth for non-secret deployment config
export DEPLOY_HOST="192.168.168.31"
export DEPLOY_USER="akushnir"
export DOMAIN="kushnir.cloud"
export REGISTRY_URL="ghcr.io"
# ... all other config
```

**Credential Model**
- GSM is the default source for secret material.
- Service accounts are for workload identity and machine-to-machine API access.
- SSH keys are for host transport/authentication only.

**Load in script**:
```bash
# init.sh automatically loads from .env if it exists
# No action needed for local non-secret config — it's automatic!
```

---

## Pattern 4: Error Handling (REQUIRED)

❌ **WRONG** (no error handling):
```bash
cp file.txt /backup/
chmod 644 /backup/file.txt
echo "Done"  # What if chmod failed?
```

✅ **CORRECT** (catch and log errors):
```bash
# Option 1: set -e (fails on first error) + logging
if ! cp file.txt /backup/; then
    log_error "Failed to copy file"
    return 1
fi

if ! chmod 644 /backup/file.txt; then
    log_error "Failed to set permissions"
    return 1
fi

log_info "File backed up successfully"
```

**Automatic Error Handling** (provided by `init.sh`):
```bash
# init.sh sets: set -euo pipefail
# This means:
# - -e: Exit on first error
# - -u: Exit if undefined variable used
# - -o pipefail: Exit if any command in pipeline fails

# init.sh also sets ERR trap:
# - Stack trace printed automatically on error
# - Return code preserved
```

**Use Canonical Error Functions**:
```bash
# For warnings: log_warn (continues execution)
if ! some_command; then
    log_warn "Command failed but continuing"
fi

# For fatal errors: log_fatal (exits immediately)
if [[ -z "$REQUIRED_VAR" ]]; then
    log_fatal "REQUIRED_VAR must be set"
fi

# For general errors: log_error (you decide exit behavior)
if ! dangerous_operation; then
    log_error "Operation failed"
    return 1
fi
```

---

## Pattern 5: Input Validation (REQUIRED)

❌ **WRONG** (no validation):
```bash
script_function() {
    local user=$1
    echo "Hello $user"  # What if $user is empty or contains injection?
}
```

✅ **CORRECT** (validate before use):
```bash
script_function() {
    local user="$1"
    
    # Validate required argument
    if [[ -z "$user" ]]; then
        log_error "Usage: script_function <username>"
        return 1
    fi
    
    # Validate format (alphanumeric only)
    if ! [[ "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid username format: $user"
        return 1
    fi
    
    log_info "Hello $user"
}
```

**Canonical Validation Functions** (from `_common/utils.sh`):
```bash
# Validate variable is set and non-empty
require_var "MY_VAR" "Description of why it's needed"

# Validate file exists
require_file "/path/to/file" "File is required for processing"

# Validate command exists on PATH
require_command "docker" "Docker is required"

# Validate directory is writable
if ! [[ -w "/var/log" ]]; then
    log_fatal "/var/log is not writable"
fi
```

---

## Pattern 6: Metadata Headers (REQUIRED - GOV-002)

Every script MUST start with metadata headers:

```bash
#!/usr/bin/env bash
################################################################################
# @file        scripts/category/script-name.sh
# @module      category/subcategory
# @description One-line description of what this script does
# @owner       platform
# @status      active
#
# USAGE
#   scripts/category/script-name.sh [arg1] [arg2]
#
# ENVIRONMENT VARIABLES
#   DEPLOY_HOST      - Production host (from .env)
#   DEPLOY_USER      - SSH user (from .env)
#
# EXIT CODES
#   0 - Success
#   1 - General error
#   2 - Config error
#   127 - Missing required command
#
# NOTES
#   Any additional context, warnings, dependencies here.
#
# Last Updated: April 17, 2026
################################################################################
```

**Validation**: Pre-commit hook checks all scripts have `@file`, `@module`, `@description`.

---

## Pattern 7: Retries & Resilience (Optional but Recommended)

Use canonical `retry` function from `_common/utils.sh`:

```bash
# Retry an operation up to 5 times with exponential backoff
if ! retry 5 "docker ps" "Docker health check"; then
    log_fatal "Docker is unreachable after 5 attempts"
fi

# Inline retry with custom logic
for i in {1..5}; do
    if curl -sf "$endpoint" > /dev/null; then
        log_info "Endpoint healthy"
        break
    fi
    if [[ $i -lt 5 ]]; then
        log_warn "Attempt $i failed, retrying..."
        sleep $((2 ** i))  # Exponential backoff
    else
        log_fatal "Endpoint unhealthy after 5 attempts"
    fi
done
```

---

## Pattern 8: Docker Operations (Optional - Use if Needed)

If your script uses Docker, source the canonical Docker helpers:

```bash
# Already loaded by init.sh if docker.sh exists
# Available functions:
docker_wait_healthy "container-name" 30        # Wait up to 30s for healthy
docker_logs "container-name"                   # Get container logs
docker_exec "container-name" "bash -c 'cmd'"  # Execute command in container
```

---

## Pattern 9: SSH Operations (Optional - Use if Needed)

If your script uses SSH, use canonical SSH helpers:

```bash
# Already loaded by init.sh if ssh.sh exists
# Available functions:
ssh_command "$DEPLOY_HOST" "ls -la /home"      # Run command on remote
ssh_copy_file "local.txt" "$DEPLOY_HOST:/tmp/" # Copy file to remote
```

---

## Checklist: Before Committing

- [ ] Script copied from `scripts/_template.sh`
- [ ] `@file`, `@module`, `@description` headers added
- [ ] All logging uses `log_info`, `log_error`, `log_fatal` (not `echo`)
- [ ] All config from `.env` or environment (no hardcoded IPs/domains)
- [ ] `SCRIPT_DIR` calculated and `init.sh` sourced
- [ ] Required commands validated with `require_command`
- [ ] Required variables validated with `require_var`
- [ ] Error handling added (either `if ! command` or rely on `set -e`)
- [ ] Cleanup/trap added for file deletion or resource release
- [ ] Script tested locally before commit
- [ ] No duplicate code (search `_common/` for existing functions first)

---

## Testing Your Script

```bash
# Test with debug output
LOG_LEVEL=0 bash scripts/my-script.sh

# Test with JSON logging (for Loki)
LOG_FORMAT=json bash scripts/my-script.sh

# Test with log file capture
LOG_FILE=/tmp/my-script.log bash scripts/my-script.sh

# Verify logging output
cat /tmp/my-script.log | jq .

# Check for errors
bash scripts/my-script.sh; echo "Exit code: $?"
```

---

## Common Mistakes

| Mistake | ❌ Wrong | ✅ Right |
|---------|---------|----------|
| Multiple init lines | `source _common/logging.sh && source _common/config.sh` | `source _common/init.sh` |
| Inline echo for errors | `echo "ERROR: ..."` | `log_error "..."` |
| Hardcoded config | `DEPLOY_HOST="192.168.168.31"` | `DEPLOY_HOST="${DEPLOY_HOST}"` |
| No input validation | `script_func() { local x=$1; ... }` | `require_var "PARAM"; script_func "$PARAM"` |
| Missing headers | Script starts with `#!/bin/bash` | Script starts with headers + `#!/usr/bin/env bash` |
| Custom logging | `write_error`, `die`, `log_err` | `log_error`, `log_fatal` |
| No cleanup | Script ends abruptly | Script has `trap cleanup EXIT` |
| set -e without error msg | Command fails silently | Use `if !` to log before failing |

---

## Getting Help

- **Canonical Libraries**: [scripts/_common/](scripts/_common/)
- **Script Template**: [scripts/_template.sh](scripts/_template.sh)
- **Governance Rules**: [.github/copilot-instructions.md](.github/copilot-instructions.md)
- **Q&A**: Ask in `#platform-eng` or open GitHub discussion

---

**Last Updated**: April 17, 2026
