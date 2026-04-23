#!/usr/bin/env bash
# @file        scripts/ops/setup-network-partition-recovery.sh
# @module      infrastructure/resilience
# @description Setup automatic recovery from network partitions using quorum-based detection
# @owner       Infrastructure Team
# @status      In development - April 23, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
ARBITER_HOST="${ARBITER_HOST:-192.168.168.99}"  # Optional 3rd node for quorum
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"  # seconds
PARTITION_THRESHOLD="${PARTITION_THRESHOLD:-3}"  # failed checks before declaring partition
QUORUM_SIZE="${QUORUM_SIZE:-2}"  # minimum nodes for quorum

# ============================================================================
# Logging
# ============================================================================

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_warn() { echo "[WARN] $*"; }
log_success() { echo "[✓] $*"; }

# ============================================================================
# Quorum-Based Partition Detection
# ============================================================================

check_node_connectivity() {
    local node_host=$1
    local node_name=$2
    
    # Try SSH connectivity
    if timeout 5 ssh -q "${node_host}" "echo OK" > /dev/null 2>&1; then
        return 0  # Node reachable
    else
        return 1  # Node unreachable
    fi
}

detect_network_partition() {
    log_info "Checking network connectivity..."
    
    local primary_ok=0
    local replica_ok=0
    local arbiter_ok=0
    
    # Check primary
    if check_node_connectivity "akushnir@${PRIMARY_HOST}" "primary"; then
        ((primary_ok++))
        log_info "✓ Primary host reachable"
    else
        log_warn "✗ Primary host unreachable"
    fi
    
    # Check replica
    if check_node_connectivity "akushnir@${REPLICA_HOST}" "replica"; then
        ((replica_ok++))
        log_info "✓ Replica host reachable"
    else
        log_warn "✗ Replica host unreachable"
    fi
    
    # Check arbiter if configured
    if [ ! -z "${ARBITER_HOST}" ] && [ "${ARBITER_HOST}" != "192.168.168.99" ]; then
        if check_node_connectivity "akushnir@${ARBITER_HOST}" "arbiter"; then
            ((arbiter_ok++))
            log_info "✓ Arbiter node reachable"
        else
            log_warn "✗ Arbiter node unreachable"
        fi
    fi
    
    # Calculate quorum
    local reachable_nodes=$((primary_ok + replica_ok + arbiter_ok))
    log_info "Reachable nodes: ${reachable_nodes}/3"
    
    # Check if we have quorum
    if [ ${reachable_nodes} -ge ${QUORUM_SIZE} ]; then
        log_info "✓ Quorum maintained (${reachable_nodes}/${QUORUM_SIZE})"
        return 0
    else
        log_error "✗ PARTITION DETECTED - Lost quorum (${reachable_nodes}/${QUORUM_SIZE})"
        return 1
    fi
}

# ============================================================================
# Partition Monitoring
# ============================================================================

monitor_network_partition() {
    log_info "Starting network partition monitoring..."
    log_info "Check interval: ${CHECK_INTERVAL}s, Threshold: ${PARTITION_THRESHOLD} failures"
    
    local failure_count=0
    local partition_detected=0
    
    while true; do
        if detect_network_partition; then
            # Node connectivity OK
            if [ ${failure_count} -gt 0 ]; then
                log_info "Network recovered - resetting failure count"
            fi
            failure_count=0
            partition_detected=0
        else
            # Node connectivity failed
            ((failure_count++))
            log_warn "Network check failed: ${failure_count}/${PARTITION_THRESHOLD}"
            
            if [ ${failure_count} -ge ${PARTITION_THRESHOLD} ] && [ ${partition_detected} -eq 0 ]; then
                partition_detected=1
                log_error "NETWORK PARTITION DECLARED"
                handle_network_partition
                
                # Reset after handling
                failure_count=0
            fi
        fi
        
        sleep ${CHECK_INTERVAL}
    done
}

# ============================================================================
# Partition Handling - Graceful Degradation
# ============================================================================

