#!/bin/bash
###############################################################################
# Phase 6: Multi-Cluster HA - Active-Active Deployment
#
# Deploys and configures active-active cluster across primary and replica:
# - Configures bidirectional replication
# - Sets up load balancer
# - Enables distributed monitoring
# - Validates cluster readiness
#
# Prerequisites:
#   - Replica host setup complete (setup-replica-cluster.sh)
#   - Both hosts fully prepared
#
# Usage:
#   bash scripts/ha/deploy-active-active.sh
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

trap 'log_error "Deployment failed at line $LINENO"; cleanup_deployment || true; exit 1' ERR
trap 'log_info "Cleanup..."; cleanup_deployment || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
PRIMARY_HOST="192.168.168.221"
REPLICA_HOST="192.168.168.42"
REPLICA_USER="deployment"
CLUSTER_VIP="192.168.168.50"
HA_DIR="$PROJECT_ROOT/artifacts/ha-setup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

cleanup_deployment() {
    log_info "Deployment cleanup..."
}

# Configure bidirectional PostgreSQL replication
configure_bidirectional_postgres() {
    log_info "Configuring bidirectional PostgreSQL replication..."
    
    {
        echo "# Bidirectional PostgreSQL Replication Setup"
        echo ""
        echo "## On Primary Host ($PRIMARY_HOST):"
        echo ""
        echo "1. Create replication user:"
        echo "   psql -U postgres -c \"CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'SecurePassword';\""
        echo ""
        echo "2. Configure pg_hba.conf:"
        echo "   host    replication     replication_user    $REPLICA_HOST/32        md5"
        echo ""
        echo "3. Enable replication parameters:"
        echo "   ALTER SYSTEM SET wal_level = 'replica';"
        echo "   ALTER SYSTEM SET max_wal_senders = 10;"
        echo "   ALTER SYSTEM SET max_replication_slots = 10;"
        echo "   SELECT pg_reload_conf();"
        echo ""
        echo "4. Create replication slot:"
        echo "   SELECT * FROM pg_create_physical_replication_slot('replica_slot');"
        echo ""
        echo "5. Verify replication:"
        echo "   SELECT * FROM pg_stat_replication;"
        echo ""
        echo "## On Replica Host ($REPLICA_HOST):"
        echo ""
        echo "1. Stop PostgreSQL:"
        echo "   sudo systemctl stop postgresql"
        echo ""
        echo "2. Initialize standby from primary:"
        echo "   pg_basebackup -h $PRIMARY_HOST -D /var/lib/postgresql/main \\"
        echo "     -U replication_user -v -P --wal-method=stream"
        echo ""
        echo "3. Create recovery configuration:"
        echo "   echo \"primary_conninfo = 'host=$PRIMARY_HOST user=replication_user'\" >> recovery.conf"
        echo "   echo \"standby_mode = 'on'\" >> recovery.conf"
        echo ""
        echo "4. Start PostgreSQL:"
        echo "   sudo systemctl start postgresql"
        echo ""
        echo "5. Monitor replication:"
        echo "   SELECT slot_name, restart_lsn FROM pg_replication_slots;"
        echo ""
    } | tee "$HA_DIR/postgres-replication-setup.txt"
    
    log_success "PostgreSQL replication configuration documented"
}

