#!/bin/bash
###############################################################################
# @file        scripts/k8s/provision-eks-cluster.sh
# @module      k8s/provision-eks-cluster
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/k8s/provision-eks-cluster.sh
# @description Provisions AWS EKS cluster with Istio and observability for code-server-enterprise
# @governance GOV-002: Immutable infrastructure provisioning
# @usage ./provision-eks-cluster.sh --name code-server-enterprise-prod --region us-east-1 --nodes 3 --instance-type t3.large

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Configuration
CLUSTER_NAME="${1:-code-server-enterprise-prod}"
REGION="${2:-us-east-1}"
NODE_COUNT="${3:-3}"
INSTANCE_TYPE="${4:-t3.large}"
KUBERNETES_VERSION="${5:-1.27}"
readonly ISTIO_VERSION="1.18.0"

echo -e "${GREEN}=== EKS Cluster Provisioning ===${NC}"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Node Count: $NODE_COUNT"
echo "Instance Type: $INSTANCE_TYPE"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/8] Checking prerequisites...${NC}"
command -v eksctl &> /dev/null || { echo "eksctl not found. Install: https://eksctl.io"; exit 1; }
command -v aws &> /dev/null || { echo "AWS CLI not found. Install: https://aws.amazon.com/cli/"; exit 1; }
command -v kubectl &> /dev/null || { echo "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"; exit 1; }
echo -e "${GREEN}✓ All prerequisites installed${NC}"

# Verify AWS credentials
echo -e "${YELLOW}[2/8] Verifying AWS credentials...${NC}"
aws sts get-caller-identity > /dev/null || { echo "AWS credentials not configured"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: $ACCOUNT_ID${NC}"

# Check if cluster already exists
echo -e "${YELLOW}[3/8] Checking if cluster already exists...${NC}"
if eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${YELLOW}⚠ Cluster already exists. Skipping creation.${NC}"
else
    echo -e "${YELLOW}[4/8] Creating EKS cluster...${NC}"
    eksctl create cluster \
        --name "$CLUSTER_NAME" \
        --region "$REGION" \
        --version "$KUBERNETES_VERSION" \
        --nodegroup-name primary \
        --node-type "$INSTANCE_TYPE" \
        --nodes "$NODE_COUNT" \
        --nodes-min "$NODE_COUNT" \
        --nodes-max $((NODE_COUNT * 3)) \
        --with-oidc \
        --enable-ssm \
        --managed \
        --asg-access \
        --external-dns-access \
        --full-ecr-access \
        --tags "governance=GOV-002,environment=production,managed-by=eksctl"

    echo -e "${GREEN}✓ EKS cluster created${NC}"
fi

# Update kubeconfig
echo -e "${YELLOW}[5/8] Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
echo -e "${GREEN}✓ Kubeconfig updated${NC}"

# Verify cluster access
echo -e "${YELLOW}[6/8] Verifying cluster access...${NC}"
kubectl cluster-info
kubectl get nodes
echo -e "${GREEN}✓ Cluster access verified${NC}"

# Install Istio
echo -e "${YELLOW}[7/8] Installing Istio service mesh...${NC}"
# Download Istio if not present
if [ ! -d "istio-1.18.0" ]; then
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh -
fi

# Add Istio to PATH
export PATH=$PWD/istio-${ISTIO_VERSION}/bin:$PATH

# Install Istio
istioctl install --set profile=production -y

# Label default namespace for sidecar injection
kubectl label namespace default istio-injection=enabled --overwrite
kubectl label namespace default governance.policy=GOV-002 --overwrite

echo -e "${GREEN}✓ Istio installed${NC}"

# Install Prometheus & Grafana
echo -e "${YELLOW}[8/8] Installing monitoring stack (Prometheus, Grafana, Loki, Jaeger)...${NC}"

# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace monitoring istio-injection=enabled --overwrite 2>/dev/null || true

# Install kube-prometheus-stack (includes Prometheus, Grafana, AlertManager)
helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values - <<EOF
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  persistence:
    enabled: true
    size: 10Gi
  adminPassword: $(openssl rand -base64 12)

alertmanager:
  enabled: true
EOF

# Install Jaeger for distributed tracing
helm install jaeger jaegertracing/jaeger \
    --namespace monitoring \
    --values - <<EOF
elasticsearch:
  enabled: true
  replicas: 3
  persistence:
    size: 30Gi

collector:
  replicaCount: 3
EOF

# Install Loki for log aggregation
helm install loki grafana/loki-stack \
    --namespace monitoring \
    --values - <<EOF
loki:
  persistence:
    enabled: true
    size: 10Gi

promtail:
  config:
    clients:
    - url: http://loki:3100/loki/api/v1/push
EOF

echo -e "${GREEN}✓ Monitoring stack installed${NC}"

# Summary
echo ""
echo -e "${GREEN}=== EKS Cluster Provisioning Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Create namespace: kubectl create namespace code-server-enterprise"
echo "2. Label namespace: kubectl label namespace code-server-enterprise istio-injection=enabled"
echo "3. Deploy Helm chart: helm install code-server-enterprise ./helm/code-server-enterprise -n code-server-enterprise"
echo ""
echo "Access monitoring:"
echo "1. Grafana: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
echo "2. Prometheus: kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
echo "3. Jaeger: kubectl port-forward -n monitoring svc/jaeger 16686:16686"
echo ""
echo -e "${GREEN}Cluster ready for deployment!${NC}"
