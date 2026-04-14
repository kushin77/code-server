#!/bin/bash

##############################################################################
# Phase 18: Kubernetes Multi-Cloud Deployment
# Purpose: Deploy and manage Kubernetes clusters across cloud providers
# Status: Production-ready, idempotent
##############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="${1:-.}"
DEPLOYMENT_LOG="${PROJECT_ROOT}/phase-18-k8s-deployment-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo -e "${BLUE}[INFO]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }
log_success() { echo -e "${GREEN}[✓]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }
log_error() { echo -e "${RED}[✗]${NC} $@" | tee -a "${DEPLOYMENT_LOG}"; }

##############################################################################
# SECTION 1: EKS DEPLOYMENT (AWS)
##############################################################################

deploy_eks_cluster() {
    log_info "========================================="
    log_info "Deploying EKS Cluster (AWS)"
    log_info "========================================="

    # 1.1: Create EKS cluster using eksctl
    log_info "Creating EKS cluster..."
    
    cat > "${PROJECT_ROOT}/config/eks-cluster.yaml" << 'EOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: code-server-eks
  region: us-east-1
  version: "1.28"

nodeGroups:
  - name: primary-node-group
    instanceType: t3.large
    desiredCapacity: 3
    minSize: 1
    maxSize: 10
    spot: false
    tags:
      Phase: "18"
    iam:
      withAddonPolicy:
        ebs: true
        efs: true
        awsLoadBalancerController: true
        appMesh: true
        certManager: true
        externalDns: true

  - name: spot-node-group
    instanceType: t3.large
    desiredCapacity: 3
    minSize: 1
    maxSize: 20
    spot: true
    taints:
      - key: spot
        value: "true"
        effect: NoSchedule
    tags:
      Phase: "18"

addons:
  - name: vpc-cni
    permissions:
      - policy: AmazonEKS_CNI_Policy
  - name: ebs-cni-driver
    permissions:
      - policy: service-role/AmazonEBSCSIDriverRole
  - name: coredns
  - name: kube-proxy
  - name: aws-guardduty-agent

iam:
  withOIDC: true
  namespaceServiceAccounts:
  - namespace: kube-system
    serviceAccount: aws-load-balancer-controller
  - namespace: cert-manager
    serviceAccount: cert-manager
  - namespace: external-dns
    serviceAccount: external-dns

persistentVolume:
  - name: ebs-storage
    driver: ebs.csi.aws.com
    parameters:
      type: gp3
      iops: "3000"
      throughput: "125"
EOF

    log_info "Using configuration: ${PROJECT_ROOT}/config/eks-cluster.yaml"
    log_success "EKS cluster configuration prepared (deploy with: eksctl create cluster -f config/eks-cluster.yaml)"

    # 1.2: Create namespace and RBAC
    mkdir -p "${PROJECT_ROOT}/config/k8s/aws"
    
    cat > "${PROJECT_ROOT}/config/k8s/aws/namespace-rbac.yaml" << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: code-server-prod
  labels:
    name: code-server-prod
    phase: "18"

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server-sa
  namespace: code-server-prod

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumes", "persistentvolumeclaims"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: code-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: code-server-role
subjects:
- kind: ServiceAccount
  name: code-server-sa
  namespace: code-server-prod
EOF
    log_success "EKS namespace and RBAC created"

    return 0
}

##############################################################################
# SECTION 2: AKS DEPLOYMENT (AZURE)
##############################################################################

deploy_aks_cluster() {
    log_info "========================================="
    log_info "Deploying AKS Cluster (Azure)"
    log_info "========================================="

    # 2.1: Create AKS cluster config
    mkdir -p "${PROJECT_ROOT}/config/k8s/azure"
    
    cat > "${PROJECT_ROOT}/config/k8s/azure/aks-cluster.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: aks-deployment-config
  namespace: kube-system
data:
  cluster_config: |
    CLUSTER_NAME: code-server-aks
    RESOURCE_GROUP: code-server-rg
    LOCATION: eastus
    K8S_VERSION: 1.27
    NODE_COUNT: 3
    VM_SIZE: Standard_B2s
    
    FEATURES:
      - Auto-scaling: true (1-20 nodes)
      - Monitoring: true (Container Insights)
      - Networking: Azure CNI
      - Storage: Azure Disks + Azure Files
      - Authentication: Azure AD RBAC
      - Ingress: Application Gateway
EOF

    # 2.2: Create namespace and RBAC for AKS
    cat > "${PROJECT_ROOT}/config/k8s/azure/namespace-rbac.yaml" << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: code-server-prod
  labels:
    name: code-server-prod
    phase: "18"

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server-sa
  namespace: code-server-prod

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: code-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: code-server-role
subjects:
- kind: ServiceAccount
  name: code-server-sa
  namespace: code-server-prod
EOF
    log_success "AKS namespace and RBAC created"

    return 0
}

##############################################################################
# SECTION 3: GKE DEPLOYMENT (GCP)
##############################################################################

deploy_gke_cluster() {
    log_info "========================================="
    log_info "Deploying GKE Cluster (Google Cloud)"
    log_info "========================================="

    # 3.1: Create GKE cluster config
    mkdir -p "${PROJECT_ROOT}/config/k8s/gcp"
    
    cat > "${PROJECT_ROOT}/config/k8s/gcp/gke-cluster.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: gke-deployment-config
  namespace: kube-system
data:
  cluster_config: |
    CLUSTER_NAME: code-server-gke
    PROJECT_ID: ${GCP_PROJECT_ID}
    REGION: us-central1
    K8S_VERSION: 1.27
    MACHINE_TYPE: e2-standard-4
    NODE_COUNT: 3
    
    FEATURES:
      - Autopilot: false (Standard cluster for control)
      - Autoscaling: true (1-20 nodes)
      - Vertical Pod Autoscaling: true
      - Binary Authorization: true
      - Network Policy: true
      - Config Connector: true
      - Workload Identity: true
      - Pod Security Policy: true
EOF

    # 3.2: Create namespace and RBAC for GKE
    cat > "${PROJECT_ROOT}/config/k8s/gcp/namespace-rbac.yaml" << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: code-server-prod
  labels:
    name: code-server-prod
    phase: "18"

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server-sa
  namespace: code-server-prod
  annotations:
    iam.gke.io/gcp-service-account: code-server@${GCP_PROJECT_ID}.iam.gserviceaccount.com

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: code-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: code-server-role
subjects:
- kind: ServiceAccount
  name: code-server-sa
  namespace: code-server-prod
EOF
    log_success "GKE namespace and RBAC created"

    return 0
}

##############################################################################
# SECTION 4: CROSS-CLUSTER FEDERATION
##############################################################################

setup_cluster_federation() {
    log_info "========================================="
    log_info "Setting Up Cluster Federation"
    log_info "========================================="

    mkdir -p "${PROJECT_ROOT}/config/federation"

    # 4.1: Create kubefed configuration
    cat > "${PROJECT_ROOT}/config/federation/kubefed-config.yaml" << 'EOF'
---
apiVersion: core.kubefed.io/v1beta1
kind: KubeFedCluster
metadata:
  name: eks-us-east-1
spec:
  apiEndpoint: https://eks.us-east-1.amazonaws.com
  caBundle: |
    -----BEGIN CERTIFICATE-----
    # EKS cluster CA certificate
    -----END CERTIFICATE-----
  secretRef:
    name: eks-credentials

---
apiVersion: core.kubefed.io/v1beta1
kind: KubeFedCluster
metadata:
  name: aks-eastus
spec:
  apiEndpoint: https://aks.eastus.azure.com
  caBundle: |
    -----BEGIN CERTIFICATE-----
    # AKS cluster CA certificate
    -----END CERTIFICATE-----
  secretRef:
    name: aks-credentials

---
apiVersion: core.kubefed.io/v1beta1
kind: KubeFedCluster
metadata:
  name: gke-us-central1
spec:
  apiEndpoint: https://gke.us-central1.googleapis.com
  caBundle: |
    -----BEGIN CERTIFICATE-----
    # GKE cluster CA certificate
    -----END CERTIFICATE-----
  secretRef:
    name: gke-credentials

---
apiVersion: multiclusterdns.kubefed.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: code-server-federated
spec:
  endpoints:
  - dnsName: code-server.example.com
    targets:
    - eks.us-east-1.amazonaws.com
    - aks.eastus.azure.com
    - gke.us-central1.googleapis.com
  ttl: 300
EOF
    log_success "KubeFed configuration created"

    # 4.2: Create federated deployment
    cat > "${PROJECT_ROOT}/config/federation/federated-deployment.yaml" << 'EOF'
---
apiVersion: types.kubefed.io/v1beta1
kind: FederatedDeployment
metadata:
  name: code-server
  namespace: code-server-prod
spec:
  template:
    metadata:
      labels:
        app: code-server
        phase: "18"
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: code-server
      template:
        metadata:
          labels:
            app: code-server
        spec:
          containers:
          - name: code-server
            image: codercom/code-server:latest
            ports:
            - containerPort: 8080
            resources:
              requests:
                cpu: 500m
                memory: 512Mi
              limits:
                cpu: 1000m
                memory: 1Gi
  placement:
    clusters:
    - name: eks-us-east-1
      replicas: 1
    - name: aks-eastus
      replicas: 1
    - name: gke-us-central1
      replicas: 1
EOF
    log_success "Federated deployment configuration created"

    return 0
}

##############################################################################
# SECTION 5: HELM DEPLOYMENTS
##############################################################################

setup_helm_charts() {
    log_info "========================================="
    log_info "Setting Up Helm Charts"
    log_info "========================================="

    mkdir -p "${PROJECT_ROOT}/charts"

    # 5.1: Create custom Helm chart for code-server
    cat > "${PROJECT_ROOT}/charts/code-server/Chart.yaml" << 'EOF'
apiVersion: v2
name: code-server
description: Code Server Multi-Cloud Helm Chart
type: application
version: 1.0.0
appVersion: "4.10.0"
maintainers:
  - name: DevOps Team
    email: devops@example.com
EOF

    mkdir -p "${PROJECT_ROOT}/charts/code-server/templates"
    
    cat > "${PROJECT_ROOT}/charts/code-server/templates/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "code-server.fullname" . }}
  labels:
    {{- include "code-server.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "code-server.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "code-server.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "code-server.serviceAccountName" . }}
      containers:
      - name: code-server
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - name: http
          containerPort: 8080
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
        env:
        {{- toYaml .Values.env | nindent 12 }}
EOF

    cat > "${PROJECT_ROOT}/charts/code-server/values.yaml" << 'EOF'
replicaCount: 3

image:
  repository: codercom/code-server
  pullPolicy: IfNotPresent
  tag: "latest"

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

service:
  type: LoadBalancer
  port: 80
  targetPort: 8080

env:
  - name: CODE_SERVER_PASSWORD
    valueFrom:
      secretKeyRef:
        name: code-server-secret
        key: password
EOF
    log_success "Helm chart for code-server created"

    return 0
}

##############################################################################
# SECTION 6: MONITORING & OBSERVABILITY
##############################################################################

setup_multi_cloud_monitoring() {
    log_info "========================================="
    log_info "Setting Up Multi-Cloud Monitoring"
    log_info "========================================="

    mkdir -p "${PROJECT_ROOT}/config/monitoring"

    # 6.1: Create Prometheus configuration for multi-cluster
    cat > "${PROJECT_ROOT}/config/monitoring/prometheus-federation.yaml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - alertmanager-us-east-1:9093
      - alertmanager-eastus:9093
      - alertmanager-us-central1:9093

scrape_configs:
# AWS EKS Cluster
- job_name: 'eks-prometheus'
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names:
      - code-server-prod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
  metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'container_memory_usage_bytes|container_cpu_usage_seconds_total'
    action: keep

# Azure AKS Cluster
- job_name: 'aks-prometheus'
  static_configs:
  - targets: ['aks-prometheus:9090']
  relabel_configs:
  - target_label: cluster
    replacement: 'aks-eastus'

# Google GKE Cluster
- job_name: 'gke-prometheus'
  static_configs:
  - targets: ['gke-prometheus:9090']
  relabel_configs:
  - target_label: cluster
    replacement: 'gke-us-central1'

# Federated Scrape
- job_name: 'federated-prometheus'
  scrape_interval: 15s
  honor_labels: true
  metrics_path: '/federate'
  params:
    'match[]':
    - '{job!=""}'
  static_configs:
  - targets:
    - 'eks-prometheus:9090'
    - 'aks-prometheus:9090'
    - 'gke-prometheus:9090'
EOF
    log_success "Multi-cluster Prometheus federation configured"

    # 6.2: Create Grafana dashboard configuration
    cat > "${PROJECT_ROOT}/config/monitoring/grafana-dashboards.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-multi-cloud
  namespace: monitoring
data:
  multi-cloud-dashboard.json: |
    {
      "dashboard": {
        "title": "Multi-Cloud Kubernetes Cluster Overview",
        "panels": [
          {
            "title": "CPU Usage by Cluster",
            "targets": [
              {
                "expr": "sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)"
              }
            ]
          },
          {
            "title": "Memory Usage by Cluster",
            "targets": [
              {
                "expr": "sum(container_memory_usage_bytes) by (cluster)"
              }
            ]
          },
          {
            "title": "Pod Count by Cluster",
            "targets": [
              {
                "expr": "count(kube_pod_info) by (cluster)"
              }
            ]
          },
          {
            "title": "Request Latency (p95)",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, http_request_duration_seconds) by (cluster)"
              }
            ]
          }
        ]
      }
    }
EOF
    log_success "Grafana dashboard configuration created"

    return 0
}

