#!/bin/bash
# Network Security Hardening - Firewall Rules Configuration
# Implements strict ingress/egress rules on both code-server hosts
# Principle: Allow only necessary traffic, deny everything else

set -euo pipefail

trap 'log_error "Security configuration failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp' EXIT

log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_success() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_info "Network Security Hardening - Firewall Configuration"
log_info "======================================================"
log_info ""

# Create firewall rules file
FIREWALL_RULES_FILE="/etc/security/firewall-rules.sh"
log_info "Creating firewall rules: $FIREWALL_RULES_FILE"

cat > /tmp/firewall-rules.sh << 'EOF'
#!/bin/bash
# Firewall Rules for code-server Infrastructure
# Applied via ufw (Ubuntu firewall) or iptables (CentOS/RHEL)
# Implements zero-trust network model with explicit allow rules

set -euo pipefail

# Initialize firewall
init_firewall() {
  if command -v ufw &> /dev/null; then
    # Ubuntu UFW firewall
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw logging on
    ufw logging medium
  elif command -v firewall-cmd &> /dev/null; then
    # CentOS/RHEL firewalld
    firewall-cmd --set-default-zone=drop
    firewall-cmd --reload
  fi
}

# Management Access
allow_management_access() {
  # SSH for infrastructure management (restricted to admin networks)
  ufw allow from 192.168.168.0/24 to any port 22/tcp comment "SSH from internal network"
  
  # Restrict to specific admin hosts if needed
  # ufw allow from 192.168.168.10 to any port 22/tcp comment "SSH from admin workstation"
}

# Internal Infrastructure Traffic
allow_internal_traffic() {
  # Docker overlay network (internal only)
  ufw allow from 10.0.0.0/8 to any comment "Docker overlay network"
  ufw allow from 172.16.0.0/12 to any comment "Docker bridge network"
  
  # Code-server replication (primary to replica)
  ufw allow from 192.168.168.31 to 192.168.168.42 port 2375/tcp comment "Docker API (primary→replica)"
  
  # Keepalived VRRP traffic (inter-host)
  ufw allow from 192.168.168.31 to 192.168.168.42 port 112 comment "VRRP (keepalived)"
  ufw allow from 192.168.168.42 to 192.168.168.31 port 112 comment "VRRP (keepalived)"
  
  # PostgreSQL replication
  ufw allow from 192.168.168.31 to 192.168.168.42 port 5432/tcp comment "PostgreSQL (primary→replica)"
}

# Public-Facing Services
allow_public_services() {
  # HTTP(S) - public access required
  ufw allow 80/tcp comment "HTTP"
  ufw allow 443/tcp comment "HTTPS"
  
  # code-server API (internal only, not publicly exposed)
  # ufw allow from 192.168.168.0/24 to any port 8080/tcp comment "code-server API"
}

# Monitoring & Observability
allow_monitoring() {
  # Prometheus scrape endpoints (internal only)
  ufw allow from 192.168.168.0/24 to any port 9090/tcp comment "Prometheus"
  ufw allow from 192.168.168.0/24 to any port 9100/tcp comment "Node Exporter"
  ufw allow from 192.168.168.0/24 to any port 9091/tcp comment "Custom metrics exporter"
  ufw allow from 192.168.168.0/24 to any port 8080/tcp comment "cAdvisor"
  
  # Grafana (internal only)
  ufw allow from 192.168.168.0/24 to any port 3000/tcp comment "Grafana"
}

# Remote Storage Access
allow_remote_storage() {
  # MinIO S3 backend (internal only)
  ufw allow from 192.168.168.0/24 to any port 9000/tcp comment "MinIO API"
  ufw allow from 192.168.168.0/24 to any port 9001/tcp comment "MinIO console"
}

# Logging & Audit
allow_logging() {
  # Syslog (internal only)
  ufw allow from 192.168.168.0/24 to any port 514/udp comment "Syslog"
  
  # Promtail log forwarding (internal)
  ufw allow from 192.168.168.0/24 to any port 3100/tcp comment "Loki logs"
}

# ICMP for diagnostics (ping, traceroute)
allow_icmp() {
  # Allow ICMP (ping, traceroute) from internal network only
  ufw allow from 192.168.168.0/24 icmp comment "ICMP (ping) from internal"
}

# DNS resolution
allow_dns() {
  # DNS to external resolvers (outbound only - already allowed by default)
  # Internal DNS server (if available)
  # ufw allow from any to 192.168.168.53 port 53/tcp comment "DNS TCP"
  # ufw allow from any to 192.168.168.53 port 53/udp comment "DNS UDP"
}

# Apply all rules
apply_rules() {
  init_firewall
  allow_management_access
  allow_internal_traffic
  allow_public_services
  allow_monitoring
  allow_remote_storage
  allow_logging
  allow_icmp
  allow_dns
  
  # Enable firewall
  ufw --force enable
  
  echo "✓ All firewall rules applied"
}

# Show current rules
show_rules() {
  ufw status numbered
}

# Rollback to previous state
rollback_rules() {
  ufw --force reset
  echo "✓ Firewall rules reset to defaults"
}

# Main
case "${1:-apply}" in
  apply)
    apply_rules
    show_rules
    ;;
  show)
    show_rules
    ;;
  rollback)
    rollback_rules
    ;;
  *)
    echo "Usage: $0 {apply|show|rollback}"
    exit 1
    ;;
esac
EOF

chmod +x /tmp/firewall-rules.sh
log_success "Firewall rules script created"
echo ""

# Display rules
log_info "Firewall Rules Summary:"
log_info "======================"
grep "ufw allow" /tmp/firewall-rules.sh | head -20
echo "..."
log_info ""
log_info "To apply rules, run:"
log_info "  sudo bash /tmp/firewall-rules.sh apply"
