#!/bin/bash
# Phase 2.1: Kubernetes OIDC Issuer Deployment (v2 - Fixed)
# Exposes K8s OIDC endpoint publicly for service token validation
# Author: @kushin77
# License: Elite Code Server Enterprise

set -euo pipefail

# Direct logging (avoid init.sh dependency)
log_info()  { echo "[INFO]  $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >&2; }
log_success() { echo "[✓]  $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >&2; }
log_error() { echo "[ERROR] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >&2; }

trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE2_DIR="$ROOT_DIR/config/iam"

# Load shared defaults when available.
if [[ -f "$SCRIPT_DIR/_common/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/_common/config.sh"
fi

# Configuration
OIDC_HOST="${OIDC_HOST:-${DEPLOY_HOST:-localhost}}"
OIDC_PORT="${OIDC_PORT:-8080}"
OIDC_PATH="/oidc"
OIDC_URL="https://${OIDC_HOST}:${OIDC_PORT}${OIDC_PATH}"
K8S_API_HOST="${K8S_API_HOST:-kubernetes.default.svc.cluster.local}"
K8S_API_PORT="${K8S_API_PORT:-443}"
NAMESPACE="${NAMESPACE:-default}"
CADDY_CONFIG="$ROOT_DIR/config/caddy"

mkdir -p "$PHASE2_DIR" "$CADDY_CONFIG"

log_info "═══════════════════════════════════════════════════════════════"
log_info "Phase 2.1: Kubernetes OIDC Issuer Deployment"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_info "Configuration:"
log_info "  OIDC Host: $OIDC_HOST"
log_info "  OIDC Port: $OIDC_PORT"
log_info "  OIDC URL: $OIDC_URL"
log_info "  K8s API: $K8S_API_HOST:$K8S_API_PORT"
log_info ""

# Step 1: Generate Caddy OIDC reverse proxy configuration
log_info "Step 1: Generating Caddy reverse proxy configuration..."
cat > "$CADDY_CONFIG/oidc-proxy.caddyfile" <<'CADDY_EOF'
# OIDC Issuer Reverse Proxy (Phase 2.1)
# Exposes Kubernetes OIDC endpoint publicly

oidc.{$APEX_DOMAIN} {
    # Reverse proxy to K8s OIDC endpoint
    reverse_proxy kubernetes.default.svc.cluster.local:443 {
        transport http {
            tls
            tls_insecure_skip_verify
        }
        uri /oidc/*
        path_regexp ^/oidc/(.*)$
        replace_uri /openid/$1
    }

    # Well-known OIDC configuration endpoint
    route /.well-known/openid-configuration {
        reverse_proxy kubernetes.default.svc.cluster.local:443 {
            transport http {
                tls
                tls_insecure_skip_verify
            }
            uri /.well-known/openid-configuration
        }
    }

    # JWKS endpoint for token validation
    route /.well-known/openid-configuration/jwks {
        reverse_proxy kubernetes.default.svc.cluster.local:443 {
            transport http {
                tls
                tls_insecure_skip_verify
            }
            uri /openid/v1/jwks
        }
    }

    # Security headers
    header X-Content-Type-Options nosniff
    header X-Frame-Options DENY
    header X-XSS-Protection "1; mode=block"
    header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

    # CORS for cross-service access
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, OPTIONS"
    header Access-Control-Allow-Headers "Content-Type, Authorization"

    # Enable TLS
    tls {$TLS_EMAIL} {
        dns cloudflare {$CLOUDFLARE_API_TOKEN}
    }

    # Logging
    log {
        output file /var/log/caddy/oidc-proxy.log {
            roll_size 100mb
            roll_keep 5
        }
        level debug
    }
}
CADDY_EOF
log_success "Generated: $CADDY_CONFIG/oidc-proxy.caddyfile"
log_info ""

# Step 2: Generate K8s OIDC configuration
log_info "Step 2: Generating Kubernetes OIDC configuration..."
cat > "$PHASE2_DIR/k8s-oidc-issuer.yaml" <<'K8S_EOF'
# Kubernetes OIDC Issuer Configuration (Phase 2.1)
# Enables JWT token generation for service-to-service authentication

apiVersion: v1
kind: ConfigMap
metadata:
  name: oidc-issuer-config
  namespace: default
data:
  issuer: "https://oidc.kushnir.cloud:8080"
  client_id: "code-server-services"
  audiences: "code-server,prometheus,loki,grafana,redis,postgresql"
  subject_claim: "sub"
  username_claim: "preferred_username"
  groups_claim: "groups"

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oidc-issuer
  namespace: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: oidc-issuer
  namespace: default
rules:
- apiGroups: [""]
  resources: ["serviceaccounts"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: oidc-issuer
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: oidc-issuer
subjects:
- kind: ServiceAccount
  name: oidc-issuer
  namespace: default
K8S_EOF
log_success "Generated: $PHASE2_DIR/k8s-oidc-issuer.yaml"
log_info ""

# Step 3: Generate test script
log_info "Step 3: Generating OIDC endpoint test script..."
cat > "$SCRIPT_DIR/test-oidc-endpoint.sh" <<'TEST_EOF'
#!/bin/bash
set -euo pipefail

OIDC_HOST="${1:-${DEPLOY_HOST:-localhost}}"
OIDC_PORT="${2:-8080}"
OIDC_URL="https://${OIDC_HOST}:${OIDC_PORT}"

echo "Testing OIDC endpoint: $OIDC_URL"
echo ""

echo "[1] Testing well-known/openid-configuration..."
curl -fsS "${OIDC_URL}/.well-known/openid-configuration" | jq . || echo "FAILED: OIDC config endpoint"

echo ""
echo "[2] Testing jwks endpoint..."
curl -fsS "${OIDC_URL}/.well-known/jwks.json" | jq . || echo "FAILED: JWKS endpoint"

echo ""
echo "[3] Testing health check..."
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" "${OIDC_URL}/health" || echo "FAILED: Health endpoint"

echo ""
echo "✓ OIDC endpoint tests complete"
TEST_EOF
chmod +x "$SCRIPT_DIR/test-oidc-endpoint.sh"
log_success "Generated: $SCRIPT_DIR/test-oidc-endpoint.sh"
log_info ""

# Step 4: Update docker-compose to include OIDC proxy
log_info "Step 4: Checking Caddyfile for OIDC configuration..."
if ! grep -q "oidc-proxy" "$CADDY_CONFIG/Caddyfile" 2>/dev/null; then
    log_info "  Adding OIDC proxy configuration to Caddyfile..."
    cat >> "$CADDY_CONFIG/Caddyfile" <<'EOF'

# Phase 2.1: OIDC Issuer Reverse Proxy
import oidc-proxy.caddyfile
EOF
    log_success "Added OIDC proxy to Caddyfile"
else
    log_success "OIDC proxy already configured in Caddyfile"
fi
log_info ""

# Step 5: Generate environment configuration
log_info "Step 5: Generating environment configuration..."
cat > "$PHASE2_DIR/oidc-issuer.env.template" <<'ENV_EOF'
# Phase 2.1: OIDC Issuer Configuration

# Public OIDC issuer URL
OIDC_ISSUER_URL=https://oidc.kushnir.cloud:8080

# Token configuration
TOKEN_EXPIRY=3600  # 1 hour
TOKEN_REFRESH_LEEWAY=300  # 5 minutes before expiry
TOKEN_AUDIENCE=code-server,prometheus,loki,grafana,redis,postgresql

# Service authentication
SERVICE_IDENTITY_NAMESPACE=default
SERVICE_ACCOUNT_NAME=oidc-issuer

# JWKS caching (for performance)
JWKS_CACHE_TTL=3600  # 1 hour
JWKS_REFRESH_INTERVAL=1800  # 30 minutes

# Logging
LOG_LEVEL=info
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/kubernetes/oidc-audit.log
ENV_EOF
log_success "Generated: $PHASE2_DIR/oidc-issuer.env.template"
log_info ""

# Final summary
log_info "═══════════════════════════════════════════════════════════════"
log_info "Phase 2.1 OIDC Issuer Deployment - Configuration Complete"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_success "Generated files:"
log_success "  - Caddy proxy config: $CADDY_CONFIG/oidc-proxy.caddyfile"
log_success "  - K8s configuration: $PHASE2_DIR/k8s-oidc-issuer.yaml"
log_success "  - Environment template: $PHASE2_DIR/oidc-issuer.env.template"
log_success "  - Test script: $SCRIPT_DIR/test-oidc-endpoint.sh"
log_info ""
log_info "Next steps:"
log_info "  1. Deploy Caddy: docker-compose up -d caddy"
log_info "  2. Apply K8s config: kubectl apply -f $PHASE2_DIR/k8s-oidc-issuer.yaml"
log_info "  3. Test endpoint: bash $SCRIPT_DIR/test-oidc-endpoint.sh"
log_info "  4. Verify from pod: kubectl exec -it <pod> -- curl https://oidc.kushnir.cloud:8080/.well-known/openid-configuration"
log_info ""
log_success "✓ Phase 2.1 Configuration Ready for Deployment"
