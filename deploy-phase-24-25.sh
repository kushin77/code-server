#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# Phase 24-25 Docker Compose Deployment Script
# ════════════════════════════════════════════════════════════════════════════
# Deploy Phase 24-25 services on Ubuntu/Debian with Docker Compose v2+
# Usage: ./deploy-phase-24-25.sh [phase24|phase25|all]
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE="${1:-all}"
DOCKER_COMPOSE_BIN="$(command -v docker-compose || command -v 'docker compose')"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! command -v 'docker compose' &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Create enterprise network if not exists
    if ! docker network inspect enterprise &> /dev/null; then
        log_info "Creating 'enterprise' Docker network..."
        docker network create --driver bridge enterprise
    fi
    
    # Create volume directories
    mkdir -p /home/$(whoami)/.docker-volumes/{minio,velero,graphql-api,developer-portal}
    mkdir -p /home/$(whoami)/.config
    
    log_info "✓ Prerequisites check passed"
}

# Create environment file if not exists
create_env_file() {
    local env_file="${ROOT_DIR}/.env.phase24-25"
    
    if [ ! -f "$env_file" ]; then
        log_warn "Creating $env_file with defaults"
        cat > "$env_file" << 'EOF'
# Phase 24-25 Operations & API Configuration

# MinIO (S3 Object Storage for Velero)
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=change-me-in-production-2024

# Database & Cache (shared with Phase 21)
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/code_server
REDIS_URL=redis://redis:6379/0

# GraphQL & Portal
NEXTAUTH_SECRET=change-this-to-random-secret-32chars
GRAPHQL_API_ENDPOINT=http://graphql-api-server:4000
DEVELOPER_PORTAL_URL=http://localhost:3001

# Logging & Monitoring
LOG_LEVEL=info
JAEGER_ENDPOINT=http://jaeger:6831

# Cost Optimization
COST_ALERT_THRESHOLD=1000
EOF
        log_warn "⚠️  Edit $env_file and configure secrets before production deployment!"
    fi
}

# Create nginx configuration for API gateway
create_nginx_config() {
    local nginx_conf="/home/$(whoami)/.config/nginx-phase25.conf"
    
    cat > "$nginx_conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=portal_limit:10m rate=5r/s;

    upstream graphql_backend {
        server graphql-api-server:4000 max_fails=3 fail_timeout=30s;
    }

    upstream portal_backend {
        server developer-portal:3000 max_fails=3 fail_timeout=30s;
    }

    server {
        listen 80;
        server_name _;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "gateway-healthy\n";
            add_header Content-Type text/plain;
        }

        # GraphQL API
        location /graphql {
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://graphql_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 60s;
        }

        # Developer Portal
        location / {
            limit_req zone=portal_limit burst=10 nodelay;
            proxy_pass http://portal_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_cache_bypass $http_upgrade;
        }
    }
}
EOF
    log_info "✓ Nginx configuration created at $nginx_conf"
}

# Deploy Phase 24 (Operations Excellence)
deploy_phase_24() {
    log_info "Deploying Phase 24: Operations Excellence..."
    
    cd "$ROOT_DIR"
    
    # Start services
    $DOCKER_COMPOSE_BIN -f docker-compose-phase-24-operations.yml \
        --env-file .env.phase24-25 \
        up -d
    
    log_info "Phase 24 services starting..."
    sleep 10
    
    # Check health
    log_info "Checking Phase 24 service health..."
    
    local services=("minio" "velero-backup-agent" "cost-engine")
    for service in "${services[@]}"; do
        if docker ps | grep -q "$service"; then
            log_info "✓ $service is running"
        else
            log_warn "⚠️  $service failed to start"
        fi
    done
    
    log_info "Phase 24 deployment complete!"
    echo ""
    echo "Access Points:"
    echo "  MinIO Console: http://192.168.168.31:9001 (credentials: minioadmin/minioadmin123)"
    echo "  Velero Agent: http://192.168.168.31:8085"
    echo ""
}

# Deploy Phase 25 (GraphQL API & Portal)
deploy_phase_25() {
    log_info "Deploying Phase 25: GraphQL API & Developer Portal..."
    
    cd "$ROOT_DIR"
    
    # Start services
    $DOCKER_COMPOSE_BIN -f docker-compose-phase-25-api.yml \
        --env-file .env.phase24-25 \
        up -d
    
    log_info "Phase 25 services starting..."
    sleep 15
    
    # Check health
    log_info "Checking Phase 25 service health..."
    
    local services=("graphql-api-server" "developer-portal" "api-gateway-nginx")
    for service in "${services[@]}"; do
        if docker ps | grep -q "$service"; then
            log_info "✓ $service is running"
        else
            log_warn "⚠️  $service failed to start"
        fi
    done
    
    log_info "Phase 25 deployment complete!"
    echo ""
    echo "Access Points:"
    echo "  GraphQL API: http://192.168.168.31:4000/graphql"
    echo "  Developer Portal: http://192.168.168.31:3001"
    echo "  API Gateway: http://192.168.168.31:8001"
    echo ""
}

# Main deployment logic
main() {
    log_info "Starting Phase 24-25 Docker Compose Deployment"
    log_info "Selected: $PHASE"
    
    check_prerequisites
    create_env_file
    create_nginx_config
    
    case "$PHASE" in
        phase24)
            deploy_phase_24
            ;;
        phase25)
            deploy_phase_25
            ;;
        all)
            deploy_phase_24
            deploy_phase_25
            ;;
        *)
            log_error "Invalid phase: $PHASE. Use: phase24, phase25, or all"
            exit 1
            ;;
    esac
    
    log_info "✅ Deployment complete!"
    log_info "View logs: docker-compose -f docker-compose-phase-24-25.yml logs -f"
}

main "$@"
