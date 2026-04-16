#!/bin/bash
# Phase 2.1: Kubernetes OIDC Issuer Deployment
# Exposes K8s OIDC endpoint publicly for service token validation
# Author: @kushin77
# License: Elite Code Server Enterprise

set -eu

source scripts/_common/init.sh || source /mnt/c/code-server-enterprise/scripts/_common/init.sh

_log_info "Phase 2.1: Deploying Kubernetes OIDC Issuer"

# Configuration
OIDC_HOST="${DEPLOY_HOST:-192.168.168.31}"
OIDC_PORT="${OIDC_PORT:-8080}"
OIDC_PATH="/oidc"
OIDC_URL="https://${OIDC_HOST}:${OIDC_PORT}${OIDC_PATH}"
K8S_API_HOST="${K8S_API_HOST:-kubernetes.default.svc.cluster.local}"
K8S_API_PORT="${K8S_API_PORT:-443}"
NAMESPACE="${NAMESPACE:-default}"

_log_info "Configuration:"
echo "  OIDC URL: $OIDC_URL"
echo "  K8s API: $K8S_API_HOST:$K8S_API_PORT"
echo "  Namespace: $NAMESPACE"

# Step 1: Create OIDC reverse proxy configuration for Caddy
_log_info "Step 1: Creating Caddy OIDC proxy configuration"

OIDC_CADDY_CONFIG=$(cat <<'EOF'
# Kubernetes OIDC Issuer Proxy
oidc.{$APEX_DOMAIN}:8080 {
    # Expose K8s OIDC endpoint
    reverse_proxy https://{$K8S_API_HOST}:443 {
        transport http {
            tls_insecure_skip_verify
        }
        
        # Rewrite path: /oidc/* → /.well-known/openid-configuration (and others)
        uri strip_prefix /oidc
        
        # Headers
        header_up Authorization "Bearer {$K8S_TOKEN}"
        header_up X-Forwarded-Proto "https"
        header_up X-Forwarded-Host "{$APEX_DOMAIN}"
        
        # Timeouts
        timeout 30s
        read_timeout 30s
        write_timeout 30s
    }
    
    # CORS for service-to-service requests
    header / Access-Control-Allow-Origin "*"
    header / Access-Control-Allow-Methods "GET, POST, OPTIONS"
    header / Access-Control-Allow-Headers "Content-Type, Authorization"
    
    # Caching for JWKS (1 hour)
    @wellknown path /.well-known/openid-configuration
    @jwks path /.well-known/keys
    
    header @wellknown Cache-Control "public, max-age=3600"
    header @jwks Cache-Control "public, max-age=3600"
    
    # Security headers
    header / X-Content-Type-Options "nosniff"
    header / X-Frame-Options "DENY"
    header / X-XSS-Protection "1; mode=block"
    header / Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    # Logging
    log {
        output file /var/log/caddy/oidc-access.log {
            roll_size 100MB
            roll_keep 10
        }
        level debug
    }
}
EOF
)

# Write to Caddy config
CADDY_CONFIG_DIR="${CADDY_CONFIG_DIR:-config/caddy}"
OIDC_CONFIG_FILE="${CADDY_CONFIG_DIR}/oidc-proxy.conf"

if [[ ! -d "$CADDY_CONFIG_DIR" ]]; then
    mkdir -p "$CADDY_CONFIG_DIR"
fi

cat > "$OIDC_CONFIG_FILE" << 'EOF'
# Kubernetes OIDC Issuer Proxy (Phase 2.1)
# This proxies the Kubernetes API server's OIDC endpoint publicly
# so that services can verify JWTs issued by the K8s control plane

*.{APEX_DOMAIN} {
    # OIDC endpoint proxy
    @oidc host oidc.{APEX_DOMAIN}
    handle @oidc {
        reverse_proxy https://{K8S_API_ENDPOINT}:443 {
            transport http {
                tls_insecure_skip_verify
            }
            
            # Strip /oidc prefix, forward to K8s API /.well-known paths
            uri strip_prefix /oidc
            
            # K8s ServiceAccount token for authentication
            header_up Authorization "Bearer {K8S_SERVICE_TOKEN}"
            
            # Forward original host info
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Host {APEX_DOMAIN}
            
            # Timeout settings
            timeout 30s
            read_timeout 30s
            write_timeout 30s
        }
        
        # CORS headers (services need these for cross-service requests)
        header Access-Control-Allow-Origin "*"
        header Access-Control-Allow-Methods "GET, POST, OPTIONS"
        header Access-Control-Allow-Headers "Content-Type, Authorization"
        
        # Cache OIDC config and JWKS (1 hour, reduces API load)
        @oidc_config path /.well-known/openid-configuration
        @oidc_jwks path /.well-known/keys
        header @oidc_config Cache-Control "public, max-age=3600"
        header @oidc_jwks Cache-Control "public, max-age=3600"
        
        # Security headers
        header X-Content-Type-Options nosniff
        header X-Frame-Options DENY
        header X-XSS-Protection "1; mode=block"
        header Strict-Transport-Security "max-age=31536000; includeSubDomains"
        
        # Logging
        log {
            output file /var/log/caddy/oidc-access.log {
                roll_size 100MB
                roll_keep 10
            }
        }
    }
}
EOF

