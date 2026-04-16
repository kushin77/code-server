#!/usr/bin/env bash
# @file        scripts/configure-workload-federation-phase2.sh
# @module      iam
# @description configure workload federation phase2 — on-prem code-server
# @owner       platform
# @status      active
#
# P1 #388 - Phase 2: Workload Federation Setup Script
# Generates deterministic IAM artifacts for service-to-service authentication.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE2_DIR="$ROOT_DIR/config/iam"

mkdir -p "$PHASE2_DIR"

write_file() {
    local path="$1"
    cat > "$path"
    log_success "Generated: $path"
}

configure_github_oidc() {
    log_info "Configuring GitHub Actions OIDC workload federation template..."
    local github_oidc_issuer="https://token.actions.githubusercontent.com"

    write_file "$PHASE2_DIR/github-oidc.env.template" <<'EOF'
# GitHub Actions OIDC Configuration (Phase 2)
GITHUB_OIDC_ISSUER="https://token.actions.githubusercontent.com"
GITHUB_OIDC_AUDIENCE="kushin77/code-server"

# Token TTL policy
TOKEN_TTL_MAIN_BRANCH=900
TOKEN_TTL_PR_BRANCH=300
TOKEN_TTL_RELEASE_TAG=600

# Subject claim patterns
SUBJECT_PATTERN_MAIN="repo:kushin77/code-server:ref:refs/heads/main"
SUBJECT_PATTERN_PR="repo:kushin77/code-server:pull_request"
SUBJECT_PATTERN_RELEASE="repo:kushin77/code-server:ref:refs/tags/v*"

# Role assignments
ROLE_MAIN_BRANCH="automation/operator"
ROLE_PR_BRANCH="automation/viewer"
ROLE_RELEASE="automation/operator"
EOF

    log_info "Validating GitHub OIDC issuer reachability..."
    curl -fsS "$github_oidc_issuer/.well-known/openid-configuration" >/dev/null
    log_success "GitHub OIDC issuer is reachable"
}

configure_kubernetes_oidc() {
    log_info "Configuring Kubernetes OIDC template and ServiceAccounts..."

    write_file "$PHASE2_DIR/k8s-oidc.env.template" <<'EOF'
# Kubernetes OIDC Configuration (on-prem)
K8S_OIDC_ISSUER="https://oidc.${DEPLOY_HOST}.nip.io"
K8S_OIDC_DISCOVERY_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/openid-configuration"
K8S_OIDC_JWKS_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/jwks.json"

# Service account role mappings
KUBE_SA_CODE_SERVER_ROLE="workload/viewer"
KUBE_SA_BACKSTAGE_ROLE="workload/operator"
KUBE_SA_APPSMITH_ROLE="workload/operator"
KUBE_SA_OLLAMA_ROLE="workload/viewer"
KUBE_SA_PROMETHEUS_ROLE="workload/viewer"
KUBE_SA_LOKI_ROLE="workload/viewer"
EOF

    write_file "$PHASE2_DIR/k8s-serviceaccounts.yaml" <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: prod
  labels:
    app: code-server
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backstage
  namespace: prod
  labels:
    app: backstage
    iam-role: workload/operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: appsmith
  namespace: prod
  labels:
    app: appsmith
    iam-role: workload/operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ollama
  namespace: prod
  labels:
    app: ollama
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: monitoring
  labels:
    app: loki
    iam-role: workload/viewer
EOF
}

create_service_account_mapping() {
    log_info "Generating ServiceAccount-to-role mapping..."

    write_file "$PHASE2_DIR/k8s-serviceaccount-roles.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-sa-role-mapping
  namespace: code-server-iam
data:
  mapping.yaml: |
    service_accounts:
      - namespace: prod
        name: code-server
        role: workload/viewer
        permissions: [code-server:execute, logs:write, metrics:export]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: backstage
        role: workload/operator
        permissions: [backstage:catalog, github:api, kubernetes:services, metrics:read]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: appsmith
        role: workload/operator
        permissions: [appsmith:workflows, deployments:execute, incidents:view]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: ollama
        role: workload/viewer
        permissions: [ollama:inference, metrics:export]
        identity_type: workload
        token_ttl_seconds: 7200
      - namespace: monitoring
        name: prometheus
        role: workload/viewer
        permissions: [prometheus:scrape, kubernetes:pods]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: monitoring
        name: loki
        role: workload/viewer
        permissions: [loki:write, kubernetes:pods]
        identity_type: workload
        token_ttl_seconds: 3600
EOF
}

