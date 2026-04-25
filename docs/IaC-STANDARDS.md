# IaC Standards — Infrastructure as Code Best Practices

**Version:** 1.0  
**Date:** April 25, 2026  
**Scope:** All infrastructure scripts in scripts/ directory  
**Enforcement:** Automated via GitHub Actions CI (scripts/ci/validate-iac-compliance.sh)

---

## 📋 Overview

Infrastructure as Code (IaC) principles ensure that all infrastructure is:
- **Immutable:** Version-controlled and auditable
- **Idempotent:** Safe to run multiple times
- **Environment-Driven:** Configuration via environment variables
- **Fault-Safe:** Error handling on all operations
- **Documented:** Clear intent and usage

These standards must be followed for all new scripts and are being retroactively applied to legacy code.

---

## ✅ IaC Principle 1: Immutability

**Definition:** All infrastructure code is version-controlled and immutable. No dynamic file generation, no runtime configuration changes.

### Requirements

**1.1 Version Control**
- All scripts stored in git repository
- All changes tracked with meaningful commit messages
- Git is the single source of truth

**1.2 No Runtime Configuration Files**
```bash
# ❌ WRONG: Generating config at runtime
docker run -e "CONFIG=$(generate_config)" myservice

# ✅ CORRECT: Configuration from template or env vars
docker run -e "CONFIG_FILE=/etc/app/config.yml" myservice
```

**1.3 No Dynamic Script Generation**
```bash
# ❌ WRONG: Generating script at runtime
echo "#!/bin/bash" > /tmp/deploy.sh
echo "docker compose up -d" >> /tmp/deploy.sh
bash /tmp/deploy.sh

# ✅ CORRECT: Use checked-in script directly
bash scripts/ops/deploy.sh
```

**1.4 Commit Message Standards**
```
Commit Format: <type>(<scope>): <subject>

Example: fix(epic#1536): remediate hardcoding in connection-pool script

Types:
  • feat: New feature or infrastructure
  • fix: Bug fix or remediation
  • docs: Documentation updates
  • chore: Maintenance tasks
  • refactor: Code restructuring

Scope: Related epic/issue number
Subject: Brief description (50 chars max)
```

### Compliance Check

```bash
# Verify all scripts are git-tracked
git ls-files scripts/ | wc -l

# Check recent commits
git log --oneline -10 scripts/

# Verify no uncommitted changes
git status scripts/
```

---

## ✅ IaC Principle 2: Idempotency

**Definition:** Scripts can be run multiple times safely with identical results.

### Requirements

**2.1 No Hardcoded State**
```bash
# ❌ WRONG: Creates different output each time
echo "Deployed: $(date)" > deployment.log

# ✅ CORRECT: Deterministic output
echo "Deployed: $DEPLOY_VERSION" > deployment.log
```

**2.2 No Timestamps in Configurations**
```bash
# ❌ WRONG: Generated configs differ each run
cat > config.yml <<EOF
# Generated: $(date)
version: 1.0
EOF

# ✅ CORRECT: Deterministic config
cat > config.yml <<EOF
# version: generated-2026-04-25 (static)
version: 1.0
EOF
```

**2.3 Explicit State Checks**
```bash
# ❌ WRONG: Assumes state
systemctl stop myservice

# ✅ CORRECT: Checks state before action
if systemctl is-active --quiet myservice; then
    systemctl stop myservice
else
    echo "Service already stopped"
fi
```

**2.4 Safe Resource Updates**
```bash
# ❌ WRONG: Always deletes and recreates
docker volume rm data
docker volume create data

# ✅ CORRECT: Preserves existing resources
docker volume create --name data 2>/dev/null || true
```

### Compliance Check

```bash
# Run script multiple times, verify identical results
bash scripts/ops/deploy.sh
sleep 5
bash scripts/ops/deploy.sh

# Check for deterministic output
bash scripts/ops/generate-config.sh | md5sum
bash scripts/ops/generate-config.sh | md5sum  # Should match

# Verify no timestamped artifacts
grep -r '\$(date' scripts/ | wc -l  # Should be 0
```

