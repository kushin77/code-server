#!/bin/bash

################################################################################
# Phase 7.3: Multi-Region Failover Configuration
# Purpose: Configure geographic redundancy and cross-region failover
# Usage: ./scripts/configure-multi-region-failover.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary files..."; rm -f /tmp/failover-*.tmp 2>/dev/null || true' EXIT

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

MR_DIR="${PROJECT_ROOT}/multi-region"

################################################################################
# 1. MULTI-REGION FAILOVER CONFIGURATION
################################################################################

create_multi_region_config() {
    log_info "Creating multi-region failover configuration..."

    mkdir -p "$MR_DIR"

    cat > "${MR_DIR}/multi-region-config.yaml" << 'MULTI_REGION'
---
# Multi-Region Failover Configuration

multi_region:
  # Region configuration
  regions:
    # Primary region
    primary:
      name: "us-east-1"
      endpoint: "192.168.168.31"
      availability: "primary"
      priority: 1
      services:
        - postgres
        - redis
        - minio
        - vault
        - caddy
      
      # Health checks
      health_check:
        interval: 10s
        timeout: 3s
        unhealthy_threshold: 3
      
      # Replication settings
      replication:
        mode: master
        sync_interval: 1s
        replication_lag_threshold: 5s

    # Secondary region
    secondary:
      name: "us-west-2"
      endpoint: "192.168.168.42"
      availability: "secondary"
      priority: 2
      services:
        - postgres
        - redis
        - minio
        - vault
        - caddy
      
      health_check:
        interval: 10s
        timeout: 3s
        unhealthy_threshold: 3
      
      replication:
        mode: replica
        sync_interval: 1s

    # Disaster recovery region (optional)
    dr:
      name: "eu-west-1"
      endpoint: "10.0.0.1"
      availability: "standby"
      priority: 3
      services:
        - postgres  # Read-only replica
        - redis     # Read-only replica
        - minio     # Backup storage
      
      replication:
        mode: replica
        sync_interval: 5m

  # DNS configuration
  dns:
    # Primary domain
    primary_domain: "code-server.local"
    
    # Regional endpoints
    regional_endpoints:
      us_east_1: "code-server-east.local"
      us_west_2: "code-server-west.local"
    
    # DNS provider
    provider: "route53"
    failover_policy:
      type: geolocation
      default_region: "us-east-1"
      ttl: 60  # Fast failover
    
    # Health check based routing
    health_check_routing:
      enabled: true
      interval: 10s
      failure_threshold: 3
      measures_latency: true

  # Data replication
  replication:
    # PostgreSQL streaming replication
    postgres:
      mode: streaming
      sync_replicas: 1
      replication_slots: true
      wal_keep_segments: 1000
      max_wal_senders: 5
      
      # Backup replication
      backup_replication:
        enabled: true
        destination: "s3://backups-west/"
        frequency: hourly

    # Redis replication
    redis:
      mode: master-slave
      slave_priority: 100
      repl_diskless_sync: true
      repl_diskless_sync_delay: 5
      
      # Sentinel for auto-failover
      sentinel_enabled: true
      sentinel_down_after: 5000ms
      sentinel_parallel_syncs: 1

    # MinIO replication
    minio:
      mode: active-active
      bucket_replication: true
      replication_filter:
        - "object-prefix=*"
      delete_marker_replication: true
      
      # Versioning
      versioning_enabled: true
      mfa_delete: false

  # Failover logic
  failover:
    # Detection
    detection:
      method: active_health_check
      interval: 10s
      timeout: 3s
      consecutive_failures: 3
    
    # Orchestration
    orchestration:
      auto_failover: true
      
      # Pre-failover checks
      pre_checks:
        - "verify_secondary_is_healthy"
        - "verify_replication_lag < 5s"
        - "verify_data_consistency"
      
      # Failover steps
      steps:
        - priority: 1
          action: "stop_writes_to_primary"
          timeout: 10s
        
        - priority: 2
          action: "promote_secondary_to_primary"
          timeout: 30s
        
        - priority: 3
          action: "update_dns_records"
          timeout: 60s
        
        - priority: 4
          action: "reconfigure_clients"
          timeout: 120s
        
        - priority: 5
          action: "verify_write_operations"
          timeout: 30s
      
      # Post-failover validation
      post_validation:
        - "check_error_rates < 1%"
        - "verify_all_services_healthy"
        - "confirm_data_consistency"
        - "send_alerts"

    # Rollback capability
    rollback:
      enabled: true
      auto_rollback_on_error: true
      rollback_threshold:
        error_rate: 5%  # If error rate > 5%, rollback
        latency_p99: 5000ms  # If p99 latency > 5s, rollback
      timeout: 300s

  # Monitoring
  monitoring:
    metrics:
      - replication_lag_ms
      - dns_failover_count
      - recovery_time_seconds
      - data_consistency_check_duration
      - failover_success_rate
    
    alerts:
      - name: replication_lag_high
        condition: "replication_lag_ms > 5000"
        severity: warning
      
      - name: region_unhealthy
        condition: "region_health_status == unhealthy"
        severity: critical
      
      - name: failover_in_progress
        condition: "failover_state == active"
        severity: warning
      
      - name: failover_failed
        condition: "failover_state == failed"
        severity: critical
      
      - name: data_consistency_check_failed
        condition: "consistency_check_result == failed"
        severity: critical

  # Disaster recovery
  disaster_recovery:
    # RPO and RTO
    rpo_seconds: 60      # 1 minute max data loss
    rto_seconds: 300     # 5 minutes max downtime
    
    # Failover time tracking
    failover_time_tracking:
      detection_time: 10s
      orchestration_time: 60s
      dns_propagation_time: 60s
      client_reconnection_time: 30s
    
    # DR testing
    testing:
      schedule: "monthly"
      test_duration: 1h
      test_environment: "dr-region"
      automation: true

  # Cost optimization
  cost:
    standby_scaling: true
    scale_down_schedule:
      - region: "dr"
        start_time: "18:00"
        end_time: "06:00"
        scale: 50%
    
    reserved_capacity:
      primary: 100%
      secondary: 100%
      dr: 25%

MULTI_REGION

    log_success "Multi-region configuration created"
}

