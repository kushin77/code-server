#!/bin/bash
# Monitoring & Health Check Scrip

echo "📊 Code-Server Enterprise Health Check"
echo "========================================"
echo ""

# Check Docker containers
echo "🐳 Container Status:"
docker-compose -f ~/code-server-enterprise/docker-compose.yml ps

echo ""
echo "📈 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
  code-server-enterprise_code-server_1 \
  code-server-enterprise_caddy_1 2>/dev/null || echo "Containers not running"

echo ""
echo "🌐 Network Connectivity:"
# Test code-server endpoin
if curl -sk https://localhost > /dev/null 2>&1; then
  echo "✅ HTTPS endpoint responding"
else
  echo "❌ HTTPS endpoint not responding"
fi

echo ""
echo "📝 Recent Logs (last 10 lines):"
docker-compose -f ~/code-server-enterprise/docker-compose.yml logs --tail=10 2>/dev/null || echo "No logs available"

echo ""
echo "✨ Health check complete!"
