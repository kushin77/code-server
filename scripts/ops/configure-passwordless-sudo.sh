#!/usr/bin/env bash
# @file        scripts/ops/configure-passwordless-sudo.sh
# @module      infrastructure/deployment-automation
# @description Configure passwordless sudo for akushnir user on both replicas (Issue #1636)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Replica hosts
REPLICA_1="192.168.168.31"
REPLICA_2="192.168.168.42"
SSH_USER="akushnir"

# Function to configure sudo on a single host
configure_replica_sudo() {
    local host="$1"
    local replica_num="${host##*.}"
    
    log_info "Configuring passwordless sudo on Replica $replica_num ($host)..."
    
    # Create sudoers.d entry (requires initial password input)
    cat << 'SUDOERS_CONTENT' | ssh "$SSH_USER@$host" "sudo tee /etc/sudoers.d/akushnir > /dev/null && sudo chmod 0440 /etc/sudoers.d/akushnir"
# Passwordless sudo for akushnir user - enables automated deployment operations
# Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
# Issue: #1636 - Configure passwordless sudo for deployment operations

# Allow all commands without password (with audit logging)
akushnir ALL=(ALL) NOPASSWD: ALL

# Security note: This allows full sudo without password. 
# In production, consider restricting to specific commands:
# akushnir ALL=(ALL) NOPASSWD: /usr/bin/docker, /bin/systemctl, etc.
SUDOERS_CONTENT
    
    if [ $? -eq 0 ]; then
        log_info "✅ Passwordless sudo configured successfully on Replica $replica_num"
        
        # Verify configuration
        log_info "Verifying sudoers configuration..."
        ssh "$SSH_USER@$host" "sudo -n true" && log_info "✅ Verification passed - sudo works without password" || log_fatal "❌ Verification failed"
    else
        log_fatal "Failed to configure sudo on Replica $replica_num"
    fi
}

main() {
    log_info "Starting passwordless sudo configuration for both replicas..."
    
    # Check SSH connectivity
    for host in "$REPLICA_1" "$REPLICA_2"; do
        log_info "Testing SSH connectivity to $host..."
        if ! ssh -o ConnectTimeout=5 "$SSH_USER@$host" "echo OK" > /dev/null 2>&1; then
            log_error "Cannot connect to $host - skipping"
            continue
        fi
        configure_replica_sudo "$host"
    done
    
    log_info "✅ Passwordless sudo configuration complete"
    log_info "Deployment automation can now use sudo commands without password prompts"
}

main "$@"
