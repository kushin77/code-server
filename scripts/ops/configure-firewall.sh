#!/bin/bash
# UFW firewall configuration for ElevatedIQ platform
# Sets up comprehensive network security policies

set -e
trap 'echo "❌ Configuration failed"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root"
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Firewall Configuration (UFW)                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
  echo "Installing UFW firewall..."
  apt-get update >/dev/null
  apt-get install -y ufw >/dev/null
fi

echo "Resetting firewall to defaults..."
ufw --force reset >/dev/null 2>&1 || true
echo "✓ Firewall reset"

echo ""
echo "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
echo "✓ Default policies set"

echo ""
echo "Configuring access rules..."

# SSH (CRITICAL - must allow!)
ufw allow 22/tcp
echo "  ✓ SSH (22/tcp)"

# HTTP/HTTPS for external traffic
ufw allow 80/tcp
ufw allow 443/tcp
echo "  ✓ HTTP/HTTPS (80/443)"

# Prometheus metrics (local only)
ufw allow from 192.168.168.0/24 to any port 9090 proto tcp
echo "  ✓ Prometheus (9090, local only)"

# Grafana (local only)
ufw allow from 192.168.168.0/24 to any port 3000 proto tcp
echo "  ✓ Grafana (3000, local only)"

# Alertmanager (local only)
ufw allow from 192.168.168.0/24 to any port 9093 proto tcp
echo "  ✓ Alertmanager (9093, local only)"

# PostgreSQL (local only)
ufw allow from 192.168.168.0/24 to any port 5432 proto tcp
echo "  ✓ PostgreSQL (5432, local only)"

# Redis (local only)
ufw allow from 192.168.168.0/24 to any port 6379 proto tcp
echo "  ✓ Redis (6379, local only)"

# Redpanda/Kafka (local only)
ufw allow from 192.168.168.0/24 to any port 9092 proto tcp
echo "  ✓ Redpanda (9092, local only)"

# Qdrant vector DB (local only)
ufw allow from 192.168.168.0/24 to any port 6333 proto tcp
ufw allow from 192.168.168.0/24 to any port 6334 proto tcp
echo "  ✓ Qdrant (6333-6334, local only)"

# VRRP for keepalived (multicast)
ufw allow from 224.0.0.0/8
echo "  ✓ VRRP multicast (224.0.0.0/8)"

# Rate limiting for SSH (prevent brute force)
echo ""
echo "Configuring rate limiting..."
ufw limit 22/tcp
echo "  ✓ SSH rate limited (max 6 per 30s)"

echo ""
echo "Enabling firewall..."
ufw --force enable >/dev/null

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Firewall Configuration Complete                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "Firewall Status:"
ufw status verbose

echo ""
echo "⚠️  Note: UFW will drop all non-whitelisted traffic"
echo "✅ Firewall is now active and protecting the platform"
