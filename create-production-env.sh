#!/bin/bash
# Generate production .env file with Cloudflare tunnel configuration

cat > .env << 'ENVEOF'
# ════════════════════════════════════════════════════════════
# Production Environment - code-server IDE
# ════════════════════════════════════════════════════════════

# DOMAIN CONFIGURATION
DOMAIN=ide.kushnir.cloud
EXTERNAL_DOMAIN=ide.kushnir.cloud

# ════════════════════════════════════════════════════════════
# CLOUDFLARE TUNNEL TOKEN (REQUIRED FOR HTTPS)
# ════════════════════════════════════════════════════════════
# 
# Instructions to obtain token:
# 1. Visit: https://dash.cloudflare.com/
# 2. Select domain: kushnir.cloud
# 3. Navigate to: Networks > Tunnels
# 4. Find tunnel: ide-home-dev
# 5. Copy the authentication token (format: NNNN-XXXXXXXXXXXX...)
# 6. Replace the value below with your actual token
# 
# Token format: 64+ character hex string starting with 4 digits
# Example: aaaa-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
#
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-}

# ════════════════════════════════════════════════════════════
# AUTHENTICATION & OAUTH2
# ════════════════════════════════════════════════════════════

# Google OAuth2 Credentials (from GCP Console)
# https://console.cloud.google.com → APIs & Services → Credentials
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-test-client-id.apps.googleusercontent.com}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-test-client-secret}

# oauth2-proxy Cookie Encryption Secret (16/24/32 bytes hex)
# Generate: openssl rand -hex 16
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET:-867e5c21f89d4b162a3dbe5924761c8a}

# Code-Server Password
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:-change-me-in-production}

# ════════════════════════════════════════════════════════════
# DNS & API MANAGEMENT (GoDaddy)
# ════════════════════════════════════════════════════════════

GODADDY_KEY=${GODADDY_KEY:-}
GODADDY_SECRET=${GODADDY_SECRET:-}

# ════════════════════════════════════════════════════════════
# OPTIONAL: GitHub Token (Copilot rate limit increase)
# ════════════════════════════════════════════════════════════

GITHUB_TOKEN=${GITHUB_TOKEN:-}

# ════════════════════════════════════════════════════════════
# SERVICE PORTS & CONFIGURATION
# ════════════════════════════════════════════════════════════

CODE_SERVER_PORT=8080
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443

# OpenTelemetry observability
OTEL_SDK_DISABLED=false
LOG_LEVEL=info

# Allowed email domains for oauth2-proxy
ALLOWED_EMAIL_DOMAINS=koshnir.cloud,bioenergystrategies.com

ENVEOF

echo "✅ Created .env with Cloudflare tunnel configuration"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS TO ENABLE HTTPS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Get Cloudflare Tunnel Token:"
echo "   Visit: https://dash.cloudflare.com/"
echo "   → Domain: kushnir.cloud"
echo "   → Networks > Tunnels > ide-home-dev"
echo "   → Copy authentication token"
echo ""
echo "2. Set token in environment:"
echo "   export CLOUDFLARE_TUNNEL_TOKEN=\"<paste-token-here>\""
echo ""
echo "3. Update .env with token:"
echo "   echo \"CLOUDFLARE_TUNNEL_TOKEN=\$CLOUDFLARE_TUNNEL_TOKEN\" >> .env"
echo ""
echo "4. Start cloudflared service:"
echo "   docker-compose up -d cloudflared"
echo ""
echo "5. Verify tunnel connection:"
echo "   docker logs cloudflared -f"
echo "   (Look for: 'connection closed' or 'connected to edge')"
echo ""
echo "6. Test HTTPS:"
echo "   curl https://ide.kushnir.cloud"
echo ""
