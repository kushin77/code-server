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

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

RESOURCE_GROUP="${1:-code-server-rg}"
CLUSTER_NAME="${2:-code-server-enterprise-prod}"
LOCATION="${3:-eastus}"
NODE_COUNT="${4:-3}"
VM_SIZE="${5:-Standard_D2s_v3}"

run_or_log() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] $*"
    else
        "$@"
    fi
}

log_section "AKS Cluster Provisioning"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Cluster Name: $CLUSTER_NAME"
log_info "Location: $LOCATION"

if [[ "$DRY_RUN" == false ]]; then
    command -v az &> /dev/null || { log_error "Azure CLI not found"; exit 1; }
    command -v kubectl &> /dev/null || { log_error "kubectl not found"; exit 1; }
    command -v helm &> /dev/null || { log_error "helm not found"; exit 1; }
else
    log_info "[DRY-RUN] Skipping az/kubectl/helm availability checks"
fi

log_info "Creating resource group..."
run_or_log az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

log_info "Creating AKS cluster..."
run_or_log az aks create \
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

log_info "Updating kubeconfig..."
run_or_log az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

log_info "Installing Istio..."
if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would extract and install Istio production profile"
else
    curl -L https://istio.io/downloadIstio | sh -
    export PATH=$PWD/istio-1.18.0/bin:$PATH
    istioctl install --set profile=production -y
fi

run_or_log kubectl label namespace default istio-injection=enabled --overwrite

log_info "Installing monitoring..."
run_or_log helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
run_or_log helm repo update
if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would create monitoring namespace and install kube-prometheus-stack"
else
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring
fi

log_success "AKS cluster ready!"
log_info "Next: Deploy Helm chart with: helm install code-server-enterprise ./helm/code-server-enterprise -n code-server-enterprise"
