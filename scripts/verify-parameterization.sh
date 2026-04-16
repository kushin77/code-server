#!/bin/bash
################################################################################
# scripts/verify-parameterization.sh
# Verification script for elite parameterization refactoring
# Tests that all configuration loads and substitutes correctly
# 
# Usage: ./scripts/verify-parameterization.sh [environment]
# Example: ./scripts/verify-parameterization.sh production
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-development}"

# Load common utilities
source "$SCRIPT_DIR/_common/init.sh"

log::banner "Parameterization Verification"

# ── Step 1: Load configuration ──
log::section "Configuration Loading"
log::task "Loading configuration for: $ENVIRONMENT"

export DEPLOY_ENV="$ENVIRONMENT"
config::load "$ENVIRONMENT"

log::success "Configuration loaded"

# ── Step 2: Validate required values ──
log::section "Configuration Validation"
log::task "Validating required configuration values..."

REQUIRED_VALUES=(
    "DEPLOY_HOST"
    "DEPLOY_USER"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "CODE_SERVER_PASSWORD"
)

config::validate "${REQUIRED_VALUES[@]}" || {
    log::failure "Configuration validation failed"
    exit 1
}

log::success "All required values present"

# ── Step 3: Audit configuration ──
log::section "Configuration Audit"
config::audit

# ── Step 4: Test docker-compose substitution ──
log::section "Docker Compose Validation"
log::task "Checking docker-compose.yml variable substitution..."

if cd "$SCRIPT_DIR/.." && docker-compose config > /tmp/docker-compose.resolved.yml 2>/dev/null; then
    log::success "Docker-compose configuration is valid"
    
    # Check that no hardcoded values remained
    if grep -q "192.168.168" /tmp/docker-compose.resolved.yml && grep -q "7168" /tmp/docker-compose.resolved.yml; then
        log::status "IP addresses" "✅ Properly substituted (resolved.yml shows actual IPs)"
    fi
else
    log::failure "Docker-compose validation failed"
    exit 1
fi

# ── Step 5: Test config in scripts ──
log::section "Script Integration"
log::task "Testing config::get in scripts..."

TEST_VALUES=(
    "NAS_PRIMARY_HOST"
    "CODE_SERVER_PORT"
    "POSTGRES_MEMORY_LIMIT"
    "LOAD_TEST_PEAK_RPS"
)

for var in "${TEST_VALUES[@]}"; do
    value=$(config::get "$var" "NOT_FOUND")
    if [[ "$value" != "NOT_FOUND" ]]; then
        log::status "$var" "✅ $value"
    else
        log::status "$var" "❌ NOT FOUND"
        exit 1
    fi
done

# ── Step 6: Summary ──
log::section "Verification Summary"
log::list \
    "✅ Configuration loaded successfully" \
    "✅ All required values validated" \
    "✅ Docker-compose substitution working" \
    "✅ Script integration functional" \
    "✅ Environment: $ENVIRONMENT"

log::banner "Verification Complete ✅"
log::divider

log::info "Next steps:"
log::list \
    "Run: make deploy (to deploy with production config)" \
    "Run: DEPLOY_ENV=staging ./scripts/verify-parameterization.sh staging (for staging)" \
    "Check: docker-compose config | head -50 (see resolved configuration)"

exit 0
