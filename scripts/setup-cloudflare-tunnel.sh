#!/bin/bash
# scripts/setup-cloudflare-tunnel.sh
# Cloudflare Tunnel setup for ide.kushnir.cloud
# Run on 192.168.168.31 (primary host)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  CLOUDFLARE TUNNEL SETUP - ide.kushnir.cloud                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# Step 1: Install cloudflared
# ============================================================================

echo -e "${YELLOW}→${NC} Step 1: Installing cloudflared..."

if command -v cloudflared &> /dev/null; then
  CURRENT_VERSION=$(cloudflared --version 2>&1 | awk '{print $NF}')
  echo -e "${GREEN}✓${NC} cloudflared already installed (version: $CURRENT_VERSION)"
else
  echo "Installing cloudflared..."
  
  # Add Cloudflare repo
  curl -L https://pkg.cloudflare.com/cloudflare-release.key | gpg --import 2>/dev/null || true
  
  # Add to apt sources
  if [[ ! -f /etc/apt/sources.list.d/cloudflare-release.list ]]; then
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/cloudflare.gpg] https://pkg.cloudflare.com/linux/$(lsb_release -sc) $(lsb_release -sc) main" | \
      tee /etc/apt/sources.list.d/cloudflare-release.list > /dev/null
  fi
  
  # Install
  apt-get update > /dev/null 2>&1
  apt-get install -y cloudflared > /dev/null 2>&1
  
  echo -e "${GREEN}✓${NC} cloudflared installed"
fi

echo ""

# ============================================================================
# Step 2: Create service user
# ============================================================================

echo -e "${YELLOW}→${NC} Step 2: Setting up service user..."

if id "cloudflare-tunnel" &>/dev/null; then
  echo -e "${GREEN}✓${NC} User 'cloudflare-tunnel' already exists"
else
  useradd -r -M -s /usr/sbin/nologin cloudflare-tunnel
  echo -e "${GREEN}✓${NC} Created 'cloudflare-tunnel' user"
fi

echo ""

# ============================================================================
# Step 3: Create configuration directory
# ============================================================================

echo -e "${YELLOW}→${NC} Step 3: Creating configuration directory..."

mkdir -p /etc/cloudflared
mkdir -p /var/log/cloudflared
chown -R cloudflare-tunnel:cloudflare-tunnel /var/log/cloudflared
chmod 755 /etc/cloudflared

echo -e "${GREEN}✓${NC} Configuration directory created"
echo ""

# ============================================================================
# Step 4: Load credentials from environment
# ============================================================================

echo -e "${YELLOW}→${NC} Step 4: Loading Cloudflare credentials..."

if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN}" ]]; then
  echo -e "${RED}✗${NC} Error: CLOUDFLARE_TUNNEL_TOKEN not set"
  echo "Set the token from https://dash.cloudflare.com/tunnels"
  echo ""
  echo "  export CLOUDFLARE_TUNNEL_TOKEN='<your-token-here>'"
  echo ""
  exit 1
fi

if [[ -z "${CLOUDFLARE_TUNNEL_ID}" ]]; then
  echo -e "${RED}✗${NC} Error: CLOUDFLARE_TUNNEL_ID not set"
  echo "Run: cloudflared tunnel list (to get tunnel ID)"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓${NC} Credentials loaded"
echo "  Tunnel ID: ${CLOUDFLARE_TUNNEL_ID:0:16}..."
echo ""

# ============================================================================
# Step 5: Create tunnel configuration
# ============================================================================

echo -e "${YELLOW}→${NC} Step 5: Creating tunnel configuration..."

cat > /etc/cloudflared/config.yml <<'TUNNEL_CONFIG'
# Cloudflare Tunnel Configuration
# For ide.kushnir.cloud

tunnel: code-server-production
token: ${CLOUDFLARE_TUNNEL_TOKEN}
credentials-file: /root/.cloudflared/credentials.json

# Logging
logLevel: info
logfile: /var/log/cloudflared/tunnel.log

# Transport settings
transport-logs: true

# Health checks
# healthcheck: http://localhost:5555

# Tunnel configuration
ingress:
  # Main code-server access
  - hostname: ide.kushnir.cloud
    service: http://localhost:8080
    originRequest:
      httpHostHeader: ide.kushnir.cloud
      noTLSVerify: false
      disableChunkedEncoding: false
      
  # Prometheus (optional, for monitoring)
  - hostname: prometheus.ide.kushnir.cloud
    service: http://localhost:9090
    originRequest:
      httpHostHeader: prometheus.ide.kushnir.cloud
      
  # Grafana (optional, for dashboards)
  - hostname: grafana.ide.kushnir.cloud
    service: http://localhost:3000
    originRequest:
      httpHostHeader: grafana.ide.kushnir.cloud
      
  # Jaeger (optional, for tracing)
  - hostname: jaeger.ide.kushnir.cloud
    service: http://localhost:16686
    originRequest:
      httpHostHeader: jaeger.ide.kushnir.cloud
      
  # AlertManager (optional, for alerts)
  - hostname: alertmanager.ide.kushnir.cloud
    service: http://localhost:9093
    originRequest:
      httpHostHeader: alertmanager.ide.kushnir.cloud

  # Catch-all (return 503 Service Unavailable)
  - service: http_status:503
