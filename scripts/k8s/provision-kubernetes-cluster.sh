#!/bin/bash
# @file scripts/k8s/provision-kubernetes-cluster.sh
# @module kubernetes-infrastructure
# @description Automated EKS cluster provisioning and initialization for Phase 4 migration
# @governance GOV-002: All infrastructure version-controlled, auditable, immutable
# @version 1.0
# @date April 26, 2026

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

################################################################################
# CONFIGURATION
################################################################################

# Cluster configuration
readonly CLUSTER_NAME="${CLUSTER_NAME:-kushnir-k8s-prod}"
readonly REGION="${AWS_REGION:-us-east-1}"
readonly NODE_TYPE="${NODE_TYPE:-t3.xlarge}"
readonly NODE_COUNT="${NODE_COUNT:-3}"
readonly K8S_VERSION="${K8S_VERSION:-1.28}"
readonly AUTH_DOMAIN="${AUTH_DOMAIN:?AUTH_DOMAIN must be set}"
readonly OIDC_ISSUER="${OIDC_ISSUER:-https://${AUTH_DOMAIN}}"
readonly CLUSTER_VERSION="phase4-migration-$(date +%Y%m%d)"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging
readonly LOG_DIR="${PROJECT_ROOT}/artifacts/k8s-provisioning"
readonly LOG_FILE="${LOG_DIR}/provisioning-$(date +%Y%m%d-%H%M%S).log"

################################################################################
# LOGGING & UTILITIES
################################################################################

init_logging() {
  mkdir -p "$LOG_DIR"
  
  cat > "$LOG_FILE" <<EOF
================================================================================
KUBERNETES CLUSTER PROVISIONING LOG
================================================================================
Cluster Name: $CLUSTER_NAME
Region: $REGION
Node Type: $NODE_TYPE x $NODE_COUNT
Kubernetes Version: $K8S_VERSION
Date: $(date -u +'%Y-%m-%d %H:%M:%S UTC')
================================================================================

EOF
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  
  local missing_tools=()
  
  # Check required tools
  for tool in aws eksctl kubectl helm jq; do
    if ! command -v "$tool" &> /dev/null; then
      missing_tools+=("$tool")
    fi
  done
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_info "Install with: brew install ${missing_tools[*]}"
    return 1
  fi
  
  log_success "All prerequisites met"
  
  # Check AWS credentials
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log_error "AWS credentials not configured"
    return 1
  fi
  
  log_success "AWS credentials valid"
}

################################################################################
# PHASE 1: CLUSTER PROVISIONING
################################################################################

provision_eks_cluster() {
  log_info "Starting EKS cluster provisioning..."
  
  local eksctl_config="/tmp/eks-cluster-config.yaml"
  
  # Generate eksctl configuration
  cat > "$eksctl_config" <<'EKSCTL_CONFIG'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: CLUSTER_NAME_PLACEHOLDER
  region: REGION_PLACEHOLDER
  version: "K8S_VERSION_PLACEHOLDER"
  tags:
    Environment: production
    Phase: kubernetes-migration
    ManagedBy: eksctl

nodeGroups:
  - name: primary-workers
    desiredCapacity: NODE_COUNT_PLACEHOLDER
    minSize: 2
    maxSize: 10
    instanceType: NODE_TYPE_PLACEHOLDER
    spot: false
    volumeSize: 100
    volumeType: gp3
    volumeIops: 3000
    volumeThroughput: 125
    labels:
      nodegroup: primary
      workload: general
    taints: []
    tags:
      NodeGroup: primary-workers
      CostCenter: infrastructure

managedNodeGroups:
  - name: monitoring
    desiredCapacity: 1
    instanceType: t3.large
    labels:
      workload: monitoring
    taints:
      - key: workload
        value: monitoring
        effect: NoSchedule

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        - awsLoadBalancerController
    - metadata:
        name: ebs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        - ebsCSIDriver
    - metadata:
        name: efs-csi-controller-sa
        namespace: kube-system
      wellKnownPolicies:
        - efsCSIDriver

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: ebs-csi-driver
    version: latest
  - name: vpc-resource-controller-k8s
    version: latest
EKSCTL_CONFIG
  
  # Replace placeholders
  sed -i "s/CLUSTER_NAME_PLACEHOLDER/${CLUSTER_NAME}/g" "$eksctl_config"
  sed -i "s/REGION_PLACEHOLDER/${REGION}/g" "$eksctl_config"
  sed -i "s/K8S_VERSION_PLACEHOLDER/${K8S_VERSION}/g" "$eksctl_config"
  sed -i "s/NODE_COUNT_PLACEHOLDER/${NODE_COUNT}/g" "$eksctl_config"
  sed -i "s/NODE_TYPE_PLACEHOLDER/${NODE_TYPE}/g" "$eksctl_config"
  
  log_info "Creating EKS cluster with eksctl..."
  log_info "Config: $eksctl_config"
  
  if eksctl create cluster -f "$eksctl_config"; then
    log_success "EKS cluster created successfully"
  else
    log_error "Failed to create EKS cluster"
    return 1
  fi
  
  # Update kubeconfig
  log_info "Updating kubeconfig..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
  
  log_success "kubeconfig updated"
}

