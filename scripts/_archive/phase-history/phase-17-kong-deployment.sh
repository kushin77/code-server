#!/bin/bash

################################################################################
# Phase 17: Kong API Gateway Deployment
# Purpose: Deploy Kong as centralized API gateway with rate limiting, OAuth2, logging
# Timeline: Phase 17 Week 1 (April 28, 2026)
#
# Usage: bash scripts/phase-17-kong-deployment.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${ROOT_DIR}/logs/phase-17-kong"
CONFIG_DIR="${ROOT_DIR}/config/phase-17"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "$LOG_DIR" "$CONFIG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/kong-deployment-${TIMESTAMP}.log"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "${LOG_DIR}/kong-deployment-${TIMESTAMP}.log"
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}" | tee -a "${LOG_DIR}/kong-deployment-${TIMESTAMP}.log"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

run_preflight() {
    log "Running pre-flight checks..."

    # Check Docker
    if ! docker ps > /dev/null 2>&1; then
        log_error "Docker daemon not responding"
        return 1
    fi
    log_success "Docker daemon: operational"

    # Check PostgreSQL
    if docker ps --format "{{.Names}}" | grep -q postgres; then
        log_success "PostgreSQL: running"
    else
        log "PostgreSQL not running, will deploy as part of Kong stack"
    fi

    # Check disk space
    local available_gb=$(df | tail -1 | awk '{print int($4 / 1024 / 1024)}')
    if [ "$available_gb" -lt 10 ]; then
        log_error "Insufficient disk space: ${available_gb}GB available (need 10GB)"
        return 1
    fi
    log_success "Disk space: ${available_gb}GB available"

    # Check existing Kong containers
    if docker ps -a --format "{{.Names}}" | grep -q kong; then
        log_error "Kong container already exists, remove first: docker rm -f kong"
        return 1
    fi
    log_success "Kong container: not running (clean state)"

    log_success "All pre-flight checks: PASSED"
    return 0
}

# ============================================================================
# KONG CONFIGURATION
# ============================================================================

create_kong_config() {
    log "Creating Kong configuration files..."

    # Create Kong database config
    cat > "${CONFIG_DIR}/kong-postgres-init.sql" << 'EOF'
-- Kong database initialization
CREATE SCHEMA IF NOT EXISTS kong;
CREATE SCHEMA IF NOT EXISTS "public";

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Kong tables (simplified - Kong will create full schema on startup)
-- This is just for documentation

-- Consumers table
CREATE TABLE IF NOT EXISTS kong_consumers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    username text UNIQUE,
    custom_id text,
    created_at timestamp DEFAULT now()
);

-- Services table
CREATE TABLE IF NOT EXISTS kong_services (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text UNIQUE,
    protocol text,
    host text,
    port integer,
    path text,
    created_at timestamp DEFAULT now()
);

-- Routes table
CREATE TABLE IF NOT EXISTS kong_routes (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id uuid REFERENCES kong_services(id),
    name text,
    methods text[],
    paths text[],
    created_at timestamp DEFAULT now()
);

-- Plugins table
CREATE TABLE IF NOT EXISTS kong_plugins (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id uuid REFERENCES kong_routes(id),
    name text,
    config jsonb,
    enabled boolean DEFAULT true,
    created_at timestamp DEFAULT now()
);

GRANT ALL PRIVILEGES ON SCHEMA kong TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA kong TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA kong TO postgres;
EOF

    log_success "Database init script created"
}

# ============================================================================
# KONG DOCKER DEPLOYMENT
# ============================================================================

