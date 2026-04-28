#!/usr/bin/env bash
###############################################################################
# Phase 2: SLOG Observability Stack - OpenSearch Cluster Deployment
#
# @file scripts/phase2/deploy-opensearch-cluster.sh
# @module phase2/observability
# @description Deploy OpenSearch cluster on primary and replica hosts
# @governance GOV-001: All logs must be centralized and immutable
# @usage ./deploy-opensearch-cluster.sh [primary|replica|both]
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set}"
REPLICA_HOST="${REPLICA_HOST:?REPLICA_HOST must be set}"
SSH_USER="${SSH_USER:-akushnir}"
SSH_PORT="${SSH_PORT:-22}"
DEPLOY_MODE="${1:-both}"

# Logging functions
log_info() { echo "[INFO]    | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_success() { echo "[SUCCESS] | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_error() { echo "[ERROR]   | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }

# Error handling
trap 'log_error "OpenSearch deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "OpenSearch deployment session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# OPENSEARCH CONFIGURATION
# ============================================================================

generate_opensearch_config() {
    local node_name=$1
    local cluster_role=$2
    local cluster_hosts=$3
    
    cat > /tmp/opensearch.yml << EOF
# OpenSearch Configuration - Phase 2 SLOG Stack

cluster.name: 'elite-enterprise-observability'
node.name: '${node_name}'
node.roles: [${cluster_role}]

# Network settings
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

# Discovery and clustering
discovery.seed_hosts: [${cluster_hosts}]
cluster.initial_master_nodes: ['primary-node', 'replica-node']

# Security (basic disabled for now, enable in Phase 5)
plugins.security.disabled: true

# Performance tuning
indices.memory.index_buffer_size: 30%
thread_pool.write.queue_size: 1000
thread_pool.search.queue_size: 5000

# Logging
logger.level: info
rootLogger.level: info
EOF
}

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================

deploy_opensearch_primary() {
    log_info "Deploying OpenSearch on primary (${PRIMARY_HOST})..."
    
    generate_opensearch_config "primary-node" "master,data,ingest" "'primary-node','replica-node'"
    
    # Create docker-compose addition for OpenSearch
    cat >> /tmp/opensearch-compose.yml << 'EOF'
version: '3.8'
services:
  opensearch:
    image: opensearchproject/opensearch:2.5.0
    container_name: opensearch-primary
    environment:
      - discovery.type=zen
      - node.name=primary-node
      - cluster.name=elite-enterprise-observability
      - OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g
      - DISABLE_SECURITY_PLUGIN=true
    ports:
      - "9200:9200"
      - "9300:9300"
    volumes:
      - opensearch-data-primary:/usr/share/opensearch/data
      - /tmp/opensearch.yml:/usr/share/opensearch/config/opensearch.yml:ro
    networks:
      - observability
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200 >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  opensearch-data-primary:

networks:
  observability:
    driver: bridge
EOF

    log_success "✓ OpenSearch primary configuration generated"
}

deploy_opensearch_replica() {
    log_info "Deploying OpenSearch on replica (${REPLICA_HOST})..."
    
    generate_opensearch_config "replica-node" "master,data,ingest" "'primary-node','replica-node'"
    
    cat >> /tmp/opensearch-compose.yml << 'EOF'
version: '3.8'
services:
  opensearch:
    image: opensearchproject/opensearch:2.5.0
    container_name: opensearch-replica
    environment:
      - discovery.type=zen
      - node.name=replica-node
      - cluster.name=elite-enterprise-observability
      - cluster.initial_master_nodes=primary-node,replica-node
      - discovery.seed_hosts=primary-node,replica-node
      - OPENSEARCH_JAVA_OPTS=-Xms2g -Xmx2g
      - DISABLE_SECURITY_PLUGIN=true
    ports:
      - "9200:9200"
      - "9300:9300"
    volumes:
      - opensearch-data-replica:/usr/share/opensearch/data
      - /tmp/opensearch.yml:/usr/share/opensearch/config/opensearch.yml:ro
    networks:
      - observability
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200 >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  opensearch-data-replica:

networks:
  observability:
    driver: bridge
EOF

    log_success "✓ OpenSearch replica configuration generated"
}

verify_opensearch_deployment() {
    log_info "Verifying OpenSearch deployment..."
    
    # Check primary
    local primary_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" \
        "curl -s http://localhost:9200 2>/dev/null | jq -r '.cluster_name' 2>/dev/null" || echo "FAIL")
    
    if [[ "$primary_status" == "elite-enterprise-observability" ]]; then
        log_success "✓ Primary OpenSearch cluster online"
    else
        log_error "Primary OpenSearch not responding"
    fi
    
    # Check replica
    local replica_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${REPLICA_HOST}" \
        "curl -s http://localhost:9200 2>/dev/null | jq -r '.cluster_name' 2>/dev/null" || echo "FAIL")
    
    if [[ "$replica_status" == "elite-enterprise-observability" ]]; then
        log_success "✓ Replica OpenSearch cluster online"
    else
        log_error "Replica OpenSearch not responding"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 2: OPENSEARCH CLUSTER DEPLOYMENT                   ║"
    log_info "║ Centralized Logging Infrastructure                       ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    case "$DEPLOY_MODE" in
        primary)
            deploy_opensearch_primary
            ;;
        replica)
            deploy_opensearch_replica
            ;;
        both)
            deploy_opensearch_primary
            deploy_opensearch_replica
            ;;
        *)
            log_error "Unknown mode: $DEPLOY_MODE"
            echo "Usage: $0 [primary|replica|both]"
            exit 1
            ;;
    esac
    
    echo ""
    log_info "Deployment configurations generated"
    log_info "Next: Deploy via docker-compose on target hosts"
    
    verify_opensearch_deployment
}

main "$@"
