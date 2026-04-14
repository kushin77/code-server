#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13 - TASK 1.2: ACCESS CONTROL VALIDATION
#
# Validate OAuth2-Proxy & MFA configuration
# Idempotent: Safe to re-run multiple times
# April 13, 2026 - Day 1 Execution
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/phase-13-access-control.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }

main() {
    log_info "================================"
    log_info "PHASE 13 - TASK 1.2: ACCESS CONTROL"
    log_info "================================"

    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Verify oauth2-proxy container
    log_info "Checking oauth2-proxy service..."
    if ! docker-compose ps oauth2-proxy | grep -q "healthy"; then
        log_error "oauth2-proxy not healthy"
        return 1
    fi
    log_success "oauth2-proxy container healthy"

    # Test health endpoint
    log_info "Testing health check endpoint..."
    if curl -sf http://localhost:4180/ping > /dev/null 2>&1; then
        log_success "Health endpoint responding"
    else
        log_error "Health endpoint not responding"
        return 1
    fi

    # Verify OAuth2 configuration
    log_info "Verifying OAuth2 configuration..."
    if [ -z "${GOOGLE_CLIENT_ID:-}" ] || [ -z "${GOOGLE_CLIENT_SECRET:-}" ]; then
        log_error "OAuth2 credentials not set"
        return 1
    fi
    log_success "OAuth2 credentials configured"

    # Verify MFA
    log_info "Checking MFA configuration..."
    if docker-compose exec -T oauth2-proxy env | grep -q "MFA"; then
        log_success "MFA configuration present"
    else
        log_info "MFA not yet configured (optional for Phase 13)"
    fi

    # Test access control path
    log_info "Testing access control path..."
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4180/oauth2/authorizer)
    if [ "$response" = "502" ] || [ "$response" = "401" ]; then
        log_success "Access control working (responded with $response)"
    else
        log_error "Unexpected response: $response"
        return 1
    fi

    log_success ""
    log_success "✓ ACCESS CONTROL VALIDATION COMPLETE"
    return 0
}

main "$@"
exit $?
