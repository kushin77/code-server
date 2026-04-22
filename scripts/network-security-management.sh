#!/usr/bin/env bash
################################################################################
# @file        scripts/network-security-management.sh
# @module      security/network
# @description Network security management for zero-trust access (iptables, audit)
# @owner       platform
# @status      active
#
# USAGE
#   scripts/network-security-management.sh [apply|verify|audit]
#
# ENVIRONMENT VARIABLES (from .env, loaded by _common/init.sh)
#   DEPLOY_HOST       - Production host IP/FQDN (e.g., 192.168.168.31)
#   DEPLOY_USER       - SSH user (e.g., akushnir)
#   DOMAIN            - Public domain (e.g., kushnir.cloud)
#
# EXIT CODES
#   0 - Success
#   1 - General error
#   2 - Config error
#   127 - Missing required command
#
# NOTES
#   - This script follows GOV-001 (Canonical Libraries) and GOV-002 (Metadata Headers)
#   - All configuration comes from environment variables, never hardcoded
#   - All errors use log_error / log_fatal from canonical logging library
#   - See scripts/_common/ for shared functions
#
# Last Updated: April 17, 2026
################################################################################

set -euo pipefail

################################################################################
# INITIALIZATION
################################################################################

# Get directory of this script and source the canonical initialization module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Canonical name for this script (used in logging/metrics)
SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION & VALIDATION
################################################################################

# Declare all configuration variables here (sourced from environment by init.sh)
readonly ALLOWED_EGRESS_PORTS=(80 443 53)  # HTTP, HTTPS, DNS
readonly ALLOWED_EGRESS_HOSTS=("github.com" "registry-1.docker.io" "auth.docker.io" "registry.docker.io" "index.docker.io" "download.docker.com" "api.github.com" "raw.githubusercontent.com")
readonly DOCKER_NETWORK_SUBNET="172.20.0.0/16"
readonly AUDIT_LOG_FILE="/var/log/zero-trust-audit.log"

# Validate required commands exist (use canonical helper from _common/utils.sh)
require_command "iptables" "iptables is required for network security"
require_command "docker" "Docker is required to run this script"

################################################################################
# HELPER FUNCTIONS (script-specific, not in _common/)
################################################################################

# HELPER FUNCTIONS (script-specific, not in _common/)

# Apply iptables rules for zero-trust egress
apply_iptables_rules() {
    log_info "Applying zero-trust iptables egress rules"
    
    # Create audit chain
    iptables -t filter -N ZERO_TRUST_AUDIT 2>/dev/null || true
    iptables -t filter -F ZERO_TRUST_AUDIT
    
    # Log all outbound connections
    iptables -t filter -A ZERO_TRUST_AUDIT -j LOG --log-prefix "ZERO-TRUST-OUT: " --log-level 6
    
    # Allow DNS
    iptables -t filter -A ZERO_TRUST_AUDIT -p udp --dport 53 -j ACCEPT
    iptables -t filter -A ZERO_TRUST_AUDIT -p tcp --dport 53 -j ACCEPT
    
    # Allow HTTP/HTTPS to allowed hosts
    for host in "${ALLOWED_EGRESS_HOSTS[@]}"; do
        # Resolve host to IP (simplified - in practice use getent or similar)
        host_ip=$(getent hosts "$host" | awk '{print $1}' | head -1)
        if [[ -n "$host_ip" ]]; then
            iptables -t filter -A ZERO_TRUST_AUDIT -d "$host_ip" -p tcp --dport 80 -j ACCEPT
            iptables -t filter -A ZERO_TRUST_AUDIT -d "$host_ip" -p tcp --dport 443 -j ACCEPT
        fi
    done
    
    # Allow Docker network internal traffic
    iptables -t filter -A ZERO_TRUST_AUDIT -s "$DOCKER_NETWORK_SUBNET" -d "$DOCKER_NETWORK_SUBNET" -j ACCEPT
    
    # Allow localhost
    iptables -t filter -A ZERO_TRUST_AUDIT -d 127.0.0.1 -j ACCEPT
    iptables -t filter -A ZERO_TRUST_AUDIT -d ::1 -j ACCEPT
    
    # Drop everything else
    iptables -t filter -A ZERO_TRUST_AUDIT -j DROP
    
    # Insert audit chain into OUTPUT chain
    iptables -t filter -C OUTPUT -j ZERO_TRUST_AUDIT 2>/dev/null || iptables -t filter -I OUTPUT -j ZERO_TRUST_AUDIT
    
    log_info "Iptables rules applied successfully"
}

# Verify iptables rules
verify_iptables_rules() {
    log_info "Verifying iptables rules"
    
    if ! iptables -t filter -L ZERO_TRUST_AUDIT >/dev/null 2>&1; then
        log_error "ZERO_TRUST_AUDIT chain not found"
        return 1
    fi
    
    local rule_count
    rule_count=$(iptables -t filter -L ZERO_TRUST_AUDIT | wc -l)
    if [[ $rule_count -lt 5 ]]; then
        log_warn "ZERO_TRUST_AUDIT chain has fewer rules than expected ($rule_count)"
    fi
    
    log_info "Iptables rules verified"
    return 0
}

# Show audit logs
show_audit_logs() {
    log_info "Showing recent zero-trust audit logs"
    
    if [[ -f "$AUDIT_LOG_FILE" ]]; then
        tail -50 "$AUDIT_LOG_FILE" | grep "ZERO-TRUST"
    else
        log_warn "Audit log file not found: $AUDIT_LOG_FILE"
        # Try journalctl or dmesg
        journalctl -k -g "ZERO-TRUST" --since "1 hour ago" 2>/dev/null || dmesg | grep "ZERO-TRUST" | tail -20
    fi
}

# Clean up iptables rules
cleanup_iptables_rules() {
    log_info "Cleaning up iptables rules"
    
    iptables -t filter -D OUTPUT -j ZERO_TRUST_AUDIT 2>/dev/null || true
    iptables -t filter -F ZERO_TRUST_AUDIT 2>/dev/null || true
    iptables -t filter -X ZERO_TRUST_AUDIT 2>/dev/null || true
    
    log_info "Iptables rules cleaned up"
}

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    log_info "Starting Network Security Management"
    
    local command="${1:-}"
    
    case "$command" in
        apply)
            apply_iptables_rules
            ;;
        verify)
            verify_iptables_rules
            ;;
        audit)
            show_audit_logs
            ;;
        cleanup)
            cleanup_iptables_rules
            ;;
        *)
            log_error "Usage: $SCRIPT_NAME {apply|verify|audit|cleanup}"
            log_error "  apply   - Apply zero-trust iptables egress rules"
            log_error "  verify  - Verify iptables rules are in place"
            log_error "  audit   - Show recent audit logs"
            log_error "  cleanup - Remove iptables rules"
            return 2
            ;;
    esac
    
    log_info "Network Security Management completed successfully"
    return 0
}

################################################################################
# ENTRYPOINT
################################################################################

# Trap signals and ensure cleanup (error-handler.sh provides ERR trap)
trap cleanup EXIT

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "$SCRIPT_NAME exited with code $exit_code"
    fi
    return $exit_code
}

# Run main function and exit with its code
main "$@"
exit $?
