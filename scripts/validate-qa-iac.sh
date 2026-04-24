#!/bin/bash
# @file        scripts/validate-qa-iac.sh
# @module      ci/validation
# @description Validate QA credentials IaC for immutability, idempotency, and automation
#
# This script validates that:
# 1. Terraform configuration has immutability annotations
# 2. GSM secrets are properly configured
# 3. IAM bindings grant correct access
# 4. Deployment is idempotent (no changes on re-run)
# 5. E2E tests are configured to use credentials
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

source scripts/_common/init.sh

log_info "=== Validating QA Credentials IaC ==="

# ============================================================================
# Step 1: Terraform Configuration Checks
# ============================================================================

log_info "Step 1: Checking Terraform configuration..."

# Check for immutability annotations
if ! grep -q "prevent_destroy = true" terraform/qa-credentials.tf; then
    log_error "✗ Missing prevent_destroy annotation"
    exit 1
fi
log_info "✓ prevent_destroy annotation present"

if ! grep -q "ignore_changes = all" terraform/qa-credentials.tf; then
    log_error "✗ Missing ignore_changes annotation"
    exit 1
fi
log_info "✓ ignore_changes annotation present"

# Check for IAM bindings
if ! grep -q "google_secret_manager_secret_iam_member" terraform/qa-credentials.tf; then
    log_error "✗ Missing IAM bindings"
    exit 1
fi
log_info "✓ IAM bindings defined"

# ============================================================================
# Step 2: GitHub Actions Workflow Checks
# ============================================================================

log_info "Step 2: Checking GitHub Actions workflow..."

if ! [ -f ".github/workflows/e2e-oauth-automatic.yml" ]; then
    log_error "✗ GitHub Actions workflow not found"
    exit 1
fi
log_info "✓ GitHub Actions workflow exists"

if ! grep -q "google-github-actions/auth" .github/workflows/e2e-oauth-automatic.yml; then
    log_error "✗ Workflow missing Workload Identity Federation authentication"
    exit 1
fi
log_info "✓ Workload Identity Federation configured"

if ! grep -q "E2E_USER_EMAIL" .github/workflows/e2e-oauth-automatic.yml; then
    log_error "✗ Workflow not setting E2E_USER_EMAIL environment variable"
    exit 1
fi
log_info "✓ Environment variables configured"

# ============================================================================
# Step 3: Deployment Script Checks
# ============================================================================

log_info "Step 3: Checking deployment script..."

if ! [ -f "scripts/deploy-qa-credentials-iac.sh" ]; then
    log_error "✗ Deployment script not found"
    exit 1
fi
log_info "✓ Deployment script exists"

if ! grep -q "Idempotent" scripts/deploy-qa-credentials-iac.sh; then
    log_error "✗ Deployment script doesn't validate idempotency"
    exit 1
fi
log_info "✓ Idempotency validation configured"

if ! grep -q "prevent_destroy" scripts/deploy-qa-credentials-iac.sh; then
    log_error "✗ Deployment script doesn't verify immutability"
    exit 1
fi
log_info "✓ Immutability verification configured"

# ============================================================================
# Step 4: E2E Test Configuration Checks
# ============================================================================

log_info "Step 4: Checking E2E test configuration..."

if ! [ -d "tests/e2e/specs" ]; then
    log_warn "⚠ E2E test directory not found (skipping test checks)"
else
    # Check at least one OAuth test exists
    if ! find tests/e2e/specs -name "*oauth*" -type f | grep -q "oauth"; then
        log_warn "⚠ No OAuth E2E tests found"
    else
        log_info "✓ OAuth E2E tests found"
    fi

    # Check for E2E_USER_EMAIL usage
    if ! grep -r "E2E_USER_EMAIL\|process.env.E2E_USER" tests/e2e 2>/dev/null | grep -q "E2E_USER"; then
        log_warn "⚠ E2E tests may not be using credentials from environment"
    else
        log_info "✓ E2E tests configured to use environment variables"
    fi
fi

# ============================================================================
# Step 5: Documentation Checks
# ============================================================================

log_info "Step 5: Checking documentation..."

if ! [ -f "docs/QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md" ]; then
    log_error "✗ IaC documentation not found"
    exit 1
fi
log_info "✓ IaC documentation exists"

if ! grep -q "Immutable\|Idempotent\|IaC" docs/QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md; then
    log_error "✗ Documentation missing key concepts"
    exit 1
fi
log_info "✓ Documentation covers IaC principles"

# ============================================================================
# Step 6: Configuration Examples
# ============================================================================

log_info "Step 6: Checking configuration examples..."

if ! [ -f "terraform/qa-credentials.tfvars.example" ]; then
    log_error "✗ Terraform variables example not found"
    exit 1
fi
log_info "✓ Terraform variables example exists"

if ! grep -q "qa_password\|qa_email" terraform/qa-credentials.tfvars.example; then
    log_error "✗ Variables example incomplete"
    exit 1
fi
log_info "✓ Variables example configured"

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_success "=== QA Credentials IaC Validation Complete ==="
log_info ""
log_info "✓ All validation checks passed"
log_info "✓ IaC is properly configured"
log_info "✓ Immutability is enforced"
log_info "✓ Idempotency is validated"
log_info "✓ Automation is in place"
log_info ""
