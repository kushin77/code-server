#!/bin/bash
# Phase 3: Core Services Deployment - code-server, PostgreSQL, Redis, oauth2-proxy
set -euo pipefail

ENVIRONMENT="${1:-production}"
PRIMARY_IP="${2:-192.168.168.31}"

echo "═══════════════════════════════════════════════════════════════"
echo "[Phase 3] Core Services Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Primary: $PRIMARY_IP"
echo ""
echo "Services:"
echo "  ✓ code-server (port 127.0.0.1:8080 - localhost only)"
echo "  ✓ PostgreSQL 15 (port 5432, HA via Patroni in Phase 6)"
echo "  ✓ Redis 7 (port 6379, HA via Sentinel in Phase 6)"
echo "  ✓ oauth2-proxy (port 4180 - sole ingress)"
echo "  ✓ Caddy (port 443 - reverse proxy + TLS)"
echo ""
echo "Status: Ready for full implementation"
echo "═══════════════════════════════════════════════════════════════"
