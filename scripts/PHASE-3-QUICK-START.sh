#!/bin/bash

# Phase 3 Production Deployment Guide - Quick Start
# Issue: kushin77/code-server#164 - k3s Kubernetes Deployment
# Target: 192.168.168.31
# Purpose: Deploy k3s cluster with GPU, storage, and networking ready

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PHASE_START=$(date +%s)

echo -e "${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║          Phase 3 Issue #164: k3s Kubernetes Deployment                    ║"
echo "║                    Production Ready - Quick Start                         ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BLUE}Date: $(date)${NC}"
echo -e "${BLUE}Host Target: 192.168.168.31${NC}"
echo ""

# ============================================================================
# STEP 1: Environment Setup
# ============================================================================

echo -e "${YELLOW}[STEP 1] Environment Validation${NC}"
echo ""

if ! command -v kubectl &>/dev/null; then
    echo -e "${YELLOW}⚠ kubectl not in local path - will install on target${NC}"
fi

if ! command -v ssh &>/dev/null; then
    echo -e "${RED}✗ ssh not available${NC}"
    exit 1
fi

REMOTE_USER="akushnir"
REMOTE_HOST="192.168.168.31"
REMOTE_ADDR="${REMOTE_USER}@${REMOTE_HOST}"

echo -e "${GREEN}✓ SSH available${NC}"
echo -e "${GREEN}✓ Target: $REMOTE_ADDR${NC}"
echo ""

# ============================================================================
# STEP 2: Transfer Deployment Scripts
# ============================================================================

echo -e "${YELLOW}[STEP 2] Transfer Deployment Scripts${NC}"
echo ""

SCRIPTS_TO_TRANSFER=(
    "scripts/phase3-k3s-setup.sh"
    "scripts/phase3-k3s-deploy.sh"
    "scripts/phase3-k3s-test.sh"
)

CONFIGS_TO_TRANSFER=(
    "kubernetes/storage-classes.yaml"
    "kubernetes/network-policies.yaml"
    "kubernetes/metallb-config.yaml"
)

echo "Transferring scripts..."
for script in "${SCRIPTS_TO_TRANSFER[@]}"; do
    if [ -f "$script" ]; then
        echo -e "  → $script"
        scp "$script" "$REMOTE_ADDR:/tmp/"
    else
        echo -e "${RED}  ✗ Missing: $script${NC}"
        exit 1
    fi
done

echo ""
echo "Transferring configurations..."
for config in "${CONFIGS_TO_TRANSFER[@]}"; do
    if [ -f "$config" ]; then
        echo -e "  → $config"
        scp "$config" "$REMOTE_ADDR:/tmp/"
    else
        echo -e "${RED}  ✗ Missing: $config${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ Files transferred${NC}"
echo ""

# ============================================================================
# STEP 3: Pre-Flight Checks (Remote)
# ============================================================================

echo -e "${YELLOW}[STEP 3] Pre-Flight Checks (Remote)${NC}"
echo ""

ssh "$REMOTE_ADDR" << 'REMOTE_CHECK'
set -euo pipefail

echo "Checking prerequisites..."

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  OS: $PRETTY_NAME"
    if ! echo "$ID" | grep -qE "ubuntu|debian|rhel|rocky|centos"; then
        echo "  ⚠ Unsupported OS: $ID"
    fi
fi

# Check kernel version
kernel_version=$(uname -r | cut -d. -f1,2)
echo "  Kernel: $(uname -r)"

# Check CPU
cpu_count=$(nproc)
echo "  CPU cores: $cpu_count"

# Check memory
mem_gb=$(free -g | awk 'NR==2 {print $2}')
echo "  Memory: ${mem_gb}GB"

# Check disk
disk_available=$(df /var/lib | tail -1 | awk '{print int($4/1024/1024)}')
echo "  Disk (/var/lib): ${disk_available}GB available"

# Check network
if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    echo "  Network: ✓ Operational"
else
    echo "  Network: ⚠ No external internet"
fi

# Check GPU (if available)
if command -v nvidia-smi &>/dev/null; then
    gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    echo "  GPU: $gpu_count device(s)"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | sed 's/^/    /'
else
    echo "  GPU: Not detected"
fi

echo ""
echo "✓ Pre-flight checks complete"

REMOTE_CHECK

echo ""

# ============================================================================
# STEP 4: k3s Setup
# ============================================================================

echo -e "${YELLOW}[STEP 4] k3s Installation${NC}"
echo ""
echo "Running: phase3-k3s-setup.sh"
echo ""

