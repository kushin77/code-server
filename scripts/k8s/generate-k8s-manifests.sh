#!/bin/bash

###############################################################################
# generate-k8s-manifests.sh
###############################################################################
# P2 #2427: Generate Kubernetes manifests for workload deployment
#
# Current state: Kubernetes provider declared in Terraform but zero manifests exist
# This script scaffolds K8s deployment for:
# - Execution scheduler
# - OPA policy engine  
# - OAuth2 proxy
# - Agent services
#
# Usage:
#   ./scripts/k8s/generate-k8s-manifests.sh --namespace code-server --registry gcr.io/my-project
#
###############################################################################

set -euo pipefail

trap 'error "Script failed at line $LINENO"' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/k8s-gen.*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K8S_DIR="${REPO_ROOT}/kubernetes"

NAMESPACE="${1:-code-server}"
REGISTRY="${2:-docker.io}"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*"; exit 1; }

# ── CLI arg parsing ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --registry)  REGISTRY="$2";  shift 2 ;;
    *) error "Unknown argument: $1" ;;
  esac
done

# ── Helpers ────────────────────────────────────────────────────────────────────
write_manifest() {
  local path="$1"; local content="$2"
  if [ -f "${path}" ]; then
    log_info "  exists (skipping): $(basename ${path})"
    return
  fi
  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "${content}" > "${path}"
  log_info "  created: $(basename ${path})"
}

log_info "========================================"
log_info "Kubernetes Manifests Generation"
log_info "Namespace : ${NAMESPACE}"
log_info "Registry  : ${REGISTRY}"
log_info "========================================"

# ── 1. Namespace ────────────────────────────────────────────────────────────────
log_info "1. Namespace"
write_manifest "${K8S_DIR}/namespace.yaml" "apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: kustomize"

# ── 2. Execution Scheduler ──────────────────────────────────────────────────────
log_info "2. Execution Scheduler"
write_manifest "${K8S_DIR}/deployments/execution-scheduler.yaml" "apiVersion: apps/v1
kind: Deployment
metadata:
  name: execution-scheduler
  namespace: ${NAMESPACE}
  labels:
    app: execution-scheduler
spec:
  replicas: 2
  selector:
    matchLabels:
      app: execution-scheduler
  template:
    metadata:
      labels:
        app: execution-scheduler
    spec:
      serviceAccountName: execution-scheduler
      containers:
        - name: execution-scheduler
          image: ${REGISTRY}/execution-scheduler:latest
          ports:
            - containerPort: 8030
          envFrom:
            - configMapRef:
                name: app-config
            - secretRef:
                name: app-secrets
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 8030
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /health
              port: 8030
            initialDelaySeconds: 5
            periodSeconds: 10"

# ── 3. OPA Policy Engine ────────────────────────────────────────────────────────
log_info "3. OPA Policy Engine"
write_manifest "${K8S_DIR}/deployments/opa-service.yaml" "apiVersion: apps/v1
kind: Deployment
metadata:
  name: opa-service
  namespace: ${NAMESPACE}
  labels:
    app: opa-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: opa-service
  template:
    metadata:
      labels:
        app: opa-service
    spec:
      containers:
        - name: opa
          image: openpolicyagent/opa:latest
          args: [\"run\", \"--server\", \"--addr=:8181\", \"--log-format=json\"]
          ports:
            - containerPort: 8181
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 8181
            initialDelaySeconds: 5
            periodSeconds: 15"

# ── 4. Network Policies ──────────────────────────────────────────────────────────
log_info "4. Network Policies"
write_manifest "${K8S_DIR}/network-policies/default-deny.yaml" "apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Ingress"

write_manifest "${K8S_DIR}/network-policies/allow-internal.yaml" "apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${NAMESPACE}"

# ── 5. RBAC ──────────────────────────────────────────────────────────────────────
log_info "5. RBAC"
write_manifest "${K8S_DIR}/rbac/service-accounts.yaml" "apiVersion: v1
kind: ServiceAccount
metadata:
  name: execution-scheduler
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auth-server
  namespace: ${NAMESPACE}"

# ── 6. Kustomization base ────────────────────────────────────────────────────────
log_info "6. Kustomization base"
write_manifest "${K8S_DIR}/kustomization.yaml" "apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - namespace.yaml
  - deployments/auth-server.yaml
  - deployments/execution-scheduler.yaml
  - deployments/hermes-integration.yaml
  - deployments/opa-service.yaml
  - network-policies/default-deny.yaml
  - network-policies/allow-internal.yaml
  - rbac/service-accounts.yaml
  - services/internal-services.yaml"

log_info ""
log_info "========================================"
log_info "Manifest generation complete"
log_info "Output: ${K8S_DIR}"
log_info "Validate: kubectl kustomize ${K8S_DIR} | kubectl apply --dry-run=client -f -"
log_info "========================================"

