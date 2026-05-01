#!/bin/bash
# @file scripts/ops/setup-qdrant-vector-db.sh
# @module infrastructure/memory-engine
# @description P3-1562 Phase 1: Deploy Qdrant vector database for organizational memory
# @governance GOV-002: All memory data version-controlled, searchable, audited
# @usage setup-qdrant-vector-db.sh [--deploy] [--check]

set -euo pipefail

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Load service names (init.sh exports REPO_ROOT)
source "${REPO_ROOT}/scripts/_common/service-names.env"
QDRANT_DATA_PATH="${REPO_ROOT}/data/qdrant"
QDRANT_CONFIG="${REPO_ROOT}/config/qdrant-config.yaml"

mkdir -p "${QDRANT_DATA_PATH}" "$(dirname "${QDRANT_CONFIG}")"

wait_for_qdrant_health() {
  local max_attempts=30
  local attempt=0
  local qdrant_url="http://${QDRANT_ENDPOINT}/readyz"

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if curl -sf "${qdrant_url}" > /dev/null 2>&1; then
      return 0
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  return 1
}

# Generate Qdrant configuration
generate_qdrant_config() {
  log_info "Generating Qdrant configuration..."
  
  cat > "${QDRANT_CONFIG}" <<'EOF'
server:
  http_port: 6333
  grpc_port: 6334

storage:
  storage_path: /qdrant/storage
  snapshots_path: /qdrant/snapshots
  wal_path: /qdrant/wal

log_level: info

api_key: null  # Disabled for internal-only access

clusters:
  enabled: false

EOF
  
  log_success "Qdrant configuration generated at ${QDRANT_CONFIG}"
}

# Create docker-compose service definition for Qdrant
generate_docker_compose_service() {
  log_info "Generating Qdrant Docker Compose service definition..."
  
  cat > "${REPO_ROOT}/docker-compose.qdrant.yml" <<EOF
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:v1.7.0@sha256:ff1639878418c0572f50a7e1314874e399537eb97e6d2f42d6b987a07a2c4c4f
    container_name: ${QDRANT_CONTAINER_NAME}
    ports:
      - "6333:6333"    # HTTP API
      - "6334:6334"    # gRPC API
    volumes:
      - ./data/qdrant/storage:/qdrant/storage
      - ./data/qdrant/snapshots:/qdrant/snapshots
      - ./data/qdrant/wal:/qdrant/wal
      - ./config/qdrant-config.yaml:/qdrant/config/qdrant.yaml
    environment:
      - QDRANT_API_KEY=
    healthcheck:
      test: ["CMD", "curl", "-f", "http://${QDRANT_ENDPOINT}/readyz"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - services

networks:
  services:
    driver: bridge
EOF
  
  log_success "Docker Compose service definition created"
}

# Initialize Qdrant collections
initialize_qdrant_collections() {
  log_info "Initializing Qdrant collections..."
  
  local collections=(
    "incidents"
    "runbooks"
    "pr_descriptions"
    "retrospectives"
    "agent_learnings"
  )
  
  for collection in "${collections[@]}"; do
    log_info "Creating collection: ${collection}"
    
    curl -s -X POST "http://${QDRANT_ENDPOINT}/collections" \
      -H 'Content-Type: application/json' \
      -d "{
        \"create_collection\": {
          \"name\": \"${collection}\",
          \"vectors\": {
            \"size\": 768,
            \"distance\": \"Cosine\"
          }
        }
      }" 2>/dev/null || log_error "Failed to create collection: ${collection}"
  done
  
  log_success "Qdrant collections initialized"
}

# Verify Qdrant health
verify_qdrant_health() {
  log_info "Verifying Qdrant health..."
  
  local max_attempts=30
  local attempt=0
  local qdrant_url="http://${QDRANT_ENDPOINT}/readyz"
  
  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if curl -sf "${qdrant_url}" > /dev/null 2>&1; then
      log_success "Qdrant health check passed"
      return 0
    fi
    
    sleep 2
    attempt=$((attempt + 1))
  done
  
  log_error "Qdrant health check failed after ${max_attempts} attempts"
  return 1
}

main() {
  local deploy=false
  local check_only=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy)
        deploy=true
        shift
        ;;
      --check)
        check_only=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Setting up Qdrant Vector Database for Organizational Memory"
  
  generate_qdrant_config
  generate_docker_compose_service
  
  if [[ "${check_only}" == "true" ]]; then
    log_success "Configuration ready - use --deploy to start Qdrant"
    return 0
  fi
  
  if [[ "${deploy}" == "true" ]]; then
    log_info "Deploying Qdrant service..."
    cd "${REPO_ROOT}"
    docker compose -f docker-compose.qdrant.yml up -d
    
    if wait_for_qdrant_health && verify_qdrant_health; then
      initialize_qdrant_collections
      log_success "Qdrant Vector Database deployed and initialized"
    else
      log_error "Qdrant deployment failed"
      return 1
    fi
  fi
}

main "$@"