deploy_kong_containers() {
    log "Deploying Kong containers..."

    # PostgreSQL for Kong
    log "Deploying PostgreSQL (Kong database backend)..."
    docker run -d \
        --name kong-postgres \
        --network kong-net \
        -e POSTGRES_USER=kong \
        -e POSTGRES_DB=kong \
        -e POSTGRES_PASSWORD=kong_secure_passwd \
        -v kong_postgres_data:/var/lib/postgresql/data \
        postgres:14-alpine

    log "Waiting for PostgreSQL to start..."
    sleep 5

    # Kong bootstrap
    log "Running Kong database migrations..."
    docker run --rm \
        --network kong-net \
        -e KONG_DATABASE=postgres \
        -e KONG_PG_HOST=kong-postgres \
        -e KONG_PG_USER=kong \
        -e KONG_PG_PASSWORD=kong_secure_passwd \
        kong:3.4-alpine kong migrations bootstrap

    log_success "Kong database migrations: complete"

    # Kong API Gateway
    log "Deploying Kong API Gateway container..."
    docker run -d \
        --name kong \
        --network kong-net \
        -e KONG_DATABASE=postgres \
        -e KONG_PG_HOST=kong-postgres \
        -e KONG_PG_USER=kong \
        -e KONG_PG_PASSWORD=kong_secure_passwd \
        -e KONG_PROXY_ACCESS_LOG=/dev/stdout \
        -e KONG_ADMIN_ACCESS_LOG=/dev/stdout \
        -e KONG_PROXY_ERROR_LOG=/dev/stderr \
        -e KONG_ADMIN_ERROR_LOG=/dev/stderr \
        -e KONG_LOG_LEVEL=info \
        -p 8000:8000 \
        -p 8443:8443 \
        -p 8001:8001 \
        -p 8444:8444 \
        kong:3.4-alpine

    log "Waiting for Kong to start..."
    sleep 3

    # Verify Kong startup
    local max_retries=30
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -s http://localhost:8001/status > /dev/null; then
            log_success "Kong API Gateway: running"
            break
        fi
        retry=$((retry + 1))
        sleep 1
    done

    if [ $retry -eq $max_retries ]; then
        log_error "Kong failed to start"
        docker logs kong
        return 1
    fi

    log_success "Kong containers deployed successfully"
}

# ============================================================================
# KONG CONFIGURATION - ROUTES & SERVICES
# ============================================================================

configure_kong_routes() {
    log "Configuring Kong routes and services..."

    local kong_admin="http://localhost:8001"

    # Service 1: code-server
    log "Creating code-server upstream..."
    curl -s -X POST "$kong_admin/services/" \
        -d name=code-server \
        -d protocol=http \
        -d host=code-server \
        -d port=9000 \
        | jq '.'

    log "Creating code-server route..."
    curl -s -X POST "$kong_admin/services/code-server/routes" \
        -d "paths[]=/ide" \
        -d methods=GET \
        -d methods=POST \
        | jq '.'

    # Service 2: git-proxy
    log "Creating git-proxy upstream..."
    curl -s -X POST "$kong_admin/services/" \
        -d name=git-proxy \
        -d protocol=http \
        -d host=git-proxy \
        -d port=22 \
        | jq '.'

    log "Creating git-proxy route..."
    curl -s -X POST "$kong_admin/services/git-proxy/routes" \
        -d "paths[]=/git" \
        -d methods=GET \
        -d methods=POST \
        | jq '.'

    # Service 3: API Gateway
    log "Creating api-gateway upstream..."
    curl -s -X POST "$kong_admin/services/" \
        -d name=api-gateway \
        -d protocol=http \
        -d host=api-gateway \
        -d port=5000 \
        | jq '.'

    log "Creating api-gateway route..."
    curl -s -X POST "$kong_admin/services/api-gateway/routes" \
        -d "paths[]=/api" \
        -d methods=GET \
        -d methods=POST \
        -d methods=DELETE \
        | jq '.'

    log_success "Kong routes and services configured"
}

# ============================================================================
# KONG PLUGINS - RATE LIMITING, OAUTH2, LOGGING
# ============================================================================

