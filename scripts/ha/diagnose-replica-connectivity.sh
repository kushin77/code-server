#!/bin/bash
###############################################################################
# Phase 6: Multi-Cluster HA Architecture - Pre-Deployment Diagnostic
#
# Validates replica host connectivity and prerequisites before
# multi-cluster deployment.
#
# Usage:
#   bash scripts/ha/diagnose-replica-connectivity.sh
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Diagnostic failed at line $LINENO"; exit 1' ERR
trap 'log_info "Diagnostic cleanup..."; cleanup_diagnostic || true' EXIT

# Configuration
REPLICA_HOST="${REPLICA_HOST:?REPLICA_HOST must be set}"
REPLICA_SSH_PORT="22"
REPLICA_USER="deployment"
DIAGNOSTIC_DIR="$REPO_ROOT/artifacts/ha-diagnostics"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

cleanup_diagnostic() {
    log_info "Diagnostic cleanup..."
}

# Test basic connectivity
test_connectivity() {
    log_info "Testing basic connectivity to replica host..."
    
    # ICMP ping
    if timeout 5 ping -c 1 "$REPLICA_HOST" &>/dev/null; then
        log_success "ICMP ping: REACHABLE"
        return 0
    else
        log_warning "ICMP ping: UNREACHABLE"
        return 1
    fi
}

# Test SSH connectivity
test_ssh() {
    log_info "Testing SSH connectivity..."
    
    if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "$REPLICA_USER@$REPLICA_HOST" "echo SSH_TEST_SUCCESSFUL" 2>/dev/null; then
        log_success "SSH: CONNECTED"
        return 0
    else
        log_warning "SSH: CONNECTION_FAILED"
        return 1
    fi
}

# Check fail2ban status on primary
check_fail2ban_primary() {
    log_info "Checking fail2ban status on primary..."
    
    if docker-compose -f "$PROJECT_ROOT/docker-compose.yml" exec -T \
        $(docker-compose -f "$PROJECT_ROOT/docker-compose.yml" ps --services 2>/dev/null | grep -E 'web|app' | head -1) \
        fail2ban-client status 2>/dev/null; then
        log_success "fail2ban detected on primary"
    else
        log_warning "fail2ban status unknown"
    fi
}

# Generate diagnostic report
generate_diagnostic_report() {
    mkdir -p "$DIAGNOSTIC_DIR"
    
    local report="$DIAGNOSTIC_DIR/connectivity-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "═════════════════════════════════════════════════════════"
        echo "PHASE 6 - REPLICA HOST CONNECTIVITY DIAGNOSTIC"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        echo "Diagnostic Timestamp: $(date)"
        echo "Replica Host: $REPLICA_HOST"
        echo "SSH User: $REPLICA_USER"
        echo ""
        
        echo "═════════════════════════════════════════════════════════"
        echo "CONNECTIVITY TESTS"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        
        echo "1. ICMP Connectivity"
        if timeout 5 ping -c 1 "$REPLICA_HOST" 2>&1; then
            echo "   Status: ✓ REACHABLE"
        else
            echo "   Status: ✗ UNREACHABLE"
            echo "   Action: Check network routing, firewall rules"
        fi
        echo ""
        
        echo "2. Network Routing"
        echo "   Route to replica:"
        ip route get "$REPLICA_HOST" 2>/dev/null || echo "   (Route lookup failed)"
        echo ""
        
        echo "3. Firewall Status"
        if command -v ufw &>/dev/null; then
            echo "   UFW Status:"
            sudo ufw status 2>/dev/null || echo "   (Requires sudo)"
        fi
        if command -v firewall-cmd &>/dev/null; then
            echo "   Firewalld Status:"
            sudo firewall-cmd --list-all 2>/dev/null || echo "   (Requires sudo)"
        fi
        echo ""
        
        echo "4. SSH Connectivity"
        if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
            "$REPLICA_USER@$REPLICA_HOST" "echo SSH_OK" 2>&1; then
            echo "   Status: ✓ CONNECTED"
        else
            echo "   Status: ✗ CONNECTION_FAILED"
            echo "   Action: Check SSH keys, firewall, fail2ban"
        fi
        echo ""
        
        echo "═════════════════════════════════════════════════════════"
        echo "RESOLUTION STEPS"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        echo "If ICMP unreachable:"
        echo "  1. Verify network configuration"
        echo "  2. Check firewall rules"
        echo "  3. Verify routing table"
        echo ""
        echo "If SSH fails:"
        echo "  1. Check SSH keys in ~/.ssh/authorized_keys on replica"
        echo "  2. Verify SSH service is running"
        echo "  3. Check fail2ban status: sudo fail2ban-client status"
        echo "  4. If fail2banned: sudo fail2ban-client set sshd unbanip <IP>"
        echo ""
        echo "For Infrastructure Team:"
        echo "  1. SSH to replica host: ssh $REPLICA_USER@$REPLICA_HOST"
        echo "  2. Check fail2ban: sudo fail2ban-client status"
        echo "  3. Unban primary if needed: sudo fail2ban-client set sshd unbanip <PRIMARY_IP>"
        echo "  4. Verify SSH service: sudo systemctl status ssh"
        echo ""
        
        echo "═════════════════════════════════════════════════════════"
        echo "NEXT STEPS"
        echo "═════════════════════════════════════════════════════════"
        echo ""
        echo "Once connectivity is restored:"
        echo "  1. Run: bash scripts/ha/setup-replica-cluster.sh"
        echo "  2. Deploy: bash scripts/ha/deploy-active-active.sh"
        echo "  3. Validate: bash scripts/ha/validate-ha-setup.sh"
        echo ""
        
    } | tee "$report"
    
    log_success "Diagnostic report: $report"
}

# Main execution
main() {
    log_info "════════════════════════════════════════════════════════"
    log_info "Phase 6: Replica Connectivity Diagnostic"
    log_info "════════════════════════════════════════════════════════"
    
    mkdir -p "$DIAGNOSTIC_DIR"
    
    # Run tests
    connectivity_ok=false
    ssh_ok=false
    
    if test_connectivity; then
        connectivity_ok=true
    fi
    
    if test_ssh; then
        ssh_ok=true
    fi
    
    # Generate report
    generate_diagnostic_report
    
    # Summary
    echo ""
    log_info "════════════════════════════════════════════════════════"
    
    if [ "$connectivity_ok" = true ] && [ "$ssh_ok" = true ]; then
        log_success "Replica host is ACCESSIBLE"
        log_info "Proceed with Phase 6 deployment:"
        log_info "  bash scripts/ha/setup-replica-cluster.sh"
    else
        log_warning "Replica host is UNREACHABLE or SSH failed"
        log_info "Action Required:"
        log_info "  1. Review diagnostic report in $DIAGNOSTIC_DIR"
        log_info "  2. Contact infrastructure team to:"
        log_info "     - Verify fail2ban configuration"
        log_info "     - Unban primary host IP if needed"
        log_info "     - Restore network connectivity"
        log_info "  3. Re-run this diagnostic after connectivity restored"
    fi
    
    log_info "════════════════════════════════════════════════════════"
}

main
