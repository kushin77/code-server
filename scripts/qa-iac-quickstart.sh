#!/bin/bash
# Quick start for QA Credentials IaC deployment
# Run this to deploy the immutable, idempotent infrastructure

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== QA Credentials IaC - Quick Start ===${NC}"
echo ""
echo "This deployment will:"
echo "  1. Create immutable GSM secrets (versioned forever)"
echo "  2. Grant CI/CD service account permanent access"
echo "  3. Enable automatic OAuth E2E testing on every commit"
echo ""

# Check if running on production host
if ! command -v terraform &> /dev/null; then
    echo "ERROR: Terraform not found. Run this on the production host (192.168.168.31)"
    echo ""
    echo "SSH to production:"
    echo "  ssh akushnir@192.168.168.31"
    echo "  cd code-server-enterprise"
    echo "  bash scripts/qa-iac-quickstart.sh"
    exit 1
fi

echo -e "${GREEN}✓ Terraform found${NC}"

# Check GCP project
GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ -z "$GCP_PROJECT" ]; then
    echo "ERROR: No GCP project configured"
    echo "Set with: gcloud config set project kushin77-ops"
    exit 1
fi

echo -e "${GREEN}✓ GCP project: $GCP_PROJECT${NC}"

# Generate password if not provided
QA_PASSWORD="${1:-}"
if [ -z "$QA_PASSWORD" ]; then
    echo ""
    echo "Generate a secure password:"
    QA_PASSWORD=$(openssl rand -hex 16 | head -c 32)
    echo "  Generated: $QA_PASSWORD"
    echo ""
    echo "Or provide as argument:"
    echo "  bash scripts/qa-iac-quickstart.sh 'your-password-here'"
    exit 0
fi

echo ""
echo "Deploying with password: ${QA_PASSWORD:0:8}..."
echo ""

# Run deployment
bash scripts/deploy-qa-credentials-iac.sh "$QA_PASSWORD"

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify in GitHub Actions: https://github.com/kushin77/code-server/actions"
echo "  2. Push any commit to main to trigger OAuth tests"
echo "  3. All E2E tests run automatically"
echo ""
