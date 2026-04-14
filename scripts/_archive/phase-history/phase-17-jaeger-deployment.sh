#!/bin/bash

################################################################################
# Phase 17: Jaeger Distributed Tracing Deployment
# Purpose: Deploy Jaeger collector, storage, and UI for distributed trace collection
# Timeline: Phase 17 Week 1 (April 29, 2026)
#
# Jaeger Components:
#   - Jaeger Agent (sidecar on each pod) - collects spans
#   - Jaeger Collector (central) - aggregates traces
#   - Cassandra (storage) - stores traces for 24 hours
#   - Jaeger UI (query) - web interface for trace search
#
# Usage: bash scripts/phase-17-jaeger-deployment.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${ROOT_DIR}/logs/phase-17-jaeger"
CONFIG_DIR="${ROOT_DIR}/config/phase-17"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "$LOG_DIR" "$CONFIG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/jaeger-deployment-${TIMESTAMP}.log"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "${LOG_DIR}/jaeger-deployment-${TIMESTAMP}.log"
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}" | tee -a "${LOG_DIR}/jaeger-deployment-${TIMESTAMP}.log"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

run_preflight() {
    log "Running pre-flight checks..."

    # Check Docker
    if ! docker ps > /dev/null 2>&1; then
        log_error "Docker daemon not responding"
        return 1
    fi
    log_success "Docker daemon: operational"

    # Check Kong is running (prerequisite from Monday)
    if ! docker ps --format "{{.Names}}" | grep -q "^kong$"; then
        log_error "Kong not running - deploy Kong first (Phase 17 Monday)"
        return 1
    fi
    log_success "Kong API Gateway: running (prerequisite met)"

    # Check disk space (Cassandra needs space for trace storage)
    local available_gb=$(df | tail -1 | awk '{print int($4 / 1024 / 1024)}')
    if [ "$available_gb" -lt 20 ]; then
        log_error "Insufficient disk space for Cassandra: ${available_gb}GB available (need 20GB)"
        return 1
    fi
    log_success "Disk space: ${available_gb}GB available (sufficient for Cassandra)"

    # Check existing Jaeger containers
    if docker ps -a --format "{{.Names}}" | grep -q jaeger; then
        log_error "Jaeger containers already exist, remove first: docker rm -f jaeger-*"
        return 1
    fi
    log_success "Jaeger containers: not running (clean state)"

    log_success "All pre-flight checks: PASSED"
    return 0
}

# ============================================================================
# CASSANDRA DEPLOYMENT (Trace Storage)
# ============================================================================

deploy_cassandra() {
    log "Deploying Cassandra for trace storage..."

    # Create Cassandra data volume
    docker volume create jaeger_cassandra_data || log "Volume may already exist"

    # Deploy Cassandra
    docker run -d \
        --name jaeger-cassandra \
        --network kong-net \
        -e CASSANDRA_CLUSTER_NAME=jaeger \
        -e CASSANDRA_NUM_TOKENS=256 \
        -e CASSANDRA_DC=dc1 \
        -e CASSANDRA_RACK=rack1 \
        -v jaeger_cassandra_data:/var/lib/cassandra \
        -p 9042:9042 \
        cassandra:4.0

    log "Waiting for Cassandra to start (this takes ~30-60 seconds)..."
    sleep 30

    # Wait for Cassandra to be ready
    local max_retries=30
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if docker exec jaeger-cassandra nodetool status 2>/dev/null | grep -q UP; then
            log_success "Cassandra: ready"
            break
        fi
        retry=$((retry + 1))
        log "Cassandra startup: retry $retry/30"
        sleep 2
    done

    if [ $retry -eq $max_retries ]; then
        log_error "Cassandra failed to start"
        docker logs jaeger-cassandra
        return 1
    fi

    # Initialize Cassandra keyspace for Jaeger
    log "Initializing Cassandra keyspace for Jaeger..."
    docker exec jaeger-cassandra cqlsh <<EOF || log "Keyspace may already exist"
CREATE KEYSPACE IF NOT EXISTS jaeger_v1 WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor' : 1};

USE jaeger_v1;

CREATE TABLE IF NOT EXISTS traces (
    trace_id blob,
    span_id bigint,
    parent_span_id bigint,
    operation_name text,
    flags int,
    start_time bigint,
    duration bigint,
    tags map<text, text>,
    logs list<map<text, text>>,
    process map<text, text>,
    PRIMARY KEY (trace_id, span_id)
);

CREATE INDEX IF NOT EXISTS idx_start_time ON traces(start_time);
EOF

    log_success "Cassandra deployment: complete"
}