---

## ✅ IaC Principle 3: Environment-Driven

**Definition:** All configuration comes from environment variables, not hardcoding.

### Requirements

**3.1 Environment Variable Pattern**
```bash
# Template
readonly SETTING_NAME="${ENV_VAR_NAME:-default_value}"

# Examples
readonly DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
readonly API_PORT="${API_PORT:-3100}"
readonly LOG_LEVEL="${LOG_LEVEL:-info}"
readonly TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
```

**3.2 No Hardcoded Values**
```bash
# ❌ WRONG: Hardcoded values
REDIS_HOST="redis.example.com"
REDIS_PORT="6379"
DB_PASSWORD="secret123"

# ✅ CORRECT: Environment-driven
readonly REDIS_HOST="${REDIS_HOST:-redis.example.com}"
readonly REDIS_PORT="${REDIS_PORT:-6379}"
readonly DB_PASSWORD="${DB_PASSWORD:-}"  # No default for secrets!
```

**3.3 Sensitive Data Handling**
```bash
# ❌ WRONG: Secret in default
readonly DB_PASSWORD="${DB_PASSWORD:-abc123}"

# ✅ CORRECT: No default for secrets
readonly DB_PASSWORD="${DB_PASSWORD:-}"
if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: DB_PASSWORD must be set" >&2
    exit 1
fi
```

**3.4 Configuration Documentation**
```bash
# Document all environment variables at script top
# Deployment configuration
readonly TARGET_HOST="${DEPLOY_HOST:-192.168.168.31}"      # IP or hostname
readonly TARGET_PORT="${DEPLOY_PORT:-3100}"                # API port (1-65535)
readonly TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"         # Deployment timeout in seconds
readonly RETRY_COUNT="${RETRY_COUNT:-5}"                   # Number of retries on failure
```

### Compliance Check

```bash
# Find all hardcoded assignments
grep -n '=['\''"]' scripts/ops/*.sh | grep -v '${' | wc -l

# Verify all variables use ${VAR:-default} pattern
grep -o '\${[A-Z_]*:-' scripts/ops/*.sh | sort | uniq

# Check for hardcoded IPs
grep -n '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' scripts/ops/*.sh | wc -l
```

---

## ✅ IaC Principle 4: Fault-Safe

**Definition:** Scripts handle errors gracefully and never leave the system in an inconsistent state.

### Requirements

**4.1 Set Error Handling**
```bash
#!/bin/bash
set -euo pipefail  # Must be on line 2 (after shebang)

# Explanation:
# set -e: Exit on any error
# set -u: Exit if undefined variable used
# set -o pipefail: Fail if any command in pipe fails
```

**4.2 Error Handling Functions**
```bash
# Define error handler
die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Use in commands
command_that_fails || die "Failed to execute command"
```

**4.3 Command Validation**
```bash
# ❌ WRONG: Doesn't check if command exists
docker compose up -d

# ✅ CORRECT: Validates prerequisites
if ! command -v docker &>/dev/null; then
    die "Docker not installed"
fi

if ! command -v docker compose &>/dev/null; then
    die "Docker Compose not available"
fi

docker compose up -d || die "Failed to start services"
```

**4.4 Rollback on Failure**
```bash
# Capture state for rollback
ROLLBACK_COMMANDS=()

# Deploy change
if ! deploy_new_version; then
    echo "Deployment failed, rolling back..."
    
    # Execute rollback
    if [ ${#ROLLBACK_COMMANDS[@]} -gt 0 ]; then
        for cmd in "${ROLLBACK_COMMANDS[@]}"; do
            eval "$cmd"
        done
    fi
    
    exit 1
fi
```

**4.5 Cleanup on Exit**
```bash
# Define cleanup function
cleanup() {
    # Always run on exit (success or failure)
    local exit_code=$?
    
    # Remove temp files
    rm -f /tmp/deploy-*
    
    # Stop background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    exit $exit_code
}

# Register cleanup function
trap cleanup EXIT
```