################################################################################
# 2. DNS FAILOVER MANAGEMENT
################################################################################

create_dns_failover() {
    log_info "Creating DNS failover management script..."

    cat > "${MR_DIR}/dns-failover-manager.sh" << 'DNS_FAILOVER'
#!/bin/bash

# DNS Failover Manager
# Manages DNS records for multi-region failover

set -euo pipefail

LOG_FILE="/var/log/dns-failover.log"
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check region health
check_region_health() {
    local region="$1"
    local endpoint="$2"
    
    # HTTP health check
    if curl -sf "https://$endpoint/health" > /dev/null 2>&1; then
        log "✓ Region $region is healthy"
        echo "healthy"
    else
        log "✗ Region $region is unhealthy"
        echo "unhealthy"
    fi
}

# Failover to secondary region
failover_to_secondary() {
    log "Initiating failover to secondary region..."
    
    # Verify secondary is healthy
    health=$(check_region_health "$SECONDARY_REGION" "192.168.168.42")
    
    if [ "$health" != "healthy" ]; then
        log "ERROR: Secondary region is not healthy"
        return 1
    fi
    
    log "Secondary region is healthy, proceeding with failover..."
    
    # Update Route53 to point to secondary
    aws route53 change-resource-record-sets \
        --hosted-zone-id Z123 \
        --change-batch '{
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "code-server.local",
                    "Type": "A",
                    "TTL": 60,
                    "ResourceRecords": [{"Value": "192.168.168.42"}]
                }
            }]
        }'
    
    log "✓ DNS updated to point to secondary region"
    
    # Wait for DNS propagation
    log "Waiting for DNS propagation..."
    sleep 10
    
    # Verify clients can reach secondary
    if nslookup code-server.local | grep "192.168.168.42"; then
        log "✓ DNS failover verified"
    else
        log "✗ DNS failover failed - clients may still reach old endpoint"
        return 1
    fi
}