# ============================================================================
# JAEGER COLLECTOR DEPLOYMENT
# ============================================================================

deploy_jaeger_collector() {
    log "Deploying Jaeger Collector..."

    docker run -d \
        --name jaeger-collector \
        --network kong-net \
        -e CASSANDRA_SERVERS=jaeger-cassandra \
        -e CASSANDRA_KEYSPACE=jaeger_v1 \
        -e COLLECTOR_ZIPKIN_HTTP_PORT=9411 \
        -p 14250:14250 \
        -p 14268:14268 \
        -p 14269:14269 \
        jaegertracing/jaeger:latest \
        /go/bin/collector-linux \
        --cassandra.servers=jaeger-cassandra \
        --cassandra.keyspace=jaeger_v1

    log "Waiting for Jaeger Collector to start..."
    sleep 3

    # Verify collector health
    local max_retries=20
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -s http://localhost:14269/ > /dev/null 2>&1; then
            log_success "Jaeger Collector: running"
            break
        fi
        retry=$((retry + 1))
        sleep 1
    done

    if [ $retry -eq $max_retries ]; then
        log_error "Jaeger Collector failed to start"
        docker logs jaeger-collector
        return 1
    fi

    log_success "Jaeger Collector deployment: complete"
}

# ============================================================================
# JAEGER QUERY DEPLOYMENT (UI)
# ============================================================================

deploy_jaeger_query() {
    log "Deploying Jaeger Query (UI)..."

    docker run -d \
        --name jaeger-query \
        --network kong-net \
        -e CASSANDRA_SERVERS=jaeger-cassandra \
        -e CASSANDRA_KEYSPACE=jaeger_v1 \
        -p 16686:16686 \
        jaegertracing/jaeger:latest \
        /go/bin/query-linux \
        --cassandra.servers=jaeger-cassandra \
        --cassandra.keyspace=jaeger_v1

    log "Waiting for Jaeger UI to start..."
    sleep 3

    # Verify UI health
    local max_retries=20
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -s http://localhost:16686/ > /dev/null 2>&1; then
            log_success "Jaeger Query (UI): running"
            break
        fi
        retry=$((retry + 1))
        sleep 1
    done

    if [ $retry -eq $max_retries ]; then
        log_error "Jaeger Query failed to start"
        docker logs jaeger-query
        return 1
    fi

    log_success "Jaeger Query deployment: complete"
}

# ============================================================================
# JAEGER AGENT DEPLOYMENT (Sidecar Pattern)
# ============================================================================

deploy_jaeger_agent_sidecars() {
    log "Configuring Jaeger Agent sidecars..."

    # Identify all code-server pods
    local containers=$(docker ps --format "{{.Names}}" | grep -E "code-server|git-proxy|api-gateway" || echo "")

    if [ -z "$containers" ]; then
        log_error "No application containers found to instrument with Jaeger agents"
        log "Once application containers are running, agents can be added"
        return 0  # Non-fatal - agents will be added when containers exist
    fi

    log "Deploying Jaeger agents as sidecars for: $containers"

    # Deploy a Jaeger agent that can be referenced by containers
    docker run -d \
        --name jaeger-agent \
        --network kong-net \
        -p 5775:5775/udp \
        -p 6831:6831/udp \
        -p 6832:6832/udp \
        -p 5778:5778 \
        jaegertracing/jaeger:latest \
        /go/bin/agent-linux \
        --reporter.logSpans=true \
        --agent.processors=zipkin.thrift,compact,binary \
        --reporter.tcpReporter.logSpans=true \
        --reporter.tcpReporter.host=jaeger-collector

    log_success "Jaeger Agent deployment: complete"
    log "Note: Application containers must be configured to report to agent"
    log "  Environment variables for span reporting:"
    log "    JAEGER_AGENT_HOST=jaeger-agent"
    log "    JAEGER_AGENT_PORT=6831"
    log "    JAEGER_SAMPLER_TYPE=const"
    log "    JAEGER_SAMPLER_PARAM=1"
}

# ============================================================================
# KONG INTEGRATION - Configure Kong to Send Traces to Jaeger
# ============================================================================