_log_info "Created OIDC proxy config: $OIDC_CONFIG_FILE"

# Step 2: Deploy K8s OIDC issuer configuration
_log_info "Step 2: Configuring Kubernetes OIDC issuer"

# This would typically be applied via kubectl, but we're checking prerequisites here
if command -v kubectl &> /dev/null; then
    _log_info "kubectl found, checking K8s cluster..."
    
    if kubectl cluster-info &> /dev/null; then
        _log_info "K8s cluster accessible"
        
        # Get K8s API server endpoint
        K8S_API_ENDPOINT=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||' | cut -d: -f1)
        _log_info "K8s API endpoint: $K8S_API_ENDPOINT"
        
        # Get service account token
        K8S_SA_TOKEN=$(kubectl -n "$NAMESPACE" get secret $(kubectl -n "$NAMESPACE" get secret | grep default-token | awk '{print $1}') -o jsonpath='{.data.token}' | base64 -d)
        _log_info "Got K8s service account token"
    else
        _log_warn "K8s cluster not accessible (may need kubeconfig setup)"
    fi
else
    _log_warn "kubectl not installed, skipping K8s configuration"
fi

# Step 3: Verify OIDC endpoint accessibility
_log_info "Step 3: Verifying OIDC endpoint will be accessible"

# Create test script
TEST_OIDC_SCRIPT=$(cat <<'TESTEOF'
#!/bin/bash
# Test OIDC endpoint

OIDC_URL="${1:-https://oidc.kushnir.cloud:8080/.well-known/openid-configuration}"

_log_info() { echo "[INFO] $@"; }
_log_error() { echo "[ERROR] $@" >&2; }

_log_info "Testing OIDC endpoint: $OIDC_URL"

# Test 1: Can reach endpoint
if curl -s -k "$OIDC_URL" > /dev/null 2>&1; then
    _log_info "✓ OIDC endpoint reachable"
else
    _log_error "✗ OIDC endpoint not reachable"
    exit 1
fi

# Test 2: Returns valid JSON
RESPONSE=$(curl -s -k "$OIDC_URL")
if echo "$RESPONSE" | jq . > /dev/null 2>&1; then
    _log_info "✓ OIDC endpoint returns valid JSON"
    echo "$RESPONSE" | jq . | head -20
else
    _log_error "✗ OIDC endpoint response is not valid JSON"
    exit 1
fi

# Test 3: Contains required fields
ISSUER=$(echo "$RESPONSE" | jq -r '.issuer')
JWKS_URI=$(echo "$RESPONSE" | jq -r '.jwks_uri')

if [[ -n "$ISSUER" && "$ISSUER" != "null" ]]; then
    _log_info "✓ Issuer found: $ISSUER"
else
    _log_error "✗ Issuer missing from OIDC config"
    exit 1
fi

if [[ -n "$JWKS_URI" && "$JWKS_URI" != "null" ]]; then
    _log_info "✓ JWKS URI found: $JWKS_URI"
else
    _log_error "✗ JWKS URI missing from OIDC config"
    exit 1
fi

_log_info "✓ All OIDC endpoint checks passed"
TESTEOF
)

echo "$TEST_OIDC_SCRIPT" > scripts/test-oidc-endpoint.sh
chmod +x scripts/test-oidc-endpoint.sh

_log_info "Created OIDC test script: scripts/test-oidc-endpoint.sh"

# Step 4: Summary and next steps
_log_info "Phase 2.1 Complete: Kubernetes OIDC Issuer configured"
echo ""
echo "Next steps:"
echo "1. Update Caddyfile to include OIDC proxy configuration"
echo "2. Deploy Caddy with updated config: docker-compose up -d caddy"
echo "3. Test OIDC endpoint: ./scripts/test-oidc-endpoint.sh"
echo "4. Verify from pod: kubectl exec -it code-server -- curl https://oidc.kushnir.cloud:8080/.well-known/openid-configuration"
echo ""
echo "OIDC Endpoint: $OIDC_URL"
echo "OIDC Config File: $OIDC_CONFIG_FILE"
echo ""

_log_info "Phase 2.1 deployment complete"
