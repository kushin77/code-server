#!/bin/bash
# CI/CD Pipeline Setup Script
# Configures GitHub Actions secrets and environments

set -e

COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

# Helper functions
log_info() { echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*"; }
log_warn() { echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $*"; }
log_error() { echo -e "${COLOR_RED}✗${COLOR_RESET} $*"; }

# Validate GitHub CLI
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) not found. Install from: https://cli.github.com"
    exit 1
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q)
log_info "Setting up CI/CD for: $REPO"

# Function to set secret
set_secret() {
    local secret_name=$1
    local secret_value=$2
    
    if [ -z "$secret_value" ]; then
        log_warn "Skipping $secret_name (empty value)"
        return
    fi
    
    echo "$secret_value" | gh secret set "$secret_name"
    log_success "Secret set: $secret_name"
}

# Function to set environment secret
set_env_secret() {
    local env_name=$1
    local secret_name=$2
    local secret_value=$3
    
    if [ -z "$secret_value" ]; then
        log_warn "Skipping $secret_name in $env_name (empty value)"
        return
    fi
    
    echo "$secret_value" | gh secret set "$secret_name" --env "$env_name"
    log_success "Secret set in $env_name: $secret_name"
}

# Function to create environment
create_environment() {
    local env_name=$1
    
    log_info "Creating environment: $env_name"
    gh api repos/{owner}/{repo}/environments \
        -X PUT \
        -f environment_name="$env_name" \
        -f deployment_branch_policy=null \
        -f reviewers='[]'
    log_success "Environment created: $env_name"
}

# Main setup
main() {
    log_info "Starting CI/CD setup..."
    
    # 1. Set repository-level secrets
    log_info ""
    log_info "=== Repository Secrets ==="
    
    read -p "GitHub Container Registry Token (for GHCR): " -s GHCR_TOKEN
    echo
    set_secret "GHCR_TOKEN" "$GHCR_TOKEN"
    
    read -p "Slack Webhook URL (for notifications): " -s SLACK_WEBHOOK
    echo
    set_secret "SLACK_WEBHOOK" "$SLACK_WEBHOOK"
    
    read -p "Snyk Token (for SAST): " -s SNYK_TOKEN
    echo
    set_secret "SNYK_TOKEN" "$SNYK_TOKEN"
    
    # 2. Create environments
    log_info ""
    log_info "=== Creating Environments ==="
    
    for env in staging production; do
        create_environment "$env"
    done
    
    # 3. Set staging environment secrets
    log_info ""
    log_info "=== Staging Environment Secrets ==="
    
    echo "Enter staging kubeconfig (paste and press Ctrl+D):"
    KUBECONFIG_STAGING=$(cat)
    KUBECONFIG_STAGING_B64=$(echo "$KUBECONFIG_STAGING" | base64)
    set_env_secret "staging" "KUBECONFIG_STAGING" "$KUBECONFIG_STAGING_B64"
    
    read -p "Staging Terraform State Bucket: " TF_STATE_BUCKET_STAGING
    set_env_secret "staging" "TF_STATE_BUCKET" "$TF_STATE_BUCKET_STAGING"
    
    read -p "Staging Cluster Context: " CLUSTER_CONTEXT_STAGING
    set_env_secret "staging" "KUBERNETES_CONTEXT" "$CLUSTER_CONTEXT_STAGING"
    
    # 4. Set production environment secrets
    log_info ""
    log_info "=== Production Environment Secrets ==="
    
    echo "Enter production kubeconfig (paste and press Ctrl+D):"
    KUBECONFIG_PROD=$(cat)
    KUBECONFIG_PROD_B64=$(echo "$KUBECONFIG_PROD" | base64)
    set_env_secret "production" "KUBECONFIG_PROD" "$KUBECONFIG_PROD_B64"
    
    read -p "Production Terraform State Bucket: " TF_STATE_BUCKET_PROD
    set_env_secret "production" "TF_STATE_BUCKET" "$TF_STATE_BUCKET_PROD"
    
    read -p "Production Cluster Context: " CLUSTER_CONTEXT_PROD
    set_env_secret "production" "KUBERNETES_CONTEXT" "$CLUSTER_CONTEXT_PROD"
    
    # 5. Verify setup
    log_info ""
    log_info "=== Verifying Setup ==="
    
    log_info "Repository Secrets:"
    gh secret list | head -10
    
    log_info ""
    log_info "Staging Environment:"
    gh api repos/{owner}/{repo}/environments/staging -q '.name'
    
    log_info ""
    log_info "Production Environment:"
    gh api repos/{owner}/{repo}/environments/production -q '.name'
    
    # 6. Summary
    log_success ""
    log_success "CI/CD setup complete!"
    log_success ""
    log_success "Next steps:"
    log_success "1. Deploy workflows to repository:"
    log_success "   git add .github/workflows/"
    log_success "   git commit -m 'ci: add github actions workflows'"
    log_success "   git push"
    log_success ""
    log_success "2. Test with a feature branch:"
    log_success "   git checkout -b feature/test"
    log_success "   git push -u origin feature/test"
    log_success "   # Create PR and watch workflows run"
    log_success ""
    log_success "3. Configure branch protection:"
    log_success "   GitHub → Settings → Branches → main"
    log_success "   → Add rule → Require status checks:"
    log_success "   ✓ terraform-validate"
    log_success "   ✓ test-suite"
    log_success ""
    log_success "4. Monitor first deployments:"
    log_success "   GitHub → Actions → Select workflow → View runs"
    log_success ""
}

# Run setup
main "$@"