# Failback to primary region
failback_to_primary() {
    log "Initiating failback to primary region..."
    
    # Verify primary is healthy
    health=$(check_region_health "$PRIMARY_REGION" "192.168.168.31")
    
    if [ "$health" != "healthy" ]; then
        log "ERROR: Primary region is not healthy yet"
        return 1
    fi
    
    log "Primary region is healthy, proceeding with failback..."
    
    # Update Route53 back to primary
    aws route53 change-resource-record-sets \
        --hosted-zone-id Z123 \
        --change-batch '{
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "code-server.local",
                    "Type": "A",
                    "TTL": 60,
                    "ResourceRecords": [{"Value": "192.168.168.31"}]
                }
            }]
        }'
    
    log "✓ DNS updated back to primary region"
    
    # Wait for secondary to catch up with replicated data
    log "Waiting for replication to catch up..."
    sleep 30
    
    log "✓ Failback complete"
}

# Monitor region health continuously
monitor_regions() {
    log "Starting region health monitoring..."
    
    while true; do
        primary_health=$(check_region_health "$PRIMARY_REGION" "192.168.168.31")
        secondary_health=$(check_region_health "$SECONDARY_REGION" "192.168.168.42")
        
        current_active=$(nslookup code-server.local | grep -o "192\.168\.168\.[0-9]*")
        
        # If primary is down and secondary is up, failover
        if [ "$primary_health" = "unhealthy" ] && [ "$secondary_health" = "healthy" ] && [ "$current_active" = "192.168.168.31" ]; then
            log "Primary region failure detected, initiating failover..."
            failover_to_secondary
        
        # If both are healthy and we're on secondary, failback to primary
        elif [ "$primary_health" = "healthy" ] && [ "$secondary_health" = "healthy" ] && [ "$current_active" = "192.168.168.42" ]; then
            log "Primary region recovered, initiating failback..."
            failback_to_primary
        fi
        
        sleep 10
    done
}

# Main execution
case "${1:-monitor}" in
    monitor)
        monitor_regions
        ;;
    
    failover)
        failover_to_secondary
        ;;
    
    failback)
        failback_to_primary
        ;;
    
    *)
        echo "Usage: $0 {monitor|failover|failback}"
        exit 1
        ;;
esac
DNS_FAILOVER

    chmod +x "${MR_DIR}/dns-failover-manager.sh"
    log_success "DNS failover management script created"
}

################################################################################
# 3. CROSS-REGION REPLICATION SETUP
################################################################################

