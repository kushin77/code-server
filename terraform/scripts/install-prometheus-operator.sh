#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# Prometheus Operator Installation for Kubernetes Monitoring
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Install and configure Prometheus Operator for cluster monitoring
# Idempotency: All operations check before executing
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo "[Prometheus] Starting Prometheus Operator installation..."

# Wait for Kubernetes API to be ready
MAX_RETRIES=30
RETRY_COUNT=0
while ! kubectl get nodes &>/dev/null; do
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[Prometheus] ERROR: Kubernetes API not ready after $MAX_RETRIES attempts"
        exit 1
    fi
    echo "[Prometheus] Waiting for Kubernetes API... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 2
    ((RETRY_COUNT++))
done

# Add Prometheus Helm repository
echo "[Prometheus] Adding Prometheus Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Check if Prometheus namespace exists
if kubectl get namespace prometheus &>/dev/null; then
    echo "[Prometheus] Prometheus namespace already exists"
else
    echo "[Prometheus] Creating prometheus namespace..."
    kubectl create namespace prometheus
fi

# Check if Prometheus Operator release exists
if helm list -n prometheus | grep -q prometheus-operator; then
    echo "[Prometheus] Prometheus Operator already installed"
else
    echo "[Prometheus] Installing Prometheus Operator..."
    helm install prometheus-operator prometheus-community/kube-prometheus-stack \
        -n prometheus \
        --set prometheus.prometheusSpec.retention=30d \
        --set alertmanager.enabled=true \
        --set grafana.enabled=true
fi

echo "[Prometheus] Prometheus Operator installation complete"
