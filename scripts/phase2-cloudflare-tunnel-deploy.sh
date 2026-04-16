#!/bin/bash
# Phase 2 Issue #181 - Cloudflare Tunnel Quick Deployment
# Production deployment script for 192.168.168.31

set -euo pipefail

echo "=== Phase 2 Issue #181: Cloudflare Tunnel Production Deployment ==="
echo "Date: $(date)"
echo "Host: $(hostname)"
echo ""

# Check prerequisites
echo "[1] Checking prerequisites..."
if ! command -v docker-compose &> /dev/null; then
    echo "✗ docker-compose not found"
    exit 1
fi
echo "✓ docker-compose available"

if ! docker ps &> /dev/null; then
    echo "✗ Docker daemon not accessible"
    exit 1
fi
echo "✓ Docker daemon responding"

# Create cloudflare directories
echo "[2] Creating Cloudflare infrastructure directories..."
mkdir -p ~/.cloudflare/certs
mkdir -p ~/.cloudflare/logs
mkdir -p ~/.cloudflare/config
echo "✓ Directories created"

# Copy config file to cloudflare directory
echo "[3] Staging tunnel configuration..."
if [ -f "config/cloudflare-tunnel-config.yml" ]; then
    cp config/cloudflare-tunnel-config.yml ~/.cloudflare/config/tunnel-config.yml
    chmod 600 ~/.cloudflare/config/tunnel-config.yml
    echo "✓ Tunnel config staged to ~/.cloudflare/config/"
else
    echo "! Config file not found at config/cloudflare-tunnel-config.yml"
fi

# Check environment
echo "[4] Checking environment..."
if grep -q "CLOUDFLARE_TUNNEL_TOKEN" .env 2>/dev/null; then
    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        echo "! CLOUDFLARE_TUNNEL_TOKEN not set in environment"
        echo "  To deploy tunnel, run:"
        echo "  export CLOUDFLARE_TUNNEL_TOKEN=<your-token>"
        echo "  docker-compose -f docker-compose.yml -f docker-compose.cloudflare-tunnel.yml up -d cloudflare-tunnel"
    else
        echo "✓ CLOUDFLARE_TUNNEL_TOKEN is set"
    fi
else
    echo "! CLOUDFLARE_TUNNEL_TOKEN not in .env"
fi

# Validate docker-compose configuration
echo "[5] Validating docker-compose configuration..."
if docker-compose -f docker-compose.yml -f docker-compose.cloudflare-tunnel.yml config &>/dev/null; then
    echo "✓ docker-compose configuration is valid"
else
    echo "✗ docker-compose configuration has errors"
    docker-compose -f docker-compose.yml -f docker-compose.cloudflare-tunnel.yml config 2>&1 | head -20
    exit 1
fi

# Verify supporting services are running
echo "[6] Verifying supporting services..."
for SERVICE in code-server oauth2-proxy prometheus; do
    if docker ps --filter "name=$SERVICE" --format "{{.State}}" 2>/dev/null | grep -q "running"; then
        echo "✓ $SERVICE is running"
    else
        echo "⚠ $SERVICE is not running (required for tunnel)"
    fi
done

echo ""
echo "=== Deployment Ready ==="
echo ""
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "To deploy Cloudflare Tunnel:"
    echo "  docker-compose -f docker-compose.yml -f docker-compose.cloudflare-tunnel.yml up -d cloudflare-tunnel"
    echo ""
    echo "To verify deployment:"
    echo "  docker-compose ps cloudflare-tunnel"
    echo "  docker logs cloudflare-tunnel"
else
    echo "Prerequisites not met. Set CLOUDFLARE_TUNNEL_TOKEN before deploying."
fi
