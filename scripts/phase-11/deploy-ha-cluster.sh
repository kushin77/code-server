#!/bin/bash
# scripts/phase-11/deploy-ha-cluster.sh
# Deploy Phase 11 HA cluster to Kubernetes

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="code-server-ha"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
DRY_RUN="${DRY_RUN:-false}"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes

# Logging
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
  exit 1
}

# Functions
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check kubectl
  if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
  fi
  log_success "kubectl found"
  
  # Check cluster connectivity
  if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
  fi
  log_success "Connected to Kubernetes cluster"
  
  # Check for required manifests
  local required_files=(
    "kubernetes/ha-config/code-server-statefulset.yaml"
    "kubernetes/ha-config/postgres-ha.yaml"
    "kubernetes/ha-config/redis-cluster.yaml"
    "kubernetes/ha-config/network-policies.yaml"
    "kubernetes/ha-config/observability/jaeger-prometheus.yaml"
  )
  
  for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
      log_error "Missing manifest: $file"
    fi
  done
  log_success "All required manifests found"
}

create_namespace() {
  log_info "Creating namespace: $NAMESPACE"
  
  if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warn "Namespace $NAMESPACE already exists"
  else
    kubectl create namespace "$NAMESPACE"
    kubectl label namespace "$NAMESPACE" monitoring=enabled
    log_success "Namespace created"
  fi
}

deploy_storage_classes() {
  log_info "Deploying storage classes..."
  
  cat <<'EOF' | kubectl apply ${DRY_RUN:+--dry-run=client} -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "1000"
  throughput: "125"
  encrypted: "true"
allowVolumeExpansion: true
EOF
  
  log_success "Storage classes deployed"
}

deploy_manifests() {
  log_info "Deploying HA manifests..."
  
  local manifests=(
    "kubernetes/ha-config/code-server-statefulset.yaml"
    "kubernetes/ha-config/postgres-ha.yaml"
    "kubernetes/ha-config/redis-cluster.yaml"
    "kubernetes/ha-config/network-policies.yaml"
    "kubernetes/ha-config/observability/jaeger-prometheus.yaml"
  )
  
  for manifest in "${manifests[@]}"; do
    log_info "Deploying $manifest..."
    kubectl apply \
      --namespace="$NAMESPACE" \
      ${DRY_RUN:+--dry-run=client} \
      -f "$manifest" || log_error "Failed to deploy $manifest"
    log_success "Deployed $manifest"
  done
}

wait_for_readiness() {
  log_info "Waiting for services to be ready..."
  
  local start_time=$(date +%s)
  
  # Wait for PostgreSQL primary
  log_info "Waiting for PostgreSQL primary..."
  until kubectl -n "$NAMESPACE" get pod -l app=postgres,role=primary | grep -q "1/1"; do
    if [ $(($(date +%s) - start_time)) -gt $TIMEOUT ]; then
      log_error "Timeout waiting for PostgreSQL primary"
    fi
    sleep 5
  done
  log_success "PostgreSQL primary ready"
  
  # Wait for PostgreSQL replicas
  log_info "Waiting for PostgreSQL replicas..."
  until [ "$(kubectl -n "$NAMESPACE" get pods -l app=postgres,role=replica --no-headers | wc -l)" = "2" ]; then
    if [ $(($(date +%s) - start_time)) -gt $TIMEOUT ]; then
      log_error "Timeout waiting for PostgreSQL replicas"
    fi
    sleep 5
  done
  log_success "PostgreSQL replicas ready"
  
  # Wait for Redis
  log_info "Waiting for Redis cluster..."
  until [ "$(kubectl -n "$NAMESPACE" get pods -l app=redis --no-headers | wc -l)" = "6" ]; then
    if [ $(($(date +%s) - start_time)) -gt $TIMEOUT ]; then
      log_error "Timeout waiting for Redis"
    fi
    sleep 5
  done
  log_success "Redis cluster ready"
  
  # Wait for code-server
  log_info "Waiting for code-server..."
  until [ "$(kubectl -n "$NAMESPACE" get pods -l app=code-server --no-headers | wc -l)" = "3" ]; then
    if [ $(($(date +%s) - start_time)) -gt $TIMEOUT ]; then
      log_error "Timeout waiting for code-server"
    fi
    sleep 5
  done
  log_success "code-server ready"
}

verify_deployment() {
  log_info "Verifying deployment..."
  
  # Check pod status
  log_info "Pod status:"
  kubectl -n "$NAMESPACE" get pods -o wide
  
  # Check services
  log_info "Service status:"
  kubectl -n "$NAMESPACE" get svc
  
  # Check PVCs
  log_info "PersistentVolumeClaim status:"
  kubectl -n "$NAMESPACE" get pvc
  
  # Perform health checks
  log_info "Running health checks..."
  
  # PostgreSQL replication check
  local pg_primary=$(kubectl -n "$NAMESPACE" get pod -l app=postgres,role=primary -o jsonpath='{.items[0].metadata.name}')
  local replication_status=$(kubectl -n "$NAMESPACE" exec "$pg_primary" -- psql -U postgres -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null || echo "0")
  
  if [ "$replication_status" -ge 2 ]; then
    log_success "PostgreSQL replication OK ($replication_status replicas)"
  else
    log_warn "PostgreSQL replication not fully healthy"
  fi
  
  # Redis cluster check
  local redis_node=$(kubectl -n "$NAMESPACE" get pod -l app=redis -o jsonpath='{.items[0].metadata.name}')
  local cluster_info=$(kubectl -n "$NAMESPACE" exec "$redis_node" -- redis-cli cluster info 2>/dev/null | grep cluster_state || echo "fail")
  
  if echo "$cluster_info" | grep -q "ok"; then
    log_success "Redis cluster OK"
  else
    log_warn "Redis cluster not fully healthy: $cluster_info"
  fi
  
  log_success "Deployment verified"
}

print_next_steps() {
  log_info "Deployment complete! Next steps:"
  echo ""
  echo "1. Access dashboards:"
  echo "   - Prometheus: kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
  echo "   - Jaeger: kubectl port-forward -n $NAMESPACE svc/jaeger 16686:16686"
  echo ""
  echo "2. View logs:"
  echo "   - kubectl logs -n $NAMESPACE -f -l app=code-server"
  echo ""
  echo "3. Run smoke tests:"
  echo "   - ./scripts/phase-11/health-check.sh"
  echo ""
  echo "4. Run chaos tests:"
  echo "   - ./scripts/phase-11/chaos-test.sh --test app-server-crash"
  echo ""
}

main() {
  log_info "=== Phase 11 HA Cluster Deployment ==="
  log_info "Namespace: $NAMESPACE"
  [ "$DRY_RUN" = "true" ] && log_warn "Running in DRY-RUN mode"
  
  check_prerequisites
  create_namespace
  deploy_storage_classes
  deploy_manifests
  
  if [ "$DRY_RUN" != "true" ]; then
    wait_for_readiness
    verify_deployment
    print_next_steps
  else
    log_warn "DRY-RUN: Skipping readiness checks"
  fi
  
  log_success "=== Deployment completed successfully ==="
}

# Run main
main
