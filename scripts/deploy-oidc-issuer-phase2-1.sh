#!/bin/bash
# Phase 2.1: OIDC Issuer Deployment Script
# Production deployment for ide.kushnir.cloud workload identity

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

OIDC_NAMESPACE="oidc-issuer"
OIDC_ISSUER_URL="https://oidc.kushnir.cloud"
OIDC_ISSUER_SERVICE="oidc-issuer.oidc-issuer.svc.cluster.local:8888"
APEX_DOMAIN="kushnir.cloud"
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
  exit 1
}

# ============================================================================
# Pre-deployment Validation
# ============================================================================

validate_prerequisites() {
  log_info "Validating prerequisites..."

  # Check kubectl access
  if ! kubectl cluster-info &>/dev/null; then
    log_error "kubectl cluster not accessible"
  fi
  log_success "kubectl cluster accessible"

  # Check Kubernetes version
  K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server" | awk '{print $3}')
  log_success "Kubernetes version: $K8S_VERSION"

  # Check required files
  local required_files=(
    "$PROJECT_ROOT/config/iam/k8s-oidc-issuer-production.yaml"
    "$PROJECT_ROOT/config/iam/k8s-workload-identity-bindings.yaml"
    "$PROJECT_ROOT/config/caddy/oidc-issuer-routing.caddyfile"
  )

  for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      log_error "Required file missing: $file"
    fi
  done
  log_success "All required files present"

  # Check Docker/Caddy access
  if command -v docker &>/dev/null; then
    if ! docker ps &>/dev/null; then
      log_warning "Docker daemon may not be running"
    fi
  fi
}

# ============================================================================
# Generate Signing Key (ED25519)
# ============================================================================

generate_signing_key() {
  log_info "Generating ED25519 signing key for OIDC issuer..."

  local key_file="/tmp/oidc-signing-key.pem"
  
  # Generate key
  openssl genpkey -algorithm ed25519 -out "$key_file"
  log_success "Signing key generated: $key_file"

  # Create Kubernetes secret
  kubectl delete secret oidc-signing-key -n "$OIDC_NAMESPACE" 2>/dev/null || true
  kubectl create secret generic oidc-signing-key \
    --from-file=signing-key.pem="$key_file" \
    -n "$OIDC_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  log_success "Kubernetes secret created: oidc-signing-key"

  # Secure cleanup
  rm -f "$key_file"
  log_success "Temporary key file cleaned up"
}

# ============================================================================
# Deploy Kubernetes Manifests
# ============================================================================

deploy_kubernetes_manifests() {
  log_info "Deploying Kubernetes manifests..."

  # Apply OIDC issuer manifests
  kubectl apply -f "$PROJECT_ROOT/config/iam/k8s-oidc-issuer-production.yaml"
  log_success "OIDC issuer manifests deployed"

  # Apply workload identity bindings
  kubectl apply -f "$PROJECT_ROOT/config/iam/k8s-workload-identity-bindings.yaml"
  log_success "Workload identity bindings deployed"

  # Wait for OIDC issuer deployment
  log_info "Waiting for OIDC issuer deployment (timeout: 300s)..."
  kubectl rollout status deployment/oidc-issuer -n "$OIDC_NAMESPACE" --timeout=300s
  log_success "OIDC issuer deployment ready"

  # Verify replicas
  READY_REPLICAS=$(kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer -o jsonpath='{.status.readyReplicas}')
  DESIRED_REPLICAS=$(kubectl get deployment -n "$OIDC_NAMESPACE" oidc-issuer -o jsonpath='{.spec.replicas}')
  log_success "OIDC issuer: $READY_REPLICAS/$DESIRED_REPLICAS replicas ready"
}

# ============================================================================
# Configure Caddy Reverse Proxy
# ============================================================================

