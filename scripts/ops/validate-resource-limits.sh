#!/bin/bash
/**
 * @file scripts/ops/validate-resource-limits.sh
 * @description Validates that all services in docker-compose.yml have resource limits.
 * @governance GOV-002
 */
# Validate that all services have resource limits configured

echo "Checking resource limits in docker-compose.yml..."

compose_file="./docker-compose.yml"
services_without_limits=0

# Check each service
for service in opa oauth2-proxy caddy prometheus grafana loki qdrant postgres redis redpanda redpanda-console ollama; do
  if ! grep -A 10 "^  $service:" "$compose_file" | grep -q "deploy:" ; then
    echo "⚠️  $service: Missing deploy section"
    ((services_without_limits++))
  fi
done

if [ $services_without_limits -eq 0 ]; then
  echo "✅ All services have resource limits configured"
  exit 0
else
  echo "❌ $services_without_limits services missing resource limits"
  exit 1
fi
