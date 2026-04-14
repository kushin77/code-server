#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Pre-Flight Deployment Checklist
# Final readiness verification before production deployment
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# UI Functions
pass() {
  echo "✅ $1"
}

fail() {
  echo "❌ $1"
  ((FAILED++))
}

warn() {
  echo "⚠️  $1"
}

# Initialize counter
FAILED=0

# --- PHASE 1: ENVIRONMENT PREREQUISITES ---
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PRE-FLIGHT DEPLOYMENT CHECKLIST                          ║"
echo "║  Final readiness verification before production            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 PHASE 1: ENVIRONMENT PREREQUISITES"
echo "═════════════════════════════════════════════════════════════"
echo ""

if [ -n "${DEPLOY_HOST:-}" ]; then
    pass "DEPLOY_HOST defined: $DEPLOY_HOST"
else
    fail "DEPLOY_HOST not defined"
fi

if [ -n "${DEPLOY_USER:-}" ]; then
    pass "DEPLOY_USER defined: $DEPLOY_USER"
else
    fail "DEPLOY_USER not defined"
fi

echo ""
echo "📋 PHASE 2: CONFIGURATION FILES"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check critical files
for file in Caddyfile docker-compose.yml prometheus.yml alertmanager.yml; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

echo ""
echo "📋 PHASE 3: NETWORKING"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check Docker and connectivity
if command -v docker &>/dev/null; then
    pass "Docker installed"
else
    fail "Docker not installed"
fi

if command -v docker-compose &>/dev/null; then
    pass "Docker Compose installed"
else
    fail "Docker Compose not installed"
fi

echo ""
echo "📋 PHASE 4: DISK SPACE"
echo "═════════════════════════════════════════════════════════════"
echo ""

# Check local disk space
LOCAL_DISK=$(df -BG "$SCRIPT_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "unknown")
if [ "$LOCAL_DISK" != "unknown" ] && [ "$LOCAL_DISK" -gt 10 ]; then
    pass "Local disk space: ${LOCAL_DISK}GB available"
else
    warn "Local disk space: ${LOCAL_DISK}GB available (recommend >= 10GB)"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"

if [ "$FAILED" -gt 0 ]; then
    echo "║  RESULT: ❌ $FAILED CHECK(S) FAILED                   ║"
    echo "║  Fix failed items before proceeding with deployment      ║"
else
    echo "║  RESULT: ✅ ALL CHECKS PASSED - READY FOR DEPLOYMENT  ║"
fi

echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Exit with appropriate code
if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
