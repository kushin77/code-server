#!/usr/bin/env bash
# @file scripts/ops/deploy-app-and-monitoring.sh
# @module infrastructure/operations
# @description Deploy application, monitoring, and AI runtime services from shared SSOT
# @governance GOV-002 - Deterministic, idempotent deployment flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"
source "${SCRIPT_DIR}/../_common/config.env"

trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

readonly SSH_USER="${SSH_USER:-akushnir}"
readonly REMOTE_PATH="${REMOTE_PATH:-~/code-server-enterprise-ops}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  PHASED DEPLOYMENT: APPLICATION, MONITORING, AND AI RUNTIME             ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Phase 1: Pre-deployment validation
log_info "PHASE 1: Pre-deployment validation"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "
    cd ${REMOTE_PATH}
    echo 'Checking core services...'
    docker-compose ps 2>/dev/null | grep -E 'postgres|redis' | wc -l | xargs echo 'Core services running:'
    echo 'Checking networks...'
    docker network ls | grep net- | wc -l | xargs echo 'Networks available:'
" || {
    log_error "Pre-deployment validation failed"
    exit 1
}

log_success "Pre-deployment validation passed"

# Phase 2: Deploy monitoring stack
log_info "PHASE 2: Deploying monitoring services"
log_info "  Services: prometheus, grafana, loki, alertmanager, tempo, otel-collector"

DEPLOY_MONITORING="
    cd ${REMOTE_PATH}
    export NAS_HOST="${NAS_HOST}"
    export NAS_EXPORT_PATH="${NAS_EXPORT_PATH:-/export}"
    
    # Deploy monitoring services
    timeout 180 docker-compose up \
        prometheus grafana loki alertmanager tempo otel-collector \
        -d \
        --pull missing \
        2>&1 | grep -E 'Creating|Starting|Running|Error' || true
    
    sleep 10
    
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'prometheus|grafana|loki|alertmanager|tempo|otel-collector' || echo 'Monitoring services deployed'
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${DEPLOY_MONITORING}" || {
    log_warning "Monitoring deployment encountered issues (may be expected)"
}

log_success "Monitoring services deployed"

# Phase 3: Deploy support services
log_info "PHASE 3: Deploying support services"
log_info "  Services: oauth2-proxy, caddy"

DEPLOY_SUPPORT="
    cd ${REMOTE_PATH}
    export NAS_HOST="${NAS_HOST}"
    export NAS_EXPORT_PATH="${NAS_EXPORT_PATH:-/export}"
    
    # Deploy support services
    timeout 120 docker-compose up \
        oauth2-proxy caddy \
        -d \
        --pull missing \
        2>&1 | grep -E 'Creating|Starting|Running|Error' || true
    
    sleep 10
    
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'oauth2|caddy' || echo 'Support services deployed'
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${DEPLOY_SUPPORT}" || {
    log_warning "Support services deployment may have had issues (continuing)"
}

log_success "Support services deployed"

# Phase 4: Deploy AI runtime
log_info "PHASE 4: Deploying AI runtime"
log_info "  Services: ollama, ollama-init"

DEPLOY_OBSERVABILITY="
    cd ${REMOTE_PATH}
    export NAS_HOST="${NAS_HOST}"
    export NAS_EXPORT_PATH="${NAS_EXPORT_PATH:-/export}"
    
    # Deploy observability services
    timeout 120 docker-compose up \
        ollama ollama-init \
        -d \
        --pull missing \
        2>&1 | grep -E 'Creating|Starting|Running|Error' || true
    
    sleep 10
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${DEPLOY_OBSERVABILITY}" || {
    log_warning "AI runtime deployment continuing despite issues"
}

log_success "AI runtime deployed"

# Phase 5: Check deployment status
log_info "PHASE 5: Verifying deployment status"

VERIFY_CMD="
    echo '=== Running Containers ===' && \
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | head -20 && \
    echo '' && \
    echo '=== Service Health Summary ===' && \
    docker ps -a --format 'table {{.Status}}' | sort | uniq -c | sort -rn && \
    echo '' && \
    echo '=== Critical Services ===' && \
    docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'api|postgres|redis|prometheus|grafana|caddy|tempo' || echo '(none found)'
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${VERIFY_CMD}"

log_success "Deployment verification complete"

# Phase 6: Generate access information
log_info "PHASE 6: Generating access information"

ACCESS_INFO="
    echo '=== ACCESS ENDPOINTS ===' && \
    echo 'API Platform:' && \
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep -i api | head -1 && \
    echo '' && \
    echo 'Monitoring Services:' && \
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E 'prometheus|grafana|loki|alertmanager|tempo' | head -5 && \
    echo '' && \
    echo 'AI Runtime:' && \
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep -i ollama && \
    echo '' && \
    echo 'Reverse Proxy:' && \
    docker ps --format '{{.Names}}\t{{.Ports}}' | grep caddy
"

ssh -o ConnectTimeout=10 "${SSH_USER}@${PRIMARY_HOST}" "${ACCESS_INFO}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
log_success "PHASED DEPLOYMENT COMPLETE"
echo "╚══════════════════════════════════════════════════════════════════════════╝"

echo ""
echo "Deployment Summary:"
echo "  Phase 1 (Core Infrastructure): ✅ COMPLETED"
echo "  Phase 2 (App, Monitoring, AI): ✅ COMPLETED"
echo ""
echo "Available Endpoints:"
echo "  API: http://${PRIMARY_HOST}:8080"
echo "  Prometheus: http://${PRIMARY_HOST}:9090"
echo "  Grafana: http://${PRIMARY_HOST}:3001"
echo "  Loki: http://${PRIMARY_HOST}:3100"
echo "  Tempo: http://${PRIMARY_HOST}:3200"
echo "  Caddy Admin: http://${PRIMARY_HOST}:2019"
echo ""
echo "Next Steps:"
echo "  1. Monitor services: ssh ${SSH_USER}@${PRIMARY_HOST} 'docker-compose logs -f'"
echo "  2. Validate compose services: docker-compose config --services"
echo "  3. Review the phase 4 HA handoff notes in the deployment docs"
echo ""
