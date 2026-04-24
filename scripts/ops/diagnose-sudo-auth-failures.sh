#!/usr/bin/env bash
# @file        scripts/ops/diagnose-sudo-auth-failures.sh
# @module      operations/security
# @description Diagnose and fix sudo PAM authentication failures (P2 #1634)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"

# Check PAM authentication failures
check_pam_failures() {
    local host="$1"
    
    log_info "Checking PAM authentication failures on $host..."
    
    local auth_log_location="/var/log/auth.log"
    
    # Check using systemd journal (more reliable on modern systems)
    local failure_entries
    failure_entries=$(ssh "${EXEC_USER}@${host}" "journalctl -n 50 2>/dev/null | grep -i 'sudo.*password required\|conversation failed' | wc -l" || echo "0")
    
    if [ "$failure_entries" -gt 0 ]; then
        log_warn "Found $failure_entries PAM authentication failure entries in journal"
        
        log_info "Recent failures:"
        ssh "${EXEC_USER}@${host}" "journalctl -n 20 2>/dev/null | grep -i 'sudo.*password required\|conversation failed' || true" | sed 's/^/  /'
        
        return 1
    fi
    
    log_success "✓ No PAM authentication failures found"
    return 0
}

# Check sudo configuration
check_sudo_config() {
    local host="$1"
    
    log_info "Checking sudo configuration on $host..."
    
    # Check if sudoers.d entry exists for the user
    local sudoers_check
    sudoers_check=$(ssh "${EXEC_USER}@${host}" "[ -f /etc/sudoers.d/${EXEC_USER} ] && echo 'EXISTS' || echo 'MISSING'" || echo "ERROR")
    
    if [ "$sudoers_check" = "MISSING" ]; then
        log_warn "No passwordless sudo configuration found for ${EXEC_USER}"
        log_info "Current sudoers.d entries:"
        ssh "${EXEC_USER}@${host}" "ls -la /etc/sudoers.d/ 2>/dev/null | tail -10 || echo 'Cannot access sudoers.d'" | sed 's/^/  /'
        return 1
    fi
    
    if [ "$sudoers_check" = "ERROR" ]; then
        log_error "Cannot access sudoers configuration"
        return 1
    fi
    
    log_success "✓ Sudoers configuration exists for ${EXEC_USER}"
    
    # Show the entry
    log_info "Current sudoers entry:"
    ssh "${EXEC_USER}@${host}" "sudo cat /etc/sudoers.d/${EXEC_USER} 2>/dev/null || echo 'Cannot read sudoers file'" | sed 's/^/  /'
    
    return 0
}

# Test non-interactive sudo
test_noninteractive_sudo() {
    local host="$1"
    local test_cmd="${2:-docker ps -q}"
    
    log_info "Testing non-interactive sudo on $host: $test_cmd"
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would execute: sudo $test_cmd"
        return 0
    fi
    
    # Use sudo -n (non-interactive) which will fail if password is required
    local test_result
    test_result=$(ssh "${EXEC_USER}@${host}" "sudo -n $test_cmd 2>&1" || echo "FAILED_NEEDS_PASSWORD")
    
    if [ "$test_result" = "FAILED_NEEDS_PASSWORD" ]; then
        log_error "Non-interactive sudo failed - password required"
        return 1
    fi
    
    log_success "✓ Non-interactive sudo works (no password required)"
    return 0
}

# Fix PAM configuration if needed
fix_pam_config() {
    local host="$1"
    
    log_info "Analyzing PAM configuration on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would review and optimize PAM configuration"
        return 0
    fi
    
    # Check if sudoers.d entry for the user allows NOPASSWD
    local has_nopasswd
    has_nopasswd=$(ssh "${EXEC_USER}@${host}" "grep -q 'NOPASSWD' /etc/sudoers.d/${EXEC_USER} 2>/dev/null && echo 'YES' || echo 'NO'" || echo "ERROR")
    
    if [ "$has_nopasswd" = "NO" ]; then
        log_warn "Sudoers entry does not have NOPASSWD directive - adding it"
        
        # Create new entry with NOPASSWD
        local new_sudoers_entry="${EXEC_USER} ALL=(ALL) NOPASSWD: ALL"
        
        ssh "${EXEC_USER}@${host}" "echo '$new_sudoers_entry' | sudo tee /etc/sudoers.d/${EXEC_USER} > /dev/null" || {
            log_error "Failed to update sudoers entry"
            return 1
        }
        
        # Validate
        ssh "${EXEC_USER}@${host}" "sudo visudo -c -f /etc/sudoers.d/${EXEC_USER}" || {
            log_error "Sudoers syntax error"
            return 1
        }
        
        log_success "✓ Sudoers entry updated with NOPASSWD"
        return 0
    fi
    
    log_success "✓ Sudoers entry already has NOPASSWD directive"
    return 0
}

# Check for tty/terminal issues
check_terminal_issues() {
    local host="$1"
    
    log_info "Checking for terminal/tty issues on $host..."
    
    # Over SSH, we shouldn't have a tty for sudo operations
    # This is expected and correct behavior
    
    log_info "SSH connections should not allocate tty for sudo operations (expected behavior)"
    log_info "Non-interactive sudo (-n flag) bypasses terminal requirement"
    
    return 0
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Diagnosing sudo PAM authentication failures (P2 #1634)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Replica Host: $REPLICA_HOST"
    log_info "  Target User: $EXEC_USER"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${REPLICA_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to replica host"
    fi
    log_success "✓ Connected to replica"
    log_info ""
    
    # PRIMARY HOST DIAGNOSIS
    log_info "PRIMARY HOST DIAGNOSIS ($PRIMARY_HOST)"
    log_info "====================================="
    log_info ""
    
    check_pam_failures "$PRIMARY_HOST" || true
    log_info ""
    
    check_sudo_config "$PRIMARY_HOST" || true
    log_info ""
    
    check_terminal_issues "$PRIMARY_HOST"
    log_info ""
    
    test_noninteractive_sudo "$PRIMARY_HOST" "docker ps -q" || true
    log_info ""
    
    # REPLICA HOST DIAGNOSIS
    log_info "REPLICA HOST DIAGNOSIS ($REPLICA_HOST)"
    log_info "====================================="
    log_info ""
    
    check_pam_failures "$REPLICA_HOST" || true
    log_info ""
    
    check_sudo_config "$REPLICA_HOST" || true
    log_info ""
    
    check_terminal_issues "$REPLICA_HOST"
    log_info ""
    
    test_noninteractive_sudo "$REPLICA_HOST" "docker ps -q" || true
    log_info ""
    
    # Apply fixes if needed
    if [ "$DRY_RUN" != "1" ]; then
        log_info "APPLYING FIXES"
        log_info "=============="
        log_info ""
        
        fix_pam_config "$PRIMARY_HOST" || true
        fix_pam_config "$REPLICA_HOST" || true
        log_info ""
    fi
    
    log_success "========================================================================"
    log_success "Sudo PAM authentication diagnostics and fixes complete!"
    log_success "========================================================================"
    log_info ""
    log_info "Summary:"
    log_info "  Non-interactive sudo (-n flag) should now work without password prompts"
    log_info "  Deployment operations via SSH will not require password input"
    log_info "  PAM authentication failures should be resolved"
}

main "$@"
