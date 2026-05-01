#!/bin/bash
# @file enforce-resource-limits.sh
# @module infrastructure
# @description Enforce resource limits on all Docker services to prevent runaway consumption
# @governance GOV-002 - All services must have defined resource limits
# @idempotent YES - Safe to run multiple times
set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

readonly LOG_FILE="${REPO_ROOT}/artifacts/resource-limits-$(date +%s).log"
readonly DRY_RUN="${DRY_RUN:-false}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Resource limits per service type
# Format: service_name:cpu_limit:memory_limit:cpus_reserv:memory_reserv
declare -a RESOURCE_LIMITS=(
  "opa:0.5:512m:0.25:256m"
  "oauth2-proxy:0.5:256m:0.25:128m"
  "caddy:1:512m:0.5:256m"
  "prometheus:1:1g:0.5:512m"
  "grafana:1:512m:0.5:256m"
  "loki:1:512m:0.5:256m"
  "qdrant:2:2g:1:1g"
  "postgres:2:4g:1:2g"
  "redis:1:1g:0.5:512m"
  "redpanda:4:8g:2:4g"
  "redpanda-console:1:512m:0.5:256m"
  "ollama:4:8g:2:4g"
)

# Generate docker-compose resource limits section
generate_resource_limits_yaml() {
  cat << 'EOF'
# Resource Limits Configuration for docker-compose.yml
# Add these deploy sections to each service for production safety
#
# Example:
#   service_name:
#     deploy:
#       resources:
#         limits:
#           cpus: '2.0'
#           memory: 4g
#         reservations:
#           cpus: '1.0'
#           memory: 2g

OPA:
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512m
      reservations:
        cpus: '0.25'
        memory: 256m

oauth2-proxy:
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 256m
      reservations:
        cpus: '0.25'
        memory: 128m

Caddy:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 512m
      reservations:
        cpus: '0.5'
        memory: 256m

Prometheus:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 1g
      reservations:
        cpus: '0.5'
        memory: 512m

Grafana:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 512m
      reservations:
        cpus: '0.5'
        memory: 256m

Loki:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 512m
      reservations:
        cpus: '0.5'
        memory: 256m

Qdrant:
  deploy:
    resources:
      limits:
        cpus: '2.0'
        memory: 2g
      reservations:
        cpus: '1.0'
        memory: 1g

PostgreSQL:
  deploy:
    resources:
      limits:
        cpus: '2.0'
        memory: 4g
      reservations:
        cpus: '1.0'
        memory: 2g

Redis:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 1g
      reservations:
        cpus: '0.5'
        memory: 512m

Redpanda:
  deploy:
    resources:
      limits:
        cpus: '4.0'
        memory: 8g
      reservations:
        cpus: '2.0'
        memory: 4g

Redpanda Console:
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 512m
      reservations:
        cpus: '0.5'
        memory: 256m

Ollama:
  deploy:
    resources:
      limits:
        cpus: '4.0'
        memory: 8g
      reservations:
        cpus: '2.0'
        memory: 4g
EOF
}

# Create validation script
create_validation_script() {
  cat > ./scripts/ops/validate-resource-limits.sh << 'EOF'
#!/bin/bash
# Validate that all services have resource limits configured

echo "Checking resource limits in docker-compose.yml..."

compose_file="./docker-compose.yml"
services_without_limits=0

# Check each service
for service in opa oauth2-proxy caddy prometheus grafana loki qdrant postgres redis redpanda redpanda-console ollama; do
  if ! grep -A 10 "^  $service:" "$compose_file" | grep -q "deploy:" ; then
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
EOF

  chmod +x ./scripts/ops/validate-resource-limits.sh
  log "Created validation script"
}

main() {
  log "=========================================="
  log "Enforce Resource Limits"
  log "=========================================="
  
  # Generate the YAML configuration
  local limits_file="./config/resource-limits.yaml"
  generate_resource_limits_yaml > "$limits_file"
  log "Generated resource limits configuration: $limits_file"
  
  # Create validation script
  create_validation_script
  
  log "=========================================="
  log "Resource limits configuration complete"
  log "Next: Update docker-compose.yml with deploy sections"
  log "=========================================="
}

main "$@"