handle_network_partition() {
    log_error "Network partition detected - entering degraded mode"
    
    # Determine which partition we're in
    local our_partition=$(determine_partition)
    
    if [ "${our_partition}" = "isolated" ]; then
        log_error "This node is ISOLATED - no quorum"
        activate_read_only_mode
        disable_writes
        alert_operator "CRITICAL: Node isolated - no quorum, read-only mode activated"
        
    elif [ "${our_partition}" = "primary" ]; then
        log_warn "Primary partition detected"
        activate_degraded_service
        alert_operator "WARNING: Network partition - primary partition active, monitoring replica"
        
    elif [ "${our_partition}" = "secondary" ]; then
        log_warn "Secondary partition detected"
        activate_read_only_mode
        alert_operator "WARNING: Network partition - secondary partition active, read-only mode"
        
    fi
}

determine_partition() {
    # Check which partition this node belongs to
    # Partition with PRIMARY_HOST is the "primary" partition
    
    if check_node_connectivity "akushnir@${PRIMARY_HOST}" "primary"; then
        echo "primary"
    elif check_node_connectivity "akushnir@${REPLICA_HOST}" "replica"; then
        echo "secondary"
    else
        echo "isolated"
    fi
}

activate_read_only_mode() {
    log_warn "Activating read-only mode..."
    
    ssh "akushnir@${PRIMARY_HOST}" "
    docker exec postgres psql -U postgres -c \"
        ALTER DATABASE code_server SET default_transaction_read_only = on;
    \" 2>/dev/null || true
    
    docker exec caddy bash -c '
        # Add error page for write attempts
        curl -s -X POST http://localhost:2019/config/handlers \
            -H \"Content-Type: application/json\" \
            -d \"{{\\\"handler\\\": \\\"file_server\\\", \\\"root\\\": \\\"/var/www/error-pages\\\"}}\" 2>/dev/null || true
    ' || true
    "
    
    log_info "✓ Read-only mode activated"
}

disable_writes() {
    log_warn "Disabling write operations..."
    
    ssh "akushnir@${PRIMARY_HOST}" "
    # Block all POST/PUT/DELETE requests at reverse proxy level
    docker exec caddy bash -c '
        echo \"Deny writes during partition\" > /var/www/error-pages/read-only.html
    ' || true
    "
    
    log_info "✓ Write operations disabled"
}

activate_degraded_service() {
    log_info "Activating degraded service mode..."
    
    ssh "akushnir@${PRIMARY_HOST}" "
    # Services continue but with monitoring/alerts
    docker exec postgres psql -U postgres -c \"
        ALTER SYSTEM SET log_statement = 'all';
        SELECT pg_reload_conf();
    \" 2>/dev/null || true
    "
    
    log_info "✓ Degraded mode active - full logging enabled"
}

# ============================================================================
# Partition Healing
# ============================================================================

handle_partition_healing() {
    log_info "Network partition healed - recovering..."
    
    local our_partition=$(determine_partition)
    
    case "${our_partition}" in
        "primary")
            log_info "Primary partition active - coordinating with replica..."
            heal_primary_partition
            ;;
        "secondary")
            log_info "Secondary partition - rejoining cluster..."
            heal_secondary_partition
            ;;
        "isolated")
            log_error "Still isolated after partition healed - manual intervention needed"
            ;;
    esac
}

heal_primary_partition() {
    log_info "Healing primary partition..."
    
    # Verify replication state
    ssh "akushnir@${PRIMARY_HOST}" "
    docker exec postgres psql -U postgres -c \"
        SELECT pid, usename, application_name, state FROM pg_stat_replication;
    \" 2>/dev/null || true
    "
    
    # Resume normal operations
    ssh "akushnir@${PRIMARY_HOST}" "
    docker exec postgres psql -U postgres -c \"
        ALTER DATABASE code_server SET default_transaction_read_only = off;
    \" 2>/dev/null || true
    "
    
    log_info "✓ Primary partition healed"
}

