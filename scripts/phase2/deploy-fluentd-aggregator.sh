#!/usr/bin/env bash
###############################################################################
# Phase 2: SLOG Observability Stack - Fluentd Log Aggregation Pipeline
#
# @file scripts/phase2/deploy-fluentd-aggregator.sh
# @module phase2/observability
# @description Deploy Fluentd on primary and replica for log collection
# @governance GOV-001: All logs must flow to OpenSearch
# @usage ./deploy-fluentd-aggregator.sh [primary|replica|both]
###############################################################################

set -euo pipefail

# Error handling
trap 'log_error "Fluentd deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "Fluentd deployment session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
SSH_USER="${SSH_USER:-akushnir}"
OPENSEARCH_HOST_PRIMARY="${OPENSEARCH_HOST_PRIMARY:-localhost}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"

# Logging functions
log_info() { echo "[INFO]    | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_success() { echo "[SUCCESS] | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_error() { echo "[ERROR]   | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }

# ============================================================================
# FLUENTD CONFIGURATION GENERATION
# ============================================================================

generate_fluentd_config() {
    cat > /tmp/fluent.conf << 'EOF'
# Fluentd Configuration - Phase 2 SLOG Pipeline

# System log input
<source>
  @type systemd
  tag systemd
  <storage>
    @type local
    persistent true
    path /var/log/fluentd/systemd.pos
  </storage>
</source>

# Docker container logs
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

# Application logs from containers (via docker logging driver)
<source>
  @type tail
  path /var/lib/docker/containers/*/*-json.log
  pos_file /var/log/fluentd/containers.pos
  tag docker.*
  <parse>
    @type json
    time_format %Y-%m-%dT%H:%M:%S.%NZ
    time_key time
  </parse>
</source>

# Filter to enrich logs
<filter **>
  @type record_transformer
  <record>
    hostname "#{Socket.gethostname}"
    timestamp ${Time.now.iso8601}
  </record>
</filter>

# Output to OpenSearch
<match **>
  @type opensearch
  host opensearch
  port 9200
  logstash_format true
  logstash_prefix logs-${HOSTNAME}
  logstash_dateformat %Y.%m.%d
  include_tag_key true
  tag_key @log_source
  flush_interval 10s
  retry_type exponential_backoff
  retry_wait 1s
  retry_max_interval 30s
  retry_max_times 17
  retry_secondary_threshold 0.5
  <secondary>
    @type file
    path /var/log/fluentd/output-%{+%Y%m%d-%H}.log
  </secondary>
</match>
EOF

    log_success "✓ Fluentd configuration generated"
}

# ============================================================================
# DOCKER COMPOSE ADDITION FOR FLUENTD
# ============================================================================

generate_fluentd_compose() {
    cat > /tmp/fluentd-compose.yml << 'EOF'
version: '3.8'
services:
  fluentd:
    image: fluent/fluentd:v1.16-1
    container_name: fluentd-aggregator
    environment:
      FLUENT_OPENSEARCH_HOST: opensearch
      FLUENT_OPENSEARCH_PORT: "9200"
      FLUENTD_UID: "0"
    ports:
      - "24224:24224"
      - "24224:24224/udp"
    volumes:
      - /tmp/fluent.conf:/fluentd/etc/fluent.conf
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/lib/docker/containers/*/*.log:/var/lib/docker/containers/*/*.log:ro
      - /var/log/fluentd:/var/log/fluentd
    depends_on:
      - opensearch
    networks:
      - observability
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

    log_success "✓ Fluentd docker-compose addition generated"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 2: FLUENTD LOG AGGREGATION PIPELINE                ║"
    log_info "║ Collecting logs from all services                        ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    generate_fluentd_config
    generate_fluentd_compose
    
    echo ""
    log_info "Fluentd configurations ready:"
    log_info "  - Fluent configuration: /tmp/fluent.conf"
    log_info "  - Docker compose: /tmp/fluentd-compose.yml"
    log_info ""
    log_info "Next: Deploy Fluentd container on both hosts"
}

main "$@"
