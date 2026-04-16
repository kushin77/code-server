#!/bin/bash
# Phase 3 Issue #170 - OPA/Kyverno Policy Engine Deployment
# Admission control & compliance enforcement for k3s cluster

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="kyverno"
KYVERNO_VERSION=${KYVERNO_VERSION:-"1.11.0"}
CLUSTER_NAME=${CLUSTER_NAME:-"code-server-prod"}

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    print_header "Prerequisites Check"
    
    local errors=0
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        ((errors++))
    else
        print_success "kubectl available"
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm not installed"
        ((errors++))
    else
        print_success "Helm available"
    fi
    
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        print_error "k3s cluster not accessible"
        ((errors++))
    else
        print_success "k3s cluster accessible"
    fi
    
    if [ $errors -gt 0 ]; then
        return 1
    fi
    
    print_success "All prerequisites met"
}

# ============================================================================
# Kyverno Installation
# ============================================================================

install_kyverno() {
    print_header "Kyverno Installation"
    
    print_step "Adding Kyverno Helm repository..."
    helm repo add kyverno https://kyverno.github.io/kyverno/ || true
    helm repo update
    
    print_step "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    print_step "Installing Kyverno $KYVERNO_VERSION..."
    
    helm upgrade --install kyverno kyverno/kyverno \
        --namespace "$NAMESPACE" \
        --version "$KYVERNO_VERSION" \
        --set replicaCount=2 \
        --set config.webhooks.maxWebhookSideEffects=15 \
        --set config.webhooks.timedOut=120s \
        --set config.webhooks.failurePolicy=fail \
        --set config.webhooks.namespaceSelector.matchExpressions[0].key=kubernetes.io/metadata.name \
        --set config.webhooks.namespaceSelector.matchExpressions[0].operator=NotIn \
        --set config.webhooks.namespaceSelector.matchExpressions[0].values[0]=kyverno \
        --set config.webhooks.namespaceSelector.matchExpressions[0].values[1]=kube-system \
        --wait
    
    print_success "Kyverno installed"
}

# ============================================================================
# Pod Security Policies
# ============================================================================

create_security_policies() {
    print_header "Pod Security Policies"
    
    print_step "Creating pod security policy..."
    
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-privileged-containers
spec:
  validationFailureAction: enforce
  rules:
    - name: "block-privileged"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Privileged containers are not allowed"
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: false
    
    - name: "block-privileged-escalation"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Privilege escalation is not allowed"
        pattern:
          spec:
            containers:
              - securityContext:
                  allowPrivilegeEscalation: false
    
    - name: "require-run-as-nonroot"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Running as root is not allowed"
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
    
    - name: "require-read-only-filesystem"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Root filesystem must be read-only"
        pattern:
          spec:
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
EOF
    
    print_success "Pod security policies created"
}

# ============================================================================
# Image Registry Policies
# ============================================================================

create_image_policies() {
    print_header "Image Registry & Vulnerability Policies"
    
    print_step "Creating image registry policy..."
    
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: enforce
  rules:
    - name: "allow-docker-io"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Images must come from approved registries"
        pattern:
          spec:
            containers:
              - image: "192.168.168.31:8443/* | docker.io/* | gcr.io/*"
    
    - name: "block-latest-tag"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Image tags must not be 'latest'"
        pattern:
          spec:
            containers:
              - image: "!*:latest"
    
    - name: "require-image-digests"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Images must be pinned by digest"
        pattern:
          spec:
            containers:
              - image: "*@sha256:*"
EOF
    
    print_success "Image registry policies created"
}

# ============================================================================
# Resource Policies
# ============================================================================

create_resource_policies() {
    print_header "Resource Quota & Limits Policies"
    
    print_step "Creating resource policies..."
    
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
    - name: "require-cpu-memory-limits"
      match:
        resources:
          kinds:
            - Pod
          excludeResources:
            names:
              - "*-system"
      validate:
        message: "CPU and memory limits are required"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
                  requests:
                    memory: "?*"
                    cpu: "?*"
    
    - name: "limit-cpu"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "CPU must not exceed 4 cores"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "<=4"
    
    - name: "limit-memory"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Memory must not exceed 8Gi"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "<=8Gi"
EOF
    
    print_success "Resource policies created"
}

# ============================================================================
# RBAC Policies
# ============================================================================

