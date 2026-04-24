#!/usr/bin/env bash
# @file        scripts/deploy-qa-service-account-cli.sh
# @module      ci/deployment
# @description Deploy QA service account to GCP via Terraform CLI
#
# This is a simple wrapper that applies Terraform with the correct GCP project
#
# Prerequisites:
#   - gcloud CLI authenticated
#   - Terraform installed
#   - GCP project set (via gcloud config or GCP_PROJECT env var)
#
# Usage:
#   bash scripts/deploy-qa-service-account-cli.sh [--project PROJECT_ID] [--auto-approve]
#
# Examples:
#   bash scripts/deploy-qa-service-account-cli.sh --project kushin77-ops
#   bash scripts/deploy-qa-service-account-cli.sh --auto-approve  # Use current gcloud project
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Parse arguments
GCP_PROJECT=""
AUTO_APPROVE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      GCP_PROJECT="$2"
      shift 2
      ;;
    --auto-approve)
      AUTO_APPROVE=1
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Determine GCP project
if [ -z "$GCP_PROJECT" ]; then
  GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
  if [ -z "$GCP_PROJECT" ]; then
    log_error "GCP project not set. Either:"
    log_error "  1. Set default: gcloud config set project PROJECT_ID"
    log_error "  2. Pass --project argument: bash $0 --project PROJECT_ID"
    exit 1
  fi
fi

log_info "Using GCP Project: $GCP_PROJECT"

# Set current project in gcloud
gcloud config set project "$GCP_PROJECT" --quiet

# Navigate to terraform directory
cd terraform

# Initialize Terraform
log_info "Initializing Terraform..."
terraform init -upgrade

# Create tfvars file
log_info "Creating terraform.tfvars..."
cat > terraform.tfvars << EOF
gcp_project_id = "$GCP_PROJECT"
EOF

# Plan
log_info "Planning Terraform changes..."
terraform plan -out=tfplan

# Apply
if [ "$AUTO_APPROVE" -eq 1 ]; then
  log_info "Applying Terraform (auto-approved)..."
  terraform apply -auto-approve tfplan
else
  log_info "Applying Terraform (requires approval)..."
  terraform apply tfplan
fi

# Get outputs
log_success "Terraform apply completed"
log_info ""
log_info "=========================================="
log_info "QA Service Account Deployed Successfully"
log_info "=========================================="
log_info ""

QA_EMAIL=$(terraform output -raw qa_user_email 2>/dev/null || echo "qa-user@${GCP_PROJECT}.iam.gserviceaccount.com")
log_success "✓ Service account email: $QA_EMAIL"
log_success "✓ GSM secret (email): qa-user-email"
log_success "✓ GSM secret (key): qa-service-account-key"
log_success "✓ GitHub Actions service account has access"

log_info ""
log_info "Next steps:"
log_info "1. Setup email forwarding in Google Workspace:"
log_info "   https://admin.google.com/"
log_info ""
log_info "2. Run E2E tests with GSM credentials:"
log_info "   bash scripts/run-e2e-tests-with-gsm.sh --project all"
log_info ""
log_info "3. Trigger CI/CD (GitHub Actions will auto-fetch credentials):"
log_info "   git push origin main"
log_info ""

cd - > /dev/null
log_success "Done!"
