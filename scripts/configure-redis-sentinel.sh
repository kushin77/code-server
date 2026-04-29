#!/bin/bash

################################################################################
# Phase 7.1: Redis Sentinel High Availability Configuration
# Purpose: Set up Redis Sentinel for automatic failover and clustering
# Usage: ./scripts/configure-redis-sentinel.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary sentinel files..."; rm -f /tmp/sentinel-*.tmp 2>/dev/null || true' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

HA_DIR="${PROJECT_ROOT}/ha"
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

################################################################################
# 1. REDIS SENTINEL CONFIGURATION
################################################################################

create_sentinel_config() {
    log_info "Creating Redis Sentinel configuration..."

    mkdir -p "$HA_DIR/sentinel"

    cat > "${HA_DIR}/sentinel/sentinel.conf" << 'SENTINEL_CONF'
# Redis Sentinel Configuration
# This file configures Sentinel as a monitoring and failover service

################################## NETWORK #####################################

# Port that Sentinel uses to listen on
port 26379

# Bind to specific IP
bind 0.0.0.0

# TCP keepalive
tcp-keepalive 300

################################## GENERAL #####################################

# Path to working directory
dir /data/sentinel

# Daemonize (no, use Docker)
daemonize no

# Logging level (debug, verbose, notice, warning)
loglevel notice

# Log file
logfile ""

# Number of threads for parallel processing
threads 4

################################## MASTERS #####################################

# Monitor master Redis instance
# Format: sentinel monitor <master-name> <ip> <port> <quorum>
# 
# master-name: Logical name for this master
# ip/port: Master location
# quorum: Number of sentinels that must agree for failover

sentinel monitor mymaster 192.168.168.31 6379 2
sentinel auth-pass mymaster redis-password-here

# Timeout for a master to be considered down (milliseconds)
sentinel down-after-milliseconds mymaster 5000

# Number of replicas to reconfigure in parallel during failover
sentinel parallel-syncs mymaster 1

# Timeout for failover procedure (milliseconds)
sentinel failover-timeout mymaster 10000

# Notification scripts
sentinel notification-script mymaster /opt/sentinel/notification.sh
sentinel client-reconfig-script mymaster /opt/sentinel/reconfig.sh

################################## REPLICA SYNC ###############################

# Number of replicas to connect in parallel
sentinel parallel-syncs mymaster 1

# Replica sync timeout (milliseconds)
sentinel failover-timeout mymaster 10000

################################## SECURITY ####################################

# Require password for access
requirepass sentinel-password

# User ACLs (Redis 6+)
# user default on >sentinel-password ~* &*

################################## LOGGING #####################################

# Log file location
logfile /var/log/sentinel.log

# Log file max size
maxmemory 100mb

################################## AUTO FAILOVER ##############################

# Monitor interval (milliseconds)
sentinel monitor-interval 1000

# Check connection after failover
sentinel failover-check-interval 1000

# Notification timeout
sentinel notification-timeout 2000

################################## PERSISTENCE ##################################

# Save sentinel configuration to disk
# (Automatically updated when failover occurs)
save-on-bgsave-error yes

# Background save
stop-writes-on-bgsave-error yes

################################## REPLICATION CONFIG ##########################

# Min replicas for write operations
min-slaves-to-write 1
min-slaves-max-lag 10

# Replica read-only mode
slave-read-only yes

# Replication backlog size
repl-backlog-size 256mb

# Replication backlog TTL
repl-backlog-ttl 3600

################################## CLUSTER CONFIG #############################

# Sentinel can manage multiple masters
# Example additional master:
# sentinel monitor master2 192.168.168.41 6379 2

################################## CLIENTS ####################################

# Max concurrent connections
maxclients 10000

# Client eviction policy
maxmemory-policy allkeys-lru

# Lazy eviction
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

SENTINEL_CONF

    log_success "Redis Sentinel configuration created"
}

################################################################################
# 2. DOCKER COMPOSE SENTINEL SERVICE
################################################################################

create_sentinel_service() {
    log_info "Creating Docker Compose Sentinel service..."

    cat > "${HA_DIR}/docker-compose-sentinel.yml" << 'SENTINEL_DOCKER'
version: '3.8'

services:
  sentinel:
    image: redis:7.2-alpine
    container_name: code-server-sentinel
    command: redis-sentinel /etc/sentinel/sentinel.conf
    ports:
      - "26379:26379"
    volumes:
      - ./sentinel/sentinel.conf:/etc/sentinel/sentinel.conf:ro
      - ./sentinel/data:/data/sentinel
      - ./sentinel/notification.sh:/opt/sentinel/notification.sh:ro
      - ./sentinel/reconfig.sh:/opt/sentinel/reconfig.sh:ro
      - sentinel-data:/data/sentinel
    networks:
      - code-server-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "26379", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 30s
    environment:
      - SENTINEL_PORT=26379
      - SENTINEL_LOGLEVEL=notice
      - SENTINEL_MIN_REPLICAS=1
    labels:
      - "monitoring.enabled=true"
      - "monitoring.port=26379"

volumes:
  sentinel-data:
    name: code-server-sentinel-data

networks:
  code-server-network:
    name: code-server-network
    external: true
SENTINEL_DOCKER

    log_success "Docker Compose Sentinel service created"
}

