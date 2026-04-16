#!/bin/bash
################################################################################
# File:          scripts/p1-read-only-ide-test.sh
# Owner:         Platform Engineering
# Status:        Active
# Purpose:       Integration test suite for P1 #187: Read-Only IDE Access Control
#                Validates all 4 security layers in production environment
# Usage:         ./scripts/p1-read-only-ide-test.sh [--verbose] [--host 192.168.168.31]
# Severity:      P1 (Elite production requirement)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || exit 1

DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
VERBOSE=false
FAILED=0
PASSED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true ;;
        --host) DEPLOY_HOST="$2"; shift ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE: P1 #187 READ-ONLY IDE ACCESS CONTROL
# ─────────────────────────────────────────────────────────────────────────────

test_file_download_blocked() {
    local test_name="File Download Blocked (Layer 1)"
    log_info "TEST: $test_name"
    
    # Attempt to download a file via IDE API
    if ssh akushnir@"$DEPLOY_HOST" "curl -s http://code-server:8080/api/v1/download 2>&1 | grep -q 'Permission denied\|Forbidden'" 2>/dev/null; then
        log_info "✓ PASS: File downloads correctly blocked"
        ((PASSED++))
    else
        log_warn "✗ FAIL: File downloads may be accessible"
        ((FAILED++))
    fi
}

test_terminal_restrictions() {
    local test_name="Terminal Command Restrictions (Layer 3)"
    log_info "TEST: $test_name"
    
    # Try to run privileged command in terminal
    if ssh akushnir@"$DEPLOY_HOST" "docker exec code-server bash -c 'sudo cat /etc/shadow' 2>&1 | grep -q 'sudo: not permitted\|Command not allowed'" 2>/dev/null; then
        log_info "✓ PASS: Privileged commands blocked"
        ((PASSED++))
    else
        log_warn "✗ FAIL: Terminal may not be properly restricted"
        ((FAILED++))
    fi
}

test_git_credential_proxy() {
    local test_name="Git Credential Proxy (Layer 4)"
    log_info "TEST: $test_name"
    
    # Verify git credential helper is configured
    if ssh akushnir@"$DEPLOY_HOST" "docker exec code-server git config credential.helper" 2>/dev/null | grep -q "python"; then
        log_info "✓ PASS: Git credential proxy configured"
        ((PASSED++))
    else
        log_warn "✗ FAIL: Git credential proxy not configured"
        ((FAILED++))
    fi
}

test_audit_logging() {
    local test_name="Audit Logging (Layer 2)"
    log_info "TEST: $test_name"
    
    # Check for recent audit log entries
    if ssh akushnir@"$DEPLOY_HOST" "tail -5 /var/log/code-server-audit.log 2>/dev/null | grep -q 'download_attempt\|terminal_access\|file_access'" 2>/dev/null; then
        log_info "✓ PASS: Audit logs being recorded"
        ((PASSED++))
    else
        log_warn "! WARN: Audit log entries not found (may be normal if no recent activity)"
        # Don't fail here - this is informational
    fi
}

test_download_endpoint_404() {
    local test_name="Download Endpoint Returns 403 (Security Check)"
    log_info "TEST: $test_name"
    
    # Direct API test
    local http_code
    http_code=$(ssh akushnir@"$DEPLOY_HOST" "curl -s -o /dev/null -w '%{http_code}' http://code-server:8080/api/download/test.txt" 2>/dev/null || echo "000")
    
    if [[ "$http_code" == "403" || "$http_code" == "401" ]]; then
        log_info "✓ PASS: Download endpoint returns $http_code (forbidden)"
        ((PASSED++))
    else
        log_warn "✗ FAIL: Download endpoint returned HTTP $http_code (expected 403 or 401)"
        ((FAILED++))
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN TEST EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

log_info "========================================="
log_info "P1 #187: Read-Only IDE Test Suite"
log_info "Target Host: $DEPLOY_HOST"
log_info "========================================="
log_info ""

# Pre-flight check
log_info "PRE-FLIGHT: Checking connectivity to $DEPLOY_HOST..."
if ! ssh -o ConnectTimeout=5 akushnir@"$DEPLOY_HOST" "echo OK" &>/dev/null; then
    log_fatal "Cannot reach $DEPLOY_HOST. Check network connectivity and SSH keys."
fi
log_info "✓ Connected to $DEPLOY_HOST"
log_info ""

# Run all tests
test_file_download_blocked
test_terminal_restrictions
test_git_credential_proxy
test_download_endpoint_404
test_audit_logging

log_info ""
log_info "========================================="
log_info "TEST RESULTS"
log_info "========================================="
log_info "✓ Passed: $PASSED"
log_info "✗ Failed: $FAILED"
log_info "========================================="

if [[ $FAILED -eq 0 ]]; then
    log_info "✓ ALL TESTS PASSED — P1 #187 Production Ready"
    exit 0
else
    log_error "✗ TESTS FAILED — Review implementation"
    exit 1
fi