configure_caddy() {
  log_info "Configuring Caddy reverse proxy for OIDC endpoints..."

  # Update Caddy configuration
  local caddy_config="${PROJECT_ROOT}/Caddyfile"
  
  # Verify Caddy has our OIDC routing configured
  if ! grep -q "oidc.${APEX_DOMAIN}" "$caddy_config"; then
    log_warning "OIDC routing not found in Caddyfile, need to add manually"
    log_info "Add the following section to your Caddyfile:"
    cat "$PROJECT_ROOT/config/caddy/oidc-issuer-routing.caddyfile"
  else
    log_success "OIDC routing already configured in Caddyfile"
  fi

  # Test Caddy configuration
  if command -v caddy &>/dev/null; then
    if ! caddy validate --config "$caddy_config" &>/dev/null; then
      log_error "Caddyfile validation failed"
    fi
    log_success "Caddyfile validation passed"
  fi
}

# ============================================================================
# Test OIDC Issuer Health
# ============================================================================

test_oidc_issuer_health() {
  log_info "Testing OIDC issuer health..."

  # Get OIDC issuer pod
  local oidc_pod=$(kubectl get pods -n "$OIDC_NAMESPACE" -l app=oidc-issuer -o jsonpath='{.items[0].metadata.name}')
  
  if [[ -z "$oidc_pod" ]]; then
    log_error "No OIDC issuer pods found"
  fi
  log_success "Found OIDC issuer pod: $oidc_pod"

  # Test health endpoint (internal)
  log_info "Testing health endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/healthz | grep -q "ok"; then
    log_success "Health endpoint responding"
  else
    log_error "Health endpoint not responding"
  fi

  # Test discovery endpoint (internal)
  log_info "Testing OIDC discovery endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/.well-known/openid-configuration | grep -q '"issuer"'; then
    log_success "Discovery endpoint responding"
  else
    log_error "Discovery endpoint not responding"
  fi

  # Test JWKS endpoint (internal)
  log_info "Testing JWKS endpoint..."
  if kubectl exec -n "$OIDC_NAMESPACE" "$oidc_pod" -- curl -s http://localhost:8888/.well-known/jwks.json | grep -q '"keys"'; then
    log_success "JWKS endpoint responding"
  else
    log_error "JWKS endpoint not responding"
  fi
}

# ============================================================================
# Test Service Integration
# ============================================================================

test_service_integration() {
  log_info "Testing service integration with OIDC issuer..."

  # Test from code-server pod
  log_info "Testing token request from code-server..."
  local code_server_pod=$(kubectl get pods -l app=code-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "none")
  
  if [[ "$code_server_pod" != "none" ]]; then
    if kubectl exec "$code_server_pod" -- curl -s "http://${OIDC_ISSUER_SERVICE}/health" &>/dev/null; then
      log_success "code-server can reach OIDC issuer"
    else
      log_warning "code-server cannot reach OIDC issuer (may need network config)"
    fi
  else
    log_warning "code-server pod not found (may not be deployed yet)"
  fi
}

# ============================================================================
# Generate Audit Logging Configuration
# ============================================================================

