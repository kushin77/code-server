#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# scripts/install-cloudflare-tunnel.sh
# Install and configure Cloudflare Tunnel for ide.kushnir.cloud
# Must run on home server (192.168.168.31)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/config.sh"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

log "Installing Cloudflare Tunnel for $DOMAIN..."

# ─────────────────────────────────────────────────────────────────────────────
# 1. Install cloudflared
# ─────────────────────────────────────────────────────────────────────────────

if ! command -v cloudflared &> /dev/null; then
    log "Installing cloudflared..."
    curl -sSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o /tmp/cloudflared && \
    sudo mv /tmp/cloudflared /usr/local/bin/ && \
    sudo chmod +x /usr/local/bin/cloudflared || die "Failed to install cloudflared"
    log "✅ cloudflared installed"
else
    log "cloudflared already installed: $(cloudflared --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Create tunnel configuration directory
# ─────────────────────────────────────────────────────────────────────────────

TUNNEL_DIR="/home/${DEPLOY_USER}/.cloudflared"
mkdir -p "$TUNNEL_DIR"
sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "$TUNNEL_DIR"
chmod 700 "$TUNNEL_DIR"

log "Tunnel directory: $TUNNEL_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Create config.yml for tunnel
# ─────────────────────────────────────────────────────────────────────────────

cat > "$TUNNEL_DIR/config.yml" << 'EOF'
# Cloudflare Tunnel configuration for kushnir.cloud
# Exposes on-prem code-server IDE via edge locations
tunnel: code-server-enterprise
credentials-file: ~/.cloudflared/code-server-enterprise.json

# Route all traffic through tunnel
ingress:
  # IDE: code-server (port 8080)
  - hostname: ide.kushnir.cloud
    service: http://localhost:8080
    originRequest:
      httpVersion: h2origin
      noTLSVerify: false
  
  # Prometheus (port 9090)
  - hostname: prometheus.kushnir.cloud
    service: http://localhost:9090
    originRequest:
      httpVersion: h2origin
  
  # Grafana (port 3000)
  - hostname: grafana.kushnir.cloud
    service: http://localhost:3000
    originRequest:
      httpVersion: h2origin
  
  # AlertManager (port 9093)
  - hostname: alertmanager.kushnir.cloud
    service: http://localhost:9093
    originRequest:
      httpVersion: h2origin
  
  # Jaeger (port 16686)
  - hostname: jaeger.kushnir.cloud
    service: http://localhost:16686
    originRequest:
      httpVersion: h2origin

  # Catch-all 404
  - service: http_status:404
EOF

sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" "$TUNNEL_DIR/config.yml"
chmod 600 "$TUNNEL_DIR/config.yml"

log "✅ Created $TUNNEL_DIR/config.yml"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Create systemd service for cloudflared
# ─────────────────────────────────────────────────────────────────────────────

sudo tee /etc/systemd/system/cloudflared.service > /dev/null << 'EOF'
[Unit]
Description=Cloudflare Tunnel for code-server-enterprise
Documentation=https://developers.cloudflare.com/cloudflare-one/connections/connect-applications/install-and-setup/tunnel-guide
After=network-online.target syslog.target
Wants=network-online.target

[Service]
Type=simple
User=akushnir
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/akushnir/.cloudflared/config.yml run
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared

[Install]
WantedBy=multi-user.target
EOF

log "✅ Created /etc/systemd/system/cloudflared.service"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Reload systemd and enable service
# ─────────────────────────────────────────────────────────────────────────────

sudo systemctl daemon-reload
sudo systemctl enable cloudflared
log "✅ Enabled cloudflared service"

log ""
log "════════════════════════════════════════════════════════════════════════════"
log "NEXT STEPS — MANUAL CLOUDFLARE SETUP REQUIRED"
log "════════════════════════════════════════════════════════════════════════════"
log ""
log "1. Go to Cloudflare dashboard: https://dash.cloudflare.com"
log "2. Navigate to Networks → Tunnels"
log "3. Create a NEW tunnel named 'code-server-enterprise'"
log "4. Copy the tunnel token (looks like): eyJh..."
log "5. Run on this machine:"
log "   sudo -u ${DEPLOY_USER} /usr/local/bin/cloudflared service install --token 'YOUR_TOKEN_HERE'"
log ""
log "6. Then start tunnel:"
log "   sudo systemctl start cloudflared"
log "   sudo systemctl status cloudflared"
log ""
log "7. Verify tunnel is working:"
log "   curl https://ide.kushnir.cloud"
log ""
log "════════════════════════════════════════════════════════════════════════════"
log ""
log "⏸️  WAITING FOR MANUAL SETUP — tunnel token required"
log ""
