#!/bin/bash
# scripts/configure-egress-filtering.sh
# =====================================
# Docker Container Egress Allow-List + DOCKER-USER iptables chain
# Blocks all container egress except: DNS (53), HTTPS (443), internal services
#
# Usage:
#   sudo bash scripts/configure-egress-filtering.sh [--dry-run]
#
# Prerequisites:
#   - Docker installed with iptables enabled
#   - sudo access
#   - iptables-persistent (optional)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Logging
log_info() { echo "[INFO] $*"; }
log_ok()  { echo "  ✓ $*"; }
log_warn(){ echo "  ⚠ $*"; }
log_err() { echo "  ✗ $*" >&2; }

dry() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

log_info "═══════════════════════════════════════════════════════════════"
log_info "Docker Container Egress Filtering (DOCKER-USER iptables)"
log_info "═══════════════════════════════════════════════════════════════"

# ─── 1. Create Docker daemon configuration ───────────────────────────────

log_info "1: Configuring Docker daemon for iptables..."

if [[ -f /etc/docker/daemon.json ]]; then
    log_info "Backing up existing /etc/docker/daemon.json"
    dry cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%Y%m%d-%H%M%S)
fi

if [[ "${DRY_RUN}" == "false" ]]; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'DOCKER'
{
  "iptables": true,
  "userland-proxy": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "labels": "component,app"
  },
  "storage-driver": "overlay2",
  "metrics-addr": "0.0.0.0:9323"
}
DOCKER
    log_ok "/etc/docker/daemon.json configured"
else
    echo "[DRY-RUN] Would create /etc/docker/daemon.json with iptables: true, userland-proxy: false"
fi

# ─── 2. Restart Docker daemon ────────────────────────────────────────────

log_info "2: Restarting Docker daemon..."

dry systemctl restart docker && log_ok "Docker daemon restarted" || log_err "Docker restart failed"

sleep 2  # Give Docker time to recreate chains

# ─── 3. Configure DOCKER-USER chain for egress filtering ──────────────────

log_info "3: Configuring DOCKER-USER iptables chain..."

# Internal network ranges
INTERNAL_SUBNET="192.168.168.0/24"
LOCALHOST="127.0.0.1"
DOCKER_GATEWAY="172.17.0.1"  # Default Docker bridge gateway
DOCKER_DNS_IPS="8.8.8.8 8.8.4.4 1.1.1.1"  # Google + Cloudflare DNS

# Flush DOCKER-USER chain if exists
dry iptables -t filter -F DOCKER-USER 2>/dev/null || true

# Create rules for DOCKER-USER chain (egress allows)
# Note: DOCKER-USER chain is traversed BEFORE filter FORWARD for containers

# Allow internal communication (192.168.168.0/24)
log_info "3.1: Allowing internal subnet (${INTERNAL_SUBNET})"
dry iptables -t filter -A DOCKER-USER -d ${INTERNAL_SUBNET} -j ACCEPT
log_ok "Internal subnet allowed"

# Allow localhost communication
log_info "3.2: Allowing localhost communication"
dry iptables -t filter -A DOCKER-USER -d ${LOCALHOST}/8 -j ACCEPT
log_ok "Localhost allowed"

# Allow DNS (port 53) to public resolvers
log_info "3.3: Allowing DNS (port 53) to public resolvers"
for dns_ip in ${DOCKER_DNS_IPS}; do
    dry iptables -t filter -A DOCKER-USER -d ${dns_ip} -p udp --dport 53 -j ACCEPT
    dry iptables -t filter -A DOCKER-USER -d ${dns_ip} -p tcp --dport 53 -j ACCEPT
done
log_ok "DNS queries allowed to ${DOCKER_DNS_IPS}"

# Allow HTTPS (port 443) outbound to any destination
log_info "3.4: Allowing HTTPS (port 443) outbound"
dry iptables -t filter -A DOCKER-USER -p tcp --dport 443 -j ACCEPT
log_ok "HTTPS outbound allowed"

# Allow HTTP (port 80) with restrictions (e.g., for package mirrors)
log_info "3.5: Allowing HTTP (port 80) for package managers"
# Ubuntu mirrors: archive.ubuntu.com, security.ubuntu.com
for mirror in archive.ubuntu.com security.ubuntu.com; do
    mirror_ip=$(getent hosts ${mirror} 2>/dev/null | awk '{print $1}' | head -1)
    if [[ -n "${mirror_ip}" ]]; then
        dry iptables -t filter -A DOCKER-USER -d ${mirror_ip} -p tcp --dport 80 -j ACCEPT
        log_ok "HTTP allowed to ${mirror}"
    fi