configure_mtls() {
    log_info "Generating mTLS cert-manager baseline..."

    write_file "$PHASE2_DIR/mtls-config.yaml" <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: code-server-iam
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: code-server-ca
  namespace: code-server-iam
spec:
  secretName: code-server-ca-secret
  duration: 87600h
  renewBefore: 720h
  commonName: kushin-code-server-ca
  isCA: true
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
EOF
}

configure_api_tokens() {
    log_info "Generating API token policy manifest..."

    write_file "$PHASE2_DIR/api-tokens-config.yaml" <<'EOF'
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
        old_token_grace_period: 24
EOF
}

configure_token_validation_service() {
    log_info "Generating token validation service deployment manifest..."

    write_file "$PHASE2_DIR/token-validation-service.yaml" <<'EOF'
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
              value: https://accounts.google.com
            - name: OIDC_JWKS_URL
              value: https://www.googleapis.com/oauth2/v3/certs
            - name: CACHE_TTL_SECONDS
              value: "300"
            - name: LOG_LEVEL
              value: info
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
}

validate_configuration() {
    log_info "Validating generated Phase 2 artifacts..."

    local files=(
        "$PHASE2_DIR/github-oidc.env.template"
        "$PHASE2_DIR/k8s-oidc.env.template"
        "$PHASE2_DIR/k8s-serviceaccounts.yaml"
        "$PHASE2_DIR/k8s-serviceaccount-roles.yaml"
        "$PHASE2_DIR/mtls-config.yaml"
        "$PHASE2_DIR/api-tokens-config.yaml"
        "$PHASE2_DIR/token-validation-service.yaml"
    )

    local file
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "$file exists"
        else
            log_error "$file missing"
            return 1
        fi
    done

    log_success "All Phase 2 configuration files generated successfully"
}

main() {
    log_info "Starting P1 #388 Phase 2 setup..."
    configure_github_oidc
    configure_kubernetes_oidc
    create_service_account_mapping
    configure_mtls
    configure_api_tokens
    configure_token_validation_service
    validate_configuration

    cat <<'EOF'

Next Steps:
1. kubectl apply -f config/iam/k8s-serviceaccounts.yaml
2. kubectl apply -f config/iam/token-validation-service.yaml
3. helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
4. kubectl apply -f config/iam/mtls-config.yaml
5. Validate OIDC token flows from GitHub Actions and service accounts

EOF
}

main "$@"
#!/usr/bin/env bash
#
# P1 #388 - Phase 2: Workload Federation Setup Script
# Generates deterministic IAM artifacts for service-to-service authentication.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE2_DIR="$ROOT_DIR/config/iam"

mkdir -p "$PHASE2_DIR"

write_file() {
    local path="$1"
    cat > "$path"
    log_success "Generated: $path"
}

configure_github_oidc() {
    log_info "Configuring GitHub Actions OIDC workload federation template..."
    local github_oidc_issuer="https://token.actions.githubusercontent.com"

    write_file "$PHASE2_DIR/github-oidc.env.template" <<'EOF'
# GitHub Actions OIDC Configuration (Phase 2)
GITHUB_OIDC_ISSUER="https://token.actions.githubusercontent.com"
GITHUB_OIDC_AUDIENCE="kushin77/code-server"

# Token TTL policy
TOKEN_TTL_MAIN_BRANCH=900
TOKEN_TTL_PR_BRANCH=300
TOKEN_TTL_RELEASE_TAG=600

# Subject claim patterns
SUBJECT_PATTERN_MAIN="repo:kushin77/code-server:ref:refs/heads/main"
SUBJECT_PATTERN_PR="repo:kushin77/code-server:pull_request"
SUBJECT_PATTERN_RELEASE="repo:kushin77/code-server:ref:refs/tags/v*"

# Role assignments
ROLE_MAIN_BRANCH="automation/operator"
ROLE_PR_BRANCH="automation/viewer"
ROLE_RELEASE="automation/operator"
EOF

    log_info "Validating GitHub OIDC issuer reachability..."
    curl -fsS "$github_oidc_issuer/.well-known/openid-configuration" >/dev/null
    log_success "GitHub OIDC issuer is reachable"
}

