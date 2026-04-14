#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/code-server-enterprise"

# Source logging library for structured logging
export LOG_FILE="${SCRIPT_DIR}/deployment.log"
source "${SCRIPT_DIR}/scripts/logging.sh" || {
    echo "ERROR: Cannot source logging library at ${SCRIPT_DIR}/scripts/logging.sh"
    exit 1
}

# Deployment target (default: 192.168.168.32)
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.32}"
DEPLOY_SSH_USER="${DEPLOY_SSH_USER:-akushnir}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-/home/akushnir/.ssh/id_ed25519}"
DEPLOY_SSH_PORT="${DEPLOY_SSH_PORT:-22}"
IS_REMOTE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host) DEPLOY_HOST="$2"; IS_REMOTE=true; shift 2 ;;
        --user) DEPLOY_SSH_USER="$2"; shift 2 ;;
        --key) DEPLOY_SSH_KEY="$2"; shift 2 ;;
        --local) IS_REMOTE=false; shift ;;
        --help) log_info "Usage: $0 [--host <ip>] [--user <user>] [--key <path>] [--local]"; exit 0 ;;
        *) shift ;;
    esac
done

# Deploy to remote host via SSH
deploy_remote() {
    local host=$1
    local user=$2
    local key=$3
    local port=$4
    
    log_info "Preparing remote deployment to ${user}@${host}:${port}"
    
    # Test SSH connectivity
    if ! ssh -i "${key}" -p "${port}" -o StrictHostKeyChecking=no "${user}@${host}" "echo OK" &>/dev/null; then
        log_error "Cannot connect to ${user}@${host}:${port}"
        return 1
    fi
    log_success "✓ SSH connectivity verified"
    
    # Create deployment package
    log_info "Creating deployment package..."
    mkdir -p /tmp/code-server-deploy
    cp -r "${PROJECT_DIR}"/* /tmp/code-server-deploy/ 2>/dev/null || true
    cd /tmp/code-server-deploy
    
    # Copy to remote
    log_info "Uploading to remote host..."
    scp -i "${key}" -P "${port}" -r . "${user}@${host}:/home/${user}/code-server-deploy/" || {
        log_error "Failed to upload deployment package"
        return 1
    }
    
    # Execute remote deployment
    log_info "Executing remote deployment..."
    ssh -i "${key}" -p "${port}" "${user}@${host}" "
        cd /home/${user}/code-server-deploy && \
        docker-compose down 2>/dev/null || true && \
        docker-compose up -d && \
        docker-compose ps
    " || {
        log_error "Remote deployment failed"
        return 1
    }
    
    log_success "✓ Remote deployment successful"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    log_success "✓ Docker found"
}

# Install/update Terraform
install_terraform() {
    log_info "Checking Terraform installation..."

    if command -v terraform &> /dev/null; then
        TF_VERSION=$(terraform version | head -n1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        log_success "✓ Terraform ${TF_VERSION} found"
        return 0
    fi

    log_info "Installing Terraform..."

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        ARCH="amd64"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="darwin"
        ARCH="amd64"
    else
        log_error "Unsupported OS: $OSTYPE (Linux-only development mandate)"
        exit 1
    fi

    TF_VERSION="1.6.0"
    TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
    TF_INSTALL_DIR="/usr/local/bin"

    log_info "Downloading Terraform ${TF_VERSION}..."
    wget -q "${TF_URL}" -O /tmp/terraform.zip
    unzip -q /tmp/terraform.zip -d "${TF_INSTALL_DIR}"
    chmod +x "${TF_INSTALL_DIR}/terraform"
    rm /tmp/terraform.zip

    log_success "✓ Terraform installed"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."

    cd "${PROJECT_DIR}"
    terraform init -upgrade

    log_success "✓ Terraform initialized"
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
    log INFO "1. Open browser: https://ide.kushnir.cloud"
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
    log INFO "Starting Code-Server Enterprise Deployment"
    log INFO "Log file: ${LOG_FILE}"
    log INFO "Target: ${DEPLOY_HOST}"
    log INFO "Remote deployment: ${IS_REMOTE}"
    log INFO ""

    check_prerequisites
    
    if [[ "${IS_REMOTE}" == "true" ]]; then
        log INFO "Deploying to remote host: ${DEPLOY_HOST}"
        deploy_remote "${DEPLOY_HOST}" "${DEPLOY_SSH_USER}" "${DEPLOY_SSH_KEY}" "${DEPLOY_SSH_PORT}" || {
            log ERROR "Remote deployment failed"
            exit 1
        }
    else
        log INFO "Deploying locally"
        install_terraform
        init_terraform
        validate_terraform
        plan_deploymen
        apply_deploymen
        output_details
        cleanup
    fi

    log SUCCESS ""
    log SUCCESS "🎉 Deployment complete!"
    log INFO "Target host: https://${DEPLOY_HOST}"
}

# Run main function
main
