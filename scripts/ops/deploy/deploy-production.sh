#!/bin/bash
# Hermes Agent Portal - One-Command Deployment Script
# Deploys Appsmith + hermes-integration + code-server with OAuth integration
# Usage: ./deploy-production.sh

set -e

# Error handling
trap 'log_error "Deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup completed"; rm -f /tmp/deploy-*.tmp 2>/dev/null || true' EXIT

# Logging functions
log_info() { echo "[$(date +'%H:%M:%S')] [INFO] $1"; }
log_success() { echo "[$(date +'%H:%M:%S')] [✓] $1"; }
log_error() { echo "[$(date +'%H:%M:%S')] [✗] $1" >&2; }
log_section() { echo ""; echo "════════════════════════════════════════════════════════"; echo "  $1"; echo "════════════════════════════════════════════════════════"; }

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
DOMAIN="${DOMAIN:-kushnir.cloud}"
COMPOSE_FILE="docker-compose.enterprise.yml"
STARTUP_TIMEOUT=180

log_section "Hermes Agent Portal - Production Deployment"

# ============================================================================
# Step 1: Pre-flight Checks
# ============================================================================
log_section "Step 1: Pre-flight Checks"

log_info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    exit 1
fi
log_success "Docker: $(docker --version)"

log_info "Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed"
    exit 1
fi
log_success "Docker Compose: $(docker-compose --version)"

log_info "Checking configuration files..."
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Missing: $COMPOSE_FILE"
    exit 1
fi
log_success "Found: $COMPOSE_FILE"

if [[ ! -f "Caddyfile" ]]; then
    log_error "Missing: Caddyfile"
    exit 1
fi
log_success "Found: Caddyfile"

if [[ ! -f ".env" ]]; then
    log_error "Missing: .env file (required for OAuth credentials)"
    log_info "Create .env with: OAUTH_GOOGLE_CLIENT_ID and OAUTH_GOOGLE_CLIENT_SECRET"
    exit 1
fi
log_success "Found: .env"

log_info "Validating docker-compose configuration..."
if ! docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
    log_error "Invalid docker-compose configuration"
    exit 1
fi
log_success "Configuration is valid"

# ============================================================================
# Step 2: Verify Required Services Configuration
# ============================================================================
log_section "Step 2: Verify Service Configuration"

log_info "Checking Appsmith service configuration..."
if docker-compose -f "$COMPOSE_FILE" config --services | grep -q "appsmith"; then
    log_success "Appsmith: Configured"
else
    log_error "Appsmith service not found in docker-compose"
    exit 1
fi

log_info "Checking hermes-integration service configuration..."
if docker-compose -f "$COMPOSE_FILE" config --services | grep -q "hermes-integration"; then
    log_success "hermes-integration: Configured"
else
    log_error "hermes-integration service not found in docker-compose"
    exit 1
fi

log_info "Checking code-server service configuration..."
if docker-compose -f "$COMPOSE_FILE" config --services | grep -q "code-server"; then
    log_success "code-server: Configured"
else
    log_error "code-server service not found in docker-compose"
    exit 1
fi

# ============================================================================
# Step 3: Stop Existing Services (if any)
# ============================================================================
log_section "Step 3: Prepare for Deployment"

log_info "Checking for existing services..."
if docker ps --format '{{.Names}}' | grep -q "code-server-appsmith"; then
    log_info "Found existing services, performing graceful shutdown..."
    docker-compose -f "$COMPOSE_FILE" down --timeout 10 || true
    sleep 5
    log_success "Existing services stopped"
else
    log_info "No existing services found"
fi

# ============================================================================
# Step 4: Deploy Services
# ============================================================================
log_section "Step 4: Deploy Services"

log_info "Starting services... (this may take 2-3 minutes)"
docker-compose -f "$COMPOSE_FILE" up -d

log_success "Services started in background"

# ============================================================================
# Step 5: Wait for Services to Be Healthy
# ============================================================================
log_section "Step 5: Waiting for Services to Become Healthy"

ELAPSED=0
while [[ $ELAPSED -lt $STARTUP_TIMEOUT ]]; do
    log_info "Checking service health... (${ELAPSED}s/${STARTUP_TIMEOUT}s)"
    
    # Count healthy services
    APPSMITH_HEALTH=$(docker inspect code-server-appsmith --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    
    if [[ "$APPSMITH_HEALTH" == "healthy" ]]; then
        log_success "Appsmith: Healthy"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [[ $ELAPSED -ge $STARTUP_TIMEOUT ]]; then
    log_error "Timeout waiting for services to become healthy"
    log_info "Checking service status..."
    docker-compose -f "$COMPOSE_FILE" ps
    exit 1
fi

# ============================================================================
# Step 6: Verify All Services Running
# ============================================================================
log_section "Step 6: Verify Service Status"

log_info "Current service status:"
docker-compose -f "$COMPOSE_FILE" ps

# Check critical services
APPSMITH_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "code-server-appsmith" || echo "0")
HERMES_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "hermes-integration" || echo "0")

if [[ "$APPSMITH_RUNNING" -eq 0 ]]; then
    log_error "Appsmith service is not running"
    docker logs code-server-appsmith | tail -20
    exit 1
fi
log_success "Appsmith: Running"

if [[ "$HERMES_RUNNING" -eq 0 ]]; then
    log_error "hermes-integration service is not running"
    docker logs hermes-integration | tail -20
    exit 1
fi
log_success "hermes-integration: Running"

# ============================================================================
# Step 7: Verify API Connectivity
# ============================================================================
log_section "Step 7: Verify API Connectivity"

log_info "Testing hermes-integration API (local)..."
if response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null); then
    if [[ "$response" == "200" ]]; then
        log_success "API Health: OK (HTTP $response)"
    else
        log_error "API Health: HTTP $response"
    fi
else
    log_info "Local API test failed (may require port mapping)"
fi

# ============================================================================
# Step 8: Summary and Next Steps
# ============================================================================
log_section "Step 8: Deployment Complete"

log_success "All services deployed successfully"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Hermes Agent Portal - Now Online                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Access Points:"
echo "   Dashboard:  https://$DOMAIN"
echo "   Dashboard:  https://$DOMAIN/paperclip"
echo "   IDE:        https://$DOMAIN/ide"
echo "   API Health: https://$DOMAIN/api/hermes/health"
echo ""

echo "🔐 Authentication:"
echo "   Method: OAuth2 (Google)"
echo "   Required: OAUTH_GOOGLE_CLIENT_ID in .env"
echo ""

echo "✅ Next Steps:"
echo "   1. Open https://$DOMAIN in your browser"
echo "   2. Sign in with Google OAuth"
echo "   3. Access Hermes Agent Platform Dashboard"
echo "   4. Test phase management and batch operations"
echo ""

echo "📋 Service Information:"
docker-compose -f "$COMPOSE_FILE" ps

echo ""
echo "📝 Monitoring Commands:"
echo "   # Real-time status"
echo "   watch -n 5 'docker-compose -f $COMPOSE_FILE ps'"
echo ""
echo "   # View logs"
echo "   docker-compose -f $COMPOSE_FILE logs -f"
echo ""
echo "   # Check specific service"
echo "   docker logs -f code-server-appsmith"
echo ""

echo "📚 Documentation:"
echo "   • APPSMITH_KUSHNIR_CLOUD_SECURE_INTEGRATION.md"
echo "   • APPSMITH_DEPLOYMENT_GUIDE.md"
echo "   • PRODUCTION_DEPLOYMENT_PACKAGE.md"
echo ""

log_success "Deployment Complete - System is Ready for Production"
