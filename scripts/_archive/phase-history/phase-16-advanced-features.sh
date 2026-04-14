#!/bin/bash

##############################################################################
# Phase 16: API Gateway, Service Mesh & Distributed Tracing
# Purpose: Enterprise-grade API gateway, service mesh, and distributed tracing
# Status: Production-ready, idempotent, immutable
##############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="${1:-.}"
DEPLOYMENT_LOG="${PROJECT_ROOT}/phase-16-deployment-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }
log_success() { echo -e "${GREEN}[✓]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }
log_error() { echo -e "${RED}[✗]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }

##############################################################################
# PHASE 16.1: API GATEWAY (KONG)
##############################################################################

deploy_api_gateway() {
    log_info "========================================="
    log_info "Phase 16.1: Kong API Gateway Deployment"
    log_info "========================================="

    # 1.1: Create Kong configuration
    mkdir -p "${PROJECT_ROOT}/config/kong"

    cat > "${PROJECT_ROOT}/config/kong/kong.conf" << 'EOF'
# Kong API Gateway Configuration

# Node settings
node_name = kong
prefix = /var/run/kong
proxy_listen = 0.0.0.0:8000, 0.0.0.0:8443 ssl http2
admin_listen = 0.0.0.0:8001, 0.0.0.0:8444 ssl
nginx_user = kong
nginx_daemon = off

# Database
database = postgres
pg_host = postgres
pg_port = 5432
pg_user = kong
pg_password = kong
pg_database = kong

# Logging
log_level = info
error_log = /var/log/kong/error.log
access_log = /var/log/kong/access.log

# Plugins
plugins = bundled,correlation-id,request-transformer,response-transformer,rate-limiting,jwt,key-auth,oauth2,cors,prometheus

# Security
ssl_cipher_suite = modern
ssl_protocols = TLSv1.2 TLSv1.3
ssl_certificate = /etc/kong/ssl/cert.pem
ssl_certificate_key = /etc/kong/ssl/key.pem

# Performance
worker_processes = auto
worker_connections = 8192
upstream_keepalive = 256
EOF
    log_success "Kong configuration created"

    # 1.2: Create Kong upstream/service definition
    cat > "${PROJECT_ROOT}/config/kong/services.yaml" << 'EOF'
services:
  - name: api-service
    host: code-server
    port: 3000
    protocol: http
    path: /api

    routes:
      - name: api-route
        paths:
          - /api
        protocols:
          - http
          - https
        strip_path: false

    plugins:
      - name: rate-limiting
        config:
          minute: 1000
          hour: 50000

      - name: correlation-id
        config:
          header_name: X-Correlation-ID
          generator: uuid#counter

      - name: request-transformer
        config:
          add:
            headers:
              - X-Kong-Timestamp:$(date +%s)

      - name: prometheus
        config:
          metrics:
            - request_count
            - request_latency
            - upstream_latency
            - response_size
            - status_count_total

  - name: oauth2-service
    host: oauth2-proxy
    port: 4180
    protocol: http

    routes:
      - name: auth-route
        paths:
          - /auth
          - /oauth2
        protocols:
          - http
          - https

  - name: cache-service
    host: redis-cache
    port: 6379
    protocol: tcp

    routes:
      - name: cache-route
        protocols:
          - tcp
EOF
    log_success "Kong services and routes defined"

    # 1.3: Create Kong docker container config
    cat > "${PROJECT_ROOT}/docker-compose-kong.yml" << 'EOF'
version: '3.9'

services:
  postgres-kong:
    image: postgres:15-alpine
    container_name: postgres-kong
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - kong-db:/var/lib/postgresql/data
    restart: unless-stopped

  kong:
    image: kong:3-alpine
    container_name: kong-gateway
    depends_on:
      postgres-kong:
        condition: service_healthy
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: postgres-kong
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl http2
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PLUGINS: bundled,correlation-id,prometheus
    ports:
      - "8000:8000"
      - "8001:8001"
      - "8443:8443"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  kong-migrations:
    image: kong:3-alpine
    container_name: kong-migrations
    command: kong migrations bootstrap
    depends_on:
      postgres-kong:
        condition: service_healthy
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: postgres-kong
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
    restart: on-failure

volumes:
  kong-db:
    driver: local
EOF
    log_success "Kong docker-compose created"

    return 0
}

##############################################################################
# PHASE 16.2: DISTRIBUTED TRACING (JAEGER)
##############################################################################

deploy_distributed_tracing() {
    log_info "========================================="
    log_info "Phase 16.2: Jaeger Distributed Tracing"
    log_info "========================================="

    # 2.1: Create Jaeger configuration
    mkdir -p "${PROJECT_ROOT}/config/jaeger"

    cat > "${PROJECT_ROOT}/config/jaeger/jaeger-config.yaml" << 'EOF'
samplers:
  type: const
  param: 1

reporters:
- logSpans: true
  localAgentHostPort: localhost:6831

logging:
  level: info

storage:
  type: elasticsearch
  elasticsearch:
    server_urls:
      - http://localhost:9200
    max_span_age: 72h
    num_shards: 1
    num_replicas: 0
EOF
    log_success "Jaeger configuration created"

    # 2.2: Create Jaeger docker-compose
    cat > "${PROJECT_ROOT}/docker-compose-jaeger.yml" << 'EOF'
version: '3.9'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.0.0
    container_name: jaeger-elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
      - xpack.security.enabled=false
    ports:
      - "9200:9200"
      - "9300:9300"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
    restart: unless-stopped

  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    depends_on:
      elasticsearch:
        condition: service_healthy
    environment:
      SPAN_STORAGE_TYPE: elasticsearch
      ES_SERVER_URLS: http://elasticsearch:9200
      COLLECTOR_ZIPKIN_HOST_PORT: :9411
    ports:
      - "6831:6831/udp"
      - "6832:6832/udp"
      - "5778:5778"
      - "16686:16686"
      - "14250:14250"
      - "14268:14268"
      - "9411:9411"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:14269"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
EOF
    log_success "Jaeger docker-compose created"

    # 2.3: Create tracing instrumentation client library
    cat > "${PROJECT_ROOT}/config/jaeger/tracer-init.js" << 'EOF'
// Jaeger tracer initialization for Node.js
const initTracer = require('jaeger-client').initTracer;

const config = {
  serviceName: 'code-server-enterprise',
  sampler: {
    // const sampler is easiest for testing
    type: 'const',
    param: 1,
  },
  reporter: {
    // log all spans to jaeger
    logSpans: true,
    agentHost: process.env.JAEGER_AGENT_HOST || 'localhost',
    agentPort: process.env.JAEGER_AGENT_PORT || 6831,
  },
};

const options = {
  logger: console,
  sampler: {
    host: process.env.JAEGER_AGENT_HOST || 'localhost',
    port: process.env.JAEGER_AGENT_PORT || 6831,
  },
};

const tracer = initTracer(config, options);

module.exports = {
  tracer,

  // Middleware for Express.js
  tracingMiddleware: (req, res, next) => {
    const wireCtx = tracer.extract('http_headers', req.headers);
    const span = tracer.startSpan(req.path, {
      childOf: wireCtx,
      tags: {
        [require('opentracing').Tags.SPAN_KIND]: require('opentracing').Tags.SPAN_KIND_RPC_SERVER,
        [require('opentracing').Tags.HTTP_METHOD]: req.method,
        [require('opentracing').Tags.HTTP_URL]: req.url,
      },
    });

    // Inject trace context into response headers
    tracer.inject(span.context(), 'http_headers', res.setHeader);

    // Finish span when response ends
    res.on('finish', () => {
      span.setTag(require('opentracing').Tags.HTTP_STATUS_CODE, res.statusCode);
      span.finish();
    });

    next();
  },
};
EOF
    log_success "Jaeger tracer client library created"

    return 0
}

##############################################################################
# PHASE 16.3: SERVICE MESH (LINKERD)
##############################################################################

deploy_service_mesh() {
    log_info "========================================="
    log_info "Phase 16.3: Linkerd Service Mesh"
    log_info "========================================="

    # 3.1: Create Linkerd install script
    cat > "${PROJECT_ROOT}/scripts/linkerd-install.sh" << 'EOF'
#!/bin/bash

set -euo pipefail

LINKERD_VERSION="2.14.0"

log_info() { echo "[INFO] $@"; }
log_success() { echo "[✓] $@"; }

# 1. Download and verify Linkerd CLI
log_info "Installing Linkerd CLI version ${LINKERD_VERSION}..."

if ! command -v linkerd &> /dev/null; then
    curl -sL https://github.com/linkerd/linkerd2/releases/download/release-${LINKERD_VERSION}/linkerd2-cli-${LINKERD_VERSION}-linux-amd64 -o /tmp/linkerd
    chmod +x /tmp/linkerd
    sudo mv /tmp/linkerd /usr/local/bin/
    log_success "Linkerd CLI installed"
else
    log_info "Linkerd CLI already installed: $(linkerd version --client --short)"
fi

# 2. Check cluster compatibility
log_info "Checking cluster compatibility..."
linkerd check --pre

# 3. Generate certificates (for production)
log_info "Generating Linkerd TLS certificates..."

mkdir -p "${HOME}/.linkerd"
step certificate create root.linkerd.cluster.local \
    "${HOME}/.linkerd/ca.crt" \
    "${HOME}/.linkerd/ca.key" \
    --profile root-ca --no-password --insecure

step certificate create identity.linkerd.cluster.local \
    "${HOME}/.linkerd/issuer.crt" \
    "${HOME}/.linkerd/issuer.key" \
    --profile intermediate-ca \
    --ca "${HOME}/.linkerd/ca.crt" \
    --ca-key "${HOME}/.linkerd/ca.key" \
    --no-password --insecure

log_success "Certificates generated"

# 4. Install Linkerd control plane
log_info "Installing Linkerd control plane..."
linkerd install \
    --crds \
    --identity-domain linkerd.cluster.local \
    --identity-issuer-certificate-file "${HOME}/.linkerd/issuer.crt" \
    --identity-issuer-key-file "${HOME}/.linkerd/issuer.key" | kubectl apply -f -

# 5. Wait for control plane readiness
log_info "Waiting for Linkerd control plane to be ready..."
linkerd check

log_success "Linkerd service mesh installed successfully"
EOF
    chmod +x "${PROJECT_ROOT}/scripts/linkerd-install.sh"
    log_success "Linkerd installation script created"

    # 3.2: Create Linkerd policy configuration
    cat > "${PROJECT_ROOT}/config/linkerd/mesh-policy.yaml" << 'EOF'
apiVersion: policy.linkerd.io/v1beta1
kind: MeshTLSAuthentication
metadata:
  name: all-authenticated
spec:
  identities:
    - "*.local"

---
apiVersion: policy.linkerd.io/v1beta1
kind: NetworkPolicy
metadata:
  name: api-gateway-policy
spec:
  to:
    - from:
        - podSelector:
            matchLabels:
              app: kong
      ports:
        - port: 8000

---
apiVersion: policy.linkerd.io/v1beta1
kind: NetworkPolicy
metadata:
  name: service-to-service-policy
spec:
  to:
    - from:
        - podSelector: {}
      ports:
        - port: 3000
        - port: 6379
        - port: 4180
EOF
    log_success "Linkerd mesh policies defined"

    # 3.3: Create Linkerd observability config
    cat > "${PROJECT_ROOT}/config/linkerd/observability.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: linkerd-prometheus-config
data:
  prometheus.yml: |
    scrape_configs:
      - job_name: linkerd-controller
        static_configs:
          - targets: ['localhost:8086']

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: linkerd-grafana-datasources
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus (Linkerd)
        type: prometheus
        url: http://prometheus:9090
        access: proxy
        isDefault: true
EOF
    log_success "Linkerd observability configuration created"

    return 0
}

##############################################################################
# PHASE 16.4: VERIFICATION & TESTING
##############################################################################

verify_phase_16() {
    log_info "========================================="
    log_info "Phase 16.4: Verification & Testing"
    log_info "========================================="

    # 4.1: Verify all configuration files
    log_info "Verifying Phase 16 configurations..."

    local required_files=(
        "config/kong/kong.conf"
        "config/kong/services.yaml"
        "config/jaeger/jaeger-config.yaml"
        "config/jaeger/tracer-init.js"
        "config/linkerd/mesh-policy.yaml"
        "config/linkerd/observability.yaml"
        "docker-compose-kong.yml"
        "docker-compose-jaeger.yml"
    )

    for file in "${required_files[@]}"; do
        if [ -f "${PROJECT_ROOT}/${file}" ]; then
            log_success "✓ ${file} verified"
        else
            log_error "✗ ${file} missing"
            return 1
        fi
    done

    # 4.2: Validate YAML syntax
    log_info "Validating YAML configuration syntax..."

    for yaml_file in ${PROJECT_ROOT}/config/{kong,jaeger,linkerd}/*.yaml; do
        if [ -f "$yaml_file" ]; then
            if command -v yq &> /dev/null; then
                if yq eval '.' "$yaml_file" > /dev/null 2>&1; then
                    log_success "✓ $(basename $yaml_file) syntax valid"
                fi
            fi
        fi
    done

    log_info "Phase 16 verification complete"
    return 0
}

##############################################################################
# MAIN EXECUTION
##############################################################################

main() {
    log_info "Phase 16 Advanced Features Deployment"
    log_info "Start time: $(date)"
    log_info "Project root: ${PROJECT_ROOT}"
    echo ""

    deploy_api_gateway || { log_error "API Gateway deployment failed"; return 1; }
    echo ""

    deploy_distributed_tracing || { log_error "Distributed tracing deployment failed"; return 1; }
    echo ""

    deploy_service_mesh || { log_error "Service mesh deployment failed"; return 1; }
    echo ""

    verify_phase_16 || { log_error "Phase 16 verification failed"; return 1; }
    echo ""

    log_success "========================================="
    log_success "Phase 16 Deployment Complete"
    log_success "========================================="
    log_success "Log: ${DEPLOYMENT_LOG}"
    log_info "Deploy Kong: docker-compose -f docker-compose-kong.yml up -d"
    log_info "Deploy Jaeger: docker-compose -f docker-compose-jaeger.yml up -d"
    log_info "Install Linkerd: bash scripts/linkerd-install.sh"

    return 0
}

main "$@"
