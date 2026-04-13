#!/bin/bash
# EXAMPLE: Cloudflare Tunnel Setup for Home Server
# This demonstrates Phase 1 (Week 1) implementation
# Based on GitHub Issue #185: https://github.com/kushin77/code-server/issues/185
#
# WARNING: This is a reference implementation. Adapt to your environment.
# Do not run this script blindly - read each section and execute manually.

set -e

echo "==========================================="
echo "Cloudflare Tunnel Setup - Phase 1"
echo "==========================================="
echo ""
echo "This script sets up Cloudflare Tunnel to expose your"
echo "home code-server instance globally with zero IP leakage."
echo ""
echo "Prerequisites:"
echo "  - Cloudflare account (free tier eligible)"
echo "  - Cloudflare API token (generate in dashboard)"
echo "  - Domain managed by Cloudflare"
echo "  - code-server running on localhost:8080"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Configuration
DOMAIN="${1:-dev.yourdomain.com}"
TUNNEL_NAME="home-dev-$(uname -n)"
CODE_SERVER_PORT=8080
CLOUDFLARE_CONFIG_DIR="$HOME/.cloudflared"

echo ""
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Tunnel: $TUNNEL_NAME"
echo "  code-server: localhost:$CODE_SERVER_PORT"
echo "  Config Dir: $CLOUDFLARE_CONFIG_DIR"
echo ""

# Step 1: Check if cloudflared is installed
echo "Step 1: Checking for cloudflared installation..."
if ! command -v cloudflared &> /dev/null; then
    echo "  ❌ cloudflared not found"
    echo ""
    echo "  Install cloudflared:"
    echo "  Ubuntu/Debian:"
    echo "    curl -L https://pkg.cloudflare.com/cloudflare-release-key.gpg | sudo apt-key add -"
    echo "    echo 'deb http://pkg.cloudflare.com/cloudflare-main focal main' | sudo tee /etc/apt/sources.list.d/cloudflare.list"
    echo "    sudo apt-get update"
    echo "    sudo apt-get install cloudflared"
    echo ""
    echo "  Or see: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/"
    exit 1
else
    echo "  ✅ cloudflared found: $(cloudflared --version)"
fi

echo ""
echo "Step 2: Authenticate with Cloudflare..."
echo "  This will open your browser to log in with Cloudflare."
echo "  You'll be asked to authorize cloudflared to manage DNS records."
echo ""
read -p "  Press Enter to continue (browser will open)..."

cloudflared login

if [ ! -f "$CLOUDFLARE_CONFIG_DIR/cert.pem" ]; then
    echo "  ❌ Authentication failed"
    exit 1
fi
echo "  ✅ Authentication successful"

echo ""
echo "Step 3: Creating tunnel '$TUNNEL_NAME'..."

# Check if tunnel already exists
if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "  ⚠️  Tunnel already exists"
    TUNNEL_UUID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
else
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_UUID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    echo "  ✅ Tunnel created: $TUNNEL_UUID"
fi

echo ""
echo "Step 4: Creating tunnel configuration..."

TUNNEL_CONFIG="$CLOUDFLARE_CONFIG_DIR/$TUNNEL_UUID.json"
if [ -f "$TUNNEL_CONFIG" ]; then
    echo "  ✅ Tunnel credentials file exists: $TUNNEL_CONFIG"
else
    echo "  ⚠️  Tunnel credentials not found at $TUNNEL_CONFIG"
    echo "  This file should have been created by 'cloudflared tunnel create'"
    ls -la "$CLOUDFLARE_CONFIG_DIR/" | grep -E "\.json|\.pem"
fi

echo ""
echo "Step 5: Creating ingress configuration (~/.cloudflared/config.yml)..."

cat > "$CLOUDFLARE_CONFIG_DIR/config.yml" << 'EOF'
# Cloudflare Tunnel Configuration
# Automatically routes traffic through Cloudflare's global network

tunnel: TUNNEL_UUID_PLACEHOLDER
credentials-file: /home/USER_PLACEHOLDER/.cloudflared/TUNNEL_UUID_PLACEHOLDER.json

# Logging
loglevel: info
logfile: /var/log/cloudflared.log