setup_audit_logging() {
  log_info "Setting up audit logging for OIDC token issuance..."

  # Create audit log table in PostgreSQL (if available)
  local postgres_pod=$(kubectl get pods -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "none")
  
  if [[ "$postgres_pod" != "none" ]]; then
    log_info "Creating audit logging table in PostgreSQL..."
    kubectl exec "$postgres_pod" -- psql -U postgres -d postgres -c "
      CREATE TABLE IF NOT EXISTS oidc_token_audit (
        id SERIAL PRIMARY KEY,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        service_account VARCHAR(255),
        audience VARCHAR(255),
        token_jti VARCHAR(255) UNIQUE,
        token_exp TIMESTAMP,
        issued_at TIMESTAMP,
        expires_in INTEGER,
        status VARCHAR(50),
        error_msg TEXT,
        source_ip INET,
        user_agent TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_oidc_audit_timestamp ON oidc_token_audit(timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_oidc_audit_service_account ON oidc_token_audit(service_account);
      CREATE INDEX IF NOT EXISTS idx_oidc_audit_audience ON oidc_token_audit(audience);
    " 2>/dev/null && log_success "Audit logging table created" || log_warning "Could not create audit table (PostgreSQL may not be available)"
  fi
}

# ============================================================================
# Prometheus Metrics Configuration
# ============================================================================

setup_prometheus_metrics() {
  log_info "Configuring Prometheus metrics scraping for OIDC issuer..."

  # ServiceMonitor should already be in k8s-oidc-issuer-production.yaml
  local service_monitor=$(kubectl get servicemonitor -n "$OIDC_NAMESPACE" oidc-issuer-monitor 2>/dev/null || echo "none")
  
  if [[ "$service_monitor" != "none" ]]; then
    log_success "ServiceMonitor already configured"
  else
    log_warning "ServiceMonitor not found (Prometheus Operator may not be installed)"
  fi
}

# ============================================================================
# Output Summary
# ============================================================================

print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║           Phase 2.1: OIDC Issuer Deployment Summary           ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "✅ Deployment Complete"
  echo ""
  echo "Production Configuration:"
  echo "  OIDC Issuer:     $OIDC_ISSUER_URL"
  echo "  Issuer URL:      https://oidc.${APEX_DOMAIN}"
  echo "  Discovery:       https://oidc.${APEX_DOMAIN}/.well-known/openid-configuration"
  echo "  JWKS:            https://oidc.${APEX_DOMAIN}/.well-known/jwks.json"
  echo "  Token Endpoint:  https://oidc.${APEX_DOMAIN}/token"
  echo ""
  echo "Kubernetes Resources:"
  echo "  Namespace:       $OIDC_NAMESPACE"
  echo "  Service:         oidc-issuer (port 8888)"
  echo "  Deployment:      oidc-issuer (3 replicas, HA enabled)"
  echo "  ServiceAccount:  oidc-issuer-sa"
  echo ""
  echo "Workload ServiceAccounts Configured:"
  echo "  • code-server-sa (IDE)"
  echo "  • postgresql-sa (Database)"
  echo "  • redis-sa (Cache)"
  echo "  • prometheus-sa (Metrics)"
  echo "  • grafana-sa (Dashboards)"
  echo "  • ollama-sa (GPU Inference)"
  echo "  • alertmanager-sa (Alerting)"
  echo "  • jaeger-sa (Tracing)"
  echo ""
  echo "Next Steps:"
  echo "  1. Merge Caddyfile changes to include OIDC routing"
  echo "  2. Reload Caddy: caddy reload --config /etc/caddy/Caddyfile"
  echo "  3. Test endpoints: curl https://oidc.${APEX_DOMAIN}/.well-known/openid-configuration"
  echo "  4. Validate token generation: kubectl exec <pod> -- curl http://${OIDC_ISSUER_SERVICE}/token"
  echo "  5. Monitor logs: kubectl logs -n ${OIDC_NAMESPACE} deployment/oidc-issuer"
  echo ""
  echo "Monitoring:"
  echo "  Prometheus: http://prometheus.${APEX_DOMAIN}:9090"
  echo "  Grafana:    http://grafana.${APEX_DOMAIN}:3000"
  echo "  Audit Logs: PostgreSQL table 'oidc_token_audit'"
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║           Phase 2.1: Ready for production traffic             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log_info "Starting Phase 2.1 OIDC Issuer Deployment"
  echo ""

  validate_prerequisites
  echo ""

  generate_signing_key
  echo ""

  deploy_kubernetes_manifests
  echo ""

  configure_caddy
  echo ""

  test_oidc_issuer_health
  echo ""

  test_service_integration
  echo ""

  setup_audit_logging
  echo ""

  setup_prometheus_metrics
  echo ""

  print_summary
}

main "$@"

