#!/bin/bash
# @file scripts/ops/setup-redpanda-eventbus.sh
# @module infrastructure/event-bus
# @description P3-1560 Phase 1: Deploy Redpanda (Kafka-compatible) event bus
# @governance GOV-002: All engineering events flow through audit-logged event bus
# @usage setup-redpanda-eventbus.sh [--deploy]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

source "${REPO_ROOT}/scripts/_common/service-names.env"
REDPANDA_DATA_PATH="${REPO_ROOT}/data/redpanda"
KAFKA_CONFIG="${REPO_ROOT}/config/kafka-topics.yaml"

mkdir -p "${REDPANDA_DATA_PATH}" "$(dirname "${KAFKA_CONFIG}")"

wait_for_redpanda_health() {
  local max_attempts=30
  local attempt=0

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if verify_redpanda_health; then
      return 0
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  return 1
}

# Generate Redpanda configuration
generate_redpanda_config() {
  log_info "Generating Redpanda configuration..."
  
  cat > "${REPO_ROOT}/config/redpanda.yaml" <<'EOF'
cluster:
  id: 1
  brokers:
    - id: 1

redpanda:
  node_id: 1
  data_directory: /var/lib/redpanda/data
  
  admin:
    address: 0.0.0.0
    port: 9644
  
  kafka_api:
    - address: 0.0.0.0
      port: 9092
  
  schema_registry:
    address: 0.0.0.0
    port: 8081
  
  rack: primary

license_check_interval_ms: 30000
EOF
  
  log_success "Redpanda configuration generated"
}

# Create Kafka topics configuration
generate_kafka_topics() {
  log_info "Generating Kafka topics configuration..."
  
  cat > "${KAFKA_CONFIG}" <<'EOF'
# Kafka Topics Configuration for ElevatedIQ DevOS
# Schema: topic_name, partitions, replication_factor, retention_ms

topics:
  # Agent Lifecycle
  - name: agent.audit
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "7776000000"  # 90 days
      compression.type: "snappy"
      cleanup.policy: "delete"
    description: "Every agent action with full context"
  
  - name: agent.lifecycle
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "7776000000"  # 90 days
    description: "Agent spawn/complete/fail/timeout events"
  
  - name: agent.awaiting_approval
    partitions: 1
    replication_factor: 1
    config:
      retention.ms: "86400000"  # 1 day
      cleanup.policy: "delete"
    description: "Actions pending human review"
  
  - name: agent.killswitch
    partitions: 1
    replication_factor: 1
    config:
      retention.ms: "31536000000"  # 1 year
    description: "Emergency stop events"
  
  # Reputation System
  - name: reputation.update
    partitions: 2
    replication_factor: 1
    config:
      retention.ms: "31536000000"  # 1 year
    description: "Score changes for engineers/agents"
  
  # Deployment Events
  - name: deploy.events
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "31536000000"  # 1 year
    description: "All deployment starts/completions/failures"
  
  # Code Review
  - name: code.review
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "31536000000"  # 1 year
    description: "PR opened/reviewed/merged/reverted"
  
  # Incidents
  - name: incident.events
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "63072000000"  # 2 years
    description: "Incidents created/resolved/escalated"
  
  # AI Interactions
  - name: ai.interactions
    partitions: 3
    replication_factor: 1
    config:
      retention.ms: "7776000000"  # 90 days
      compression.type: "snappy"
    description: "Prompt/response metadata from Prompt Gateway"
  
  # System Alerts
  - name: system.alerts
    partitions: 2
    replication_factor: 1
    config:
      retention.ms: "2592000000"  # 30 days
    description: "Infrastructure alerts from Prometheus"
EOF
  
  log_success "Kafka topics configuration created"
}

