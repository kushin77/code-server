#!/bin/bash
# GOV-002: Enterprise Governance Compliance
# Component: Istio Service Mesh Installation Script
# Date: April 25, 2026
# Version: 1.0.0
# Purpose: Automated Istio installation and configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_success "kubectl found: $(kubectl version --client --short)"
    
    # Check Helm (optional)
    if command -v helm &> /dev/null; then
        log_success "Helm found: $(helm version --short)"
    else
        log_warning "Helm not found (optional)"
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_success "Connected to Kubernetes cluster"
    
    # Check Kubernetes version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | grep -oP 'v\K[^.]+\.[^.]+' || echo "unknown")
    log_info "Kubernetes version: $K8S_VERSION"
    
    # Check for istioctl
    if ! command -v istioctl &> /dev/null; then
        log_warning "istioctl not found - installing..."
        install_istioctl
    else
        log_success "istioctl found: $(istioctl version)"
    fi
}

# Install istioctl if not present
install_istioctl() {
    log_info "Installing istioctl..."
    
    # Detect OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    
    ISTIO_VERSION="1.18.0"
    DOWNLOAD_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-${OS}-${ARCH}.tar.gz"
    
    log_info "Downloading Istio from $DOWNLOAD_URL..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    curl -L "$DOWNLOAD_URL" | tar xz
    
    sudo mv "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/istioctl
    sudo chmod +x /usr/local/bin/istioctl
    
    cd -
    rm -rf "$TEMP_DIR"
    
    log_success "istioctl installed: $(istioctl version)"
}

# Install Istio control plane
install_istio() {
    log_info "Installing Istio control plane (v1.18.0)..."
    
    # Create istio-system namespace
    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    log_info "istio-system namespace created"
    
    # Install Istio using istioctl
    istioctl install --set profile=production \
        --set meshConfig.enableAutoMtls=true \
        --set meshConfig.mtlsPolicy=STRICT \
        --set meshConfig.accessLogFile="/dev/stdout" \
        -y
    
    log_success "Istio control plane installed"
    
    # Wait for Istio pods to be ready
    log_info "Waiting for Istio control plane to be ready..."
    kubectl rollout status deployment/istiod -n istio-system --timeout=300s
    log_success "Istio control plane ready"
}

# Deploy Istio configuration
deploy_istio_config() {
    log_info "Deploying Istio configuration..."
    
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    CONFIG_DIR="$SCRIPT_DIR"
    
    # Deploy namespaces
    log_info "Deploying namespaces..."
    kubectl apply -f "$CONFIG_DIR/namespace.yaml"
    
    # Wait for namespace labels to be applied
    sleep 2
    
    # Deploy security policies
    log_info "Deploying security policies (mTLS enforcement)..."
    kubectl apply -f "$CONFIG_DIR/peer-authentication.yaml"
    
    # Deploy gateway
    log_info "Deploying ingress gateway..."
    kubectl apply -f "$CONFIG_DIR/gateway.yaml"
    
    # Deploy destination rules
    log_info "Deploying destination rules (traffic policies)..."
    kubectl apply -f "$CONFIG_DIR/destination-rules.yaml"
    
    # Deploy telemetry configuration
    log_info "Deploying telemetry configuration (Jaeger tracing)..."
    kubectl apply -f "$CONFIG_DIR/telemetry.yaml"
    
    # Deploy proxy configuration
    log_info "Deploying proxy configuration..."
    kubectl apply -f "$CONFIG_DIR/proxy-config.yaml"
    
    log_success "Istio configuration deployed"
}

# Verify installation
verify_installation() {
    log_info "Verifying Istio installation..."
    
    # Check Istio control plane
    log_info "Checking Istio control plane pods..."
    kubectl get pods -n istio-system
    
    # Check Istio configuration
    log_info "Checking Istio resources in code-server-enterprise namespace..."
    kubectl get peerauthentication,gateway,virtualservice,destinationrule -n code-server-enterprise
    
    # Check ingress gateway
    log_info "Checking ingress gateway..."
    kubectl get svc -n istio-system -l istio=ingressgateway
    
    # Get ingress gateway external IP
    INGRESS_IP=$(kubectl get svc -n istio-system -l istio=ingressgateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    log_info "Ingress gateway external IP: $INGRESS_IP"
    
    log_success "Installation verification complete"
}

# Enable sidecar injection for namespace
enable_sidecar_injection() {
    NAMESPACE="${1:-code-server-enterprise}"
    
    log_info "Enabling sidecar injection for namespace: $NAMESPACE"
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite
    
    log_info "Rolling out deployments to inject sidecars..."
    kubectl rollout restart deployment -n "$NAMESPACE"
    
    log_success "Sidecar injection enabled for $NAMESPACE"
}

# Test mTLS enforcement
test_mtls() {
    log_info "Testing mTLS enforcement..."
    
    # Create test pod without sidecar
    kubectl run test-pod --image=curlimages/curl -n code-server-enterprise \
        --rm -it -- sleep 30 2>/dev/null || true
    
    # Try to connect to API service (should fail without proper mTLS)
    log_info "Testing connectivity to API service..."
    kubectl run test-client --image=curlimages/curl -n code-server-enterprise \
        --rm -it -- curl -v http://api:3100/health 2>&1 | grep -E "(Connected|refused|403)" || true
    
    log_warning "mTLS test requires manual verification - check kubectl logs"
}

# Main installation flow
main() {
    log_info "Starting Istio Service Mesh installation..."
    log_info "Version: 1.18.0 | Profile: Production | mTLS: STRICT"
    
    check_prerequisites
    install_istio
    deploy_istio_config
    enable_sidecar_injection "code-server-enterprise"
    verify_installation
    
    log_success "Istio Service Mesh installation complete!"
    log_info "Next steps:"
    log_info "1. Deploy your applications (sidecars will be injected automatically)"
    log_info "2. Access Jaeger UI: kubectl port-forward -n code-server-enterprise svc/jaeger 16686:16686"
    log_info "3. Access Grafana: kubectl port-forward -n code-server-enterprise svc/grafana 3000:3000"
    log_info "4. Verify services: kubectl get pods -n code-server-enterprise"
}

# Run main function
main "$@"
