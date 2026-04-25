#!/bin/bash
###############################################################################
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Purpose: Validates that all services in docker-compose.yml have resource limits
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1536 (Infrastructure Standards)
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Checking resource limits in docker-compose.yml..."

compose_file="./docker-compose.yml"
services_without_limits=0

service_has_deploy() {
  local service_name="$1"

  awk -v svc="  ${service_name}:" '
    BEGIN { in_block = 0; found = 0 }
    $0 == svc { in_block = 1; next }
    in_block && $0 ~ /^  [A-Za-z0-9._-]+:/ { exit found ? 0 : 1 }
    in_block && $0 ~ /^[[:space:]]*deploy:/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$compose_file"
}

# Check each service
for service in opa oauth2-proxy caddy prometheus grafana loki qdrant postgres redis redpanda redpanda-console ollama; do
  if ! service_has_deploy "$service"; then
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
