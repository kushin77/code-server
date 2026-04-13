#!/bin/bash
# Portable health check script — works from any directory
# Usage: ./health-check.sh [domain]
set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"
DOMAIN="${1:-localhost}"

echo "📊 Code-Server Enterprise Health Check"
echo "========================================"
echo ""

# Check Docker containers
echo "🐳 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "📈 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
  code-server oauth2-proxy caddy 2>/dev/null || echo "  (some containers not running)"

echo ""
echo "🌐 Network Connectivity:"
if curl -sk --max-time 5 "https://${DOMAIN}" > /dev/null 2>&1; then
  echo "  ✅ HTTPS endpoint responding: https://${DOMAIN}"
else
  echo "  ❌ HTTPS endpoint not responding: https://${DOMAIN}"
fi

if curl -sf --max-time 5 "http://oauth2-proxy:4180/ping" > /dev/null 2>&1; then
  echo "  ✅ oauth2-proxy /ping: OK"
else
  echo "  ❌ oauth2-proxy not responding"
fi

if curl -sf --max-time 5 "http://code-server:8080/healthz" > /dev/null 2>&1; then
  echo "  ✅ code-server /healthz: OK"
else
  echo "  ❌ code-server not responding"
fi

echo ""
echo "📝 Recent Logs (last 10 lines each):"
docker compose -f "$COMPOSE_FILE" logs --tail=10 2>/dev/null || echo "  No logs available"

echo ""
echo "✨ Health check complete!"
