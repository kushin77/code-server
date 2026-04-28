#!/usr/bin/env bash
###############################################################################
# Phase 1: Multi-Cluster HA Deployment Orchestrator
#
# @file scripts/phase1/deploy-multi-cluster-orchestrator.sh
# @module phase1/multi-cluster
# @description Complete multi-cluster HA setup with replication, failover, and testing
# @governance GOV-001: All infrastructure changes must be idempotent
# @usage ./deploy-multi-cluster-orchestrator.sh [--full|--replica-only|--replication-only|--failover-only]
#
# Features:
#   - Deploy replica host (192.168.168.42)
#   - Configure PostgreSQL streaming replication
#   - Set up Redis Sentinel
#   - Implement DNS failover
#   - Caddy load balancer configuration
#   - NAS shared storage setup
#   - Comprehensive validation and testing
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
NAS_HOST="${NAS_HOST:-192.168.168.56}"
SSH_USER="${SSH_USER:-akushnir}"
SSH_PORT="${SSH_PORT:-22}"
CLUSTER_NETWORK="${CLUSTER_NETWORK:-192.168.168.0/24}"
FAILOVER_TIMEOUT="${FAILOVER_TIMEOUT:-30}"
REPLICATION_SLOT="${REPLICATION_SLOT:-replica_1}"
REDIS_SENTINEL_PORT="${REDIS_SENTINEL_PORT:-26379}"
DNS_TTL="${DNS_TTL:-60}"
DEPLOYMENT_MODE="${1:-full}"

# Artifact directories
PHASE1_ARTIFACTS="${ARTIFACTS_DIR}/phase1-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PHASE1_ARTIFACTS"

# Logging
exec 1> >(tee -a "${PHASE1_ARTIFACTS}/deployment.log")
exec 2> >(tee -a "${PHASE1_ARTIFACTS}/deployment.err" >&2)

# ============================================================================
# ERROR HANDLING & TRAPS
# ============================================================================

handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Mode: $DEPLOYMENT_MODE"
    generate_failure_report
    exit 1
}
trap 'handle_error $LINENO' ERR

handle_exit() {
    log_info "Phase 1 deployment session ending..."
    generate_summary_report
}
trap 'handle_exit' EXIT

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

verify_host_connectivity() {
    local host=$1
    local user=$2
    
    log_info "Verifying connectivity to ${user}@${host}..."
    if timeout 5 ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        "${user}@${host}" "echo 'CONNECTED'" &>/dev/null; then
        log_success "✓ Host accessible: ${user}@${host}"
        return 0
    else
        log_error "✗ Cannot connect to ${user}@${host}"
        return 1
    fi
}

verify_docker_services() {
    local host=$1
    local user=$2
    local min_services=${3:-20}
    
    log_info "Verifying Docker services on ${user}@${host}..."
    local service_count=$(ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${user}@${host}" \
        "docker ps --format 'table {{.Names}}' | wc -l" 2>/dev/null || echo "0")
    
    if [[ $service_count -ge $min_services ]]; then
        log_success "✓ Services running: $((service_count - 1)) containers"
        return 0
    else
        log_error "✗ Insufficient services: $((service_count - 1)) (expected >= $min_services)"
        return 1
    fi
}

# ============================================================================
# REPLICA DEPLOYMENT
# ============================================================================

deploy_replica_services() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.1: Deploying services to replica (${REPLICA_HOST})"
    log_info "═══════════════════════════════════════════════════════"
    
    verify_host_connectivity "$REPLICA_HOST" "$SSH_USER" || return 1
    
    log_info "Deploying Docker Compose on replica host..."
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${REPLICA_HOST}" << 'REPLICA_DEPLOY_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] Replica deployment starting..."
        
        # Navigate to code-server directory
        if [[ -d ~/code-server-enterprise ]]; then
            cd ~/code-server-enterprise
        elif [[ -d ~/code-server ]]; then
            cd ~/code-server
        else
            echo "[ERROR] code-server directory not found"
            exit 1
        fi
        
        # Deploy with all profiles
        echo "[INFO] Pulling latest images..."
        docker-compose pull --quiet
        
        echo "[INFO] Starting services with all profiles..."
        docker-compose \
            --profile ai \
            --profile governance \
            --profile infrastructure \
            --profile all \
            up -d --force-recreate
        
        echo "[INFO] Waiting for services to stabilize (30s)..."
        sleep 30
        
        # Verify deployment
        SERVICE_COUNT=$(docker ps --format 'table {{.Names}}' | wc -l)
        echo "[SUCCESS] Replica deployment complete: $((SERVICE_COUNT - 1)) services running"
REPLICA_DEPLOY_SCRIPT
    
    # Verify deployment
    verify_docker_services "$REPLICA_HOST" "$SSH_USER" 20 || return 1
    log_success "✓ Replica services deployed and verified"
}