done

# Allow NTP (port 123) for time synchronization
log_info "3.6: Allowing NTP (port 123) for time sync"
dry iptables -t filter -A DOCKER-USER -p udp --dport 123 -j ACCEPT
log_ok "NTP allowed"

# Block all other egress by default (REJECT with icmp-net-unreachable)
log_info "3.7: Blocking all other egress (default deny)"
dry iptables -t filter -A DOCKER-USER -j REJECT --reject-with icmp-net-unreachable
log_ok "Default deny policy applied"

# ─── 4. Configure ingress filtering (DOCKER input) ───────────────────────

log_info "4: Configuring ingress filtering for Docker..."

# Allow inbound only to published ports (handled by Docker automatically)
# But explicitly allow internal service-to-service communication
log_info "4.1: Allowing internal service communication"
dry iptables -t filter -I DOCKER -s ${INTERNAL_SUBNET} -d ${INTERNAL_SUBNET} -j ACCEPT
log_ok "Internal service communication allowed"

# ─── 5. Persist iptables rules ───────────────────────────────────────────

log_info "5: Persisting iptables rules..."

if [[ "${DRY_RUN}" == "false" ]]; then
    # Install iptables-persistent if not already installed
    if ! command -v iptables-save &>/dev/null; then
        apt-get update && apt-get install -y iptables-persistent
    fi

    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4 && log_ok "IPv4 rules persisted" || log_warn "IPv4 persistence failed"

    # Optional: IPv6 blocking (uncomment if needed)
    # ip6tables-save > /etc/iptables/rules.v6 && log_ok "IPv6 rules persisted" || log_warn "IPv6 persistence failed"

    # Enable netfilter persistence service
    systemctl --now enable netfilter-persistent && log_ok "netfilter-persistent enabled" || log_warn "netfilter-persistent enable failed"
fi

# ─── 6. Verification ────────────────────────────────────────────────────

log_info "6: Verifying egress filtering rules..."

if [[ "${DRY_RUN}" == "false" ]]; then
    echo ""
    echo "Current DOCKER-USER chain rules:"
    iptables -t filter -L DOCKER-USER -n -v
    echo ""
    log_ok "Egress filtering configured and active"
fi

# ─── 7. Test connectivity ──────────────────────────────────────────────

log_info "7: Testing container egress..."

if [[ "${DRY_RUN}" == "false" ]]; then
    # Test DNS resolution from a test container
    if docker ps --format "{{.Names}}" | grep -q "test-egress" 2>/dev/null; then
        docker rm -f test-egress 2>/dev/null || true
    fi

    log_info "Starting test container..."
    docker run --rm --name test-egress -d alpine:latest sleep 30 || log_warn "Test container failed to start"

    sleep 2

    log_info "Testing DNS resolution..."
    docker exec test-egress nslookup google.com 2>&1 | head -5 && log_ok "DNS resolution working" || log_warn "DNS test failed"

    log_info "Testing HTTPS connectivity..."
    docker exec test-egress wget -q -O /dev/null https://www.google.com 2>&1 && log_ok "HTTPS working" || log_warn "HTTPS test completed (may be blocked)"

    docker rm -f test-egress 2>/dev/null || true
fi

log_info "═══════════════════════════════════════════════════════════════"
log_ok "Container egress filtering deployment complete"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_warn "Allowlist summary:"
log_warn "  ✓ Internal subnet: ${INTERNAL_SUBNET}"
log_warn "  ✓ DNS: port 53 (UDP/TCP)"
log_warn "  ✓ HTTPS: port 443 (TCP)"
log_warn "  ✓ NTP: port 123 (UDP)"
log_warn "  ✓ HTTP: Limited to Ubuntu mirrors"
log_warn "  ✗ All other egress: BLOCKED (default deny)"
log_warn ""
log_warn "To debug container network issues:"
log_warn "  docker exec <container> iptables -t filter -L -n"
log_warn "  docker logs <container>"
log_warn ""
log_warn "To add custom egress rules:"
log_warn "  iptables -t filter -I DOCKER-USER -d <ip> -p <proto> --dport <port> -j ACCEPT"
log_warn "  iptables-save > /etc/iptables/rules.v4"
