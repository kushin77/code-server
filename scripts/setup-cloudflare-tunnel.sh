#!/bin/bash
# @file        scripts/setup-cloudflare-tunnel.sh
# @module      operations
# @description setup cloudflare tunnel — on-prem code-server
# @owner       platform
# @status      active
# Phase 7d-001: Cloudflare Tunnel Setup Script (P1 #351)
# Implements installation and service management for cloudflared on-prem.

set -euo pipefail

# Configuration (Overridable via ENV)
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
TUNNEL_USER="cloudflare-tunnel"
CLOUDFLARED_VERSION="latest"
CLOUDFLARED_SHA256="${CLOUDFLARED_SHA256:-}"

if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    echo "❌ ERROR: CLOUDFLARE_TUNNEL_TOKEN is not set."
    exit 1
fi

echo "🚀 Starting Cloudflare Tunnel Setup..."

# 1. Install cloudflared
if ! command -v cloudflared &> /dev/null; then
    echo "📦 Downloading cloudflared..."
    # Using the official Linux amd64 binary (debian-based check)
    if [ -f /etc/debian_version ]; then
        curl -fsSL --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    else
        # Generic binary install
        curl -fsSL --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
        if [ -n "$CLOUDFLARED_SHA256" ]; then
            echo "$CLOUDFLARED_SHA256  cloudflared" | sha256sum -c -
        fi
        chmod +x cloudflared
        sudo mv cloudflared /usr/local/bin/
    fi
else
    echo "✅ cloudflared is already installed: $(cloudflared --version)"
fi

# 2. Create service user if it doesn't exist
if ! id "$TUNNEL_USER" &>/dev/null; then
    echo "👤 Creating service user: $TUNNEL_USER"
    sudo useradd -r -s /usr/sbin/nologin "$TUNNEL_USER"
fi

# 3. Create systemd service
echo "🏗️ Configuring systemd service..."
sudo install -d -m 700 /etc/cloudflared
printf "CLOUDFLARE_TUNNEL_TOKEN=%s\n" "$CLOUDFLARE_TUNNEL_TOKEN" | sudo tee /etc/cloudflared/cloudflared.env >/dev/null
sudo chmod 600 /etc/cloudflared/cloudflared.env

cat <<EOF | sudo tee /etc/systemd/system/cloudflared.service
[Unit]
Description=Cloudflare Tunnel (P1 #351)
After=network.target
StartLimitInterval=0
StartLimitBurst=0

[Service]
Type=simple
User=$TUNNEL_USER
EnvironmentFile=/etc/cloudflared/cloudflared.env
ExecStart=/usr/local/bin/cloudflared tunnel run --token \\${CLOUDFLARE_TUNNEL_TOKEN}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared

[Install]
WantedBy=multi-user.target
EOF

# 4. Reload and start
echo "🔄 Reloading systemd and starting tunnel..."
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared

echo "✨ Cloudflare Tunnel setup complete. Checking status..."
sudo systemctl status cloudflared --no-pager | grep "Active:"