# Ingress rules - define what traffic routes where
ingress:
  # Primary IDE access
  - hostname: dev.yourdomain.com
    service: http://localhost:8080
    originRequest:
      # Enable compression for WebSocket (terminal)
      http2Origin: true
  
  # Terminal proxy (optional, future)
  - hostname: terminal.yourdomain.com
    service: http://localhost:3000
    originRequest:
      http2Origin: true
  
  # Default: return 404 for unmatched traffic
  - service: http_status:404

# Connection settings
originRequest:
  connectTimeout: 30s
  noTLSVerify: false
  
# See full options at:
# https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/local-management/ingress/
EOF

# Replace placeholders
sed -i "s|TUNNEL_UUID_PLACEHOLDER|$TUNNEL_UUID|g" "$CLOUDFLARE_CONFIG_DIR/config.yml"
sed -i "s|USER_PLACEHOLDER|$USER|g" "$CLOUDFLARE_CONFIG_DIR/config.yml"

echo "  ✅ Configuration created: $CLOUDFLARE_CONFIG_DIR/config.yml"
echo ""
echo "  Contents:"
head -30 "$CLOUDFLARE_CONFIG_DIR/config.yml" | sed 's/^/    /'

echo ""
echo "Step 6: Setting DNS records in Cloudflare..."
echo "  You must manually add CNAME records in Cloudflare dashboard:"
echo ""
echo "  1. Go to: https://dash.cloudflare.com/"
echo "  2. Select your domain (yourdomain.com)"
echo "  3. Go to DNS > Records"
echo "  4. Create two CNAME records:"
echo ""
echo "     Name: dev"
echo "     Type: CNAME"
echo "     Content: $TUNNEL_UUID.cfargotunnel.com"
echo "     TTL: Auto"
echo "     Proxy: Tunneled"
echo ""
echo "     Name: terminal"
echo "     Type: CNAME"
echo "     Content: $TUNNEL_UUID.cfargotunnel.com"
echo "     TTL: Auto"
echo "     Proxy: Tunneled"
echo ""
read -p "  Press Enter when DNS records are created..."

echo ""
echo "Step 7: Testing DNS resolution..."
sleep 5
if nslookup "dev.yourdomain.com" 2>/dev/null | grep -q "cloudflare"; then
    echo "  ✅ DNS resolves correctly"
else
    echo "  ⚠️  DNS not yet resolved (may take a few minutes)"
fi

echo ""
echo "Step 8: Starting tunnel..."
echo "  To run tunnel manually (for testing):"
echo "    cloudflared tunnel run $TUNNEL_NAME"
echo ""
echo "  To set up as systemd service (recommended):"
echo "    sudo cloudflared install"
echo "    sudo systemctl start cloudflared"
echo ""
echo "  Or run:"
read -p "    Start tunnel now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  Starting tunnel..."
    cloudflared tunnel run "$TUNNEL_NAME" &
    TUNNEL_PID=$!
    sleep 5
    
    echo ""
    echo "Step 9: Verifying connectivity..."
    if curl -s -o /dev/null -w "%{http_code}" "https://dev.yourdomain.com" | grep -q "200\|302"; then
        echo "  ✅ IDE is accessible at https://dev.yourdomain.com"
        echo "  ✅ Tunnel working!"
    else
        echo "  ⚠️  Could not reach IDE yet (may need more time)"
    fi
    
    echo ""
    echo "  Tunnel running (PID: $TUNNEL_PID)"
    echo "  Press Ctrl+C to stop"
    wait $TUNNEL_PID
else
    echo "  Skipped tunnel startup"
fi

echo ""
echo "==========================================="
echo "✅ Cloudflare Tunnel Setup Complete!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "  1. Set up Cloudflare Access for zero-trust auth"
echo "  2. Verify home server IP is NOT exposed"
echo "  3. Test IDE loads at https://dev.yourdomain.com"
echo "  4. Proceed to Phase 2 (Read-only access control)"
echo ""
echo "For production, set up as systemd service:"
echo "  sudo cloudflared install"
echo "  sudo systemctl enable cloudflared"
echo "  sudo systemctl start cloudflared"
echo ""
echo "Documentation:"
echo "  GitHub Issue #185: https://github.com/kushin77/code-server/issues/185"
echo "  Cloudflare Docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/"
echo ""