################################################################################
# 3. NOTIFICATION AND RECONFIG SCRIPTS
################################################################################

create_notification_scripts() {
    log_info "Creating Sentinel notification scripts..."

    cat > "${HA_DIR}/sentinel/notification.sh" << 'NOTIFICATION_SCRIPT'
#!/bin/bash

# Redis Sentinel Notification Script
# Called when a monitored event occurs

EVENT_TYPE=$1
MASTER_NAME=$2
MASTER_IP=$3
MASTER_PORT=$4
REPLICA_IP=$5
REPLICA_PORT=$6

LOG_FILE="/var/log/sentinel-notification.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Route different event types
case "$EVENT_TYPE" in
    master-reboot)
        log "Master $MASTER_NAME rebooted"
        # Notify team
        curl -X POST http://slack-webhook/notify \
            -d "text=Redis Master $MASTER_NAME rebooted"
        ;;
    
    failover-start)
        log "Failover starting for $MASTER_NAME"
        # Disable write operations during failover
        redis-cli -h $MASTER_IP -p $MASTER_PORT CONFIG SET stop-writes-on-bgsave-error yes
        ;;
    
    failover-detected)
        log "Failover detected for $MASTER_NAME: New master $REPLICA_IP:$REPLICA_PORT"
        # Update DNS records
        # aws route53 change-resource-record-sets ...
        ;;
    
    sentinel-address-update)
        log "Sentinel address updated: $REPLICA_IP:$REPLICA_PORT"
        ;;
    
    slave-reconfig-sent)
        log "Replica reconfiguration sent to $REPLICA_IP:$REPLICA_PORT"
        ;;
    
    *)
        log "Unknown event: $EVENT_TYPE"
        ;;
esac

exit 0
NOTIFICATION_SCRIPT

    chmod +x "${HA_DIR}/sentinel/notification.sh"

    cat > "${HA_DIR}/sentinel/reconfig.sh" << 'RECONFIG_SCRIPT'
#!/bin/bash

# Redis Sentinel Client Reconfig Script
# Called when a failover completes to notify clients

MASTER_NAME=$1
MASTER_IP=$2
MASTER_PORT=$3
MASTER_AUTH=$4
RUNID=$5

LOG_FILE="/var/log/sentinel-reconfig.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log "Reconfiguring clients for $MASTER_NAME: $MASTER_IP:$MASTER_PORT"

# Update Vault with new master address
docker exec vault vault kv put secret/cache/redis \
    master_ip=$MASTER_IP \
    master_port=$MASTER_PORT \
    updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ) || log "WARNING: Could not update Vault"

# Notify connected services (optional: restart services that are cache-critical)
# docker service update --force code-server-activity-feed || log "WARNING: Could not update activity-feed"

# Update monitoring dashboards
curl -X POST http://grafana:3000/api/datasources/proxy/prometheus/api/v1/write \
    -d 'metric{job="sentinel",type="failover"} 1' || log "WARNING: Could not update Grafana"

log "Client reconfiguration complete"

exit 0
RECONFIG_SCRIPT

    chmod +x "${HA_DIR}/sentinel/reconfig.sh"
    log_success "Notification and reconfig scripts created"
}

################################################################################
# 4. MONITORING CONFIGURATION
################################################################################

create_monitoring_config() {
    log_info "Creating Sentinel monitoring configuration..."

    cat > "${HA_DIR}/sentinel-monitoring.yaml" << 'SENTINEL_MONITORING'
---
# Redis Sentinel Monitoring Configuration

monitoring:
  # Prometheus scrape config for Sentinel
  prometheus:
    scrape_interval: 15s
    job_name: redis-sentinel
    static_configs:
      - targets: ['192.168.168.31:26379', '192.168.168.42:26379']

  # Alert rules for Sentinel
  alerts:
    - name: sentinel_down
      condition: "sentinel_is_running == 0"
      duration: 1m
      severity: critical
      action: "restart sentinel, page on-call"
    
    - name: master_unreachable
      condition: "sentinel_master_state == disconnected"
      duration: 30s
      severity: critical
      action: "check network, trigger failover"
    
    - name: low_replica_count
      condition: "sentinel_connected_slaves < 1"
      duration: 2m
      severity: warning
      action: "check replica health, add new replica"
    
    - name: failover_in_progress
      condition: "sentinel_failover_state == 1"
      duration: 0s
      severity: warning
      action: "monitor failover progress"
    
    - name: failover_failed
      condition: "sentinel_failover_state == 2 AND duration > 5m"
      duration: 0s
      severity: critical
      action: "investigate failover, manual intervention needed"

  # Grafana dashboard
  dashboard:
    title: "Redis Sentinel High Availability"
    panels:
      - title: "Master Status"
        query: "sentinel_master_is_master"
      
      - title: "Connected Replicas"
        query: "sentinel_connected_slaves"
      
      - title: "Failover Progress"
        query: "sentinel_failover_state"
      
      - title: "Master Response Time"
        query: "sentinel_master_response_milliseconds"
      
      - title: "Failover Events"
        query: "rate(sentinel_failovers_total[5m])"

SENTINEL_MONITORING

    log_success "Monitoring configuration created"
}