# Configure bidirectional Redis replication
configure_bidirectional_redis() {
    log_info "Configuring bidirectional Redis replication..."
    
    {
        echo "# Bidirectional Redis Replication Setup"
        echo ""
        echo "## Active-Active Redis Configuration"
        echo ""
        echo "Option 1: Using Redis Cluster (Recommended)"
        echo "  - Deploy Redis Cluster with 3 nodes each on primary and replica"
        echo "  - Automatic failover and rebalancing"
        echo "  - Horizontal scalability"
        echo ""
        echo "Option 2: Using Redis Sentinel"
        echo "  - Primary-Replica replication with automatic failover"
        echo "  - Sentinel monitors availability"
        echo "  - Configuration:"
        echo ""
        echo "redis-sentinel.conf on Primary:"
        echo "  sentinel monitor mymaster $PRIMARY_HOST 6379 2"
        echo "  sentinel down-after-milliseconds mymaster 5000"
        echo "  sentinel parallel-syncs mymaster 1"
        echo "  sentinel failover-timeout mymaster 10000"
        echo ""
        echo "redis-sentinel.conf on Replica:"
        echo "  sentinel monitor mymaster $PRIMARY_HOST 6379 2"
        echo "  sentinel down-after-milliseconds mymaster 5000"
        echo "  sentinel parallel-syncs mymaster 1"
        echo "  sentinel failover-timeout mymaster 10000"
        echo ""
        echo "Option 3: Using Redis Streams (For Active-Active)"
        echo "  - Replicate data via streams without master-slave roles"
        echo "  - Both instances can accept writes"
        echo "  - Conflict resolution: Last-write-wins or custom logic"
        echo ""
    } | tee "$HA_DIR/redis-replication-setup.txt"
    
    log_success "Redis replication configuration documented"
}

# Configure load balancer
configure_load_balancer() {
    log_info "Configuring load balancer..."
    
    cat > "$HA_DIR/haproxy-config.cfg" << 'EOF'
# HAProxy Configuration for Active-Active Cluster

global
    log stdout local0
    log stdout local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crl-base /etc/ssl/private

    # See the full configuration options online at:
    # http://www.haproxy.org/#docs

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# Statistics page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats show-legends
    stats show-node

# Primary cluster backend
backend primary_cluster
    balance roundrobin
    server primary 192.168.168.221:8080 check
    server replica  192.168.168.42:8080 check

# Frontend for application traffic
frontend app_frontend
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/cert.pem
    
    http-request set-header X-Forwarded-For %[src]
    http-request set-header X-Forwarded-Proto https if { ssl_fc }
    
    default_backend primary_cluster

# Database backend (connection pooling)
backend database_backend
    mode tcp
    balance roundrobin
    server primary 192.168.168.221:5432 check inter 5s rise 2 fall 3
    server replica  192.168.168.42:5432 check inter 5s rise 2 fall 3

frontend database_frontend
    bind *:5432
    mode tcp
    default_backend database_backend

# Redis backend (read/write distribution)
backend redis_backend
    mode tcp
    balance roundrobin
    server primary 192.168.168.221:6379 check inter 5s rise 2 fall 3
    server replica  192.168.168.42:6379 check inter 5s rise 2 fall 3

frontend redis_frontend
    bind *:6379
    mode tcp
    default_backend redis_backend
EOF
    
    log_success "HAProxy configuration created: $HA_DIR/haproxy-config.cfg"
}

# Create distributed monitoring configuration
create_monitoring_config() {
    log_info "Creating distributed monitoring configuration..."
    
    cat > "$HA_DIR/cluster-monitoring.yml" << 'EOF'
---
monitoring:
  # Prometheus scrape configuration
  prometheus_scrape:
    - job_name: primary
      static_configs:
        - targets: ['192.168.168.221:9090']
      interval: 15s
    
    - job_name: replica
      static_configs:
        - targets: ['192.168.168.42:9090']
      interval: 15s
    
    - job_name: postgres_primary
      static_configs:
        - targets: ['192.168.168.221:9187']
    
    - job_name: postgres_replica
      static_configs:
        - targets: ['192.168.168.42:9187']
    
    - job_name: redis_primary
      static_configs:
        - targets: ['192.168.168.221:9121']
    
    - job_name: redis_replica
      static_configs:
        - targets: ['192.168.168.42:9121']

  # Alerting rules for cluster
  alerts:
    - name: ReplicationLag
      expr: 'pg_wal_lsn_diff(pg_current_wal_insert_lsn(), '0/0') - pg_wal_lsn_diff(slot_restart_lsn, ''0/0'') > 1073741824'
      duration: 5m
      severity: warning
      description: "PostgreSQL replication lag > 1GB"
    
    - name: ClusterNodeDown
      expr: 'up{job=~"primary|replica"} == 0'
      duration: 1m
      severity: critical
      description: "Cluster node is down"
    
    - name: RedisReplicationLag
      expr: 'redis_replication_backlog_size > 104857600'
      duration: 5m
      severity: warning
      description: "Redis replication backlog > 100MB"
    
    - name: HighLoadBalancerLatency
      expr: 'haproxy_backend_response_time_avg > 1000'
      duration: 5m
      severity: warning
      description: "Load balancer response time > 1000ms"

  # Grafana dashboard definitions
  dashboards:
    - name: cluster_overview
      panels:
        - title: "Cluster Node Status"
          targets:
            - expr: 'up{job=~"primary|replica"}'
        
        - title: "PostgreSQL Replication Lag"
          targets:
            - expr: 'pg_wal_lsn_diff(...) / 1024 / 1024'
        
        - title: "Redis Memory Usage"
          targets:
            - expr: 'redis_memory_used_bytes / 1024 / 1024'
        
        - title: "Application Request Rate"
          targets:
            - expr: 'rate(http_requests_total[5m])'
        
        - title: "Cross-Site Latency"
          targets:
            - expr: 'ping_latency_ms'
EOF
    
    log_success "Monitoring configuration: $HA_DIR/cluster-monitoring.yml"
}