configure_kong_plugins() {
    log "Configuring Kong plugins..."

    local kong_admin="http://localhost:8001"

    # Rate limiting plugin
    log "Enabling rate limiting plugin..."
    curl -s -X POST "$kong_admin/routes/code-server/plugins" \
        -d name=rate-limiting \
        -d config.minute=600 \
        -d config.policy=local \
        | jq '.'

    # OAuth2 validation plugin (if Jaeger collector available)
    log "Enabling OAuth2 validation plugin..."
    curl -s -X POST "$kong_admin/routes/code-server/plugins" \
        -d name=oauth2 \
        -d config.cache_credentials=true \
        -d config.mandatory_scope=true \
        | jq '.'

    # Request logging plugin
    log "Enabling request logging plugin..."
    curl -s -X POST "$kong_admin/routes/code-server/plugins" \
        -d name=request-logger \
        -d config.http_endpoint=http://jaeger-collector:14268/api/traces \
        | jq '.' || log "Note: Jaeger collector not yet available, logging will activate in Phase 17 Week 1 Tuesday"

    # CORS plugin
    log "Enabling CORS plugin..."
    curl -s -X POST "$kong_admin/routes/code-server/plugins" \
        -d name=cors \
        -d config.origins=* \
        -d config.methods=GET,POST,HEAD,PUT,DELETE \
        | jq '.'

    log_success "Kong plugins configured"
}

# ============================================================================
# KONG HEALTH CHECKS
# ============================================================================

validate_kong_deployment() {
    log "Validating Kong deployment..."

    local kong_admin="http://localhost:8001"
    local kong_proxy="http://localhost:8000"

    # Health check
    log "Kong admin health check..."
    if curl -s "$kong_admin/status" | jq '.database.ok' | grep -q true; then
        log_success "Kong database: healthy"
    else
        log_error "Kong database connection failed"
        return 1
    fi

    # List routes
    log "Configured routes:"
    curl -s "$kong_admin/routes" | jq '.data[] | {name: .name, paths: .paths}'

    # Test routing to code-server (should fail gracefully if code-server not up)
    log "Testing Kong proxy (code-server route should exist)..."
    curl -s -I "$kong_proxy/ide/" | head -5 || log "Code-server not yet running (this is OK)"

    log_success "Kong validation: PASSED"
}

# ============================================================================
# STATUS SUMMARY
# ============================================================================

print_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  PHASE 17 KONG API GATEWAY DEPLOYMENT COMPLETE             ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Kong Admin API (configuration):"
    echo "  URL: http://localhost:8001/"
    echo "  Commands:"
    echo "    - List services: curl http://localhost:8001/services"
    echo "    - List routes: curl http://localhost:8001/routes"
    echo "    - List plugins: curl http://localhost:8001/plugins"
    echo ""
    echo "Kong Proxy (API gateway):"
    echo "  URL: http://localhost:8000/"
    echo "  Routes:"
    echo "    - code-server: http://localhost:8000/ide/"
    echo "    - git-proxy: http://localhost:8000/git/"
    echo "    - API gateway: http://localhost:8000/api/"
    echo ""
    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep kong
    echo ""
    echo "Next steps:"
    echo "  1. Verify code-server is accessible through Kong: curl http://localhost:8000/ide/"
    echo "  2. Verify git-proxy routing: curl http://localhost:8000/git/"
    echo "  3. Check Kong logs: docker logs kong"
    echo "  4. Proceed to Phase 17 Week 1 Tuesday: Jaeger deployment"
    echo ""
    log_success "Phase 17 Kong deployment: COMPLETE"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  PHASE 17: KONG API GATEWAY DEPLOYMENT${NC}"
    echo -e "${BLUE}  Timeline: April 28, 2026 (Phase 17 Week 1 Monday)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    log "Starting Kong deployment..."
    log "Timestamp: $(date)"
    log "Working directory: $ROOT_DIR"

    # Execute deployment steps
    if ! run_preflight; then
        log_error "Pre-flight checks failed"
        exit 1
    fi

    create_kong_config
    deploy_kong_containers
    configure_kong_routes
    configure_kong_plugins

    if ! validate_kong_deployment; then
        log_error "Kong validation failed"
        exit 1
    fi

    print_summary
    log "Kong deployment complete!"
}

# Execute
main "$@"
