#!/bin/bash
# Setup Cloudflare Tunnel for code-server
# Implements issue #185: Cloudflare Tunnel Setup for Home Server IDE Access

set -e

echo "🚀 Cloudflare Tunnel Setup for Code-Server"
echo "=========================================="
echo ""

# Configuration variables
TUNNEL_NAME="${TUNNEL_NAME:-home-dev}"
DOMAIN="${DOMAIN:-dev.example.com}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
TERMINAL_PORT="${TERMINAL_PORT:-3000}"
CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1: Installation & Authentication
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}PHASE 1: Cloudflare Tunnel Installation${NC}"
echo "=========================================="

# Check if cloudflared is installed
if command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}✅ cloudflared is installed${NC}"
    cloudflared --version
else
    echo -e "${YELLOW}⬇️  Installing cloudflared...${NC}"
    
    # Detect OS and install accordingly
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        brew install cloudflare/cloudflare/cloudflared
    else
        echo -e "${RED}❌ Unsupported OS. Please install cloudflared manually:${NC}"
        echo "   https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
        exit 1
    fi
    
    echo -e "${GREEN}✅ cloudflared installed${NC}"
fi

# Verify Cloudflare API credentials
echo ""
echo -e "${YELLOW}Verifying Cloudflare credentials...${NC}"
if cloudflared config validate &> /dev/null || [ -f "$CONFIG_DIR/cert.pem" ]; then
    echo -e "${GREEN}✅ Cloudflare credentials found${NC}"
else
    echo -e "${YELLOW}🔐 Authenticating with Cloudflare...${NC}"
    echo "   Opening browser for authentication..."
    cloudflared login
    
    if [ -f "$CONFIG_DIR/cert.pem" ]; then
        echo -e "${GREEN}✅ Authentication successful${NC}"
    else
        echo -e "${RED}❌ Authentication failed${NC}"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2: Create Tunnel
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}PHASE 2: Creating Cloudflare Tunnel${NC}"
echo "===================================="

# Check if tunnel already exists
if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
    echo -e "${GREEN}✅ Tunnel '$TUNNEL_NAME' already exists${NC}"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
else
    echo "Creating tunnel: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME"
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    echo -e "${GREEN}✅ Tunnel created: $TUNNEL_NAME (ID: $TUNNEL_ID)${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3: Configure Tunnel Routing
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}PHASE 3: Configuring Tunnel Routing${NC}"
echo "====================================="

# Create/update config file
echo "Creating tunnel configuration: $CONFIG_FILE"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
# Cloudflare Tunnel Configuration
# Auto-generated: $(date)

tunnel: $TUNNEL_NAME
credentials-file: $CONFIG_DIR/${TUNNEL_ID}.json

ingress:
  # Code-Server IDE
  - hostname: $DOMAIN
    service: http://localhost:$CODE_SERVER_PORT
    
  # Terminal Proxy (optional, if implemented)
  - hostname: terminal.${DOMAIN#*.}
    service: http://localhost:$TERMINAL_PORT
    
  # Catch-all (return 404 for unknown routes)
  - service: http_status:404

# Logging configuration
logger:
  level: info
  
# Connection settings
originRequest:
  http2Origin: true
  connectTimeout: 30s
  tlsTimeout: 10s
  tcpKeepAlive: 30s
  
# Advanced: http access logging
accessLogs:
  enabled: true
EOF

echo -e "${GREEN}✅ Configuration file created: $CONFIG_FILE${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 4: Create Tunnel Route (CloudflareAccess via DNS)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}PHASE 4: Setting Up DNS Route${NC}"
echo "==============================="

# Get tunnel token for CloudflareAccess
echo "Getting tunnel credentials..."
if [ -f "$CONFIG_DIR/${TUNNEL_ID}.json" ]; then
    echo -e "${GREEN}✅ Tunnel credentials file exists${NC}"
    
    # Show CNAME record needed
    echo ""
    echo -e "${YELLOW}📋 Add to Cloudflare DNS:${NC}"
    echo "   Type: CNAME"
    echo "   Name: ${DOMAIN%.*}"
    echo "   Target: ${TUNNEL_ID}.cfargotunnel.com"
    echo ""
else
    echo -e "${RED}⚠️  Credentials file not found${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 5: Systemd Service Setup (Optional)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}PHASE 5: Setting Up Auto-Start (Optional)${NC}"
echo "========================================"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/systemd/system/cloudflared.service ]; then
        echo -e "${GREEN}✅ Systemd service already configured${NC}"
    else
        echo -e "${YELLOW}Setting up systemd service...${NC}"
        
        # Create systemd service file (requires sudo)
        sudo tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel for Code-Server
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/cloudflared tunnel run $TUNNEL_NAME
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable cloudflared.service
        echo -e "${GREEN}✅ Systemd service configured${NC}"
        echo "   Start with: sudo systemctl start cloudflared"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 6: Test & Verify
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}PHASE 6: Verification${NC}"
echo "====================="

echo ""
echo -e "${YELLOW}Testing tunnel connectivity...${NC}"

# Start tunnel in background for testing
echo "Starting tunnel (background)..."
cloudflared tunnel run "$TUNNEL_NAME" \
    --config "$CONFIG_FILE" \
    --no-autoupdate \
    &
TUNNEL_PID=$!

# Wait for tunnel to start
sleep 3

# Check if tunnel is running
if ps -p $TUNNEL_PID > /dev/null; then
    echo -e "${GREEN}✅ Tunnel process started (PID: $TUNNEL_PID)${NC}"
else
    echo -e "${RED}❌ Tunnel failed to start${NC}"
    exit 1
fi

# Kill background process (will be restarted by systemd)
kill $TUNNEL_PID 2>/dev/null || true
wait $TUNNEL_PID 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Summary & Next Steps
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}✅ CLOUDFLARE TUNNEL SETUP COMPLETE${NC}"
echo "===================================="
echo ""
echo "📋 NEXT STEPS:"
echo ""
echo "1. Add DNS CNAME record in Cloudflare:"
echo "   - Type: CNAME"
echo "   - Name: ${DOMAIN%.*}"
echo "   - Target: ${TUNNEL_ID}.cfargotunnel.com"
echo ""
echo "2. Start the tunnel:"
echo "   - Systemd: sudo systemctl start cloudflared"
echo "   - Manual: cloudflared tunnel run $TUNNEL_NAME --config $CONFIG_FILE"
echo ""
echo "3. Access Code-Server:"
echo "   - URL: https://${DOMAIN}"
echo ""
echo "4. [ ] Verify tunnel status:"
echo "   cloudflared tunnel status $TUNNEL_NAME"
echo ""
echo "5. [ ] Check Cloudflare dashboard:"
echo "   https://dash.cloudflare.com/cgi-bin/account/tunnels"
echo ""
echo "📊 Configuration:"
echo "   - Tunnel: $TUNNEL_NAME"
echo "   - Domain: $DOMAIN"
echo "   - Code-Server Port: $CODE_SERVER_PORT"
echo "   - Config: $CONFIG_FILE"
echo ""
echo "🔐 Security Notes:"
echo "   - Tunnel encrypts traffic end-to-end"
echo "   - No home IP exposure"
echo "   - Next: Enable Cloudflare Access for MFA & time-limits"
echo ""