TUNNEL_CONFIG

# Replace environment variables in config
sed -i "s|\${CLOUDFLARE_TUNNEL_TOKEN}|$CLOUDFLARE_TUNNEL_TOKEN|g" /etc/cloudflared/config.yml

echo -e "${GREEN}✓${NC} Configuration file created"
echo ""

# ============================================================================
# Step 6: Create systemd service
# ============================================================================

echo -e "${YELLOW}→${NC} Step 6: Creating systemd service..."

cat > /etc/systemd/system/cloudflared.service <<'SERVICE_CONFIG'
[Unit]
Description=Cloudflare Tunnel (code-server-production)
After=network.target
StartLimitInterval=0
StartLimitBurst=0
Documentation=https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

[Service]
Type=simple
User=cloudflare-tunnel
WorkingDirectory=/etc/cloudflared

# Run cloudflared tunnel
ExecStart=/usr/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run

# Restart policy
Restart=always
RestartSec=5

# Resource limits
LimitNOFILE=65536
LimitNPROC=512

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudflared

# Security
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/cloudflared

[Install]
WantedBy=multi-user.target
SERVICE_CONFIG

systemctl daemon-reload
echo -e "${GREEN}✓${NC} Systemd service created"
echo ""

# ============================================================================
# Step 7: Enable and start service
# ============================================================================

echo -e "${YELLOW}→${NC} Step 7: Starting cloudflared service..."

systemctl enable cloudflared
systemctl start cloudflared

# Wait for startup
sleep 5

# Check status
if systemctl is-active --quiet cloudflared; then
  echo -e "${GREEN}✓${NC} cloudflared service started successfully"
  systemctl status cloudflared --no-pager | head -10
else
  echo -e "${RED}✗${NC} cloudflared service failed to start"
  journalctl -u cloudflared -n 20 --no-pager
  exit 1
fi

echo ""

# ============================================================================
# Step 8: Verify tunnel connectivity
# ============================================================================

echo -e "${YELLOW}→${NC} Step 8: Verifying tunnel connectivity..."

# Wait a moment for tunnel to stabilize
sleep 10

# Check logs for "Connection established"
if journalctl -u cloudflared -n 50 --no-pager | grep -q "Connection established"; then
  echo -e "${GREEN}✓${NC} Tunnel connected successfully"
else
  echo -e "${YELLOW}⚠${NC} Tunnel status unknown, checking connectivity..."
fi

# Try to access via tunnel
TUNNEL_URL="https://ide.kushnir.cloud/healthz"
echo "Checking: $TUNNEL_URL"

if curl -s -f "$TUNNEL_URL" > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Tunnel is accessible"
else
  echo -e "${YELLOW}⚠${NC} Could not verify tunnel (this is normal on first setup)"
  echo "Wait 2-3 minutes for DNS propagation"
fi

echo ""

# ============================================================================
# Step 9: Configure Prometheus metrics
# ============================================================================

echo -e "${YELLOW}→${NC} Step 9: Setting up Prometheus monitoring..."

cat > /etc/prometheus/cloudflared-rules.yml <<'PROMETHEUS_CONFIG'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'cloudflared'
    metrics_path: '/metrics'
    scrape_interval: 30s
    static_configs:
      - targets: ['127.0.0.1:7878']

alert_rules:
  - alert: CloudflareTunnelDown
    expr: up{job="cloudflared"} == 0
    for: 2m
    annotations:
      summary: "Cloudflare Tunnel is down"
PROMETHEUS_CONFIG

echo -e "${GREEN}✓${NC} Prometheus configuration updated"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ CLOUDFLARE TUNNEL SETUP COMPLETE${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Access Points:"
echo "  🖥️  Code IDE:        https://ide.kushnir.cloud"
echo "  📊 Grafana:         https://grafana.ide.kushnir.cloud"
echo "  📈 Prometheus:      https://prometheus.ide.kushnir.cloud"
echo "  🔍 Jaeger:          https://jaeger.ide.kushnir.cloud"
echo "  🚨 AlertManager:    https://alertmanager.ide.kushnir.cloud"
echo ""
echo "Monitoring:"
echo "  View logs:          journalctl -u cloudflared -f"
echo "  Check status:       systemctl status cloudflared"
echo "  Tunnel dashboard:   https://dash.cloudflare.com/tunnels"
echo ""
echo "Next steps:"
echo "  1. Verify DNS resolution: nslookup ide.kushnir.cloud"
echo "  2. Test access: curl https://ide.kushnir.cloud/healthz"
echo "  3. Check Prometheus: http://localhost:9090/targets"
echo ""
