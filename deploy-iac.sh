#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/code-server-enterprise"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Color codes for outpu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shif
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${BLUE}[${timestamp}]${NC} ${message}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[${timestamp}]${NC} ${message}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}]${NC} ${message}"
            ;;
    esac
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log ERROR "Docker is not installed"
        exit 1
    fi
    log SUCCESS "✓ Docker found"

    # Check WSL (if on Windows)
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        if ! command -v wsl &> /dev/null; then
            log ERROR "WSL is not installed"
            exit 1
        fi
        log SUCCESS "✓ WSL found"
    fi
}

# Install/update Terraform
install_terraform() {
    log INFO "Checking Terraform installation..."

    if command -v terraform &> /dev/null; then
        TF_VERSION=$(terraform version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        log SUCCESS "✓ Terraform ${TF_VERSION} found"
        return 0
    fi

    log INFO "Installing Terraform..."

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        ARCH="amd64"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
        ARCH="amd64"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
        ARCH="amd64"
    else
        log ERROR "Unsupported OS: $OSTYPE"
        exit 1
    fi

    TF_VERSION="1.6.0"
    TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
    TF_INSTALL_DIR="/usr/local/bin"

    log INFO "Downloading Terraform ${TF_VERSION}..."
    wget -q "${TF_URL}" -O /tmp/terraform.zip
    unzip -q /tmp/terraform.zip -d "${TF_INSTALL_DIR}"
    chmod +x "${TF_INSTALL_DIR}/terraform"
    rm /tmp/terraform.zip

    log SUCCESS "✓ Terraform installed"
}

# Initialize Terraform
init_terraform() {
    log INFO "Initializing Terraform..."

    cd "${PROJECT_DIR}"
    terraform init -upgrade

    log SUCCESS "✓ Terraform initialized"
}

# Validate Terraform configuration
validate_terraform() {
    log INFO "Validating Terraform configuration..."

    cd "${PROJECT_DIR}"
    terraform validate

    log SUCCESS "✓ Terraform configuration is valid"
}

# Plan deploymen
plan_deployment() {
    log INFO "Planning deployment..."

    cd "${PROJECT_DIR}"
    terraform plan -out=tfplan

    log SUCCESS "✓ Deployment plan created"
}

# Apply deploymen
apply_deployment() {
    log INFO "Applying Terraform configuration..."

    cd "${PROJECT_DIR}"
    terraform apply -auto-approve tfplan

    log SUCCESS "✓ Deployment applied"
}

# Output access details
output_details() {
    log INFO "Retrieving access details..."

    cd "${PROJECT_DIR}"

    log SUCCESS "=========================================="
    log SUCCESS "Code-Server Enterprise Deployment Complete"
    log SUCCESS "=========================================="

    terraform output -raw code_server_url 2>/dev/null
    log SUCCESS "Password: $(terraform output -raw code_server_password 2>/dev/null || echo 'See .tfstate')"

    log INFO ""
    log INFO "Next steps:"
    log INFO "1. Open browser: http://localhost"
    log INFO "2. Login with password above"
    log INFO "3. No GitHub authentication needed"
    log INFO "4. All infrastructure managed by Terraform"
    log INFO ""
}

# Cleanup function
cleanup() {
    log WARN "Cleaning up..."
    cd "${PROJECT_DIR}"
    rm -f tfplan
    log SUCCESS "Cleanup complete"
}

# Main execution
main() {
    log INFO "Starting Code-Server Enterprise IaC Deployment"
    log INFO "Log file: ${LOG_FILE}"
    log INFO ""

    check_prerequisites
    install_terraform
    init_terraform
    validate_terraform
    plan_deploymen
    apply_deploymen
    output_details
    cleanup

    log SUCCESS ""
    log SUCCESS "🎉 Deployment successful! Access your IDE at: http://localhost"
}

# Run main function
main
