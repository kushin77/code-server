#!/usr/bin/env bash
#
# P1 #388 - Phase 2: Workload Federation Setup Script
# Configures GitHub Actions OIDC, K8s OIDC issuer, and service account mappings
#

set -euo pipefail

# Source common logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config/iam"

mkdir -p "$CONFIG_DIR"

# ============================================================================
# SECTION 1: GitHub Actions OIDC Provider Configuration
# ============================================================================

configure_github_oidc() {
    log_info "Configuring GitHub Actions OIDC Provider..."
  local github_oidc_issuer="https://token.actions.githubusercontent.com"
    
    # This should be configured in Terraform (see terraform/iam.tf)
    # But we'll create environment-specific configuration here
    
    cat > "$PROJECT_ROOT/.env.github-oidc" <<'EOF'
# GitHub Actions OIDC Configuration
GITHUB_OIDC_ISSUER="https://token.actions.githubusercontent.com"
GITHUB_OIDC_AUDIENCE="kushin77/code-server"

# Token validation configuration
TOKEN_TTL_MAIN_BRANCH=900          # 15 minutes for main branch
TOKEN_TTL_PR_BRANCH=300            # 5 minutes for PR branches
TOKEN_TTL_RELEASE_TAG=600          # 10 minutes for release tags

# Subject claim patterns (GitHub Actions workflow identifiers)
SUBJECT_PATTERN_MAIN="repo:kushin77/code-server:ref:refs/heads/main"
SUBJECT_PATTERN_PR="repo:kushin77/code-server:pull_request"
SUBJECT_PATTERN_RELEASE="repo:kushin77/code-server:ref:refs/tags/v*"

# Role assignments
ROLE_MAIN_BRANCH="automation/operator"
ROLE_PR_BRANCH="automation/viewer"
ROLE_RELEASE="automation/operator"
EOF

  log_success "Created .env.github-oidc configuration"
    
    # Validate GitHub OIDC issuer is accessible
    log_info "Validating GitHub OIDC issuer..."
    if curl -fsS "$github_oidc_issuer/.well-known/openid-configuration" > /dev/null; then
        log_success "GitHub OIDC issuer is accessible"
    else
        log_error "Failed to reach GitHub OIDC issuer"
        return 1
    fi
}

# ============================================================================
# SECTION 2: Kubernetes OIDC Issuer Configuration
# ============================================================================

configure_kubernetes_oidc() {
    log_info "Configuring Kubernetes OIDC Issuer..."
    
    # K8s OIDC issuer URL (on-prem or cloud provider)
    # For on-prem with nip.io DNS: https://oidc.192.168.168.31.nip.io
    # For GKE: https://container.googleapis.com/v1/projects/{PROJECT_ID}/locations/{LOCATION}/clusters/{CLUSTER_NAME}
    
    cat > "$PROJECT_ROOT/.env.k8s-oidc" <<'EOF'
# Kubernetes OIDC Configuration (on-prem example)
K8S_OIDC_ISSUER="https://oidc.192.168.168.31.nip.io"
K8S_OIDC_DISCOVERY_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/openid-configuration"
K8S_OIDC_JWKS_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/jwks.json"

# Service account to role mappings
KUBE_SA_CODE_SERVER_ROLE="workload/viewer"
KUBE_SA_BACKSTAGE_ROLE="workload/operator"
KUBE_SA_APPSMITH_ROLE="workload/operator"
KUBE_SA_OLLAMA_ROLE="workload/viewer"
KUBE_SA_PROMETHEUS_ROLE="workload/viewer"
KUBE_SA_LOKI_ROLE="workload/viewer"
EOF

    log_success "Created .env.k8s-oidc configuration"
    
    # Create Kubernetes ServiceAccount manifests
    log_info "Creating K8s ServiceAccount manifests..."
    
    cat > "$PROJECT_ROOT/k8s-serviceaccounts.yaml" <<'EOF'
---
# Code-Server IDE (user sessions)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: prod
  labels:
    app: code-server
    iam-role: workload/viewer

---
# Backstage (software catalog)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backstage
  namespace: prod
  labels:
    app: backstage
    iam-role: workload/operator

---
# Appsmith (operational workflows)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: appsmith
  namespace: prod
  labels:
    app: appsmith
    iam-role: workload/operator

---
# Ollama (AI inference)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ollama
  namespace: prod
  labels:
    app: ollama
    iam-role: workload/viewer

---
# Prometheus (metrics collection)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
    iam-role: workload/viewer

---
# Loki (log aggregation)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: monitoring
  labels:
    app: loki
    iam-role: workload/viewer
EOF

    log_success "Created k8s-serviceaccounts.yaml"
}

# ============================================================================
# SECTION 3: Service Account to Role Mapping
# ============================================================================

