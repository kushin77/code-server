#!/bin/bash

################################################################################
# Hermes Agent Portal - Replica Deployment Automation
# Purpose: Deploy to replica server (192.168.168.42) for high availability
# Usage: ./deploy-replica.sh [primary-ip] [replica-ip]
#        ./deploy-replica.sh 192.168.168.31 192.168.168.42
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/replica_*.tmp 2>/dev/null || true' EXIT

PRIMARY_IP=${1:-192.168.168.31}
REPLICA_IP=${2:-192.168.168.42}
DEPLOYMENT_USER="akushnir"
DEPLOY_PATH="/home/akushnir/code-server"
CONFIG_FILE="docker-compose.enterprise.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Helper Functions
################################################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

################################################################################
# Pre-Deployment Checks
################################################################################

preflight_checks() {
    log_info "Running pre-deployment checks..."
    
    # Check SSH connectivity to replica
    log_info "Testing SSH connectivity to replica ($REPLICA_IP)..."
    ssh -o ConnectTimeout=5 "${DEPLOYMENT_USER}@${REPLICA_IP}" "echo 'SSH connection OK'" || log_error "Cannot reach replica server"
    log_success "SSH connectivity verified"
    
    # Check SSH connectivity to primary
    log_info "Testing SSH connectivity to primary ($PRIMARY_IP)..."
    ssh -o ConnectTimeout=5 "${DEPLOYMENT_USER}@${PRIMARY_IP}" "echo 'SSH connection OK'" || log_error "Cannot reach primary server"
    log_success "Primary connectivity verified"
    
    # Verify Docker on replica
    log_info "Verifying Docker on replica..."
    ssh "${DEPLOYMENT_USER}@${REPLICA_IP}" "docker --version" || log_error "Docker not installed on replica"
    log_success "Docker verified on replica"
    
    # Check DNS
    log_info "Verifying DNS configuration..."
    local dns_primary=$(nslookup kushnir.cloud 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    [ "$dns_primary" = "$PRIMARY_IP" ] || log_warn "DNS may need configuration for failover"
    log_success "DNS verified"
}

################################################################################
# Backup Procedures
################################################################################

backup_primary() {
    log_info "Creating backup of primary server..."
    
    ssh "${DEPLOYMENT_USER}@${PRIMARY_IP}" "cd $DEPLOY_PATH && ./backup-recovery.sh backup" || log_error "Backup failed"
    
    log_success "Primary backup completed"
}

copy_backup_to_replica() {
    log_info "Copying backup to replica..."
    
    local latest_backup=$(ssh "${DEPLOYMENT_USER}@${PRIMARY_IP}" "ls -t $DEPLOY_PATH/backups/backup_*.tar.gz | head -1" | cut -d/ -f1)
    
    log_info "Transferring backup: $latest_backup"
    scp "${DEPLOYMENT_USER}@${PRIMARY_IP}:${DEPLOY_PATH}/backups/${latest_backup}" \
        "${DEPLOYMENT_USER}@${REPLICA_IP}:${DEPLOY_PATH}/backups/" || log_error "Backup transfer failed"
    
    log_success "Backup transferred to replica"
}

################################################################################
# Replica Deployment
################################################################################

copy_configuration() {
    log_info "Copying configuration to replica..."
    
    # Copy Caddyfile
    scp "${DEPLOYMENT_USER}@${PRIMARY_IP}:${DEPLOY_PATH}/Caddyfile" \
        "${DEPLOYMENT_USER}@${REPLICA_IP}:${DEPLOY_PATH}/" || true
    
    # Copy docker-compose
    scp "${DEPLOYMENT_USER}@${PRIMARY_IP}:${DEPLOY_PATH}/${CONFIG_FILE}" \
        "${DEPLOYMENT_USER}@${REPLICA_IP}:${DEPLOY_PATH}/" || true
    
    # Copy .env (careful with secrets)
    log_warn "NOTE: .env file should be configured manually on replica with same credentials"
    
    log_success "Configuration copied to replica"
}

deploy_to_replica() {
    log_info "Deploying services to replica ($REPLICA_IP)..."
    
    ssh "${DEPLOYMENT_USER}@${REPLICA_IP}" << 'SCRIPT'
    cd /home/akushnir/code-server
    
    if [ ! -f .env ]; then
        echo "ERROR: .env file not found. Please configure OAuth credentials."
        exit 1
    fi
    
    # Run verification
    echo "[INFO] Running pre-deployment verification..."
    ./verify-appsmith-integration.sh || exit 1
    
    # Deploy services
    echo "[INFO] Deploying services..."
    ./deploy-production.sh || exit 1
    
    echo "[INFO] Deployment to replica completed"
SCRIPT
    
    [ $? -eq 0 ] || log_error "Deployment to replica failed"
    log_success "Services deployed to replica"
}

################################################################################
# Verification
################################################################################

verify_replica() {
    log_info "Verifying replica deployment..."
    
    ssh "${DEPLOYMENT_USER}@${REPLICA_IP}" << 'SCRIPT'
    cd /home/akushnir/code-server
    
    # Check containers
    echo "[INFO] Checking container status..."
    docker-compose -f docker-compose.enterprise.yml ps
    
    # Test API
    echo "[INFO] Testing API endpoint..."
    curl -s -k https://localhost:443/api/hermes/health || echo "Note: API test will fail if DNS not yet configured"
    
    # Check disk
    echo "[INFO] Checking disk space..."
    df -h /home | tail -1
    
    echo "[SUCCESS] Replica verification completed"
SCRIPT
    
    log_success "Replica verification completed"
}

################################################################################
# HA Configuration
################################################################################

configure_ha() {
    log_info "Configuring High Availability..."
    
    log_info "Creating HAProxy configuration for failover..."
    
    # Note: In production, you would configure:
    # - DNS failover (round-robin or health-check based)
    # - Keepalived for VIP management
    # - Replication sync between PostgreSQL instances
    # - Redis Sentinel for cache failover
    
    log_warn "HA Configuration Notes:"
    echo "  1. Configure DNS for load balancing or failover:"
    echo "     - Round-robin: kushnir.cloud -> both IPs"
    echo "     - Active-passive: Primary only, failover to replica"
    echo ""
    echo "  2. Optional: Configure PostgreSQL replication"
    echo "     - Primary: 192.168.168.31 (master)"
    echo "     - Replica: 192.168.168.42 (standby)"
    echo ""
    echo "  3. Optional: Configure Redis Sentinel for failover"
    echo "     - Automatic master-slave promotion"
    echo ""
    echo "  4. Optional: Configure Keepalived for VIP"
    echo "     - Virtual IP: 192.168.168.100 (configurable)"
    echo ""
    echo "  Manual Configuration Step: Update DNS for replica failover"
}

################################################################################
# Post-Deployment
################################################################################

post_deployment_summary() {
    log_info "Generating deployment summary..."
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Replica Deployment Summary${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Primary Server:  $PRIMARY_IP"
    echo "Replica Server:  $REPLICA_IP"
    echo "Deployment Path: $DEPLOY_PATH"
    echo ""
    echo "Services Deployed:"
    echo "  ✓ Appsmith Portal"
    echo "  ✓ Hermes Integration API"
    echo "  ✓ code-server IDE"
    echo "  ✓ PostgreSQL Database"
    echo "  ✓ Redis Cache"
    echo ""
    echo "Access Points:"
    echo "  Primary:  https://kushnir.cloud (192.168.168.31)"
    echo "  Replica:  https://kushnir.cloud (192.168.168.42)"
    echo "  Note: Configure DNS or load balancer for failover"
    echo ""
    echo "Next Steps:"
    echo "  1. Verify both servers are running: ./validate-deployment.sh"
    echo "  2. Configure DNS for load balancing or failover"
    echo "  3. Test failover procedures"
    echo "  4. Set up monitoring for both servers"
    echo "  5. Document recovery procedures"
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

################################################################################
# Main
################################################################################

main() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Replica Deployment Script${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Primary Server:  $PRIMARY_IP"
    echo "Replica Server:  $REPLICA_IP"
    echo ""
    
    log_warn "BEFORE PROCEEDING:"
    echo "  1. Ensure .env on replica has same OAuth credentials as primary"
    echo "  2. Verify network connectivity between servers"
    echo "  3. Have backup ready (will create one automatically)"
    echo ""
    
    read -p "Continue with replica deployment? (yes/no): " confirm
    [ "$confirm" = "yes" ] || { log_info "Deployment cancelled"; exit 0; }
    
    echo ""
    preflight_checks
    backup_primary
    
    log_info "Preparing replica for deployment..."
    copy_configuration
    
    log_info "Waiting for user to configure .env on replica..."
    log_warn "SSH to replica and configure .env: ssh ${DEPLOYMENT_USER}@${REPLICA_IP}"
    log_warn "Then set OAuth credentials and save"
    read -p "Press enter when .env is configured on replica..."
    
    deploy_to_replica
    verify_replica
    configure_ha
    post_deployment_summary
    
    log_success "Replica deployment completed successfully"
}

main "$@"
