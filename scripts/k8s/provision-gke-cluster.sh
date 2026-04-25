#!/bin/bash
###############################################################################
# @file        scripts/k8s/provision-gke-cluster.sh
# @module      k8s/provision-gke-cluster
# @description Infrastructure automation script
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/k8s/provision-gke-cluster.sh
# @description Provisions Google Cloud GKE cluster with Istio and observability
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage ./provision-gke-cluster.sh <project-id> [cluster-name] [region] [nodes] [machine-type]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ID="${1:-}"
CLUSTER_NAME="${2:-code-server-enterprise-prod}"
REGION="${3:-us-central1}"
NODE_COUNT="${4:-3}"
MACHINE_TYPE="${5:-n1-standard-2}"
KUBERNETES_VERSION="${6:-1.27}"
readonly ISTIO_VERSION="1.18.0"

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: PROJECT_ID is required${NC}"
    echo "Usage: $0 <project-id> [cluster-name] [region] [node-count] [machine-type]"
    exit 1
fi

echo -e "${GREEN}=== GKE Cluster Provisioning ===${NC}"
echo "Project ID: $PROJECT_ID"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

command -v gcloud &> /dev/null || { echo "gcloud CLI not found"; exit 1; }
command -v kubectl &> /dev/null || { echo "kubectl not found"; exit 1; }

echo -e "${YELLOW}Configuring GCP...${NC}"
gcloud config set project "$PROJECT_ID"
gcloud services enable container.googleapis.com compute.googleapis.com

echo -e "${YELLOW}Creating GKE cluster...${NC}"
gcloud container clusters create "$CLUSTER_NAME" \
    --region "$REGION" \
    --num-nodes "$NODE_COUNT" \
    --machine-type "$MACHINE_TYPE" \
    --enable-ip-alias \
    --enable-autorepair \
    --enable-autoupgrade \
    --addons HttpLoadBalancing \
    --workload-pool="$PROJECT_ID.svc.id.goog" \
    --cluster-version "$KUBERNETES_VERSION" \
    --labels "governance=GOV-002,environment=production"

echo -e "${YELLOW}Updating kubeconfig...${NC}"
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION"

echo -e "${YELLOW}Installing Istio...${NC}"
curl -L https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" sh -
export PATH=$PWD/istio-${ISTIO_VERSION}/bin:$PATH
istioctl install --set profile=production -y

kubectl label namespace default istio-injection=enabled --overwrite

echo -e "${YELLOW}Installing monitoring stack...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring

echo -e "${GREEN}✓ GKE cluster ready!${NC}"
echo "Next: Deploy Helm chart with: helm install code-server-enterprise ./helm/code-server-enterprise -n code-server-enterprise"