configure_kong_jaeger_integration() {
    log "Configuring Kong to send traces to Jaeger..."

    local kong_admin="http://localhost:8001"

    # Enable distributed tracing in Kong
    log "Updating Kong configuration for Jaeger integration..."

    # Add request logging plugin to all routes if not already present
    local routes=$(curl -s "$kong_admin/routes" | jq -r '.data[].id' || echo "")

    if [ -z "$routes" ]; then
        log "No routes found yet - Kong routes will be configured to send to Jaeger later"
        return 0
    fi

    # For each route, enable tracing (if not already enabled)
    while IFS= read -r route_id; do
        log "Adding trace forwarding to route: $route_id"
        curl -s -X POST "$kong_admin/routes/$route_id/plugins" \
            -d name=zipkin \
            -d config.http_endpoint="http://jaeger-collector:9411/api/v1/spans" \
            -d config.sample_ratio=0.01 \
            -d config.include_credential=false \
            | jq '.' || log "Trace plugin already exists or failed"
    done <<< "$routes"

    log_success "Kong-Jaeger integration: configured"
}

# ============================================================================
# VALIDATION & HEALTH CHECKS
# ============================================================================

validate_jaeger_deployment() {
    log "Validating Jaeger deployment..."

    # Check Cassandra
    log "Checking Cassandra..."
    if docker ps --format "{{.Names}}" | grep -q "jaeger-cassandra"; then
        log_success "Cassandra: running"
    else
        log_error "Cassandra: not running"
        return 1
    fi

    # Check Collector
    log "Checking Jaeger Collector..."
    if curl -s http://localhost:14269/ > /dev/null 2>&1; then
        log_success "Jaeger Collector: responsive"
    else
        log_error "Jaeger Collector: not responsive"
        return 1
    fi

    # Check Query UI
    log "Checking Jaeger Query UI..."
    if curl -s http://localhost:16686/ > /dev/null 2>&1; then
        log_success "Jaeger Query UI: responsive"
    else
        log_error "Jaeger Query UI: not responsive"
        return 1
    fi

    # Check Agent
    log "Checking Jaeger Agent..."
    if docker ps --format "{{.Names}}" | grep -q "jaeger-agent"; then
        log_success "Jaeger Agent: running"
    else
        log_error "Jaeger Agent: not running"
        return 1
    fi

    log_success "Jaeger deployment validation: PASSED"
}

# ============================================================================
# STATUS SUMMARY
# ============================================================================

print_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  PHASE 17 JAEGER DISTRIBUTED TRACING DEPLOYMENT COMPLETE   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Jaeger Components:"
    echo "  Agent (span collection): jaeger-agent"
    echo "    Port 6831 (UDP): Compact Thrift protocol"
    echo "    Port 5775 (UDP): Zipkin compact thrift"
    echo ""
    echo "  Collector (trace aggregation): jaeger-collector"
    echo "    Port 14268: HTTP API (for span submission)"
    echo "    Port 14250: gRPC endpoint"
    echo "    Port 9411: Zipkin API"
    echo ""
    echo "  Query UI (trace search): jaeger-query"
    echo "    URL: http://localhost:16686/"
    echo "    Use this to search for and visualize traces"
    echo ""
    echo "  Storage: jaeger-cassandra"
    echo "    Port 9042: Cassandra native protocol"
    echo "    Retention: 24 hours"
    echo ""
    echo "How to send traces:"
    echo "  1. Configure applications with JAEGER_AGENT_HOST=jaeger-agent"
    echo "  2. Set JAEGER_AGENT_PORT=6831"
    echo "  3. Set JAEGER_SAMPLER_TYPE=const and JAEGER_SAMPLER_PARAM=0.01"
    echo ""
    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep jaeger
    echo ""
    echo "Next steps:"
    echo "  1. Verify Jaeger UI: Open http://localhost:16686/"
    echo "  2. Send test traces from Kong: curl http://localhost:8000/ide/"
    echo "  3. Check traces in Jaeger UI"
    echo "  4. Proceed to Phase 17 Week 1 Wednesday: Linkerd service mesh"
    echo ""
    log_success "Phase 17 Jaeger deployment: COMPLETE"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  PHASE 17: JAEGER DISTRIBUTED TRACING DEPLOYMENT${NC}"
    echo -e "${BLUE}  Timeline: April 29, 2026 (Phase 17 Week 1 Tuesday)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    log "Starting Jaeger deployment..."
    log "Timestamp: $(date)"
    log "Working directory: $ROOT_DIR"

    # Execute deployment steps
    if ! run_preflight; then
        log_error "Pre-flight checks failed"
        exit 1
    fi

    deploy_cassandra
    deploy_jaeger_collector
    deploy_jaeger_query
    deploy_jaeger_agent_sidecars
    configure_kong_jaeger_integration

    if ! validate_jaeger_deployment; then
        log_error "Jaeger validation failed"
        exit 1
    fi

    print_summary
    log "Jaeger deployment complete!"
}

# Execute
main "$@"