### Compliance Check

```bash
# Find scripts without set -euo pipefail
find scripts/ -name "*.sh" -exec grep -L "set -euo pipefail" {} \;

# Verify error messages go to stderr
grep 'echo.*>&2' scripts/ops/*.sh | wc -l

# Check for error exit codes
grep 'exit [1-9]' scripts/ops/*.sh | wc -l
```

---

## ✅ IaC Principle 5: Documented

**Definition:** Scripts are self-documenting with clear intent, usage, and owner information.

### Requirements

**5.1 @governance Header**
```bash
#!/bin/bash
# @governance: <Short purpose> — <brief description>
# Purpose: <What does this script do>
# Author: <Your name or team>
# Date: <YYYY-MM-DD of creation>
# Related issues: #<issue>, #<issue>
#
# Usage:
#   DEPLOY_HOST=192.168.168.31 bash scripts/ops/deploy-production.sh
#
# Environment variables:
#   DEPLOY_HOST: Target host IP (default: 192.168.168.31)
#   DEPLOY_PORT: API port (default: 3100)
#   TIMEOUT: Deployment timeout in seconds (default: 600)

set -euo pipefail
```

**5.2 Inline Comments**
```bash
# Explain WHY, not WHAT (code shows WHAT)

# ❌ WRONG: Comments state the obvious
i=$((i + 1))  # Increment i

# ✅ CORRECT: Comments explain intent
i=$((i + 1))  # Retry counter; stop after 30 attempts
```

**5.3 Function Documentation**
```bash
# Function: deploy_service
# Purpose: Deploy service to target host
# Parameters:
#   $1: Service name
#   $2: Target host IP
# Returns: 0 on success, 1 on failure
# Example:
#   deploy_service "myapp" "192.168.168.31"
deploy_service() {
    local service_name="$1"
    local target_host="$2"
    
    # Implementation...
}
```

**5.4 Usage Examples**
```bash
# Include examples in script header or documentation

# Usage:
#   # Deploy with defaults
#   bash scripts/ops/deploy.sh
#
#   # Deploy to specific host
#   DEPLOY_HOST=192.168.168.42 bash scripts/ops/deploy.sh
#
#   # Deploy with custom timeout
#   TIMEOUT=1800 bash scripts/ops/deploy.sh
```

### Compliance Check

```bash
# Find scripts without @governance headers
find scripts/ -name "*.sh" -exec grep -L "@governance" {} \;

# Verify header format
grep -A2 "^# @governance:" scripts/ops/*.sh

# Check for inline comments (quality assessment)
grep '^\s*#' scripts/ops/*.sh | wc -l
```

---

## 🔧 Script Template

Use this template for all new infrastructure scripts:

```bash
#!/bin/bash
# @governance: <Purpose> — <brief description>
# Purpose: <What does this script do>
# Author: Autonomous Agent
# Date: $(date +%Y-%m-%d)
# Related issues: #<issue>, #<issue>
#
# Usage:
#   bash scripts/ops/my-script.sh
#
# Environment variables:
#   VAR_NAME: Description (default: value)

set -euo pipefail

# Script metadata
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration (all env-var driven)
readonly TARGET_HOST="${TARGET_HOST:-192.168.168.31}"
readonly TARGET_PORT="${TARGET_PORT:-3100}"
readonly TIMEOUT="${TIMEOUT:-600}"

# Logging functions
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

die() {
    log_error "$@"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    # Add cleanup operations here
    exit $exit_code
}

trap cleanup EXIT

# Main function
main() {
    log_info "Starting script..."
    
    # Your code here
    
    log_info "Script completed successfully"
}

main "$@"
```

---

## 🔍 Validation Tools

### Tool 1: Built-in Bash Checks

```bash
# Syntax check (no execution)
bash -n scripts/ops/my-script.sh

# Verbose mode (see all operations)
bash -x scripts/ops/my-script.sh

# Debug mode
bash -vx scripts/ops/my-script.sh
```

### Tool 2: ShellCheck (Static Analysis)

