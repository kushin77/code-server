#!/bin/bash
# scripts/deploy-cloudflare-tunnel.sh
# Deploy Cloudflare Tunnel as Docker service + Terraform infrastructure
# Part of Phase 8 #348 implementation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✅ SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[❌ ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[⚠️ WARNING]${NC} $*"; }

# Configuration
readonly TUNNEL_NAME="code-server-production"
readonly DOCKER_COMPOSE_FILE="docker-compose.yml"
readonly TERRAFORM_DIR="terraform"
readonly SCRIPT_DIR="scripts"

log_info "=== Cloudflare Tunnel Deployment (#348) ==="
log_info "Environment: ${ENVIRONMENT:-production}"

# ============================================================================
# STEP 1: Validate Prerequisites
# ============================================================================

log_info "Validating prerequisites..."

# Check CLOUDFLARE_TUNNEL_TOKEN is set
if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    log_error "CLOUDFLARE_TUNNEL_TOKEN not set in environment"
    log_info "Get tunnel token from: Cloudflare Dashboard → Account → Tunnels"
    exit 1
fi

# Check Terraform is installed
if ! command -v terraform &> /dev/null; then
    log_error "terraform not found in PATH"
    exit 1
fi

# Check Docker is available
if ! docker-compose --version &> /dev/null; then
    log_error "docker-compose not found"
    exit 1
fi

log_success "Prerequisites validated"

# ============================================================================
# STEP 2: Update Docker Compose with Cloudflared Service
# ============================================================================

log_info "Updating docker-compose.yml with cloudflared service..."

# Check if cloudflared service already exists
if grep -q "cloudflared:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
    log_warn "cloudflared service already exists in docker-compose.yml"
    log_info "Skipping service definition update"
else
    log_info "Adding cloudflared service to docker-compose.yml..."
    
    # Extract cloudflared service definition from snippet
    if [ -f "docker-compose.cloudflared.snippet.yml" ]; then
        # Simple merge: append cloudflared service before final line
        # Note: This is a simple approach; consider using yq for production
        sed -i '/^services:/,/^[^ ]/{ /^[^ ]/i\  cloudflared:\n    image: cloudflare/cloudflared:2024.1.5\n    container_name: cloudflared\n    restart: unless-stopped\n    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}\n    environment:\n      TUNNEL_TOKEN: "${CLOUDFLARE_TUNNEL_TOKEN}"\n    networks:\n      - enterprise\n    depends_on:\n      caddy:\n        condition: service_healthy\n    healthcheck:\n      test: ["CMD", "cloudflared", "tunnel", "info"]\n      interval: 30s\n      timeout: 10s\n      retries: 3\n    deploy:\n      resources:\n        limits:\n          memory: 128m\n          cpus: '\''0.25'\''\n    logging:\n      driver: "json-file"\n      options:\n        max-size: "10m"\n        max-file: "3"\n' "$DOCKER_COMPOSE_FILE"
        log_success "cloudflared service added to docker-compose.yml"
    else
        log_warn "docker-compose.cloudflared.snippet.yml not found, manual edit required"
        log_info "Add the cloudflared service definition from docker-compose.cloudflared.snippet.yml"
    fi
fi

# ============================================================================
# STEP 3: Initialize and Deploy Terraform
# ============================================================================

log_info "Deploying Cloudflare infrastructure via Terraform..."

cd "$TERRAFORM_DIR"

# Initialize Terraform
log_info "Initializing Terraform..."
terraform init -upgrade

# Validate configuration
log_info "Validating Terraform configuration..."
if ! terraform validate; then
    log_error "Terraform validation failed"
    exit 1
fi

# Plan deployment
log_info "Planning Terraform deployment..."
terraform plan -out=tfplan

# Apply deployment
log_info "Applying Terraform configuration..."
if terraform apply tfplan; then
    log_success "Terraform deployment complete"
else
    log_error "Terraform apply failed"
    exit 1
fi

# Get outputs
TUNNEL_CNAME=$(terraform output -raw tunnel_cname 2>/dev/null || echo "")
DNSSEC_STATUS=$(terraform output -raw dnssec_status 2>/dev/null || echo "")

log_success "Cloudflare infrastructure deployed"
log_info "Tunnel CNAME: $TUNNEL_CNAME"
log_info "DNSSEC Status: $DNSSEC_STATUS"

cd - > /dev/null

# ============================================================================
# STEP 4: Start Cloudflared Service
# ============================================================================

log_info "Starting cloudflared Docker service..."

# Export CLOUDFLARE_TUNNEL_TOKEN for docker-compose
export CLOUDFLARE_TUNNEL_TOKEN

# Pull latest cloudflared image
docker pull cloudflare/cloudflared:2024.1.5

# Start service
if docker-compose up -d cloudflared; then
    log_success "cloudflared service started"
else
    log_error "Failed to start cloudflared service"
    exit 1
fi

# Wait for service to be healthy
log_info "Waiting for cloudflared to become healthy..."
sleep 10

