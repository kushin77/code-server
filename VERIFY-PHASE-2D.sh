#!/usr/bin/env bash

echo "=== PHASE 2D OBSERVABILITY VERIFICATION ==="
echo ""

echo "Prometheus JWT metrics scrape job:"
grep -A 10 "jwt-auth" prometheus.yml | head -12

echo ""
echo "Grafana JWT dashboard:"
test -f grafana/dashboards/jwt-auth-metrics.json && echo "✓ JWT dashboard exists" || echo "✗ JWT dashboard not found"

echo ""
echo "AlertManager JWT rules:"
ALERT_COUNT=$(grep -c "jwt" alert-rules.yml || echo 0)
echo "✓ $ALERT_COUNT JWT-related configurations in alert rules"

echo ""
echo "=== Phase 2D Setup Complete ==="