create_service_account_mapping() {
    log_info "Creating Service Account to Role Mapping..."
    
    cat > "$CONFIG_DIR/k8s-serviceaccount-roles.yaml" <<'EOF'
# P1 #388 Phase 2 - K8s ServiceAccount to IAM Role Mapping
# Defines which K8s ServiceAccounts map to which application roles

apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-sa-role-mapping
  namespace: code-server-iam
data:
  
  # YAML structure: namespace/serviceaccount -> role + permissions
  mapping.yaml: |
    service_accounts:
      
      # Code-Server (IDE)
      - namespace: prod
        name: code-server
        role: workload/viewer
        permissions:
          - code-server:execute
          - logs:write
          - metrics:export
        identity_type: workload
        token_ttl_seconds: 3600
      
      # Backstage (Catalog)
      - namespace: prod
        name: backstage
        role: workload/operator
        permissions:
          - backstage:catalog
          - github:api
          - kubernetes:services
          - metrics:read
        identity_type: workload
        token_ttl_seconds: 3600
      
      # Appsmith (Workflows)
      - namespace: prod
        name: appsmith
        role: workload/operator
        permissions:
          - appsmith:workflows
          - deployments:execute
          - incidents:view
        identity_type: workload
        token_ttl_seconds: 3600
      
      # Ollama (AI)
      - namespace: prod
        name: ollama
        role: workload/viewer
        permissions:
          - ollama:inference
          - metrics:export
        identity_type: workload
        token_ttl_seconds: 7200
      
      # Prometheus (Monitoring)
      - namespace: monitoring
        name: prometheus
        role: workload/viewer
        permissions:
          - prometheus:scrape
          - kubernetes:pods
        identity_type: workload
        token_ttl_seconds: 3600
      
      # Loki (Logging)
      - namespace: monitoring
        name: loki
        role: workload/viewer
        permissions:
          - loki:write
          - kubernetes:pods
        identity_type: workload
        token_ttl_seconds: 3600
EOF

    log_success "Created k8s-serviceaccount-roles.yaml"
}

# ============================================================================
# SECTION 4: mTLS Certificate Configuration
# ============================================================================

configure_mtls() {
    log_info "Configuring mTLS Certificate Management..."
    
    cat > "$CONFIG_DIR/mtls-config.yaml" <<'EOF'
# P1 #388 Phase 2 - mTLS Configuration
# Auto-rotation of certificates for pod-to-pod encrypted communication

apiVersion: v1
kind: ConfigMap
metadata:
  name: mtls-config
  namespace: code-server-iam
data:
  
  ca-config.json: |
    {
      "signing": {
        "default": {
          "expiration": "87600h",
          "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
          ]
        }
      }
    }
  
  csr-config.json: |
    {
      "CN": "kushin-code-server-ca",
      "key": {
        "algo": "rsa",
        "size": 4096
      },
      "names": [
        {
          "C": "US",
          "ST": "CA",
          "L": "San Francisco",
          "O": "kushin"
        }
      ]
    }
  
  # Certificate rotation schedule
  rotation-policy.yaml: |
    rotation:
      enabled: true
      schedule: "monthly (1st of month at 00:00 UTC)"
      validity_days: 90
      auto_rotation_days: 30
      overlap_period: 24h  # Old cert valid for 24h after new one issued
      notification_days_before_expiry: 7

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: code-server-ca
  namespace: code-server-iam
spec:
  secretName: code-server-ca-secret
  duration: 87600h  # 10 years
  renewBefore: 720h  # 30 days
  commonName: "kushin-code-server-ca"
  isCA: true
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer

---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: code-server-iam
spec:
  selfSigned: {}
EOF

    log_success "Created mtls-config.yaml"
}

# ============================================================================
# SECTION 5: API Token Management
# ============================================================================