wait_for_cluster_ready() {
  log_info "Waiting for cluster to be ready..."
  
  local max_attempts=60
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if kubectl cluster-info &> /dev/null; then
      local nodes_ready
      nodes_ready=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
      
      if [[ $nodes_ready -ge $NODE_COUNT ]]; then
        log_success "Cluster is ready with $nodes_ready nodes"
        return 0
      fi
    fi
    
    log_info "Waiting for nodes to be ready... (attempt $((attempt + 1))/$max_attempts)"
    sleep 30
    attempt+=1
  done
  
  log_error "Cluster did not become ready within timeout"
  return 1
}

################################################################################
# PHASE 2: STORAGE CONFIGURATION
################################################################################

configure_storage_classes() {
  log_info "Configuring storage classes..."
  
  # Create fast SSD storage class
  kubectl apply -f - <<'STORAGE_CLASS'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: io1
  iops: "1000"
  encrypted: "true"
  fstype: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
  fstype: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  basePath: "/kushnir-enterprise"
  subPathPattern: "${.PVC.namespace}/${.PVC.name}"
  ensureUniqueDirectory: "true"
volumeBindingMode: WaitForFirstConsumer
STORAGE_CLASS
  
  log_success "Storage classes configured"
}

################################################################################
# PHASE 3: SERVICE MESH (ISTIO) SETUP
################################################################################

install_istio() {
  log_info "Installing Istio service mesh..."
  
  local istio_version="1.18.0"
  
  # Download Istio
  log_info "Downloading Istio ${istio_version}..."
  
  if [[ ! -d "/tmp/istio-${istio_version}" ]]; then
    curl -L "https://istio.io/downloadIstio" | ISTIO_VERSION="${istio_version}" bash - 2>/dev/null
  fi
  
  cd "/tmp/istio-${istio_version}" || return 1
  
  # Install Istio operator
  ./bin/istioctl install --set profile=production -y
  
  log_success "Istio installed"
}

configure_istio_mesh() {
  log_info "Configuring Istio mesh networking..."
  
  # Create istio-system namespace with sidecar injection
  kubectl label namespace production istio-injection=enabled
  
  # Enable mutual TLS
  kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: production
spec:
  providers:
  - name: "oidc-provider"
    issuer: "${OIDC_ISSUER}"
    jwksUri: "${OIDC_ISSUER}/.well-known/jwks.json"
EOF
  
  log_success "Istio mesh configured with mTLS"
}

################################################################################
# PHASE 4: MONITORING STACK
################################################################################

