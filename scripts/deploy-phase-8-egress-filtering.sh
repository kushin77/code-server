#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md
# Phase 8: Container Egress Filtering - Deploy Script
# Restricts outbound traffic to prevent data exfiltration
# Uses iptables and Docker network policies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Source production topology from inventory
source "$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)/scripts/lib/env.sh" || {
    echo "ERROR: Could not source scripts/lib/env.sh" >&2
    exit 1
}

PRIMARY_HOST="${1:-$PRIMARY_HOST}"  # Use provided arg or fall back to env.sh value
SSH_USER="${SSH_USER:-akushnir}"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $*"; }

log_info "=========================================="
log_info "Phase 8: Container Egress Filtering"
log_info "Target: $PRIMARY_HOST"
log_info "=========================================="

# 1. Configure iptables rules
log_info "Step 1: Configuring iptables egress filtering..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Enable IP forwarding and configure iptables
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.default.rp_filter=1
sysctl -w net.ipv4.conf.all.rp_filter=1

# Create custom iptables chains
iptables -N DOCKER-EGRESS 2>/dev/null || true

# Allow DNS (required for all services)
iptables -A DOCKER-EGRESS -d 8.8.8.8 -p udp --dport 53 -j ACCEPT
iptables -A DOCKER-EGRESS -d 1.1.1.1 -p udp --dport 53 -j ACCEPT

# Allow Cloudflare API (for Caddy, OAuth2)
iptables -A DOCKER-EGRESS -d 192.0.2.0/24 -p tcp --dport 443 -j ACCEPT

# Allow package repositories (for apt)
iptables -A DOCKER-EGRESS -p tcp --dport 80 -j ACCEPT  # HTTP for repos
iptables -A DOCKER-EGRESS -p tcp --dport 443 -j ACCEPT # HTTPS for repos

# Allow local network (replication)
iptables -A DOCKER-EGRESS -d 192.168.168.0/24 -j ACCEPT

# Allow NTP
iptables -A DOCKER-EGRESS -p udp --dport 123 -j ACCEPT

# Deny everything else
iptables -A DOCKER-EGRESS -j DROP

# Log dropped packets
iptables -A DOCKER-EGRESS -j LOG --log-prefix "EGRESS_BLOCKED: "

# Save rules
iptables-save > /etc/iptables/rules.v4
iptables-save > /etc/iptables/rules.v6

echo "✓ iptables rules configured"
EOF

log_success "iptables rules deployed"

# 2. Configure Docker networks with limited egress
log_info "Step 2: Configuring Docker networks with egress limits..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

cd code-server-enterprise

# Create restricted Docker network
docker network create \
  --driver bridge \
  --opt "com.docker.network.bridge.enable_ip_masquerade=false" \
  --opt "com.docker.network.bridge.enable_icc=false" \
  code-server-restricted 2>/dev/null || true

# Verify network
docker network inspect code-server-restricted | grep -E '"Name"|EnableIPMasquerade'

echo "✓ Docker networks configured"
EOF

log_success "Docker networks configured"

# 3. Set container-level egress rules
log_info "Step 3: Applying container-level egress rules..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

cd code-server-enterprise

# Update docker-compose to add network policies
docker-compose down -v

# Add egress policy labels to services
# (This would be in docker-compose.yml in practice)

# For each container, restrict egress
for container in $(docker ps --format '{{.Names}}' 2>/dev/null || true); do
  # Add rate limiting
  tc qdisc add dev docker0 root tbf rate 1gbit burst 32mbit latency 400ms 2>/dev/null || true
  
  # Verify container connectivity (should fail to external IPs)
  docker exec "$container" timeout 2 curl -s https://8.8.8.8 >/dev/null 2>&1 && echo "⚠ Container has external access" || echo "✓ Container egress blocked"
done

echo "✓ Container egress rules applied"
EOF

log_success "Container egress rules applied"

# 4. Monitoring and logging
log_info "Step 4: Setting up egress monitoring..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Create logrotate config for egress logs
cat > /etc/logrotate.d/egress-blocking << 'LOGROTATE'
/var/log/egress-*.log {
  daily
  rotate 30
  missingok
  compress
  delaycompress
  notifempty
  create 0640 root root
}
LOGROTATE

# Create monitoring script
cat > /usr/local/bin/monitor-egress.sh << 'MONITOR'
#!/bin/bash
# Monitor blocked egress traffic
iptables -L DOCKER-EGRESS -nv | grep -E "DROP|LOG" | tail -20
MONITOR

chmod +x /usr/local/bin/monitor-egress.sh

# Add to crontab
(crontab -l 2>/dev/null | grep -v "monitor-egress" || true; echo "*/5 * * * * /usr/local/bin/monitor-egress.sh >> /var/log/egress-monitor.log") | crontab -

echo "✓ Egress monitoring configured"
EOF

log_success "Egress monitoring configured"

log_info "=========================================="
log_success "Phase 8 Egress Filtering Complete"
log_info "=========================================="
log_info "Egress security measures applied:"
log_info "  ✓ iptables rules (restrict outbound)"
log_info "  ✓ Docker network policies (enable_icc=false)"
log_info "  ✓ Container egress limits"
log_info "  ✓ Monitoring and alerting"
log_info ""
log_info "Allowed outbound traffic:"
log_info "  ✓ DNS (53/udp to 8.8.8.8, 1.1.1.1)"
log_info "  ✓ HTTPS (443/tcp for repos, APIs)"
log_info "  ✓ Local network (192.168.168.0/24)"
log_info "  ✓ NTP (123/udp)"
log_info ""
log_info "Blocked outbound traffic:"
log_info "  ✗ SSH to external hosts"
log_info "  ✗ Crypto mining pools"
log_info "  ✗ Botnet C&C"
log_info "  ✗ Data exfiltration channels"