create_rbac_policies() {
    print_header "RBAC & Access Control Policies"
    
    print_step "Creating RBAC policies..."
    
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-service-account-tokens
spec:
  validationFailureAction: audit
  rules:
    - name: "restrict-automount-service-account-token"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Automounting of service account tokens is not allowed"
        pattern:
          spec:
            automountServiceAccountToken: false
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-webhook-configurations
spec:
  validationFailureAction: audit
  rules:
    - name: "restrict-mutating-webhook-changes"
      match:
        resources:
          kinds:
            - MutatingWebhookConfiguration
      validate:
        message: "Only cluster admins can modify webhook configurations"
        pattern:
          webhooks:
            - clientConfig:
                service:
                  namespace: "kyverno"
EOF
    
    print_success "RBAC policies created"
}

# ============================================================================
# Network Policies
# ============================================================================

create_network_policies() {
    print_header "Network Security Policies"
    
    print_step "Creating network policies..."
    
    kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-network-policy
spec:
  validationFailureAction: audit
  rules:
    - name: "require-network-policy"
      match:
        resources:
          kinds:
            - Namespace
          selector:
            matchLabels:
              require-network-policy: "true"
      validate:
        message: "Network policies must exist for restricted namespaces"
        pattern:
          metadata:
            labels:
              require-network-policy: "true"
EOF
    
    print_success "Network policies created"
}

# ============================================================================
# Audit & Monitoring
# ============================================================================

create_monitoring_policies() {
    print_header "Policy Monitoring & Auditing"
    
    print_step "Creating audit logging configuration..."
    
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: kyverno-audit-config
  namespace: kyverno
data:
  audit-level: "RequestResponse"
  audit-max-age: "30"
  audit-max-backup: "10"
  audit-max-size: "100"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: audit-policy-violations
spec:
  validationFailureAction: audit
  rules:
    - name: "log-all-policy-violations"
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Policy violation audit logging enabled"
        pattern:
          metadata:
            annotations:
              audit.kyverno.io/timestamp: "?*"
EOF
    
    print_success "Monitoring policies created"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    print_header "Installation Verification"
    
    print_step "Checking Kyverno pods..."
    if kubectl get pods -n "$NAMESPACE" | grep -q "kyverno"; then
        print_success "Kyverno pods running"
    else
        print_error "Kyverno pods not found"
        return 1
    fi
    
    print_step "Verifying policy count..."
    local policy_count=$(kubectl get clusterpolicies -o json | jq '.items | length')
    print_success "Found $policy_count cluster policies"
    
    print_step "Checking webhook configurations..."
    if kubectl get validatingwebhookconfigurations | grep -q "kyverno"; then
        print_success "Validating webhooks configured"
    else
        print_error "Validating webhooks not found"
        return 1
    fi
    
    print_success "Installation verified"
}

# ============================================================================
# Health Check
# ============================================================================

health_check() {
    print_header "Health Check"
    
    local errors=0
    
    print_step "Checking Kyverno deployment..."
    if kubectl get deployment -n "$NAMESPACE" kyverno | grep -q "kyverno"; then
        local ready=$(kubectl get deployment -n "$NAMESPACE" kyverno -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment -n "$NAMESPACE" kyverno -o jsonpath='{.spec.replicas}')
        if [ "$ready" == "$desired" ]; then
            print_success "Kyverno deployment: $ready/$desired replicas ready"
        else
            print_error "Kyverno not fully ready: $ready/$desired"
            ((errors++))
        fi
    fi
    
    print_step "Verifying policy effectiveness..."
    if kubectl get clusterpolicies | grep -q "restrict"; then
        print_success "Security policies active"
    else
        print_error "Security policies not found"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        print_success "All health checks passed"
        return 0
    else
        print_error "Health check failed"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_header "Phase 3 Issue #170: OPA/Kyverno Policy Engine Setup"
    
    local start_time=$(date +%s)
    
    check_prerequisites || exit 1
    install_kyverno || exit 1
    create_security_policies || exit 1
    create_image_policies || exit 1
    create_resource_policies || exit 1
    create_rbac_policies || exit 1
    create_network_policies || exit 1
    create_monitoring_policies || exit 1
    verify_installation || exit 1
    health_check || exit 1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "✅ OPA/Kyverno Setup Complete"
    print_success "Total deployment time: ${duration}s"
    print_info "Policies are now enforcing compliance across the cluster"
}

main "$@"