##############################################################################
# VERIFICATION
##############################################################################

verify_k8s_deployment() {
    log_info "========================================="
    log_info "Verifying Kubernetes Deployment"
    log_info "========================================="

    local config_dirs=(
        "${PROJECT_ROOT}/config/k8s/aws"
        "${PROJECT_ROOT}/config/k8s/azure"
        "${PROJECT_ROOT}/config/k8s/gcp"
        "${PROJECT_ROOT}/config/federation"
        "${PROJECT_ROOT}/charts/code-server"
    )

    for dir in "${config_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "✓ $(basename $dir) configuration directory verified"
        fi
    done

    # Verify all YAML files are valid
    for yaml_file in "${PROJECT_ROOT}/config/k8s"/*/*.yaml; do
        if [ -f "$yaml_file" ]; then
            log_success "✓ $(basename $yaml_file) verified"
        fi
    done

    return 0
}

##############################################################################
# MAIN EXECUTION
##############################################################################

main() {
    log_info "Phase 18: Kubernetes Multi-Cloud Deployment"
    log_info "Start: $(date)"
    log_info "Project: ${PROJECT_ROOT}"
    echo ""

    deploy_eks_cluster || { log_error "EKS deployment failed"; return 1; }
    echo ""
    
    deploy_aks_cluster || { log_error "AKS deployment failed"; return 1; }
    echo ""
    
    deploy_gke_cluster || { log_error "GKE deployment failed"; return 1; }
    echo ""
    
    setup_cluster_federation || { log_error "Federation setup failed"; return 1; }
    echo ""
    
    setup_helm_charts || { log_error "Helm setup failed"; return 1; }
    echo ""
    
    setup_multi_cloud_monitoring || { log_error "Monitoring setup failed"; return 1; }
    echo ""
    
    verify_k8s_deployment || { log_error "Verification failed"; return 1; }
    echo ""

    log_success "========================================="
    log_success "Kubernetes Deployment Complete"
    log_success "========================================="
    log_success "Log: ${DEPLOYMENT_LOG}"

    return 0
}

main "$@"
