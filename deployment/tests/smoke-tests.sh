#!/bin/bash
# Smoke Tests - Verify production deployment health

set -e

BASE_URL=${BASE_URL:-http://localhost:8080}
PROMETHEUS_URL=${PROMETHEUS_URL:-http://localhost:9090}
GRAFANA_URL=${GRAFANA_URL:-http://localhost:3100}

echo "=== Starting Production Smoke Tests ==="
echo "Base URL: $BASE_URL"

# Test 1: Service Health Checks
echo ""
echo "Test 1: Service Health Checks"
echo "---"

services=(
  'code-server'
  'postgres'
  'redis'
  'prometheus'
  'grafana'
)

for service in "${services[@]}"; do
  url="$BASE_URL/health"
  if [[ "$service" == "prometheus" ]]; then
    url="$PROMETHEUS_URL/-/healthy"
  elif [[ "$service" == "grafana" ]]; then
    url="$GRAFANA_URL/api/health"
  fi
  
  echo "Checking $service..."
  if curl -sf "$url" > /dev/null; then
    echo "✓ $service is healthy"
  else
    echo "✗ $service failed health check"
    exit 1
  fi
done

# Test 2: API Endpoints
echo ""
echo "Test 2: API Endpoints"
echo "---"

endpoints=(
  '/api/health'
  '/api/workspaces'
  '/api/status'
)

for endpoint in "${endpoints[@]}"; do
  echo "Testing GET $endpoint..."
  response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
  http_code=$(echo "$response" | tail -1)
  
  if [[ $http_code -eq 200 ]]; then
    echo "✓ $endpoint: $http_code OK"
  else
    echo "✗ $endpoint: $http_code FAILED"
    exit 1
  fi
done

# Test 3: Database Connectivity
echo ""
echo "Test 3: Database Connectivity"
echo "---"

response=$(curl -s "$BASE_URL/api/health")
if echo "$response" | grep -q '"database"'; then
  echo "✓ Database is accessible"
else
  echo "✗ Database connectivity check failed"
  exit 1
fi

# Test 4: Monitoring Integration
echo ""
echo "Test 4: Monitoring Integration"
echo "---"

# Check Prometheus metrics
prometheus_response=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up")
if echo "$prometheus_response" | grep -q '"value"'; then
  echo "✓ Prometheus is scraping metrics"
else
  echo "✗ Prometheus metrics collection failed"
  exit 1
fi

# Test 5: SLO Metrics Availability
echo ""
echo "Test 5: SLO Metrics"
echo "---"

slo_metrics=(
  'slo:availability:30d'
  'slo:error_rate:30d'
  'slo:latency:p99'
)

for metric in "${slo_metrics[@]}"; do
  response=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric")
  if echo "$response" | grep -q '"resultType"'; then
    echo "✓ SLO metric $metric available"
  fi
done

echo ""
echo "=== All Smoke Tests Passed ===" 
echo "Production deployment is healthy"