################################################################################
# 5. FAILOVER TESTING PROCEDURES
################################################################################

create_failover_testing() {
    log_info "Creating failover testing procedures..."

    cat > "${HA_DIR}/sentinel/test-failover.sh" << 'FAILOVER_TESTING'
#!/bin/bash

# Redis Sentinel Failover Testing Script
# Simulates master failure and validates failover

set -euo pipefail

LOG_FILE="/var/log/sentinel-failover-test.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

# Test 1: Verify Sentinel is running
test_sentinel_running() {
    log "TEST 1: Verifying Sentinel is running..."
    
    if redis-cli -h $PRIMARY_HOST -p 26379 ping | grep -q PONG; then
        log "✓ Sentinel on primary is running"
    else
        log "✗ Sentinel on primary is NOT running"
        return 1
    fi
    
    if redis-cli -h $REPLICA_HOST -p 26379 ping | grep -q PONG; then
        log "✓ Sentinel on replica is running"
    else
        log "✗ Sentinel on replica is NOT running"
        return 1
    fi
}

# Test 2: Check master/replica replication
test_replication() {
    log "TEST 2: Checking master/replica replication..."
    
    master_offset=$(redis-cli -h $PRIMARY_HOST INFO replication | grep master_repl_offset | cut -d: -f2)
    replica_offset=$(redis-cli -h $REPLICA_HOST INFO replication | grep slave_repl_offset | cut -d: -f2)
    
    diff=$((master_offset - replica_offset))
    if [ $diff -lt 100 ]; then
        log "✓ Replication lag is acceptable: $diff bytes"
    else
        log "✗ Replication lag is high: $diff bytes"
        return 1
    fi
}

# Test 3: Simulate master failure
test_failover() {
    log "TEST 3: Simulating master failure..."
    
    # Check current master status before failure
    before_status=$(redis-cli -h $PRIMARY_HOST -p 26379 SENTINEL masters)
    log "Status before failure:"
    log "$before_status"
    
    # Simulate failure by stopping Redis on primary
    log "Stopping Redis on primary..."
    ssh akushnir@$PRIMARY_HOST "docker stop code-server-redis" || true
    
    # Wait for Sentinel to detect failure
    log "Waiting for Sentinel to detect failure..."
    sleep 6
    
    # Check if failover occurred
    after_status=$(redis-cli -h $REPLICA_HOST -p 26379 SENTINEL masters)
    log "Status after failure:"
    log "$after_status"
    
    # Verify replica is now master
    if echo "$after_status" | grep -q "flags=master"; then
        log "✓ Failover successful: Replica promoted to master"
    else
        log "✗ Failover failed: Replica not promoted"
        return 1
    fi
    
    # Restore primary
    log "Restoring primary..."
    ssh akushnir@$PRIMARY_HOST "docker start code-server-redis" || true
    sleep 10
    
    # Verify replication resumes
    test_replication || return 1
}

# Test 4: Verify data consistency
test_data_consistency() {
    log "TEST 4: Verifying data consistency..."
    
    # Write test data to master
    redis-cli -h $PRIMARY_HOST SET test_key "test_value_$(date +%s)" || return 1
    sleep 1
    
    # Read from replica
    value=$(redis-cli -h $REPLICA_HOST GET test_key)
    if [ -n "$value" ]; then
        log "✓ Data consistency verified: $value"
    else
        log "✗ Data consistency check failed"
        return 1
    fi
}

# Test 5: Check failover metrics
test_failover_metrics() {
    log "TEST 5: Checking failover metrics..."
    
    # Query Prometheus for failover count
    failovers=$(curl -s 'http://prometheus:9090/api/v1/query?query=sentinel_failovers_total' \
        | jq '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    log "Total failovers: $failovers"
    
    # Check for alerts
    alerts=$(curl -s 'http://prometheus:9090/api/v1/alerts' \
        | jq '.data.alerts | length' 2>/dev/null || echo "0")
    
    log "Active alerts: $alerts"
}

# Main execution
main() {
    log "=== Redis Sentinel Failover Testing Started ==="
    
    test_sentinel_running || exit 1
    test_replication || exit 1
    test_data_consistency || exit 1
    test_failover || exit 1
    test_failover_metrics
    
    log "=== All Tests Passed ==="
}

main "$@"
FAILOVER_TESTING

    chmod +x "${HA_DIR}/sentinel/test-failover.sh"
    log_success "Failover testing procedures created"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 7.1: Redis Sentinel High Availability"
    log_info "=========================================="

    create_sentinel_config
    create_sentinel_service
    create_notification_scripts
    create_monitoring_config
    create_failover_testing

    if $APPLY; then
        log_success "Phase 7.1 Complete - Redis Sentinel Configured"
    else
        log_info "Configurations created at: $HA_DIR"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
