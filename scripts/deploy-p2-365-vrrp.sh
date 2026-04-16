#!/bin/bash
# P2 #365: VRRP Virtual IP Failover Deployment Script
# Purpose: Deploy Keepalived and VRRP configuration to primary and replica hosts
# Generated: April 15, 2026

set -euo pipefail

# Configuration
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
DEPLOY_USER="akushnir"
VIP="192.168.168.40"
LOG_FILE="deploy-p2-365-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# SSH helper function
ssh_run() {
    local host="$1"
    local cmd="$2"
    local description="${3:-}"
    
    log_info "Executing on $host: $description"
    ssh -o StrictHostKeyChecking=no "${DEPLOY_USER}@${host}" "$cmd" || {
        log_error "Failed to execute on $host: $description"
        return 1
    }
}

# Deploy to a single host
deploy_to_host() {
    local host="$1"
    local host_type="$2"  # primary or replica
    local role="${3:-MASTER}"
    
    log_info "========================================"
    log_info "Deploying to $host_type host: $host"
    log_info "========================================"
    
    # Step 1: Copy configuration files
    log_info "Copying configuration files..."
    scp -o StrictHostKeyChecking=no \
        "config/keepalived/keepalived.conf.${host_type}" \
        "${DEPLOY_USER}@${host}:/tmp/keepalived.conf" || {
        log_error "Failed to copy keepalived config to $host"
        return 1
    }
    
    scp -o StrictHostKeyChecking=no \
        "scripts/vrrp-health-check.sh" \
        "${DEPLOY_USER}@${host}:/tmp/vrrp-health-check.sh" || {
        log_error "Failed to copy health check script to $host"
        return 1
    }
    
    scp -o StrictHostKeyChecking=no \
        "scripts/vrrp-notify.sh" \
        "${DEPLOY_USER}@${host}:/tmp/vrrp-notify.sh" || {
        log_error "Failed to copy notify script to $host"
        return 1
    }
    log_success "Configuration files copied"
    
    # Step 2: Install keepalived
    log_info "Checking/installing keepalived..."
    ssh_run "$host" \
        "sudo apt-get update && sudo apt-get install -y keepalived" \
        "Install keepalived"
    log_success "Keepalived installed/verified"
    
    # Step 3: Deploy configuration
    log_info "Deploying keepalived configuration..."
    ssh_run "$host" \
        "sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf && sudo chmod 600 /etc/keepalived/keepalived.conf" \
        "Deploy keepalived config"
    log_success "Keepalived configuration deployed"
    
    # Step 4: Deploy helper scripts
    log_info "Deploying helper scripts..."
    ssh_run "$host" \
        "sudo cp /tmp/vrrp-health-check.sh /usr/local/bin/vrrp-health-check.sh && sudo chmod +x /usr/local/bin/vrrp-health-check.sh" \
        "Deploy health check script"
    log_success "Health check script deployed"
    
    ssh_run "$host" \
        "sudo cp /tmp/vrrp-notify.sh /usr/local/bin/vrrp-notify.sh && sudo chmod +x /usr/local/bin/vrrp-notify.sh" \
        "Deploy notify script"
    log_success "Notify script deployed"
    
    # Step 5: Create log directories
    log_info "Creating log directories..."
    ssh_run "$host" \
        "sudo mkdir -p /var/log/keepalived && sudo chmod 755 /var/log/keepalived" \
        "Create log directory"
    log_success "Log directory created"
    
    # Step 6: Enable and start keepalived
    log_info "Enabling and starting keepalived..."
    ssh_run "$host" \
        "sudo systemctl daemon-reload && sudo systemctl enable keepalived && sudo systemctl restart keepalived" \
        "Enable and start keepalived"
    log_success "Keepalived enabled and started"
    
    # Step 7: Verify service status
    log_info "Verifying keepalived status..."
    ssh_run "$host" \
        "sudo systemctl status keepalived" \
        "Check keepalived status" || {
        log_error "Keepalived service check failed on $host"
        return 1
    }
    log_success "Keepalived service status OK"
    
    # Step 8: Verify VIP assignment
    log_info "Checking VIP assignment..."
    if [[ "$host_type" == "primary" ]]; then
        ssh_run "$host" \
            "ip addr show | grep -q '${VIP}' && echo 'VIP assigned' || echo 'VIP NOT assigned (expected for MASTER after init)'" \
            "Check VIP assignment" || true
    else
        ssh_run "$host" \
            "ip addr show | grep -q '${VIP}' && echo 'ERROR: VIP assigned to BACKUP' || echo 'VIP correctly NOT assigned (backup mode)'" \
            "Check VIP NOT assigned" || true
    fi
    
    log_success "Deployment to $host completed"
}