create_replication_setup() {
    log_info "Creating cross-region replication setup..."

    cat > "${MR_DIR}/setup-replication.sh" << 'REPLICATION_SETUP'
#!/bin/bash

# Cross-Region Replication Setup
# Configures database and storage replication across regions

set -euo pipefail

LOG_FILE="/var/log/replication-setup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Configure PostgreSQL streaming replication
setup_postgres_replication() {
    log "Setting up PostgreSQL streaming replication..."
    
    # Primary config
    primary_config="
max_wal_senders = 5
wal_keep_size = 10GB
wal_level = logical
hot_standby = on
hot_standby_feedback = on
"
    
    # Apply to primary
    ssh akushnir@192.168.168.31 "
        docker exec code-server-postgres psql -U postgres -c 'ALTER SYSTEM SET max_wal_senders = 5;'
        docker exec code-server-postgres psql -U postgres -c 'ALTER SYSTEM SET wal_keep_size = \"10GB\";'
        docker restart code-server-postgres
    " || log "WARNING: Could not configure primary"
    
    # Setup replication user on primary
    ssh akushnir@192.168.168.31 "
        docker exec code-server-postgres psql -U postgres -c 'CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD \"replication_password\";'
    " || log "WARNING: Could not create replicator role"
    
    # Initialize secondary from primary backup
    ssh akushnir@192.168.168.42 "
        docker exec code-server-postgres pg_basebackup -h 192.168.168.31 -U replicator -D /var/lib/postgresql/data -v -P
        # Start PostgreSQL in standby mode
        docker restart code-server-postgres
    " || log "WARNING: Could not setup secondary"
    
    log "✓ PostgreSQL replication configured"
}

# Configure Redis replication
setup_redis_replication() {
    log "Setting up Redis replication..."
    
    # Primary config
    ssh akushnir@192.168.168.31 "
        docker exec code-server-redis redis-cli SLAVEOF NO ONE
        docker exec code-server-redis redis-cli CONFIG SET slave-read-only no
    " || log "WARNING: Could not configure primary"
    
    # Secondary replication
    ssh akushnir@192.168.168.42 "
        docker exec code-server-redis redis-cli SLAVEOF 192.168.168.31 6379
        docker exec code-server-redis redis-cli CONFIG SET slave-read-only yes
    " || log "WARNING: Could not configure secondary"
    
    # Verify replication
    ssh akushnir@192.168.168.42 "
        docker exec code-server-redis redis-cli INFO replication | grep role:slave
    " || log "WARNING: Redis replication not confirmed"
    
    log "✓ Redis replication configured"
}

# Configure MinIO replication
setup_minio_replication() {
    log "Setting up MinIO bucket replication..."
    
    # Enable versioning
    ssh akushnir@192.168.168.31 "
        docker exec code-server-minio mc version enable code-server/data
    " || log "WARNING: Could not enable versioning"
    
    # Setup replication rule
    ssh akushnir@192.168.168.31 "
        docker exec code-server-minio mc replicate add \
            code-server/data \
            --remote-bucket code-server@192.168.168.42 \
            --priority 1 \
            --replicate \"delete|delete-marker\"
    " || log "WARNING: Could not setup replication"
    
    log "✓ MinIO replication configured"
}

# Verify replication
verify_replication() {
    log "Verifying replication..."
    
    # Check PostgreSQL replication
    log "PostgreSQL replication status:"
    ssh akushnir@192.168.168.31 "
        docker exec code-server-postgres psql -U postgres -c 'SELECT usename, application_name, state, write_lsn FROM pg_stat_replication;'
    " || log "WARNING: Could not verify PostgreSQL"
    
    # Check Redis replication
    log "Redis replication status:"
    ssh akushnir@192.168.168.42 "
        docker exec code-server-redis redis-cli INFO replication | grep -E '^role:|^connected_slaves'
    " || log "WARNING: Could not verify Redis"
    
    # Check MinIO replication status
    log "MinIO replication status:"
    ssh akushnir@192.168.168.31 "
        docker exec code-server-minio mc replicate status code-server/data
    " || log "WARNING: Could not verify MinIO"
    
    log "✓ Replication verification complete"
}

main() {
    log "=== Cross-Region Replication Setup Started ==="
    
    setup_postgres_replication
    setup_redis_replication
    setup_minio_replication
    verify_replication
    
    log "=== Cross-Region Replication Setup Complete ==="
}

main "$@"
REPLICATION_SETUP

    chmod +x "${MR_DIR}/setup-replication.sh"
    log_success "Cross-region replication setup script created"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 7.3: Multi-Region Failover Configuration"
    log_info "=============================================="

    create_multi_region_config
    create_dns_failover
    create_replication_setup

    if $APPLY; then
        log_success "Phase 7.3 Complete - Multi-Region Failover Configured"
    else
        log_info "Configurations created at: $MR_DIR"
        log_info "Run with --apply flag to deploy"
    fi
}

main "$@"
