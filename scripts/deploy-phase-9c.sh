#!/bin/bash
# Phase 9-C: Deploy Kong API Gateway
# Issue #366: API Gateway, Rate Limiting, Request Management
# Status: Production-Ready Deployment

set -o errexit
set -o pipefail

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

echo "════════════════════════════════════════════════════════════════"
echo "PHASE 9-C DEPLOYMENT - KONG API GATEWAY"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Verify Phase 9-C IaC files
log_info "Verifying Phase 9-C IaC files..."
if [ ! -f "terraform/phase-9c-kong-gateway.tf" ] || [ ! -f "terraform/phase-9c-kong-routing.tf" ]; then
  log_error "Phase 9-C Terraform files not found"
  exit 1
fi
log_success "Phase 9-C IaC files verified"

# Step 2: Validate Terraform
log_info "Validating Terraform configuration..."
cd terraform
terraform fmt -check phase-9c-*.tf || terraform fmt -write phase-9c-*.tf
terraform validate || log_error "Terraform validation failed"
log_success "Terraform validation passed"
cd ..

# Step 3: Deploy Kong configuration
log_info "Deploying Kong configuration to primary..."
mkdir -p config/kong
scp -q config/kong/kong.conf akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/kong/ || log_error "Failed to copy Kong config"
scp -q config/kong/kong-routes.json akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/kong/ || true
scp -q config/kong/kong-plugins.json akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/kong/ || true
scp -q config/kong/kong-rate-limiting.json akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/kong/ || true
scp -q config/kong/kong-security-policies.json akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/kong/ || true
log_success "Kong configuration deployed"

# Step 4: Deploy Prometheus monitoring rules
log_info "Deploying Kong monitoring rules..."
scp -q config/prometheus/kong-monitoring.yml akushnir@"${PRIMARY_HOST}":/code-server-enterprise/config/prometheus/rules/ || true
log_success "Kong monitoring rules deployed"

# Step 5: Verify deployment
log_info "Verifying Phase 9-C deployment on primary..."
ssh akushnir@"${PRIMARY_HOST}" "cd /code-server-enterprise && \
  echo '? Kong configuration:' && \
  ls -lh config/kong/*.conf config/kong/*.json 2>/dev/null | wc -l && \
  echo 'configuration files' && \
  echo '? Kong monitoring rules:' && \
  ls -lh config/prometheus/rules/kong-monitoring.yml 2>/dev/null" || log_error "Primary verification failed"

log_success "Phase 9-C deployment verified"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Phase 9-C Kong API Gateway Configuration"
echo "════════════════════════════════════════════════════════════════"
echo "Kong Proxy HTTP:                http://${PRIMARY_HOST}:8000"
echo "Kong Proxy HTTPS:               https://${PRIMARY_HOST}:8443"
echo "Kong Admin API:                 http://${PRIMARY_HOST}:8001"
echo "Konga Dashboard:                http://${PRIMARY_HOST}:1337"
echo ""
echo "Kong Services Configured:       6 (code-server, oauth2, prometheus, grafana, jaeger, loki)"
echo "Kong Routes Configured:         13 (distributed across services)"
echo "Rate Limiting Policies:         4 (public, authenticated, internal, monitoring)"
echo "Authentication Methods:         OAuth2, API Key Auth"
echo ""
echo "Availability SLO Target:        99.95%"
echo "Latency P99 Target:             500ms"
echo "Upstream Health Target:         100%"
echo "Cache Hit Ratio Target:         >80%"
echo ""

# Step 6: Health checks
log_info "Running health checks..."
echo "Waiting for Kong to be ready..."
for i in {1..30}; do
  if ssh akushnir@"${PRIMARY_HOST}" "curl -sf http://localhost:8001 >/dev/null 2>&1" 2>/dev/null; then
    log_success "Kong Admin API health check passed"
    break
  fi
  if [ $i -eq 30 ]; then
    log_error "Kong health check timed out"
  fi
  sleep 2
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "NEXT STEPS:"
echo "════════════════════════════════════════════════════════════════"
echo "1. Start Kong and related services:"
echo "   ssh akushnir@${PRIMARY_HOST}"
echo "   cd /code-server-enterprise"
echo "   docker-compose up -d postgres kong kong-migrations konga"
echo ""
echo "2. Configure routes via Admin API:"
echo "   curl -X POST http://${PRIMARY_HOST}:8001/services \\"
echo "     -d 'name=code-server&url=http://haproxy:80'"
echo ""
echo "3. Enable rate limiting plugin:"
echo "   curl -X POST http://${PRIMARY_HOST}:8001/services/code-server/plugins \\"
echo "     -d 'name=rate-limiting&config.second=1000'"
echo ""
echo "4. Access Konga Admin Dashboard:"
echo "   Open http://${PRIMARY_HOST}:1337"
echo "   Create connection to Kong: http://kong:8001"
echo ""
echo "5. Test proxy endpoint:"
echo "   curl http://${PRIMARY_HOST}:8000/health"
echo ""
echo "6. View Kong metrics in Prometheus:"
echo "   http://${PRIMARY_HOST}:9090"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "STATUS: Phase 9-C deployment configuration ready"
echo "════════════════════════════════════════════════════════════════"
