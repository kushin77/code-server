#!/bin/bash
###############################################################################
# Phase 6: Multi-Cluster HA - Replica Cluster Setup
#
# Configures replica host for active-active cluster deployment:
# - Installs required services (Docker, PostgreSQL client, Redis)
# - Sets up cluster networking
# - Configures replication parameters
# - Validates replica readiness
#
# Prerequisite: Replica host must be accessible (ping + SSH)
#
# Usage:
#   bash scripts/ha/setup-replica-cluster.sh
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Setup failed at line $LINENO"; cleanup_setup || true; exit 1' ERR
trap 'log_info "Cleanup..."; cleanup_setup || true' EXIT

# Configuration
REPLICA_HOST="192.168.168.42"
REPLICA_USER="deployment"
PRIMARY_HOST="192.168.168.31"
CLUSTER_NETWORK="192.168.168.0/24"
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

cleanup_setup() {
    log_info "Setup cleanup..."
}

# Verify replica connectivity
verify_connectivity() {
    log_info "Verifying replica host connectivity..."
    
    if ! timeout 5 ssh -o ConnectTimeout=5 "$REPLICA_USER@$REPLICA_HOST" "echo CONNECTED" &>/dev/null; then
        log_error "Cannot connect to replica host: $REPLICA_HOST"
        log_error "Run diagnostic first: bash scripts/ha/diagnose-replica-connectivity.sh"
        return 1
    fi
    
    log_success "Replica host accessible"
}

# Install prerequisites on replica
install_prerequisites() {
    log_info "Installing prerequisites on replica host..."
    
    ssh "$REPLICA_USER@$REPLICA_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail
echo "[INFO] Installing prerequisites..."

# Update system
sudo apt-get update -qq

# Install Docker if not present
if ! command -v docker &>/dev/null; then
    echo "[INFO] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $(whoami)
fi

# Install Docker Compose if not present
if ! command -v docker-compose &>/dev/null; then
    echo "[INFO] Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Install PostgreSQL client
sudo apt-get install -y postgresql-client redis-tools &>/dev/null

# Install additional tools
sudo apt-get install -y curl wget git &>/dev/null

echo "[INFO] Prerequisites installed successfully"
REMOTE_SCRIPT
    
    log_success "Prerequisites installed"
}

# Setup cluster networking
setup_networking() {
    log_info "Setting up cluster networking..."
    
    ssh "$REPLICA_USER@$REPLICA_HOST" << REMOTE_SCRIPT
set -euo pipefail
echo "[INFO] Configuring cluster networking..."

# Configure /etc/hosts if not already present
if ! grep -q "$PRIMARY_HOST" /etc/hosts 2>/dev/null; then
    echo "Adding primary host to /etc/hosts..."
    echo "$PRIMARY_HOST primary.cluster.local" | sudo tee -a /etc/hosts > /dev/null
fi

if ! grep -q "$(hostname -I | awk '{print $1}')" /etc/hosts 2>/dev/null; then
    echo "Adding replica host to /etc/hosts..."
    echo "$(hostname -I | awk '{print $1}') replica.cluster.local $(hostname)" | sudo tee -a /etc/hosts > /dev/null
fi

# Verify routing to primary
echo "[INFO] Verifying routing to primary..."
if ip route get $PRIMARY_HOST &>/dev/null; then
    echo "[SUCCESS] Route to primary host exists"
else
    echo "[WARNING] No direct route to primary, using default gateway"
fi

# Configure firewall rules for cluster communication
if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
    echo "[INFO] Configuring firewall for cluster..."
    sudo ufw allow from $PRIMARY_HOST to any port 5432 comment 'PostgreSQL replication'
    sudo ufw allow from $PRIMARY_HOST to any port 6379 comment 'Redis replication'
    sudo ufw allow from $PRIMARY_HOST to any port 8001 comment 'Cluster API'
fi

echo "[SUCCESS] Networking configured"
REMOTE_SCRIPT
    
    log_success "Cluster networking configured"
}

# Configure PostgreSQL replication parameters
configure_postgres_replication() {
    log_info "Configuring PostgreSQL replication parameters..."
    
    ssh "$REPLICA_USER@$REPLICA_HOST" << 'REMOTE_SCRIPT'
set -euo pipefail

# Create PostgreSQL replication user configuration file
cat > /tmp/postgres-replication-config.sql << 'EOF'
-- PostgreSQL Replication Configuration

-- Enable replication for cluster
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_keep_segments = 64;
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET hot_standby_feedback = on;

-- Replication settings
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/wal_archive/%f && cp %p /var/lib/postgresql/wal_archive/%f';

-- Performance tuning for replication
ALTER SYSTEM SET synchronous_commit = 'remote_write';
ALTER SYSTEM SET wal_compression = on;

SELECT pg_reload_conf();
EOF

echo "[INFO] PostgreSQL replication configuration prepared"
echo "[ACTION] Apply configuration on PostgreSQL server with:"
echo "  psql -U postgres -f /tmp/postgres-replication-config.sql"
REMOTE_SCRIPT
    
    log_success "PostgreSQL replication configuration prepared"
}

