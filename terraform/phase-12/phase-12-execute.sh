#!/bin/bash

# Phase 12 Execution Script - Multi-Region Federation Setup
# Usage: ./phase-12-execute.sh [validate|plan|apply|destroy]
# Date: April 13, 2026

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="code-server-enterprise"
PHASE="12"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="logs/phase-12-execution-${TIMESTAMP}.log"

# Ensure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# Pre-flight checks
preflight_check() {
    log "Running pre-flight checks..."

    # Check for required tools
    for tool in aws terraform jq curl; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install it before proceeding."
        fi
    done

    log "✓ All required tools are available"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'"
    fi

    log "✓ AWS credentials verified"

    # Check Terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    log "✓ Terraform version: $TERRAFORM_VERSION"

    # Check terraform.tfvars
    if [ ! -f "terraform.tfvars" ]; then
        error "terraform.tfvars not found. Please copy terraform.tfvars.example and update values"
    fi

    if grep -q "PLACEHOLDER" terraform.tfvars; then
        error "terraform.tfvars contains PLACEHOLDER values. Please update with actual AWS IDs"
    fi

    log "✓ terraform.tfvars is configured"
}

# Validate configuration
validate() {
    log "Validating Terraform configuration..."

    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init -no-color

    # Validate syntax
    log "Validating Terraform syntax..."
    terraform validate -no-color || error "Terraform validation failed"

    # Format check
    log "Checking Terraform formatting..."
    terraform fmt -check -recursive . || warning "Some files need formatting"

    # Security scanning (tfsec)
    if command -v tfsec &> /dev/null; then
        log "Running security scan (tfsec)..."
        tfsec . --format json > tfsec-report.json || true
        if [ -s tfsec-report.json ]; then
            warning "Security issues found. Check tfsec-report.json"
        fi
    fi

    success "Terraform configuration is valid"
}

# Plan deployment
plan() {
    log "Planning Terraform deployment..."

    # Generate plan
    PLAN_FILE="phase-12-${TIMESTAMP}.tfplan"
    terraform plan -out="$PLAN_FILE" -no-color 2>&1 | tee -a "$LOG_FILE"

    # Extract summary
    SUMMARY=$(terraform show -json "$PLAN_FILE" | jq -r '.resource_changes | length')

    log "Plan summary:"
    log "  File: $PLAN_FILE"
    log "  Resources: $SUMMARY"

    # Ask for confirmation
    read -p "Review the plan above. Continue with apply? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        apply "$PLAN_FILE"
    else
        warning "Plan cancelled by user"
        rm -f "$PLAN_FILE"
    fi
}

# Apply deployment
apply() {
    local plan_file="${1:-}"

    if [ -z "$plan_file" ]; then
        error "No plan file provided for apply"
    fi

    if [ ! -f "$plan_file" ]; then
        error "Plan file not found: $plan_file"
    fi

    log "Applying Terraform plan: $plan_file"

    # Apply with auto approval
    terraform apply -no-color -input=false "$plan_file" 2>&1 | tee -a "$LOG_FILE"

    # Save outputs
    log "Saving Terraform outputs..."
    terraform output -json > "phase-12-outputs-${TIMESTAMP}.json"

    success "Phase 12.1 Infrastructure deployment completed!"
    log "Outputs saved to: phase-12-outputs-${TIMESTAMP}.json"

    # Print important outputs
    log "Important endpoints:"
    terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
}

# Post-deployment validation
validate_deployment() {
    log "Validating Phase 12.1 deployment..."

    # Get outputs
    declare -A regions=( [primary]="us-east-1" [secondary]="us-west-2" [tertiary]="eu-west-1" )

    for region_name in "${!regions[@]}"; do
        region=${regions[$region_name]}
        log "Checking region: $region_name ($region)"

        # Get VPC info
        vpc_id=$(aws ec2 describe-vpcs \
            --region "$region" \
            --filters "Name=tag:Phase,Values=12" \
            --query "Vpcs[0].VpcId" \
            --output text 2>/dev/null || echo "NOTFOUND")

        if [ "$vpc_id" != "NOTFOUND" ] && [ -n "$vpc_id" ]; then
            log "  ✓ VPC: $vpc_id"

            # Check connectivity
            # (Add network ping validation here)
        else
            warning "  VPC not found in $region"
        fi
    done

    success "Deployment validation completed"
}

# Destroy infrastructure (DANGEROUS)
destroy() {
    warning "⚠️  This will DESTROY all Phase 12 infrastructure"
    warning "This action cannot be undone!"

    read -p "Type 'DESTROY_PHASE_12' to confirm: " -r
    if [[ $REPLY == "DESTROY_PHASE_12" ]]; then
        log "Destroying Phase 12 infrastructure..."
        terraform destroy -auto-approve -no-color 2>&1 | tee -a "$LOG_FILE"
        success "Infrastructure destroyed"
    else
        warning "Destroy cancelled"
    fi
}

# Main execution
main() {
    local command="${1:-validate}"

    log "=========================================="
    log "Phase 12 Execution Script"
    log "Project: $PROJECT_NAME"
    log "Phase: $PHASE"
    log "Command: $command"
    log "=========================================="

    # Always run preflight checks first
    preflight_check

    case "$command" in
        validate)
            validate
            ;;
        plan)
            validate
            plan
            ;;
        apply)
            validate
            plan
            ;;
        destroy)
            destroy
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac

    log "=========================================="
    log "Phase 12 execution script completed"
    log "Log file: $LOG_FILE"
    log "=========================================="
}

# Run main function
main "$@"
