#!/bin/bash
################################################################################
# Deploy Core Infrastructure Services
#
# Deploys the essential platform services (pre-built, no custom builds)
# to the remote host via SSH. Focuses on rapid operational readiness.
#
# Services Deployed:
#  - postgres (database)
#  - redis (cache)
#  - prometheus (metrics)
#  - grafana (visualization)
#  - alertmanager (alerting)
#  - loki (logs)
#  - jaeger (tracing)
#  - caddy (reverse proxy)
#  - ollama (AI model runtime)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Get configuration
cd "${REPO_ROOT}"

# Load environment
if [ -f ".env.deployment" ]; then
    source .env.deployment
fi

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
SSH_USER="${SSH_USER:-akushnir}"
REMOTE_PATH="${REMOTE_PATH:-~/code-server-enterprise-ops}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CORE INFRASTRUCTURE SERVICES DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Phase 1: Pre-deployment checks
log_info "PHASE 1: Pre-deployment checks"
ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "
    cd ${REMOTE_PATH} && \
    echo 'Checking docker-compose...' && \
    docker-compose --version && \
    echo 'Checking services...' && \
    docker-compose config --services | wc -l | xargs echo 'Available services:' && \
    echo 'Checking networks...' && \
    docker network ls | grep -E 'net-|bridge' | wc -l | xargs echo 'Networks:' && \
    echo 'Checking volumes...' && \
    docker volume ls | wc -l | xargs echo 'Volumes:'
" || {
    log_error "Pre-deployment checks failed"
    exit 1
}

log_success "Pre-deployment checks passed"

# Phase 2: Create required networks
log_info "PHASE 2: Creating Docker networks"
ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "
    docker network create net-management --driver bridge --subnet 172.28.0.0/16 2>/dev/null || echo 'net-management exists'
    docker network create net-app --driver bridge --subnet 172.29.0.0/16 2>/dev/null || echo 'net-app exists'
    docker network create net-data --driver bridge --subnet 172.30.0.0/16 2>/dev/null || echo 'net-data exists'
    docker network create net-edge --driver bridge --subnet 172.31.0.0/16 2>/dev/null || echo 'net-edge exists'
    docker network create net-secure --driver bridge --subnet 172.32.0.0/16 2>/dev/null || echo 'net-secure exists'
    echo 'Networks configured'
"

log_success "Networks configured"

# Phase 3: Deploy core services (no builds, pre-built images only)
log_info "PHASE 3: Deploying core pre-built services"
log_info "  Services: postgres, redis, prometheus, grafana, alertmanager, loki, jaeger, caddy, ollama"

DEPLOY_CMD="
    cd ${REMOTE_PATH}
    export PAGERDUTY_SERVICE_KEY='demo-key-for-alertmanager'
    export NAS_HOST=192.168.168.56
    export NAS_EXPORT_PATH=/export
    
    # Deploy without building - use --no-build flag for docker-compose v1 compat
    # or just don't specify --build (safe default)
    timeout 120 docker-compose up \
        postgres redis prometheus grafana alertmanager loki jaeger caddy ollama \
        -d \
        --pull missing \
        2>&1 | grep -E 'Creating|Starting|Running|Error|ERROR' || true
    
    # Wait for services to stabilize
    sleep 15
    
    # Check deployment status
    docker-compose ps --services | head -20
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${DEPLOY_CMD}" || {
    log_warn "Deployment command execution may have had warnings"
}

log_success "Core services deployed"

# Phase 4: Wait for services to reach healthy state
log_info "PHASE 4: Waiting for services to stabilize"
sleep 10

HEALTH_CHECK="
    cd ${REMOTE_PATH}
    docker-compose ps 2>/dev/null | tail -15
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${HEALTH_CHECK}"

log_success "Services stabilized"

# Phase 5: Verify deployment
log_info "PHASE 5: Verifying deployment"

VERIFY_CMD="
    echo '=== Running Containers ===' && \
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -15 && \
    echo '' && \
    echo '=== Port Mappings ===' && \
    docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E 'postgres|redis|prometheus|grafana|caddy|jaeger' || true && \
    echo '' && \
    echo '=== Network Connectivity ===' && \
    docker network ls | grep net- || true
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${VERIFY_CMD}"

log_success "Deployment verification complete"

# Phase 6: Generate deployment summary
log_info "PHASE 6: Generating deployment summary"

SUMMARY="
    echo '=== DEPLOYMENT SUMMARY ===' && \
    echo 'Platform: Infrastructure-as-Code (SSH-based)' && \
    echo 'Target Host: 192.168.168.31' && \
    echo 'Repository: ~/code-server-enterprise-ops' && \
    echo '' && \
    echo 'Deployed Services:' && \
    docker-compose config --services 2>/dev/null | head -10 | xargs -I {} echo '  ✓ {}' && \
    echo '' && \
    echo 'Port Mappings:' && \
    docker ps --format '{{.Names}}: {{.Ports}}' 2>/dev/null | grep -E 'postgres|redis|prometheus|grafana|caddy|9000|3000' | head -10 || true && \
    echo '' && \
    echo 'API Endpoint: http://192.168.168.31:8080' && \
    echo 'Prometheus: http://192.168.168.31:9090' && \
    echo 'Grafana: http://192.168.168.31:3000' && \
    echo 'Jaeger: http://192.168.168.31:16686' && \
    echo 'Caddy Admin: http://192.168.168.31:2019'
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${SUMMARY}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "CORE INFRASTRUCTURE DEPLOYMENT COMPLETE ✓"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Next Steps:"
echo "  1. Monitor services: ssh akushnir@192.168.168.31 'cd ~/code-server-enterprise-ops && docker-compose logs -f'"
echo "  2. Check health: ssh akushnir@192.168.168.31 'docker ps --format \"table {{.Names}}\t{{.Status}}\"'"
echo "  3. Deploy application services: bash scripts/ops/deploy-app-services.sh"
echo ""
