#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# Helm Setup for Kubernetes Package Management
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Install and configure Helm for package management
# Idempotency: All operations check before executing
# ═════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo "[Helm Setup] Starting Helm installation and configuration..."

# Check if Helm is already installed
if command -v helm &> /dev/null; then
    echo "[Helm Setup] Helm is already installed at $(command -v helm)"
    HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
    echo "[Helm Setup] Helm version: $HELM_VERSION"
    exit 0
fi

# Install Helm from official script
echo "[Helm Setup] Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

if command -v helm &> /dev/null; then
    echo "[Helm Setup] Helm installed successfully"
    helm version --short
else
    echo "[Helm Setup] ERROR: Helm installation failed"
    exit 1
fi

echo "[Helm Setup] Helm setup complete"