install_prometheus() {
  log_info "Installing Prometheus monitoring..."
  
  kubectl create namespace monitoring || true
  
  # Add Prometheus Helm repo
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  
  # Install Prometheus
  helm install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f - <<'PROMETHEUS_VALUES'
prometheus:
  prometheusSpec:
    retention: 15d
    scrapeInterval: 15s
    evaluationInterval: 30s
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi
grafana:
  enabled: true
  adminPassword: "CHANGEME"
  persistence:
    enabled: true
    storageClassName: standard
    size: 10Gi
alertmanager:
  enabled: true
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
PROMETHEUS_VALUES
  
  log_success "Prometheus and Grafana installed"
}

install_loki() {
  log_info "Installing Loki log aggregation..."
  
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  
  helm install loki grafana/loki-stack \
    -n monitoring \
    -f - <<'LOKI_VALUES'
loki:
  persistence:
    enabled: true
    storageClassName: standard
    size: 50Gi
promtail:
  enabled: true
  config:
    clients:
    - url: http://loki:3100/loki/api/v1/push
LOKI_VALUES
  
  log_success "Loki log aggregation installed"
}

################################################################################
# PHASE 5: VERIFICATION
################################################################################

verify_cluster_health() {
  log_info "Verifying cluster health..."
  
  # Check nodes
  log_info "Node status:"
  kubectl get nodes -o wide | tee -a "$LOG_FILE"
  
  # Check namespaces
  log_info "Namespaces:"
  kubectl get namespaces | tee -a "$LOG_FILE"
  
  # Check storage classes
  log_info "Storage classes:"
  kubectl get storageclass | tee -a "$LOG_FILE"
  
  # Check Istio
  log_info "Istio components:"
  kubectl get deployments -n istio-system | tee -a "$LOG_FILE"
  
  # Check monitoring
  log_info "Monitoring stack:"
  kubectl get deployments -n monitoring | tee -a "$LOG_FILE"
  
  log_success "Cluster health verification complete"
}

generate_summary_report() {
  log_info "Generating provisioning summary..."
  
  cat >> "$LOG_FILE" <<EOF

================================================================================
CLUSTER PROVISIONING SUMMARY
================================================================================

Cluster: $CLUSTER_NAME
Region: $REGION
Kubernetes Version: $K8S_VERSION
Node Type: $NODE_TYPE x $NODE_COUNT

Installed Components:
- [x] EKS Cluster (3 nodes with auto-scaling 2-10)
- [x] Storage Classes (fast-ssd, standard, efs)
- [x] Istio Service Mesh (mTLS STRICT mode)
- [x] Prometheus & Grafana (15-day retention)
- [x] Loki Log Aggregation (50GB storage)
- [x] CoreDNS, kube-proxy, VPC CNI

Next Steps:
1. Update kubeconfig: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
2. Deploy Helm charts: helm install code-server ./helm/code-server-enterprise
3. Verify services: kubectl get deployments -n production
4. Monitor dashboard: kubectl port-forward -n monitoring svc/grafana 3000:3000

Access URLs (after port-forward):
- Grafana: http://localhost:3000 (admin/CHANGEME)
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100

Estimated Cost: ~\$599/month (3x t3.xlarge + storage + monitoring)

Provisioning Log: $LOG_FILE
================================================================================

EOF

  cat "$LOG_FILE"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  init_logging
  
  log_info "Starting Kubernetes cluster provisioning..."
  log_info "Target: AWS EKS in $REGION"
  
  # Execute provisioning phases
  check_prerequisites || exit 1
  provision_eks_cluster || exit 1
  wait_for_cluster_ready || exit 1
  configure_storage_classes || exit 1
  install_istio || exit 1
  configure_istio_mesh || exit 1
  install_prometheus || exit 1
  install_loki || exit 1
  verify_cluster_health || exit 1
  generate_summary_report
  
  log_success "✅ Kubernetes cluster provisioning complete!"
  log_success "Cluster ready for Helm deployment"
  log_info "Log file: $LOG_FILE"
}

# Execute
main "$@"