# Generate Docker Compose service
generate_docker_compose_service() {
  log_info "Generating Docker Compose service for Redpanda..."
  
  cat > "${REPO_ROOT}/docker-compose.redpanda.yml" <<EOF
version: '3.8'

services:
  redpanda:
    image: docker.redpanda.com/redpandadata/redpanda:v26.1.6@sha256:e5b6aaecf38861d199b0d26d635b83da26dd6e6acf0684cd8b92f16b4f4b8733
    container_name: ${REDPANDA_CONTAINER_NAME}
    command:
      - redpanda
      - start
      - --node-id=1
      - --kafka-addr=0.0.0.0:9092
      - --advertise-kafka-addr=redpanda:9092
      - --schema-registry-addr=0.0.0.0:8081
      - --rpc-addr=0.0.0.0:33145
      - --advertise-rpc-addr=redpanda:33145
    ports:
      - "9092:9092"   # Kafka broker
      - "8081:8081"   # Schema Registry
      - "9644:9644"   # Admin API
    volumes:
      - ./data/redpanda:/var/lib/redpanda/data
    healthcheck:
      test: ["CMD", "rpk", "cluster", "info"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    networks:
      - services
  
  redpanda-console:
    image: docker.redpanda.com/redpandadata/console:v3.7.1@sha256:d5ec9a54339db74d8efa61b18576185903694bee1deb4c029befa492e41ac78f
    container_name: ${REDPANDA_CONSOLE_CONTAINER_NAME}
    environment:
      KAFKA_BROKERS: redpanda:9092
      SCHEMA_REGISTRY_URL: http://redpanda:8081
    ports:
      - "8080:8080"
    depends_on:
      - redpanda
    restart: unless-stopped
    networks:
      - services

networks:
  services:
    driver: bridge
EOF
  
  log_success "Docker Compose service configuration created"
}

# Initialize Kafka topics
initialize_kafka_topics() {
  log_info "Initializing Kafka topics..."
  
  if ! command -v rpk &> /dev/null; then
    log_error "rpk CLI not found. Install redpanda-cli or use docker exec"
    return 1
  fi
  
  # Wait for broker to be ready
  local max_attempts=30
  local attempt=0
  
  while [[ ${attempt} -lt ${max_attempts} ]]; do
    if rpk cluster info --brokers="${REDPANDA_KAFKA_ENDPOINT}" > /dev/null 2>&1; then
      log_success "Redpanda broker ready"
      break
    fi
    sleep 2
    attempt=$((attempt + 1))
  done
  
  if [[ ${attempt} -eq ${max_attempts} ]]; then
    log_error "Redpanda broker not ready after ${max_attempts} attempts"
    return 1
  fi
  
  # Create topics
  rpk topic create agent.audit --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create agent.lifecycle --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create deploy.events --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create incident.events --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create code.review --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create ai.interactions --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=3 --replicas=1 || true
  rpk topic create reputation.update --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=2 --replicas=1 || true
  rpk topic create system.alerts --brokers="${REDPANDA_KAFKA_ENDPOINT}" --partitions=2 --replicas=1 || true
  
  log_success "Kafka topics initialized"
}

# Verify deployment
verify_redpanda_health() {
  log_info "Verifying Redpanda health..."
  
  if ! curl -sf "http://${REDPANDA_ADMIN_ENDPOINT}/v1/cluster/brokers" > /dev/null 2>&1; then
    log_error "Redpanda admin API not responding"
    return 1
  fi
  
  if ! curl -sf "http://${REDPANDA_SCHEMA_REGISTRY_ENDPOINT}/subjects" > /dev/null 2>&1; then
    log_error "Schema Registry not responding"
    return 1
  fi
  
  log_success "Redpanda health check passed"
  return 0
}

main() {
  local deploy=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy)
        deploy=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Setting up Redpanda Event Bus for ElevatedIQ DevOS"
  
  generate_redpanda_config
  generate_kafka_topics
  generate_docker_compose_service
  
  if [[ "${deploy}" == "true" ]]; then
    log_info "Deploying Redpanda..."
    cd "${REPO_ROOT}"
    docker compose -f docker-compose.redpanda.yml up -d

    if wait_for_redpanda_health; then
      initialize_kafka_topics
      log_success "Redpanda Event Bus deployed and initialized"
    else
      log_error "Redpanda deployment failed"
      return 1
    fi
  else
    log_success "Configuration ready - use --deploy to start Redpanda"
  fi
}

main "$@"