configure_kubernetes_oidc() {
    log_info "Configuring Kubernetes OIDC template and ServiceAccounts..."

    write_file "$PHASE2_DIR/k8s-oidc.env.template" <<'EOF'
# Kubernetes OIDC Configuration (on-prem)
K8S_OIDC_ISSUER="https://oidc.${DEPLOY_HOST}.nip.io"
K8S_OIDC_DISCOVERY_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/openid-configuration"
K8S_OIDC_JWKS_ENDPOINT="${K8S_OIDC_ISSUER}/.well-known/jwks.json"

# Service account role mappings
KUBE_SA_CODE_SERVER_ROLE="workload/viewer"
KUBE_SA_BACKSTAGE_ROLE="workload/operator"
KUBE_SA_APPSMITH_ROLE="workload/operator"
KUBE_SA_OLLAMA_ROLE="workload/viewer"
KUBE_SA_PROMETHEUS_ROLE="workload/viewer"
KUBE_SA_LOKI_ROLE="workload/viewer"
EOF

    write_file "$PHASE2_DIR/k8s-serviceaccounts.yaml" <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: prod
  labels:
    app: code-server
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backstage
  namespace: prod
  labels:
    app: backstage
    iam-role: workload/operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: appsmith
  namespace: prod
  labels:
    app: appsmith
    iam-role: workload/operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ollama
  namespace: prod
  labels:
    app: ollama
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
    iam-role: workload/viewer
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: monitoring
  labels:
    app: loki
    iam-role: workload/viewer
EOF
}

create_service_account_mapping() {
    log_info "Generating ServiceAccount-to-role mapping..."

    write_file "$PHASE2_DIR/k8s-serviceaccount-roles.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-sa-role-mapping
  namespace: code-server-iam
data:
  mapping.yaml: |
    service_accounts:
      - namespace: prod
        name: code-server
        role: workload/viewer
        permissions: [code-server:execute, logs:write, metrics:export]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: backstage
        role: workload/operator
        permissions: [backstage:catalog, github:api, kubernetes:services, metrics:read]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: appsmith
        role: workload/operator
        permissions: [appsmith:workflows, deployments:execute, incidents:view]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: prod
        name: ollama
        role: workload/viewer
        permissions: [ollama:inference, metrics:export]
        identity_type: workload
        token_ttl_seconds: 7200
      - namespace: monitoring
        name: prometheus
        role: workload/viewer
        permissions: [prometheus:scrape, kubernetes:pods]
        identity_type: workload
        token_ttl_seconds: 3600
      - namespace: monitoring
        name: loki
        role: workload/viewer
        permissions: [loki:write, kubernetes:pods]
        identity_type: workload
        token_ttl_seconds: 3600
EOF
}

configure_mtls() {
    log_info "Generating mTLS cert-manager baseline..."

    write_file "$PHASE2_DIR/mtls-config.yaml" <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: code-server-iam
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: code-server-ca
  namespace: code-server-iam
spec:
  secretName: code-server-ca-secret
  duration: 87600h
  renewBefore: 720h
  commonName: kushin-code-server-ca
  isCA: true
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
EOF
}

configure_api_tokens() {
    log_info "Generating API token policy manifest..."

    write_file "$PHASE2_DIR/api-tokens-config.yaml" <<'EOF'
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
        old_token_grace_period: 24
EOF
}

configure_token_validation_service() {
    log_info "Generating token validation service deployment manifest..."

    write_file "$PHASE2_DIR/token-validation-service.yaml" <<'EOF'
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
              value: https://accounts.google.com
            - name: OIDC_JWKS_URL
              value: https://www.googleapis.com/oauth2/v3/certs
            - name: CACHE_TTL_SECONDS
              value: "300"
            - name: LOG_LEVEL
              value: info
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
}

validate_configuration() {
    log_info "Validating generated Phase 2 artifacts..."

    local files=(
        "$PHASE2_DIR/github-oidc.env.template"
        "$PHASE2_DIR/k8s-oidc.env.template"
        "$PHASE2_DIR/k8s-serviceaccounts.yaml"
        "$PHASE2_DIR/k8s-serviceaccount-roles.yaml"
        "$PHASE2_DIR/mtls-config.yaml"
        "$PHASE2_DIR/api-tokens-config.yaml"
        "$PHASE2_DIR/token-validation-service.yaml"
    )

    local file
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "$file exists"
        else
            log_error "$file missing"
            return 1
        fi
    done

    log_success "All Phase 2 configuration files generated successfully"
}

main() {
    log_info "Starting P1 #388 Phase 2 setup..."
    configure_github_oidc
    configure_kubernetes_oidc
    create_service_account_mapping
    configure_mtls
    configure_api_tokens
    configure_token_validation_service
    validate_configuration

    cat <<'EOF'

Next Steps:
1. kubectl apply -f config/iam/k8s-serviceaccounts.yaml
2. kubectl apply -f config/iam/token-validation-service.yaml
3. helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
4. kubectl apply -f config/iam/mtls-config.yaml
5. Validate OIDC token flows from GitHub Actions and service accounts

EOF
}

main "$@"