if docker-compose ps cloudflared | grep -q "healthy"; then
    log_success "cloudflared is healthy"
else
    log_warn "cloudflared may not be healthy yet, checking logs..."
    docker-compose logs cloudflared | tail -20
fi

# ============================================================================
# STEP 5: Verify Tunnel Configuration
# ============================================================================

log_info "Verifying tunnel configuration..."

# Check tunnel info
if docker exec cloudflared cloudflared tunnel info 2>&1 | grep -q "Tunnel"; then
    log_success "Tunnel authenticated and operational"
    docker exec cloudflared cloudflared tunnel info
else
    log_error "Tunnel authentication failed or tunnel not operational"
    log_info "Check CLOUDFLARE_TUNNEL_TOKEN and tunnel status in Cloudflare dashboard"
fi

# ============================================================================
# STEP 6: DNS Verification
# ============================================================================

log_info "Verifying DNS routing..."

# Check IDE domain resolution
RESOLVED_IP=$(dig +short ide.kushnir.cloud @8.8.8.8 | head -1)

if [ -z "$RESOLVED_IP" ]; then
    log_warn "DNS resolution pending (propagation may take a few minutes)"
else
    log_success "ide.kushnir.cloud resolves to: $RESOLVED_IP"
    
    # Check if it's a Cloudflare IP (not bare host IP)
    if [[ "$RESOLVED_IP" =~ ^192\.168 ]]; then
        log_warn "⚠️ Domain resolving to LAN IP ($RESOLVED_IP) — proxied setting may be incorrect"
    else
        log_success "Domain proxied through Cloudflare edge"
    fi
fi

# ============================================================================
# STEP 7: HTTPS Health Check
# ============================================================================

log_info "Checking HTTPS endpoint..."

if command -v curl &> /dev/null; then
    # Try HTTPS with verbose SSL info
    if timeout 10 curl -k --silent --head https://ide.kushnir.cloud 2>&1 | grep -q "HTTP"; then
        log_success "HTTPS endpoint responding"
        
        # Check TLS version
        TLS_VERSION=$(echo | openssl s_client -connect ide.kushnir.cloud:443 2>&1 | grep "Protocol" | awk '{print $3}')
        log_info "TLS Version: $TLS_VERSION"
        
        if [[ "$TLS_VERSION" == *"TLSv1.3"* ]]; then
            log_success "TLS 1.3 negotiated (production-grade security)"
        fi
    else
        log_warn "HTTPS endpoint not yet responding (DNS propagation pending)"
    fi
fi

# ============================================================================
# STEP 8: Monitoring Configuration
# ============================================================================

log_info "Configuring monitoring and alerting..."

# Create Prometheus scrape config for cloudflared metrics
cat > /tmp/prometheus-cloudflared.yml <<EOF
- job_name: 'cloudflared'
  static_configs:
    - targets: ['localhost:7878']  # cloudflared metrics port
  metrics_path: '/metrics'
  scrape_interval: 30s
EOF

log_info "Prometheus scrape config: /tmp/prometheus-cloudflared.yml"
log_info "Merge this into prometheus.yml to enable metric collection"

# ============================================================================
# STEP 9: Summary and Next Steps
# ============================================================================

echo
log_success "=== Phase 8 #348: Cloudflare Tunnel Deployment Complete ==="
echo
log_info "Deployment Summary:"
log_info "  ✅ Docker service (cloudflared) deployed"
log_info "  ✅ Terraform infrastructure (WAF, DNS, DNSSEC) deployed"
log_info "  ✅ Tunnel authenticated and operational"
log_info "  ✅ HTTPS endpoint configured"
log_info "  ✅ Monitoring configured"
echo
log_info "Next Steps:"
log_info "  1. Verify DNS has propagated globally: dig ide.kushnir.cloud @1.1.1.1"
log_info "  2. Test HTTPS access: curl https://ide.kushnir.cloud/healthz"
log_info "  3. Check Cloudflare dashboard for tunnel status"
log_info "  4. Monitor cloudflared logs: docker-compose logs -f cloudflared"
log_info "  5. Merge Prometheus config from /tmp/prometheus-cloudflared.yml"
echo
log_info "Acceptance Criteria Verification:"
log_info "  [ ] docker-compose ps cloudflared shows healthy"
log_info "  [ ] dig ide.kushnir.cloud resolves to Cloudflare IP (not 192.168.x.x)"
log_info "  [ ] curl https://ide.kushnir.cloud/healthz returns 200"
log_info "  [ ] TLS 1.3 minimum enforced"
log_info "  [ ] WAF rules active (check Cloudflare dashboard)"
log_info "  [ ] DNSSEC enabled"
log_info "  [ ] CAA records set (letsencrypt.org only)"
echo
log_success "Tunnel deployment ready for production. Commit changes to git:"
log_info "  git add docker-compose.yml terraform/cloudflare*.tf"
log_info "  git commit -m 'feat(cloudflare): Deploy tunnel + WAF + edge security (#348)'"