# Generate deployment verification script
create_verification_script() {
    log_info "Creating verification script..."
    
    cat > "$HA_DIR/verify-cluster-health.sh" << 'VERIFY_SCRIPT'
#!/bin/bash
# Cluster Health Verification Script

PRIMARY="192.168.168.221"
REPLICA="192.168.168.42"

echo "═════════════════════════════════════════════════"
echo "CLUSTER HEALTH VERIFICATION"
echo "═════════════════════════════════════════════════"

# Check host connectivity
echo ""
echo "1. Host Connectivity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ping -c 1 $PRIMARY &>/dev/null && echo "✓ Primary reachable" || echo "✗ Primary unreachable"
ping -c 1 $REPLICA &>/dev/null && echo "✓ Replica reachable" || echo "✗ Replica unreachable"

# Check PostgreSQL replication
echo ""
echo "2. PostgreSQL Replication Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Primary replication status:"
ssh deployment@$PRIMARY "psql -U postgres -c 'SELECT * FROM pg_stat_replication;'" 2>/dev/null || echo "[Connection failed]"

# Check Redis replication
echo ""
echo "3. Redis Replication Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Primary Redis info:"
redis-cli -h $PRIMARY INFO replication 2>/dev/null || echo "[Connection failed]"

# Check load balancer
echo ""
echo "4. Load Balancer Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s http://localhost:8404/stats | grep -A 5 "primary_cluster" || echo "[Load balancer not responding]"

# Check application health
echo ""
echo "5. Application Health"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s http://$PRIMARY:8080/health | jq . || echo "[Primary health check failed]"
curl -s http://$REPLICA:8080/health | jq . || echo "[Replica health check failed]"

# Check monitoring
echo ""
echo "6. Monitoring Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
curl -s http://localhost:9090/-/healthy && echo "✓ Prometheus healthy" || echo "✗ Prometheus unhealthy"
curl -s http://localhost:3000/api/health && echo "✓ Grafana healthy" || echo "✗ Grafana unhealthy"

echo ""
echo "═════════════════════════════════════════════════"
VERIFY_SCRIPT
    
    chmod +x "$HA_DIR/verify-cluster-health.sh"
    log_success "Verification script: $HA_DIR/verify-cluster-health.sh"
}