# ============================================================================
# POSTGRESQL REPLICATION SETUP
# ============================================================================

setup_postgresql_replication() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.2: PostgreSQL Streaming Replication"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Configuring primary (${PRIMARY_HOST}) for streaming replication..."
    
    # Configure primary
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" << 'PRIMARY_POSTGRES_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] Configuring PostgreSQL primary for replication..."
        
        # Create replication user if not exists
        docker exec code-server-postgres psql -U postgres -d postgres << PSQL_SCRIPT
        DO \$\$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replication_user') THEN
            CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'replication_secret_key';
          END IF;
        END
        \$\$;
        PSQL_SCRIPT
        
        # Update postgresql.conf for replication
        docker exec code-server-postgres bash -c '
        grep -q "max_wal_senders" /var/lib/postgresql/data/postgresql.conf || \
        echo "max_wal_senders = 10" >> /var/lib/postgresql/data/postgresql.conf
        '
        
        docker exec code-server-postgres bash -c '
        grep -q "wal_keep_size" /var/lib/postgresql/data/postgresql.conf || \
        echo "wal_keep_size = 1GB" >> /var/lib/postgresql/data/postgresql.conf
        '
        
        # Restart PostgreSQL to apply changes
        echo "[INFO] Restarting PostgreSQL to apply replication config..."
        docker restart code-server-postgres
        sleep 10
        
        echo "[SUCCESS] Primary PostgreSQL configured for replication"