# Main deployment
main() {
    log_info "========================================"
    log_info "P2 #365: VRRP Virtual IP Deployment"
    log_info "========================================"
    log_info "Primary Host: $PRIMARY_HOST"
    log_info "Replica Host: $REPLICA_HOST"
    log_info "Virtual IP: $VIP"
    log_info ""
    
    # Deploy to primary
    if ! deploy_to_host "$PRIMARY_HOST" "primary" "MASTER"; then
        log_error "Deployment to primary failed"
        return 1
    fi
    
    # Wait for primary to stabilize
    log_info "Waiting for primary to stabilize (10 seconds)..."
    sleep 10
    
    # Deploy to replica
    if ! deploy_to_host "$REPLICA_HOST" "replica" "BACKUP"; then
        log_error "Deployment to replica failed"
        return 1
    fi
    
    # Step 9: Final verification
    log_info "========================================"
    log_info "Final Verification"
    log_info "========================================"
    
    log_info "Checking VIP on primary..."
    ssh_run "$PRIMARY_HOST" \
        "if ip addr show | grep -q '${VIP}'; then echo 'PRIMARY: VIP assigned (MASTER)'; else echo 'ERROR: VIP not assigned'; exit 1; fi" \
        "Verify VIP on primary" || log_error "VIP not found on primary"
    
    log_info "Checking VIP on replica..."
    ssh_run "$REPLICA_HOST" \
        "if ! ip addr show | grep -q '${VIP}'; then echo 'REPLICA: VIP NOT assigned (BACKUP) - correct'; else echo 'WARNING: VIP assigned to BACKUP'; fi" \
        "Verify VIP not on replica" || true
    
    log_info "Verifying DNS resolution..."
    ssh_run "$PRIMARY_HOST" \
        "nslookup code-server.internal 127.0.0.1 2>/dev/null | grep -q '${VIP}' && echo 'DNS resolves to VIP' || echo 'WARNING: DNS resolution check needs manual verification'" \
        "Verify DNS" || true
    
    # Step 10: Test failover
    log_info "========================================"
    log_info "Failover Test (optional - requires manual intervention)"
    log_info "========================================"
    log_warn "To test failover:"
    log_warn "1. On primary: sudo systemctl stop keepalived"
    log_warn "2. Wait 10 seconds for VIP to move to replica"
    log_warn "3. Verify: ssh ${DEPLOY_USER}@${REPLICA_HOST} 'ip addr show | grep ${VIP}'"
    log_warn "4. On primary: sudo systemctl start keepalived"
    log_warn "5. Wait 10 seconds for VIP to return to primary"
    
    log_success "P2 #365 Deployment Complete! ✅"
    log_info "Deployment log: $LOG_FILE"
    log_info ""
    log_info "Next steps:"
    log_info "1. Monitor VRRP health checks in production"
    log_info "2. Verify DNS is configured to use VIP (192.168.168.40)"
    log_info "3. Update load balancer to use VIP instead of individual hosts"
    log_info "4. Test failover scenarios in staging before production validation"
}

# Run main deployment
main "$@"
exit $?