configure_api_tokens() {
    log_info "Configuring API Tokens..."
    
    cat > "$CONFIG_DIR/api-tokens-config.yaml" <<'EOF'
# P1 #388 Phase 2 - API Token Configuration
# Long-lived tokens for webhook integrations and external API calls

apiVersion: v1
kind: ConfigMap
metadata:
  name: api-tokens-config
  namespace: code-server-iam
data:
  
  token-policy.yaml: |
    token_management:
      
      generation:
        algorithm: HMAC-SHA256
        length_bytes: 32
        encoding: base64url
      
      storage:
        backend: kubernetes-secret
        encryption: AES-256-GCM
        access_control: RBAC
      
      rotation:
        enabled: true
        schedule: monthly
        notification_days_before: 7
        old_token_grace_period: 24 # hours
    
    token_types:
      
      github_webhook:
        name: GitHub Webhook Auth
        scope: ["github:webhook:verify"]
        validity_days: 365
        issuer: code-server-iam
      
      slack_webhook:
        name: Slack Webhook Auth
        scope: ["slack:webhook"]
        validity_days: 90
        issuer: code-server-iam
      
      datadog:
        name: DataDog Integration
        scope: ["datadog:events", "datadog:metrics"]
        validity_days: 365
        issuer: code-server-iam
      
      pagerduty:
        name: PagerDuty Integration
        scope: ["pagerduty:incidents"]
        validity_days: 90
        issuer: code-server-iam
      
      external_api:
        name: External API Token
        scope: ["external:api"]
        validity_days: 180
        issuer: code-server-iam

---
# Secret for GitHub webhook token
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-token
  namespace: code-server-iam
type: Opaque
stringData:
  token: "REPLACE_WITH_OPENSSL_BASE64_32"  # Generate during deploy and inject via secret manager
  expires_at: "2027-04-22T00:00:00Z"

---
# Secret for Slack webhook token
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook-token
  namespace: code-server-iam
type: Opaque
stringData:
  token: "REPLACE_WITH_OPENSSL_BASE64_32"  # Generate during deploy and inject via secret manager
  expires_at: "2026-07-22T00:00:00Z"
EOF

    log_success "Created api-tokens-config.yaml"
}

# ============================================================================
# SECTION 6: Token Validation Service Configuration
# ============================================================================

configure_token_validation_service() {
    log_info "Configuring Token Validation Service..."
    
    cat > "$CONFIG_DIR/token-validation-service.yaml" <<'EOF'
# P1 #388 Phase 2 - Token Validation Service
# Microservice for validating JWTs and API tokens

apiVersion: apps/v1
kind: Deployment
metadata:
  name: token-validation-service
  namespace: code-server-iam
spec:
  replicas: 3
  selector:
    matchLabels:
      app: token-validation-service
  template:
    metadata:
      labels:
        app: token-validation-service
    spec:
      serviceAccountName: token-validation-service
      containers:
      - name: token-validator
        image: code-server/token-validation-service:v1.0.0
        ports:
        - containerPort: 9000
        env:
        - name: OIDC_ISSUER_URL
          value: "https://accounts.google.com"
        - name: OIDC_JWKS_URL
          value: "https://www.googleapis.com/oauth2/v3/certs"
        - name: CACHE_TTL_SECONDS
          value: "300"
        - name: LOG_LEVEL
          value: "info"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 9000
          initialDelaySeconds: 10
          periodSeconds: 10
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"

---
apiVersion: v1
kind: Service
metadata:
  name: token-validation-service
  namespace: code-server-iam
spec:
  selector:
    app: token-validation-service
  ports:
  - name: http
    port: 9000
    targetPort: 9000
  type: ClusterIP

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: token-validation-service
  namespace: code-server-iam
EOF

    log_success "Created token-validation-service.yaml"
}

# ============================================================================
# SECTION 7: Validation and Testing
# ============================================================================

validate_configuration() {
    log_info "Validating Phase 2 Configuration..."
    
    # Check all required files exist
    local files=(
      "$PROJECT_ROOT/.env.github-oidc"
      "$PROJECT_ROOT/.env.k8s-oidc"
      "$PROJECT_ROOT/k8s-serviceaccounts.yaml"
      "$CONFIG_DIR/k8s-serviceaccount-roles.yaml"
      "$CONFIG_DIR/mtls-config.yaml"
      "$CONFIG_DIR/api-tokens-config.yaml"
      "$CONFIG_DIR/token-validation-service.yaml"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            log_success "✓ $file exists"
        else
            log_error "✗ $file missing"
            return 1
        fi
    done
    
    log_success "All Phase 2 configuration files created"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting P1 #388 Phase 2 Setup..."
    
    configure_github_oidc
    configure_kubernetes_oidc
    create_service_account_mapping
    configure_mtls
    configure_api_tokens
    configure_token_validation_service
    validate_configuration
    
    log_success "Phase 2 configuration complete!"
    
    cat << 'EOF'

Next Steps:

1. Deploy ServiceAccounts to K8s:
  kubectl apply -f $PROJECT_ROOT/k8s-serviceaccounts.yaml

2. Deploy IAM service (token validation):
  kubectl apply -f $CONFIG_DIR/token-validation-service.yaml

3. Configure cert-manager for mTLS:
   helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
  kubectl apply -f $CONFIG_DIR/mtls-config.yaml

4. Test GitHub Actions OIDC:
   - Create test workflow in .github/workflows/test-oidc.yml
   - Verify token generation from GitHub

5. Test K8s OIDC:
   - Deploy test pod and verify token injection
   - Validate token signature

6. Verify service-to-service calls:
   - Backstage → GitHub API
   - Appsmith → K8s API
   - Other service pairs

EOF
}

main "$@"
