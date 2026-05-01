#!/bin/bash
###############################################################################
# @file        scripts/ops/validate-resource-limits.sh
# @module      ops/validate-resource-limits
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/ops/validate-resource-limits.sh
# @description Validates that all services in docker-compose.yml have resource limits.
# @governance GOV-002
# Validate that all services have resource limits configured

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    services_without_limits+=1
  fi
done

if [ $services_without_limits -eq 0 ]; then
  echo "✅ All services have resource limits configured"
  exit 0
else
  echo "❌ $services_without_limits services missing resource limits"
  exit 1
fi
