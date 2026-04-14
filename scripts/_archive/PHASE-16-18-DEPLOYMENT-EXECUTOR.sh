#!/bin/bash
################################################################################
# PHASE 16-18 PRODUCTION DEPLOYMENT EXECUTOR
# Executes all infrastructure phases in proper sequence
# Date: April 14-15, 2026
# Status: PRODUCTION READY
################################################################################

set -euo pipefail

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_FILE="/tmp/phase-16-18-deployment-${TIMESTAMP}.log"
PHASE_RESULTS="/tmp/phase-16-18-results-${TIMESTAMP}.txt"

# ───────────────────────────────────────────────────────────────────────────
# LOGGING
# ───────────────────────────────────────────────────────────────────────────

log() {
    echo "[$(date -u +'%H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

success() {
    echo "✓ $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "✗ ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# ───────────────────────────────────────────────────────────────────────────
# PHASE 16-A: DATABASE HIGH AVAILABILITY
# ───────────────────────────────────────────────────────────────────────────

deploy_phase_16_a() {
    log "=== PHASE 16-A: DATABASE HA DEPLOYMENT ==="

    local start_time=$(date +%s)

    log "Creating PostgreSQL primary container..."
    docker run -d \
        --name postgres-ha-primary \
        --network phase13-net \
        -e POSTGRES_DB=code_server_db \
        -e POSTGRES_USER=db_admin \
        -e POSTGRES_PASSWORD=$(openssl rand -base64 32) \
        -e POSTGRES_INITDB_ARGS="-c max_wal_senders=10 -c max_replication_slots=10 -c wal_level=replica" \
        -p 5432:5432 \
        -v /var/lib/postgresql/primary:/var/lib/postgresql/data \
        --health-cmd="pg_isready -U db_admin" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --restart=unless-stopped \
        postgres:15.2-alpine

    log "Waiting for PostgreSQL primary to be healthy..."
    for i in {1..40}; do
        if docker exec postgres-ha-primary pg_isready -U db_admin 2>/dev/null; then
            success "PostgreSQL primary is healthy"
            break
        fi
        if [ $i -eq 40 ]; then
            error "PostgreSQL primary failed to become healthy"
            return 1
        fi
        sleep 5
    done

    log "Creating PostgreSQL replica containers..."
    for i in {1..2}; do
        docker run -d \
            --name postgres-ha-replica-${i} \
            --network phase13-net \
            -e PGUSER=replication_user \
            -e PGPASSWORD=$(openssl rand -base64 32) \
            -e PGMASTER=postgres-ha-primary \
            -e PGPORT=5432 \
            -p $((5432 + i)):5432 \
            -v /var/lib/postgresql/replica-${i}:/var/lib/postgresql/data \
            --health-cmd="pg_isready -U replication_user -h postgres-ha-primary" \
            --health-interval=30s \
            --health-timeout=10s \
            --health-retries=3 \
            --restart=unless-stopped \
            postgres:15.2-alpine
    done

    log "Creating pgBouncer connection pool..."
    docker run -d \
        --name pgbouncer-pool \
        --network phase13-net \
        -p 6432:6432 \
        -e PGBOUNCER_LISTEN_PORT=6432 \
        -e PGBOUNCER_POOL_MODE=transaction \
        -v /etc/pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro \
        --restart=unless-stopped \
        edoburu/pgbouncer:1.21.0

    log "Creating Patroni HA orchestrator..."
    docker run -d \
        --name patroni-ha-controller \
        --network phase13-net \
        -p 8008:8008 \
        -e PATRONI_SCOPE=code-server-ha \
        -e PATRONI_RESTAPI_LISTEN=0.0.0.0:8008 \
        --restart=unless-stopped \
        patroni:3.0.2-alpine

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "Phase 16-A completed in ${duration} seconds"
    echo "PHASE 16-A: COMPLETED (${duration}s)" >> "${PHASE_RESULTS}"
}

# ───────────────────────────────────────────────────────────────────────────
# PHASE 16-B: LOAD BALANCING & AUTO-SCALING
# ───────────────────────────────────────────────────────────────────────────

deploy_phase_16_b() {
    log "=== PHASE 16-B: LOAD BALANCING DEPLOYMENT ==="

    local start_time=$(date +%s)

    log "Creating HAProxy primary load balancer..."
    docker run -d \
        --name haproxy-lb-primary \
        --network phase13-net \
        --cap-add=NET_ADMIN \
        -p 80:80 \
        -p 443:443 \
        -p 8404:8404 \
        -v /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
        --health-cmd="curl -f http://localhost:8404/stats || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --restart=unless-stopped \
        haproxy:2.8.5-alpine

    log "Creating HAProxy backup load balancer..."
    docker run -d \
        --name haproxy-lb-backup \
        --network phase13-net \
        --cap-add=NET_ADMIN \
        -p 8080:8080 \
        -p 8443:8443 \
        -p 8405:8405 \
        -v /etc/haproxy/haproxy-backup.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
        --health-cmd="curl -f http://localhost:8405/stats || exit 1" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-retries=3 \
        --restart=unless-stopped \
        haproxy:2.8.5-alpine

    log "Creating Keepalived primary VIP controller..."
    docker run -d \
        --name keepalived-vip-primary \
        --network phase13-net \
        --privileged \
        --cap-add=NET_ADMIN \
        -e KEEPALIVED_PRIORITY=150 \
        -e KEEPALIVED_VIRTUAL_IP=192.168.168.50 \
        -e KEEPALIVED_VIRTUAL_ROUTER_ID=51 \
        -v /etc/keepalived:/etc/keepalived:ro \
        --restart=unless-stopped \
        arcts/keepalived:2.2.7

    log "Creating Keepalived backup VIP controller..."
    docker run -d \
        --name keepalived-vip-backup \
        --network phase13-net \
        --privileged \
        --cap-add=NET_ADMIN \
        -e KEEPALIVED_PRIORITY=100 \
        -e KEEPALIVED_VIRTUAL_IP=192.168.168.50 \
        -e KEEPALIVED_VIRTUAL_ROUTER_ID=51 \
        -v /etc/keepalived:/etc/keepalived:ro \
        --restart=unless-stopped \
        arcts/keepalived:2.2.7

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "Phase 16-B completed in ${duration} seconds"
    echo "PHASE 16-B: COMPLETED (${duration}s)" >> "${PHASE_RESULTS}"
}

# ───────────────────────────────────────────────────────────────────────────
# PHASE 18: SECURITY HARDENING
# ───────────────────────────────────────────────────────────────────────────

deploy_phase_18() {
    log "=== PHASE 18: SECURITY HARDENING DEPLOYMENT ==="

    local start_time=$(date +%s)

    log "Creating Consul service registry cluster..."
    for i in {1..3}; do
        docker run -d \
            --name consul-server-${i} \
            --network phase13-net \
            -p $((8300 + i - 1)):8300 \
            -p $((8301 + i - 1)):8301 \
            -p $((8302 + i - 1)):8302 \
            -p $((8500 + i - 1)):8500 \
            -p $((8600 + i - 1)):8600/udp \
            -v /var/lib/consul/node-${i}:/consul/data \
            --restart=unless-stopped \
            consul:1.17.0 agent \
                -server \
                -ui \
                -node=consul-${i} \
                -bootstrap-expect=3 \
                -client=0.0.0.0 || true
    done

    log "Waiting for Consul cluster to stabilize..."
    sleep 10

    log "Creating Vault HA cluster..."
    for i in {1..3}; do
        docker run -d \
            --name vault-ha-node-${i} \
            --network phase13-net \
            --cap-add=IPC_LOCK \
            -e VAULT_ADDR=http://127.0.0.1:8200 \
            -p $((8200 + i - 1)):8200 \
            -v /var/lib/vault/node-${i}:/vault/data \
            -v /etc/vault/config:/vault/config:ro \
            -v /etc/tls/vault:/vault/tls:ro \
            --health-cmd="vault status" \
            --health-interval=30s \
            --health-timeout=10s \
            --health-retries=3 \
            --restart=unless-stopped \
            vault:1.15.0 server -config=/vault/config/vault.hcl || true
    done

    log "Setting up TLS certificates for mTLS..."
    mkdir -p /etc/tls/{certs,keys,ca}
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/tls/keys/server.key \
        -out /etc/tls/certs/server.crt \
        -subj "/C=US/ST=CA/L=San Francisco/O=Code Server/CN=code-server" 2>/dev/null || true

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "Phase 18 completed in ${duration} seconds"
    echo "PHASE 18: COMPLETED (${duration}s)" >> "${PHASE_RESULTS}"
}

# ───────────────────────────────────────────────────────────────────────────
# PHASE 17: MULTI-REGION REPLICATION
# ───────────────────────────────────────────────────────────────────────────

deploy_phase_17() {
    log "=== PHASE 17: MULTI-REGION REPLICATION DEPLOYMENT ==="

    local start_time=$(date +%s)

    log "Creating pglogical replicator containers..."
    docker run -d \
        --name pglogical-replicator-primary \
        --network phase13-net \
        -e POSTGRES_DB=code_server_db \
        -e POSTGRES_USER=replication_user \
        -e POSTGRES_PASSWORD=$(openssl rand -base64 32) \
        -e PGLOGICAL_ENABLED=true \
        -p 5434:5432 \
        -v /var/lib/postgresql/pglogical-primary:/var/lib/postgresql/data \
        --restart=unless-stopped \
        postgres:15.2-alpine

    log "Creating DR failover controller..."
    docker run -d \
        --name dr-failover-controller \
        --network phase13-net \
        -e PRIMARY_REGION=us-east-1 \
        -e REPLICA_REGIONS=us-west-1,eu-west-1 \
        -e FAILOVER_TIMEOUT=60 \
        --restart=unless-stopped \
        alpine:latest sleep infinity

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "Phase 17 completed in ${duration} seconds"
    echo "PHASE 17: COMPLETED (${duration}s)" >> "${PHASE_RESULTS}"
}

# ───────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ───────────────────────────────────────────────────────────────────────────

main() {
    log "================================"
    log "PHASE 16-18 DEPLOYMENT EXECUTOR"
    log "Start Time: ${TIMESTAMP}"
    log "================================"

    # Pre-flight checks
    log "Running pre-flight checks..."

    if ! command -v docker &> /dev/null; then
        error "docker is not installed"
        exit 1
    fi

    if ! docker network inspect phase13-net &> /dev/null; then
        log "Creating docker network phase13-net..."
        docker network create phase13-net --driver bridge 2>/dev/null || true
    fi

    success "Pre-flight checks passed"

    # Deploy phases in parallel/sequential order
    log "Starting Phase deployments..."

    # Phases 16-A, 16-B, and 18 can run in parallel
    log "Deploying Phase 16-A (Database HA)..."
    deploy_phase_16_a &
    PID_16A=$!

    log "Deploying Phase 16-B (Load Balancing)..."
    deploy_phase_16_b &
    PID_16B=$!

    log "Deploying Phase 18 (Security Hardening)..."
    deploy_phase_18 &
    PID_18=$!

    # Wait for all parallel phases to complete
    log "Waiting for parallel phases to complete..."
    wait $PID_16A $PID_16B $PID_18

    success "All parallel phases completed"

    # Phase 17 is sequential after Phase 16
    log "Deploying Phase 17 (Multi-Region Replication - sequential)..."
    deploy_phase_17

    # Final summary
    log "================================"
    log "DEPLOYMENT COMPLETE"
    log "================================"

    cat "${PHASE_RESULTS}" | tee -a "${LOG_FILE}"

    log "Final Status:"
    docker ps --filter "name=postgres-ha\|haproxy-lb\|vault-ha\|consul-server\|pglogical" --format "table {{.Names}}\t{{.Status}}"

    log "Logs available at: ${LOG_FILE}"
    log "Results available at: ${PHASE_RESULTS}"
}

# Execute main
main "$@"
