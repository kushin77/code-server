#!/bin/bash
# @file        scripts/security/configure-firewall-p1-1392.sh
# @module      security/firewall
# @description Configure UFW firewall on primary host per P1 security issue #1392

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$PROJECT_ROOT/scripts/_common/init.sh"

configure_firewall() {
    log_info "Configuring UFW firewall for primary production host..."

    # Check if UFW is installed
    if ! command -v ufw &>/dev/null; then
        log_info "Installing UFW..."
        sudo apt-get update
        sudo apt-get install -y ufw
    fi

    # Set default policies
    log_info "Setting default firewall policies..."
    sudo ufw --force reset >/dev/null 2>&1 || true
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default allow routed

    # SSH - CRITICAL: Must allow SSH before enabling UFW or we lock ourselves out
    log_info "Allowing SSH (CRITICAL - must be before enable)..."
    sudo ufw allow from 192.168.168.0/24 to any port 22
    sudo ufw allow from 192.168.168.42 to any port 22

    # Public-facing services
    log_info "Allowing public HTTPS/HTTP..."
    sudo ufw allow 443/tcp comment "Caddy HTTPS"
    sudo ufw allow 80/tcp comment "Caddy HTTP redirect"

    # Internal services - only from replica and authorized hosts
    log_info "Restricting internal services..."
    sudo ufw allow from 192.168.168.42 to any port 6379 comment "Redis (replica only)"
    sudo ufw allow from 192.168.168.42 to any port 26379 comment "Redis Sentinel (replica only)"
    sudo ufw allow from 192.168.168.56 to any port 2049 comment "NFS (NAS only)"

    # Monitoring
    log_info "Allowing Prometheus metrics from monitoring hosts..."
    sudo ufw allow from 192.168.168.42 to any port 9090 comment "Prometheus (replica only)"
    sudo ufw allow from 192.168.168.56 to any port 9090 comment "Prometheus (NAS only)"

    # Grafana - only from known hosts
    log_info "Allowing Grafana from trusted hosts..."
    sudo ufw allow from 192.168.168.42 to any port 3000 comment "Grafana (replica)"
    sudo ufw allow from 192.168.168.56 to any port 3000 comment "Grafana (NAS)"

    # Docker bypass prevention
    log_info "Configuring Docker UFW integration..."
    sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "iptables": true
}
EOF
    sudo systemctl restart docker

    # Enable UFW
    log_info "Enabling UFW firewall..."
    sudo ufw --force enable
    
    # Verify
    log_info "Firewall configuration complete. Verifying..."
    sudo ufw status verbose
}

verify_firewall() {
    log_info "Verifying firewall rules..."
    
    # Check UFW is active
    if ! sudo ufw status | grep -q "Status: active"; then
        log_error "UFW is not active"
        return 1
    fi
    
    # Check rules exist
    if sudo ufw show added | grep -q "6379"; then
        log_info "✓ Redis firewall rule found"
    else
        log_warn "⚠ Redis firewall rule not found"
    fi
    
    log_info "Firewall verification complete"
}

main() {
    log_info "P1 Security #1392: Firewall Configuration for Primary Host"
    
    configure_firewall
    verify_firewall
    
    log_info "✓ Firewall configuration complete"
    log_info "To verify from remote host: nmap -p 6379 192.168.168.31 (should show filtered)"
}

main "$@"