ssh "$REMOTE_ADDR" "sudo bash /tmp/phase3-k3s-setup.sh" || {
    echo -e "${RED}✗ Setup failed${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ k3s setup complete${NC}"
echo ""

# ============================================================================
# STEP 5: k3s Cluster Deployment
# ============================================================================

echo -e "${YELLOW}[STEP 5] k3s Cluster Deployment${NC}"
echo ""
echo "Running: phase3-k3s-deploy.sh"
echo "(This may take 5-10 minutes - please wait)"
echo ""

ssh "$REMOTE_ADDR" "sudo bash /tmp/phase3-k3s-deploy.sh" || {
    echo -e "${RED}✗ Deployment failed${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ k3s cluster deployment complete${NC}"
echo ""

# ============================================================================
# STEP 6: Apply Kubernetes Manifests
# ============================================================================

echo -e "${YELLOW}[STEP 6] Apply Kubernetes Configurations${NC}"
echo ""

ssh "$REMOTE_ADDR" << 'REMOTE_APPLY'
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for API server..."
while ! kubectl cluster-info &>/dev/null; do
    echo "  ... waiting ..."
    sleep 5
done

echo "✓ API server ready"
echo ""

echo "Applying storage classes..."
sudo kubectl apply -f /tmp/storage-classes.yaml
echo "✓ Storage configured"
echo ""

echo "Applying network policies..."
sudo kubectl apply -f /tmp/network-policies.yaml
echo "✓ Network policies configured"
echo ""

echo "Applying MetalLB configuration..."
sudo kubectl apply -f /tmp/metallb-config.yaml
echo "✓ Load balancer configured"
echo ""

echo "Waiting for system pods..."
sleep 10

echo "System pod status:"
sudo kubectl get pods -n kube-system -o wide
echo ""

REMOTE_APPLY

echo -e "${GREEN}✓ Kubernetes configurations applied${NC}"
echo ""

# ============================================================================
# STEP 7: Validation
# ============================================================================

echo -e "${YELLOW}[STEP 7] Cluster Validation${NC}"
echo ""

ssh "$REMOTE_ADDR" "sudo bash /tmp/phase3-k3s-test.sh" || {
    echo -e "${YELLOW}⚠ Some tests failed - review output above${NC}"
}

echo ""

# ============================================================================
# STEP 8: Post-Deployment Configuration
# ============================================================================

echo -e "${YELLOW}[STEP 8] Post-Deployment Configuration${NC}"
echo ""

ssh "$REMOTE_ADDR" << 'REMOTE_CONFIG'
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Cluster Information:"
echo "====================="
echo ""
echo "API Server: https://192.168.168.31:6443"
echo ""

echo "Nodes:"
sudo kubectl get nodes -o wide
echo ""

echo "Storage Classes:"
sudo kubectl get storageclasses
echo ""

echo "System Pods:"
sudo kubectl get pods -n kube-system -o wide
echo ""

echo "Services:"
sudo kubectl get svc -A
echo ""

echo "Load Balancer Addresses:"
sudo kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}'
echo ""

# Save kubeconfig for local access
echo "Creating kubeconfig file..."
sudo cp /etc/rancher/k3s/k3s.yaml /tmp/k3s.kubeconfig
sudo chmod 644 /tmp/k3s.kubeconfig

REMOTE_CONFIG

echo ""

# ============================================================================
# STEP 9: Download kubeconfig
# ============================================================================

echo -e "${YELLOW}[STEP 9] Local Configuration${NC}"
echo ""

if scp "$REMOTE_ADDR:/tmp/k3s.kubeconfig" "./k3s.kubeconfig" 2>/dev/null; then
    echo -e "${GREEN}✓ kubeconfig downloaded: ./k3s.kubeconfig${NC}"
    echo ""
    echo "To use locally:"
    echo "  export KUBECONFIG=\$PWD/k3s.kubeconfig"
    echo "  kubectl get nodes"
else
    echo -e "${YELLOW}⚠ Could not download kubeconfig - copy manually if needed${NC}"
fi

echo ""

# ============================================================================
# STEP 10: Verification Summary
# ============================================================================

PHASE_END=$(date +%s)
PHASE_DURATION=$((PHASE_END - PHASE_START))

echo -e "${MAGENTA}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                     DEPLOYMENT COMPLETE                                   ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${GREEN}✓ Duration: ${PHASE_DURATION}s ($(date -d@${PHASE_DURATION} +%H:%M:%S 2>/dev/null || echo ${PHASE_DURATION}s))${NC}"
echo ""

# ============================================================================
# Next Steps
# ============================================================================

echo -e "${BLUE}NEXT STEPS:${NC}"
echo ""
echo "1. Verify cluster is operational:"
echo "   export KUBECONFIG=./k3s.kubeconfig"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo ""
echo "2. Test GPU allocation (if GPU present):"
echo "   kubectl describe node | grep -i gpu"
echo ""
echo "3. Test storage:"
echo "   kubectl apply -f - <<EOF"
echo "   apiVersion: v1"
echo "   kind: PersistentVolumeClaim"
echo "   metadata:"
echo "     name: test-pvc"
echo "   spec:"
echo "     accessModes:"
echo "       - ReadWriteOnce"
echo "     storageClassName: local-path"
echo "     resources:"
echo "       requests:"
echo "         storage: 1Gi"
echo "   EOF"
echo ""
echo "4. Proceed to Issue #165 (Harbor Registry):"
echo "   Once verified, deploy Harbor for private container registry"
echo ""
echo "5. Document any custom configurations:"
echo "   - Storage paths"
echo "   - Network settings"
echo "   - GPU scheduling policies"
echo ""

echo -e "${BLUE}CLUSTER ACCESS:${NC}"
echo ""
echo "Local (with kubeconfig):"
echo "  kubectl get nodes"
echo ""
echo "Remote (SSH to host):"
echo "  ssh akushnir@192.168.168.31"
echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo "  kubectl get nodes"
echo ""

echo -e "${BLUE}MONITORING & TROUBLESHOOTING:${NC}"
echo ""
echo "Check logs:"
echo "  ssh akushnir@192.168.168.31 journalctl -u k3s -f"
echo ""
echo "Check status:"
echo "  ssh akushnir@192.168.168.31 sudo systemctl status k3s"
echo ""
echo "Check resources:"
echo "  kubectl top nodes"
echo "  kubectl top pods -A"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Phase 3 Issue #164: k3s Deployment - COMPLETE ✓${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

exit 0