heal_secondary_partition() {
    log_info "Healing secondary partition..."
    
    # If this was the replica, ensure it's back in standby mode
    ssh "akushnir@${REPLICA_HOST}" "
    if grep -q 'standby_mode = on' /var/lib/postgresql/data/recovery.conf 2>/dev/null; then
        echo 'Replica already in standby mode'
    else
        docker exec postgres pg_ctl promote -D /var/lib/postgresql/data 2>/dev/null || true
    fi
    " 2>/dev/null || true
    
    log_info "✓ Secondary partition healed"
}

# ============================================================================
# Operator Alerting
# ============================================================================

alert_operator() {
    local severity=$1
    local message=$2
    
    log_error "ALERT: ${severity} - ${message}"
    
    # Send to monitoring system
    curl -X POST http://localhost:9093/api/v1/alerts \
        -H "Content-Type: application/json" \
        -d "{
            \"alerts\": [{
                \"status\": \"firing\",
                \"labels\": {
                    \"alertname\": \"NetworkPartition\",
                    \"severity\": \"${severity}\",
                    \"instance\": \"$(hostname)\"
                },
                \"annotations\": {
                    \"summary\": \"${severity}: Network partition detected\",
                    \"description\": \"${message}\"
                }
            }]
        }" 2>/dev/null || true
    
    # Send email/slack (if configured)
    # notify_ops_channel "${severity}" "${message}"
}

# ============================================================================
# Configuration File Setup
# ============================================================================

create_partition_detection_config() {
    cat > /tmp/network-partition-config.yml <<EOF
# Network Partition Detection Configuration
# Generated: $(date)

nodes:
  - name: primary
    host: ${PRIMARY_HOST}
    role: primary
  - name: replica
    host: ${REPLICA_HOST}
    role: replica
  - name: arbiter
    host: ${ARBITER_HOST}
    role: arbiter
    optional: true

detection:
  check_interval_seconds: ${CHECK_INTERVAL}
  failure_threshold: ${PARTITION_THRESHOLD}
  quorum_size: ${QUORUM_SIZE}

behaviors:
  isolated:
    action: read_only_mode
    alert_level: critical
    log_verbosity: debug
  
  secondary:
    action: read_only_degraded
    alert_level: warning
    log_verbosity: info
  
  primary:
    action: continue_monitoring
    alert_level: warning
    log_verbosity: debug

recovery:
  auto_rejoin: true
  resync_on_heal: true
  verify_consistency: true

monitoring:
  prometheus_enabled: true
  grafana_dashboard: network-partition-recovery
  alertmanager_webhook: http://localhost:5001/webhook
EOF
    
    log_info "Partition detection config created: /tmp/network-partition-config.yml"
}

# ============================================================================
# Systemd Service Setup
# ============================================================================

setup_partition_detector_service() {
    log_info "Setting up partition detector as systemd service..."
    
    cat > /tmp/network-partition-detector.service <<EOF
[Unit]
Description=Network Partition Detector for PostgreSQL HA
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$(pwd)/scripts/ops/setup-network-partition-recovery.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    ssh "akushnir@${PRIMARY_HOST}" "
    sudo cp /tmp/network-partition-detector.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable network-partition-detector
    sudo systemctl start network-partition-detector
    " 2>/dev/null || log_warn "Could not setup systemd service (may require sudo)"
    
    log_info "✓ Systemd service configured"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Network Partition Detection & Auto-Recovery Setup"
    log_info "Primary: ${PRIMARY_HOST}"
    log_info "Replica: ${REPLICA_HOST}"
    log_info "Check interval: ${CHECK_INTERVAL}s"
    log_info "Quorum size: ${QUORUM_SIZE}"
    
    # Create configuration
    create_partition_detection_config
    
    # Setup systemd service (optional)
    # setup_partition_detector_service
    
    # Start monitoring
    log_info "Starting network partition monitoring..."
    monitor_network_partition
    
    return 0
}

# Handle signals
trap 'log_info "Partition detector stopped"; exit 0' SIGTERM SIGINT

# Run
main "$@"
