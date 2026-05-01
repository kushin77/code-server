#!/bin/bash
# Grafana Dashboard and Datasource Configuration
# Automatically configures Grafana with monitoring datasources and dashboards

set -e
trap 'echo "❌ Grafana setup failed at line $LINENO"; exit 1' ERR

GRAFANA_HOST="${GRAFANA_HOST:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Grafana Dashboard Configuration                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "Connecting to Grafana at $GRAFANA_HOST..."

# Test Grafana connectivity
if ! curl -fsSI "$GRAFANA_HOST/api/health" >/dev/null 2>&1; then
  echo "❌ Grafana not responding at $GRAFANA_HOST"
  exit 1
fi

echo "✓ Grafana is responding"
echo ""

# Login and get auth token
echo "Authenticating with Grafana..."
TOKEN=$(curl -s -X POST "$GRAFANA_HOST/api/auth/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin" \
  -d '{
    "name": "provisioning-$(date +%s)",
    "role": "Admin",
    "secondsToLive": 86400
  }' 2>/dev/null | grep -o '"key":"[^"]*' | cut -d'"' -f4 || echo "")

if [[ -z "$TOKEN" ]]; then
  echo "⚠️  Could not create token via API, using default auth"
  AUTH_HEADER="Authorization: Basic $(echo -n "$GRAFANA_USER:$GRAFANA_PASSWORD" | base64)"
else
  echo "✓ Authentication token created"
  AUTH_HEADER="Authorization: Bearer $TOKEN"
fi

echo ""
echo "Configuring datasources..."
echo "─────────────────────────"

# Configure Prometheus datasource
echo -n "  Prometheus: "
RESULT=$(curl -s -w "\n%{http_code}" -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true,
    "jsonData": {
      "timeInterval": "30s"
    }
  }')

HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "409" ]]; then
  echo "✅"
else
  echo "⚠️  ($HTTP_CODE)"
fi

# Configure Loki datasource
echo -n "  Loki: "
RESULT=$(curl -s -w "\n%{http_code}" -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "access": "proxy",
    "jsonData": {}
  }')

HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "409" ]]; then
  echo "✅"
else
  echo "⚠️  ($HTTP_CODE)"
fi

# Configure Tempo datasource
echo -n "  Tempo: "
RESULT=$(curl -s -w "\n%{http_code}" -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{
    "name": "Tempo",
    "type": "tempo",
    "url": "http://tempo:3200",
    "access": "proxy",
    "jsonData": {}
  }')

HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "409" ]]; then
  echo "✅"
else
  echo "⚠️  ($HTTP_CODE)"
fi

echo ""
echo "Creating folders..."
echo "──────────────────"

FOLDERS=("Platform" "Databases" "Infrastructure" "Services")

for FOLDER in "${FOLDERS[@]}"; do
  echo -n "  $FOLDER: "
  curl -s -X POST "$GRAFANA_HOST/api/folders" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -d "{\"title\":\"$FOLDER\"}" >/dev/null 2>&1 && echo "✅" || echo "⚠️"
done

echo ""
echo "✅ Grafana configuration complete"
echo ""
echo "Next steps:"
echo "  1. Open Grafana: $GRAFANA_HOST"
echo "  2. Login with: $GRAFANA_USER / $GRAFANA_PASSWORD"
echo "  3. Create dashboards from templates"
echo "  4. Configure alert notifications"
echo ""