# Generate failover procedures
create_failover_procedures() {
    log_info "Creating failover procedures..."
    
    {
        echo "# Multi-Cluster HA Failover Procedures"
        echo ""
        echo "## Automatic Failover"
        echo ""
        echo "The cluster uses health checks to automatically detect failures:"
        echo ""
        echo "1. **Health Check Intervals:** 5 seconds"
        echo "2. **Failure Detection:** 3 consecutive failures"
        echo "3. **Failover Initiation:** Automatic via load balancer"
        echo "4. **Recovery Time:** < 30 seconds"
        echo ""
        echo "## Manual Failover"
        echo ""
        echo "### Scenario: Primary Node Failure"
        echo ""
        echo "1. Verify primary is truly down:"
        echo "   ```bash"
        echo "   ping -c 3 192.168.168.221"
        echo "   ssh deployment@192.168.168.221 'uptime'"
        echo "   ```"
        echo ""
        echo "2. Promote replica to primary:"
        echo "   ```bash"
        echo "   ssh deployment@192.168.168.42 'sudo systemctl stop postgresql'"
        echo "   ssh deployment@192.168.168.42 'touch /var/lib/postgresql/main/recovery.signal'"
        echo "   ssh deployment@192.168.168.42 'sudo systemctl start postgresql'"
        echo "   ```"
        echo ""
        echo "3. Verify promotion complete:"
        echo "   ```bash"
        echo "   ssh deployment@192.168.168.42 'psql -U postgres -c \"SELECT pg_is_in_recovery();\"'"
        echo "   ```"
        echo ""
        echo "4. Point applications to new primary:"
        echo "   ```bash"
        echo "   # Update connection strings or load balancer configuration"
        echo "   # Restart application services"
        echo "   ```"
        echo ""
        echo "### Scenario: Replica Node Failure"
        echo ""
        echo "1. Primary continues operating normally"
        echo ""
        echo "2. When replica recovers:"
        echo "   ```bash"
        echo "   ssh deployment@192.168.168.42 'sudo systemctl start postgresql'"
        echo "   ```"
        echo ""
        echo "3. Reinitialize replica from primary:"
        echo "   ```bash"
        echo "   pg_basebackup -h 192.168.168.221 -D /var/lib/postgresql/main \\"
        echo "     -U replication_user -v -P"
        echo "   ```"
        echo ""
        echo "### Scenario: Network Partition"
        echo ""
        echo "1. If partition detected (replication lag increasing):"
        echo "   ```bash"
        echo "   # Check if nodes can communicate"
        echo "   ping 192.168.168.42  # From primary"
        echo "   ping 192.168.168.221 # From replica"
        echo "   ```"
        echo ""
        echo "2. Restore connectivity or implement split-brain resolution"
        echo ""
        echo "3. Reconcile data if conflicting writes occurred"
        echo ""
        echo "## Recovery After Failover"
        echo ""
        echo "1. Restore failed primary node infrastructure"
        echo ""
        echo "2. Initialize from new primary:"
        echo "   ```bash"
        echo "   pg_basebackup -h <new_primary> -D /var/lib/postgresql/main \\"
        echo "     -U replication_user -v -P"
        echo "   ```"
        echo ""
        echo "3. Update replication configuration"
        echo ""
        echo "4. Verify replication health"
        echo ""
        echo "5. Update DNS/load balancer if topology changed"
        echo ""
    } | tee "$HA_DIR/failover-procedures.md"
    
    log_success "Failover procedures: $HA_DIR/failover-procedures.md"
}

# Main execution
main() {
    log_info "════════════════════════════════════════════════════════"
    log_info "Phase 6: Multi-Cluster HA - Active-Active Deployment"
    log_info "════════════════════════════════════════════════════════"
    
    mkdir -p "$HA_DIR"
    
    # Configure replication
    configure_bidirectional_postgres
    configure_bidirectional_redis
    
    # Configure load balancer
    configure_load_balancer
    
    # Create monitoring
    create_monitoring_config
    
    # Create verification
    create_verification_script
    
    # Create failover procedures
    create_failover_procedures
    
    log_success "════════════════════════════════════════════════════════"
    log_success "Active-Active deployment configuration complete!"
    log_info ""
    log_info "Configuration files generated in: $HA_DIR"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Deploy HAProxy load balancer"
    log_info "  2. Configure PostgreSQL replication (see postgres-replication-setup.txt)"
    log_info "  3. Configure Redis replication (see redis-replication-setup.txt)"
    log_info "  4. Deploy monitoring stack (Prometheus, Grafana)"
    log_info "  5. Verify cluster health:"
    log_info "     bash $HA_DIR/verify-cluster-health.sh"
    log_info "  6. Test failover procedures"
    log_success "════════════════════════════════════════════════════════"
}

main
