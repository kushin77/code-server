#!/usr/bin/env bash
# @file        scripts/ops/verify-ide-session-lb-secret.sh
# @module      infrastructure/secrets
# @description Verify IDE_SESSION_LB_SECRET rotation was successful and secret734 is inactive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
SSH_USER="${DEPLOY_USER:-akushnir}"

main() {
    log_info "Verifying IDE_SESSION_LB_SECRET rotation..."
    
    local checks_passed=0
    local checks_total=0
    
    # Check 1: Verify secret not in primary Caddyfile
    log_info "[1/6] Checking primary Caddyfile for hardcoded secret734..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$PRIMARY_HOST" \
        "grep -q 'secret734' ~/code-server-enterprise/Caddyfile" 2>/dev/null; then
        log_error "✗ Found hardcoded 'secret734' in primary Caddyfile"
    else
        log_info "✓ No hardcoded 'secret734' found in primary"
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 2: Verify secret not in replica Caddyfile
    log_info "[2/6] Checking replica Caddyfile for hardcoded secret734..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$REPLICA_HOST" \
        "grep -q 'secret734' ~/code-server-enterprise/Caddyfile" 2>/dev/null; then
        log_error "✗ Found hardcoded 'secret734' in replica Caddyfile"
    else
        log_info "✓ No hardcoded 'secret734' found in replica"
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check 3: Verify primary .env has IDE_SESSION_LB_SECRET set
    log_info "[3/6] Checking primary .env for IDE_SESSION_LB_SECRET..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$PRIMARY_HOST" \
        "grep -q '^IDE_SESSION_LB_SECRET=' ~/code-server-enterprise/.env" 2>/dev/null; then
        log_info "✓ IDE_SESSION_LB_SECRET found in primary .env"
        checks_passed=$((checks_passed + 1))
    else
        log_error "✗ IDE_SESSION_LB_SECRET not found in primary .env"
    fi
    
    # Check 4: Verify replica .env has IDE_SESSION_LB_SECRET set
    log_info "[4/6] Checking replica .env for IDE_SESSION_LB_SECRET..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$REPLICA_HOST" \
        "grep -q '^IDE_SESSION_LB_SECRET=' ~/code-server-enterprise/.env" 2>/dev/null; then
        log_info "✓ IDE_SESSION_LB_SECRET found in replica .env"
        checks_passed=$((checks_passed + 1))
    else
        log_error "✗ IDE_SESSION_LB_SECRET not found in replica .env"
    fi
    
    # Check 5: Verify Caddy is healthy on primary
    log_info "[5/6] Verifying Caddy health on primary..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$PRIMARY_HOST" \
        "curl -sf https://192.168.168.31/health 2>/dev/null || curl -sk https://192.168.168.31/health 2>/dev/null" &>/dev/null; then
        log_info "✓ Caddy healthy on primary"
        checks_passed=$((checks_passed + 1))
    else
        log_warn "⚠ Could not verify Caddy health on primary (check network connectivity)"
    fi
    
    # Check 6: Verify Caddy is healthy on replica
    log_info "[6/6] Verifying Caddy health on replica..."
    checks_total=$((checks_total + 1))
    if ssh -o BatchMode=yes "$SSH_USER@$REPLICA_HOST" \
        "curl -sf https://192.168.168.42/health 2>/dev/null || curl -sk https://192.168.168.42/health 2>/dev/null" &>/dev/null; then
        log_info "✓ Caddy healthy on replica"
        checks_passed=$((checks_passed + 1))
    else
        log_warn "⚠ Could not verify Caddy health on replica (check network connectivity)"
    fi
    
    # Summary
    log_info ""
    log_info "═════════════════════════════════════════════════════════════"
    log_info "Verification Summary: $checks_passed/$checks_total checks passed"
    log_info "═════════════════════════════════════════════════════════════"
    
    if [[ $checks_passed -eq $checks_total ]]; then
        log_info "✓ All verification checks passed!"
        return 0
    else
        log_error "✗ Some verification checks failed"
        return 1
    fi
}

main "$@"
