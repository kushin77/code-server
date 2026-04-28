#!/bin/bash
###############################################################################
# @file        scripts/k8s/provision-aks-cluster.sh
# @module      k8s/provision-aks-cluster
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
# @file scripts/k8s/provision-aks-cluster.sh
# @description Provisions Azure AKS cluster with Istio and observability
# @governance GOV-002: Immutable infrastructure provisioning
# @usage ./provision-aks-cluster.sh [resource-group] [cluster-name] [location] [nodes] [vm-size]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

RESOURCE_GROUP="${1:-code-server-rg}"
CLUSTER_NAME="${2:-code-server-enterprise-prod}"
LOCATION="${3:-eastus}"
NODE_COUNT="${4:-3}"
VM_SIZE="${5:-Standard_D2s_v3}"

echo -e "${GREEN}=== AKS Cluster Provisioning ===${NC}"
echo "Resource Group: $RESOURCE_GROUP"
echo "Cluster Name: $CLUSTER_NAME"
echo "Location: $LOCATION"
echo ""

command -v az &> /dev/null || { echo "Azure CLI not found"; exit 1; }
command -v kubectl &> /dev/null || { echo "kubectl not found"; exit 1; }

echo -e "${YELLOW}Creating resource group...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" || true

echo -e "${YELLOW}Creating AKS cluster...${NC}"
az aks create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --node-count "$NODE_COUNT" \
    --vm-set-type VirtualMachineScaleSets \
    --load-balancer-sku standard \
    --enable-managed-identity \
    --network-plugin azure \
    --network-policy azure \
    --enable-cluster-autoscaling \
    --min-count "$NODE_COUNT" \
    --max-count $((NODE_COUNT * 3)) \
    --node-vm-size "$VM_SIZE"

echo -e "${YELLOW}Updating kubeconfig...${NC}"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo -e "${YELLOW}Installing Istio...${NC}"
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.18.0/bin:$PATH
istioctl install --set profile=production -y

kubectl label namespace default istio-injection=enabled --overwrite

echo -e "${YELLOW}Installing monitoring...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring

echo -e "${GREEN}✓ AKS cluster ready!${NC}"
echo "Next: Deploy Helm chart with: helm install code-server-enterprise ./helm/code-server-enterprise -n code-server-enterprise"