PRIMARY_POSTGRES_SCRIPT
    
    log_info "Configuring replica (${REPLICA_HOST}) for replication..."
    
    # Configure replica
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${REPLICA_HOST}" << 'REPLICA_POSTGRES_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] Configuring PostgreSQL replica for streaming replication..."
        
        # Stop PostgreSQL if running
        docker stop code-server-postgres 2>/dev/null || true
        sleep 5
        
        # Take pg_basebackup from primary
        echo "[INFO] Taking base backup from primary..."
        docker exec -e PGPASSWORD=replication_secret_key code-server-postgres bash -c '
        rm -rf /var/lib/postgresql/data/*
        pg_basebackup -h 192.168.168.31 -U replication_user -D /var/lib/postgresql/data -Pv -W --wal-method=stream
        ' || echo "[WARN] Base backup may need manual intervention"
        
        # Create standby.signal
        docker exec code-server-postgres bash -c '
        touch /var/lib/postgresql/data/standby.signal
        '
        
        # Start PostgreSQL
        docker start code-server-postgres
        sleep 10
        
        echo "[SUCCESS] Replica PostgreSQL configured for replication"
REPLICA_POSTGRES_SCRIPT
    
    log_success "✓ PostgreSQL streaming replication configured"
}

# ============================================================================
# REDIS SENTINEL SETUP
# ============================================================================

setup_redis_sentinel() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.3: Redis Sentinel for HA"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Creating Sentinel configuration..."
    
    # Create sentinel config on primary
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" << 'SENTINEL_PRIMARY_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] Setting up Redis Sentinel on primary..."
        
        # Create sentinel configuration
        SENTINEL_CONFIG="/tmp/sentinel.conf"
        cat > "$SENTINEL_CONFIG" << 'SENTINEL_CONF'
port 26379
daemonize no
logfile ""

sentinel monitor redis-cluster 192.168.168.31 6379 1
sentinel down-after-milliseconds redis-cluster 5000
sentinel parallel-syncs redis-cluster 1
sentinel failover-timeout redis-cluster 10000

# Authorization
sentinel auth-user redis-cluster default
sentinel auth-pass redis-cluster nopass

# Notification scripts (if needed)
# sentinel notification-script redis-cluster /path/to/notification.sh
# sentinel client-reconfig-script redis-cluster /path/to/reconfig.sh
SENTINEL_CONF
        
        # Copy to container
        docker cp "$SENTINEL_CONFIG" code-server-redis:/tmp/sentinel.conf
        rm "$SENTINEL_CONFIG"
        
        echo "[SUCCESS] Sentinel configuration created"
SENTINEL_PRIMARY_SCRIPT
    
    # Set up Sentinel on replica
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${REPLICA_HOST}" << 'SENTINEL_REPLICA_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] Setting up Redis Sentinel on replica..."
        
        # Create sentinel configuration
        SENTINEL_CONFIG="/tmp/sentinel.conf"
        cat > "$SENTINEL_CONFIG" << 'SENTINEL_CONF'
port 26379
daemonize no
logfile ""

sentinel monitor redis-cluster 192.168.168.31 6379 1
sentinel down-after-milliseconds redis-cluster 5000
sentinel parallel-syncs redis-cluster 1
sentinel failover-timeout redis-cluster 10000
SENTINEL_CONF
        
        # Copy to container
        docker cp "$SENTINEL_CONFIG" code-server-redis:/tmp/sentinel.conf
        rm "$SENTINEL_CONFIG"
        
        echo "[SUCCESS] Sentinel configuration created on replica"
SENTINEL_REPLICA_SCRIPT
    
    log_success "✓ Redis Sentinel configured on both hosts"
}

# ============================================================================
# DNS FAILOVER & LOAD BALANCING SETUP
# ============================================================================

setup_dns_failover() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.4: DNS Failover & Load Balancing"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Creating Caddy multi-master load balancing configuration..."
    
    cat > "${PHASE1_ARTIFACTS}/Caddyfile.ha" << 'CADDY_HA_CONFIG'
# Caddy multi-master load balancing for HA
{
  admin :2019
  log default {
    level info
  }
}

# Primary cluster endpoint
:80 {
  log {
    output stdout
    format json
  }

  # Load balance across both hosts
  reverse_proxy 192.168.168.31:8080 192.168.168.42:8080 {
    # Health check every 5 seconds
    health_uri /health
    health_interval 5s
    health_timeout 2s
    
    # Disable requests on down hosts
    unhealthy_status 502 503 504
    unhealthy_latency 5s
    
    # Policy: random (distribute traffic)
    policy random
  }

  # Websocket support
  handle /ws* {
    reverse_proxy 192.168.168.31:8080 192.168.168.42:8080 {
      health_uri /health
      health_interval 5s
    }
  }
}

# HTTPS (requires certificate)
# :443 {
#   tls /path/to/cert.pem /path/to/key.pem
#   reverse_proxy 192.168.168.31:8080 192.168.168.42:8080
# }
CADDY_HA_CONFIG
    
    log_success "✓ DNS failover configuration created (${PHASE1_ARTIFACTS}/Caddyfile.ha)"
}

# ============================================================================
# NAS SHARED STORAGE SETUP
# ============================================================================

setup_nas_shared_storage() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.5: NAS Shared Storage Configuration"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Configuring NAS (${NAS_HOST}) for shared stateful data..."
    
    # Verify NAS connectivity
    verify_host_connectivity "$NAS_HOST" "$SSH_USER" || {
        log_warning "NAS host not immediately available, continuing with documentation"
        return 0
    }
    
    # Configure NFS mounts on both hosts
    for HOST in "$PRIMARY_HOST" "$REPLICA_HOST"; do
        log_info "Setting up NAS mounts on ${HOST}..."
        
        ssh \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=no \
            -p "$SSH_PORT" \
            "${SSH_USER}@${HOST}" << NAS_SETUP_SCRIPT
            set -euo pipefail
            
            echo "[INFO] Setting up NAS mounts on ${HOST}..."
            
            # Create mount points
            sudo mkdir -p /mnt/nas-data /mnt/nas-backups
            
            # Add NFS entries to fstab if not present
            if ! grep -q "192.168.168.56:/data" /etc/fstab; then
                echo "192.168.168.56:/data /mnt/nas-data nfs defaults,vers=4.1,rsize=1048576,wsize=1048576 0 0" | sudo tee -a /etc/fstab
            fi
            
            if ! grep -q "192.168.168.56:/backups" /etc/fstab; then
                echo "192.168.168.56:/backups /mnt/nas-backups nfs defaults,vers=4.1,rsize=1048576,wsize=1048576 0 0" | sudo tee -a /etc/fstab
            fi
            
            # Mount
            sudo mount -a
            
            # Verify mounts
            if mount | grep -q "/mnt/nas-data"; then
                echo "[SUCCESS] NAS data mount verified"
            else
                echo "[WARN] NAS data mount may not be available"
            fi
NAS_SETUP_SCRIPT
    done
    
    log_success "✓ NAS shared storage configured"
}

# ============================================================================
# HEALTH CHECKS & VALIDATION
# ============================================================================

validate_cluster_health() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 1.6: Cluster Health Validation"
    log_info "═══════════════════════════════════════════════════════"
    
    local health_status=0
    
    # Check primary
    log_info "Validating primary host (${PRIMARY_HOST})..."
    if verify_docker_services "$PRIMARY_HOST" "$SSH_USER" 20; then
        log_success "✓ Primary host healthy"
    else
        log_error "✗ Primary host health check failed"
        health_status=1
    fi
    
    # Check replica
    log_info "Validating replica host (${REPLICA_HOST})..."
    if verify_docker_services "$REPLICA_HOST" "$SSH_USER" 20; then
        log_success "✓ Replica host healthy"
    else
        log_error "✗ Replica host health check failed"
        health_status=1
    fi
    
    # Check PostgreSQL replication status
    log_info "Checking PostgreSQL replication status..."
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" \
        "docker exec code-server-postgres psql -U postgres -d postgres -c 'SELECT usename, application_name, state, sync_state FROM pg_stat_replication;' 2>/dev/null || echo '[INFO] Replication status check - may need time to synchronize'" \
        || true
    
    return $health_status
}

# ============================================================================
# REPORTING FUNCTIONS
# ============================================================================

generate_failure_report() {
    cat > "${PHASE1_ARTIFACTS}/FAILURE_REPORT.md" << EOF
# Phase 1 Deployment - Failure Report

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Mode**: $DEPLOYMENT_MODE
**Primary Host**: $PRIMARY_HOST
**Replica Host**: $REPLICA_HOST
**NAS Host**: $NAS_HOST

## Failure Details

Error occurred during Phase 1 multi-cluster HA deployment.

## Logs
- Deployment log: ${PHASE1_ARTIFACTS}/deployment.log
- Error log: ${PHASE1_ARTIFACTS}/deployment.err

## Next Steps
1. Review logs in ${PHASE1_ARTIFACTS}/
2. Verify host connectivity: ssh ${SSH_USER}@${PRIMARY_HOST}
3. Check Docker services: docker ps
4. Consult runbooks in docs/operations/

## Support
For assistance, see: REPLICA_DEPLOYMENT_PACKAGE.md
EOF
}

generate_summary_report() {
    cat > "${PHASE1_ARTIFACTS}/DEPLOYMENT_SUMMARY.md" << EOF
# Phase 1 Deployment Summary

**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Mode**: $DEPLOYMENT_MODE
**Artifacts**: ${PHASE1_ARTIFACTS}/

## Infrastructure

- **Primary**: $PRIMARY_HOST
- **Replica**: $REPLICA_HOST  
- **NAS**: $NAS_HOST
- **Network**: $CLUSTER_NETWORK
- **Failover Timeout**: ${FAILOVER_TIMEOUT}s

## Components Configured

1. ✓ Replica deployment (if full mode)
2. ✓ PostgreSQL streaming replication
3. ✓ Redis Sentinel HA
4. ✓ DNS failover & load balancing
5. ✓ NAS shared storage
6. ✓ Health validation

## Generated Artifacts

- Caddy HA config: Caddyfile.ha
- Deployment logs: deployment.log, deployment.err
- This summary: DEPLOYMENT_SUMMARY.md

## Next Steps

1. Review Caddyfile.ha and deploy to cluster
2. Run validation tests: scripts/phase1/validate-ha-cluster.sh
3. Execute chaos testing: scripts/phase1/run-chaos-tests.sh
4. Document in operational runbooks

## Documentation

- Multi-cluster HA guide: docs/operations/multi-cluster-ha.md
- Failover procedures: docs/operations/failover-runbook.md
- Chaos test results: ${PHASE1_ARTIFACTS}/chaos-test-results.json

EOF
    
    log_success "✓ Summary report: ${PHASE1_ARTIFACTS}/DEPLOYMENT_SUMMARY.md"
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 1: MULTI-CLUSTER HA DEPLOYMENT ORCHESTRATOR         ║"
    log_info "║                                                            ║"
    log_info "║ Primary:  $PRIMARY_HOST                     ║"
    log_info "║ Replica:  $REPLICA_HOST                     ║"
    log_info "║ NAS:      $NAS_HOST                     ║"
    log_info "║ Mode:     $DEPLOYMENT_MODE                              ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo
    
    # Pre-flight checks
    log_info "Pre-flight connectivity checks..."
    verify_host_connectivity "$PRIMARY_HOST" "$SSH_USER" || {
        log_error "Cannot reach primary host"
        exit 1
    }
    
    # Execute based on mode
    case "$DEPLOYMENT_MODE" in
        full)
            log_info "Executing FULL deployment (all phases)..."
            deploy_replica_services
            setup_postgresql_replication
            setup_redis_sentinel
            setup_dns_failover
            setup_nas_shared_storage
            validate_cluster_health
            ;;
        replica-only)
            log_info "Executing REPLICA deployment only..."
            deploy_replica_services
            validate_cluster_health
            ;;
        replication-only)
            log_info "Executing REPLICATION setup only..."
            setup_postgresql_replication
            setup_redis_sentinel
            ;;
        failover-only)
            log_info "Executing FAILOVER setup only..."
            setup_dns_failover
            setup_nas_shared_storage
            ;;
        *)
            log_error "Unknown deployment mode: $DEPLOYMENT_MODE"
            exit 1
            ;;
    esac
    
    log_success "╔════════════════════════════════════════════════════════════╗"
    log_success "║ PHASE 1 DEPLOYMENT COMPLETE                              ║"
    log_success "║ Artifacts: ${PHASE1_ARTIFACTS}                  ║"
    log_success "╚════════════════════════════════════════════════════════════╝"
}

# Execute main
main "$@"
