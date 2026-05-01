#!/bin/bash
# Deploy production-grade identical docker-compose to both cluster nodes
# This ensures both PRIMARY and REPLICA have the SAME services in the SAME configuration

set -e

# Error handling
trap 'echo "❌ Script failed at line $LINENO"; exit 1' ERR
trap 'echo "🧹 Cleanup completed"; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
REMOTE_USER="akushnir"
REMOTE_DIR="~/code-server-enterprise-ops"

echo "🚀 PRODUCTION REPLICA DEPLOYMENT"
echo "=================================="
echo ""

# Function to deploy to a node
deploy_to_node() {
    local host=$1
    local role=$2
    
    echo "📍 Deploying to $role ($host)..."
    
    # Copy docker-compose
    echo "  • Copying docker-compose.yml..."
    scp -o ConnectTimeout=10 "$SCRIPT_DIR/docker-compose.production-replica.yml" \
        "$REMOTE_USER@$host:$REMOTE_DIR/docker-compose.yml"
    
    # Copy all config files
    echo "  • Syncing config/ files..."
    rsync -av -e ssh --exclude='*.bak' "$SCRIPT_DIR/config/" \
        "$REMOTE_USER@$host:$REMOTE_DIR/config/"
    
    # Copy scripts
    echo "  • Syncing scripts/ files..."
    rsync -av -e ssh "$SCRIPT_DIR/scripts/" \
        "$REMOTE_USER@$host:$REMOTE_DIR/scripts/"
    
    # Copy certificates (if they exist)
    if [ -d "$SCRIPT_DIR/certs" ]; then
        echo "  • Syncing certs/"...
        rsync -av -e ssh "$SCRIPT_DIR/certs/" \
            "$REMOTE_USER@$host:$REMOTE_DIR/certs/"
    fi
    
    echo "  • Pulling images and starting services..."
    ssh "$REMOTE_USER@$host" "cd $REMOTE_DIR && docker-compose up -d"
    
    echo "  ✅ $role deployment complete"
    echo ""
}

# Deploy to both nodes
deploy_to_node "$PRIMARY_HOST" "PRIMARY"
deploy_to_node "$REPLICA_HOST" "REPLICA"

echo ""
echo "🔍 VERIFICATION"
echo "==============="
echo ""

echo "PRIMARY Node Services:"
ssh "$REMOTE_USER@$PRIMARY_HOST" "docker ps --format 'table {{.Names}}\t{{.Status}}' | head -10"

echo ""
echo "REPLICA Node Services:"
ssh "$REMOTE_USER@$REPLICA_HOST" "docker ps --format 'table {{.Names}}\t{{.Status}}' | head -10"

echo ""
echo "✅ PRODUCTION REPLICA DEPLOYMENT COMPLETE"
echo ""
echo "Next Steps:"
echo "1. Verify services are healthy: docker-compose ps"
echo "2. Check logs: docker-compose logs postgres"
echo "3. Verify replication: psql -h 192.168.168.31 -U postgres -d app_db -c 'SELECT * FROM pg_stat_replication;'"
echo "4. Monitor dashboards: http://192.168.168.31:3000 (Grafana)"
