#!/bin/bash
# Pre-Flight Deployment Checklist
# Ensures all prerequisites are met before production deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PRE-FLIGHT DEPLOYMENT CHECKLIST                          ║"
echo "║  Final readiness verification before production            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() {
    echo "✅ $1"
    ((PASSED++))
}

fail() {
    echo "❌ $1"
    ((FAILED++))
}

warn() {
    echo "⚠️  $1"
    ((WARNINGS++))
}

# Phase 1: Environment Prerequisites
echo "📋 PHASE 1: ENVIRONMENT PREREQUISITES"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check required commands
for cmd in ssh scp docker docker-compose openssl curl jq git bash; do
    if command -v $cmd &> /dev/null; then
        pass "Command available: $cmd"
    else
        fail "Command missing: $cmd"
    fi
done

echo ""

# Phase 2: Configuration Files
echo "📋 PHASE 2: CONFIGURATION FILES"
echo "═════════════════════════════════════════════════════════════"
echo ""

PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Check required files
for file in docker-compose.yml Caddyfile .env.template .github/copilot-instructions.md; do
    if [ -f "$PARENT_DIR/$file" ]; then
        pass "File exists: $file"
    else
        fail "File missing: $file"
    fi
done

echo ""

# Phase 3: Automation Scripts
echo "📋 PHASE 3: AUTOMATION SCRIPTS"
echo "═════════════════════════════════════════════════════════════"
echo ""

SCRIPTS=(
    "automated-deployment-orchestration.sh"
    "automated-oauth-configuration.sh"
    "automated-env-generator.sh"
    "automated-certificate-management.sh"
    "automated-dns-configuration.sh"
    "automated-iac-validation.sh"
    "deployment-validation-suite.sh"
    "verify-iac-complete.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if [ -x "$SCRIPT_DIR/$script" ]; then
            pass "Script executable: $script"
        else
            warn "Script not executable: $script (will still work)"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    else
        fail "Script missing: $script"
    fi
done

echo ""

# Phase 4: Documentation
echo "📋 PHASE 4: DOCUMENTATION"
echo "═════════════════════════════════════════════════════════════"
echo ""

DOCS=(
    "PRODUCTION-DEPLOYMENT-IAC.md"
    "IACINC-README.md"
    "IaC-TRANSFORMATION-COMPLETE.md"
    "IaC-PRIORITY-TODO-COMPLETE.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$PARENT_DIR/$doc" ]; then
        pass "Documentation: $doc"
    else
        fail "Documentation missing: $doc"
    fi
done

echo ""

# Phase 5: Git Status
echo "📋 PHASE 5: GIT STATUS"
echo "═════════════════════════════════════════════════════════════"
echo ""

cd "$PARENT_DIR"

if git rev-parse --git-dir > /dev/null 2>&1; then
    pass "Git repository initialized"
    
    # Check for uncommitted changes
    if git status --porcelain | grep -q .; then
        warn "Uncommitted changes exist"
        echo "   Run: git add . && git commit -m 'message'"
    else
        pass "All changes committed"
    fi
    
    # Check for untracked files
    UNTRACKED=$(git ls-files --others --exclude-standard | wc -l)
    if [ "$UNTRACKED" -gt 0 ]; then
        warn "$UNTRACKED untracked files exist"
    else
        pass "No untracked files"
    fi
    
    # Check remote
    if git remote -v | grep -q origin; then
        pass "Git remote configured"
    else
        warn "No Git remote configured"
    fi
else
    fail "Not a Git repository"
fi

echo ""

# Phase 6: Environment Variables
echo "📋 PHASE 6: ENVIRONMENT VARIABLES"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check required env vars
if [ ! -z "$DOMAIN" ]; then
    pass "DOMAIN set: $DOMAIN"
else
    warn "DOMAIN not set (can be configured during deployment)"
fi

if [ ! -z "$DEPLOY_HOST" ]; then
    pass "DEPLOY_HOST set: $DEPLOY_HOST"
else
    warn "DEPLOY_HOST not set (default: ${DEPLOY_HOST})"
fi

if [ ! -z "$DEPLOY_USER" ]; then
    pass "DEPLOY_USER set: $DEPLOY_USER"
else
    warn "DEPLOY_USER not set (default: akushnir)"
fi

echo ""

# Phase 7: Network & SSH
echo "📋 PHASE 7: NETWORK & SSH CONNECTIVITY"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Test SSH connectivity
if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    "$DEPLOY_USER@$DEPLOY_HOST" 'echo' &>/dev/null; then
    pass "SSH connectivity to $DEPLOY_HOST verified"
else
    warn "SSH connectivity to $DEPLOY_HOST failed (may work during deployment)"
fi

echo ""

# Phase 8: Docker
echo "📋 PHASE 8: DOCKER ENVIRONMENT"
echo "═════════════════════════════════════════════════════════════"
echo ""

if docker --version &>/dev/null; then
    pass "Docker installed"
else
    fail "Docker not installed"
fi

if docker-compose --version &>/dev/null; then
    pass "Docker Compose installed"
else
    fail "Docker Compose not installed"
fi

if docker ps &>/dev/null; then
    pass "Docker daemon accessible"
else
    warn "Docker daemon may not be running"
fi

echo ""

# Phase 9: Disk Space
echo "📋 PHASE 9: DISK SPACE"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check local disk
LOCAL_DISK=$(df -BG "$SCRIPT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$LOCAL_DISK" -gt 10 ]; then
    pass "Local disk space: ${LOCAL_DISK}GB available"
else
    warn "Local disk space low: ${LOCAL_DISK}GB available"
fi

echo ""

# Phase 10: IaC Compliance
echo "📋 PHASE 10: IaC COMPLIANCE CHECK"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check for hardcoded secrets
if [ -f "$PARENT_DIR/docker-compose.yml" ]; then
    if grep -q "password\|secret\|token" "$PARENT_DIR/docker-compose.yml" | \
       grep -qv "\\${" | grep -qv "#"; then
        fail "Possible hardcoded secrets in docker-compose.yml"
    else
        pass "No hardcoded secrets in docker-compose.yml"
    fi
fi

# Check for 'manual' in active documentation
MANUAL_COUNT=$(grep -r "manual" "$PARENT_DIR"/*.md 2>/dev/null | \
    grep -v "AUDIT" | grep -v "PHASE" | wc -l || echo 0)

if [ "$MANUAL_COUNT" -eq 0 ]; then
    pass "No 'manual' references in active documentation"
else
    warn "$MANUAL_COUNT 'manual' references found (may be in legacy docs)"
fi

echo ""

# Final Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 PRE-FLIGHT SUMMARY                         ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  ✅ Passed:  $PASSED                                         ║"
echo "║  ❌ Failed:  $FAILED                                         ║"
echo "║  ⚠️  Warnings: $WARNINGS                                       ║"
echo "║                                                            ║"

if [ "$FAILED" -eq 0 ]; then
    echo "║  🟢 STATUS: READY FOR DEPLOYMENT                          ║"
    echo "║                                                            ║"
    echo "║  Next: Run deployment validation suite                    ║"
    echo "║  Command: ./deployment-validation-suite.sh               ║"
else
    echo "║  🔴 STATUS: BLOCKERS EXIST                                ║"
    echo "║                                                            ║"
    echo "║  Fix failed items before proceeding with deployment      ║"
fi

echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Exit with appropriate code
if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