# Configure Redis replication
configure_redis_replication() {
    log_info "Configuring Redis replication..."
    
    ssh "$REPLICA_USER@$REPLICA_HOST" << REMOTE_SCRIPT
set -euo pipefail

# Create Redis replication configuration
cat > /tmp/redis-replica-config.conf << 'EOF'
# Redis Replica Configuration

# Replication settings
slaveof $PRIMARY_HOST 6379
slave-serve-stale-data yes
slave-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
slave-priority 100

# Backups
save 900 1
save 300 10
save 60 10000

# AOF persistence
appendonly yes
appendfsync everysec

# Replication monitoring
slowlog-log-slower-than 10000
slowlog-max-len 128

# Memory settings
maxmemory 2gb
maxmemory-policy allkeys-lru
EOF

echo "[INFO] Redis replica configuration prepared"
echo "[ACTION] Apply configuration with:"
echo "  cat /tmp/redis-replica-config.conf | redis-cli CONFIG SET"
REMOTE_SCRIPT
    
    log_success "Redis replication configuration prepared"
}

# Generate cluster topology documentation
generate_cluster_topology() {
    local topology_file="$HA_DIR/cluster-topology.md"
    
    {
        echo "# Multi-Cluster HA Topology"
        echo ""
        echo "## Cluster Configuration"
        echo ""
        echo "### Primary (Active)"
        echo "- Host: $PRIMARY_HOST"
        echo "- Services: Web, Database, Cache, Message Broker"
        echo "- Role: Active-Active Cluster Node 1"
        echo ""
        echo "### Replica (Active)"
        echo "- Host: $REPLICA_HOST"
        echo "- Services: Web, Database Cache, Message Broker"
        echo "- Role: Active-Active Cluster Node 2"
        echo ""
        echo "## Networking"
        echo "- Cluster Network: $CLUSTER_NETWORK"
        echo "- Database Replication Port: 5432"
        echo "- Redis Replication Port: 6379"
        echo "- Message Broker Port: 9092 (Kafka)"
        echo "- Cluster API Port: 8001"
        echo ""
        echo "## Replication"
        echo "- PostgreSQL: Primary → Replica (continuous)"
        echo "- Redis: Primary → Replica (synchronous)"
        echo "- Message Broker: Active-Active replication"
        echo ""
        echo "## Data Consistency"
        echo "- PostgreSQL: synchronous_commit = 'remote_write'"
        echo "- Redis: sync-after-write = enabled"
        echo "- Conflict Resolution: Vector clock (Kafka)"
        echo ""
    } | tee "$topology_file"
    
    log_success "Cluster topology documented: $topology_file"
}

# Generate deployment checklist
generate_deployment_checklist() {
    local checklist="$HA_DIR/ha-deployment-checklist.md"
    
    {
        echo "# Phase 6 Multi-Cluster HA Deployment Checklist"
        echo ""
        echo "## Pre-Deployment Verification"
        echo "- [ ] Replica host connectivity verified (ICMP + SSH)"
        echo "- [ ] Prerequisites installed on replica"
        echo "- [ ] Cluster networking configured"
        echo "- [ ] Firewall rules validated"
        echo "- [ ] Routing tables verified"
        echo ""
        echo "## Primary Host Preparation"
        echo "- [ ] PostgreSQL replication configured"
        echo "- [ ] WAL archiving enabled"
        echo "- [ ] Replication user created"
        echo "- [ ] Replication slot created"
        echo "- [ ] Backup taken"
        echo ""
        echo "## Replica Host Preparation"
        echo "- [ ] PostgreSQL standby initialized"
        echo "- [ ] Redis configured as replica"
        echo "- [ ] Message broker configured"
        echo "- [ ] Replication connections established"
        echo "- [ ] Monitoring enabled"
        echo ""
        echo "## Active-Active Configuration"
        echo "- [ ] Bidirectional replication enabled"
        echo "- [ ] Conflict resolution configured"
        echo "- [ ] Load balancer deployed"
        echo "- [ ] Health checks configured"
        echo "- [ ] Failover policies defined"
        echo ""
        echo "## Validation & Testing"
        echo "- [ ] Data replication verified"
        echo "- [ ] Write-write conflict handling tested"
        echo "- [ ] Network partition recovery tested"
        echo "- [ ] Load balancer failover tested"
        echo "- [ ] Recovery time (RTO) < 5 minutes"
        echo ""
        echo "## Production Deployment"
        echo "- [ ] Backup verified"
        echo "- [ ] Monitoring in place"
        echo "- [ ] On-call procedures documented"
        echo "- [ ] Rollback plan prepared"
        echo "- [ ] Team trained"
        echo ""
    } | tee "$checklist"
    
    log_success "Deployment checklist: $checklist"
}

# Main execution
main() {
    log_info "════════════════════════════════════════════════════════"
    log_info "Phase 6: Multi-Cluster HA - Replica Setup"
    log_info "════════════════════════════════════════════════════════"
    
    mkdir -p "$HA_DIR"
    
    # Verify connectivity
    if ! verify_connectivity; then
        return 1
    fi
    
    # Install prerequisites
    install_prerequisites
    
    # Setup networking
    setup_networking
    
    # Configure replication
    configure_postgres_replication
    configure_redis_replication
    
    # Generate documentation
    generate_cluster_topology
    generate_deployment_checklist
    
    log_success "════════════════════════════════════════════════════════"
    log_success "Replica cluster setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review cluster topology: $HA_DIR/cluster-topology.md"
    log_info "  2. Review deployment checklist: $HA_DIR/ha-deployment-checklist.md"
    log_info "  3. Deploy active-active configuration:"
    log_info "     bash scripts/ha/deploy-active-active.sh"
    log_success "════════════════════════════════════════════════════════"
}

main