```bash
# Install ShellCheck
apt-get install shellcheck  # Linux
brew install shellcheck      # macOS

# Check single script
shellcheck scripts/ops/my-script.sh

# Check all scripts
shellcheck scripts/**/*.sh

# Ignore specific warnings
shellcheck -x scripts/ops/my-script.sh  # Follow source files
```

### Tool 3: IaC Compliance Validator

```bash
# Run built-in validator
bash scripts/ci/validate-iac-compliance.sh

# Generate violation report
bash scripts/ci/generate-iac-violations-report.sh

# Run specific checks
bash scripts/ci/validate-iac-compliance.sh 2>&1 | grep "hardcoding"
```

---

## 📊 Compliance Enforcement

### GitHub Actions Integration

All PRs must pass IaC compliance checks before merge:

```yaml
name: IaC Compliance Check
on: [pull_request]

jobs:
  iac-compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run IaC validation
        run: bash scripts/ci/validate-iac-compliance.sh
```

### Pre-Commit Hook

Local validation before commit:

```bash
#!/bin/bash
# Save as .git/hooks/pre-commit and chmod +x

echo "Running IaC compliance check..."
bash scripts/ci/validate-iac-compliance.sh || {
    echo "IaC compliance check failed. Commit aborted."
    exit 1
}
```

---

## 🎓 Migration Guide

### Converting Legacy Scripts

**Step 1: Add Error Handling**
```bash
# Line 2 (after shebang)
set -euo pipefail
```

**Step 2: Add @governance Header**
```bash
# Lines 2-10 (before set -euo pipefail)
# @governance: <Purpose> — <description>
# Purpose: <What it does>
# Author: <Creator>
# Date: <YYYY-MM-DD>
```

**Step 3: Extract Hardcoded Values to Environment Variables**
```bash
# Find hardcoding
grep -n '=['\''"]' scripts/ops/my-script.sh | grep -v '${'

# Replace each one
OLD_HOST="192.168.168.31"
NEW_HOST='readonly TARGET_HOST="${TARGET_HOST:-192.168.168.31}"'
```

**Step 4: Remove Timestamps**
```bash
# Find timestamps
grep -n '\$(date' scripts/ops/my-script.sh

# Remove or replace with static version
# OLD: echo "Generated: $(date)"
# NEW: echo "Generated: 2026-04-25"
```

**Step 5: Add Cleanup and Error Handling**
```bash
# Add trap at top of main()
trap cleanup EXIT

# Add functions
cleanup() { ... }
die() { ... }
```

**Step 6: Verify Compliance**
```bash
# Run validator
bash scripts/ci/validate-iac-compliance.sh

# Run syntax check
bash -n scripts/ops/my-script.sh

# Run script
bash scripts/ops/my-script.sh
```

---

## 📋 Compliance Checklist

Use this for code review:

- [ ] `set -euo pipefail` on line 2
- [ ] `@governance` header with purpose
- [ ] `readonly` for all configuration variables
- [ ] All variables use `${VAR:-default}` pattern
- [ ] No hardcoded IPs, ports, or credentials
- [ ] No `$(date)` or dynamic timestamps
- [ ] Error handling on all critical commands
- [ ] `trap cleanup EXIT` for resource cleanup
- [ ] Inline comments explaining WHY (not WHAT)
- [ ] Function documentation for complex logic
- [ ] Usage examples in header comments
- [ ] Bash syntax check: `bash -n` passes
- [ ] IaC compliance check passes
- [ ] Tested with multiple runs (idempotency)

---

## 📞 Support & Questions

- **Standards Questions:** Review this document
- **Compliance Issues:** Run `bash scripts/ci/validate-iac-compliance.sh`
- **Remediation Help:** See docs/IaC-REMEDIATION-BACKLOG.md
- **Template Requests:** Use script template in Section 6

---

**Version:** 1.0  
**Status:** Active  
**Last Updated:** April 25, 2026  
**Maintainer:** Autonomous Agent  
**Enforcement:** Mandatory for all new infrastructure code  
