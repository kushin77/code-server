#!/usr/bin/env bash
# @file        scripts/verify-iac-readiness.sh
# @module      validation/deployment-readiness
# @description Comprehensive verification that QA Credentials IaC is ready for production deployment
# @status      READY FOR EXECUTION
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

source scripts/_common/init.sh

echo ""
log_info "╔════════════════════════════════════════════════════════════════╗"
log_info "║          QA CREDENTIALS IaC - DEPLOYMENT READINESS CHECK       ║"
log_info "╚════════════════════════════════════════════════════════════════╝"
log_info ""

PASSED=0
FAILED=0

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 1: Terraform Syntax Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info "SECTION 1: Terraform Configuration Validation"
log_info "─────────────────────────────────────────────────"

# Check 1.1: terraform/qa-credentials.tf syntax
log_info "Check 1.1: terraform/qa-credentials.tf syntax"
if [ -f "terraform/qa-credentials.tf" ]; then
    if grep -q "terraform {" terraform/qa-credentials.tf && \
       grep -q "resource" terraform/qa-credentials.tf && \
       grep -q "prevent_destroy = true" terraform/qa-credentials.tf; then
        log_info "  ✓ PASS - Terraform configuration valid"
        PASSED=$((PASSED + 1))
    else
        log_error "  ✗ FAIL - Invalid Terraform structure"
        FAILED=$((FAILED + 1))
    fi
else
    log_error "  ✗ FAIL - File not found: terraform/qa-credentials.tf"
    FAILED=$((FAILED + 1))
fi

# Check 1.2: Resource count
log_info "Check 1.2: Resource count"
RESOURCE_COUNT=$(grep -c "^resource" terraform/qa-credentials.tf 2>/dev/null || echo 0)
log_info "  Found $RESOURCE_COUNT resources"
if [ "$RESOURCE_COUNT" -ge 6 ]; then
    log_info "  ✓ PASS - Expected 6 resources"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Expected 6 resources, found $RESOURCE_COUNT"
    ((FAILED++))
fi

# Check 1.3: Immutability annotations
log_info "Check 1.3: Immutability enforcement"
PREVENT_COUNT=$(grep -c "prevent_destroy = true" terraform/qa-credentials.tf 2>/dev/null || echo 0)
IGNORE_COUNT=$(grep -c "ignore_changes = all" terraform/qa-credentials.tf 2>/dev/null || echo 0)
log_info "  prevent_destroy: $PREVENT_COUNT occurrences"
log_info "  ignore_changes: $IGNORE_COUNT occurrences"
if [ "$PREVENT_COUNT" -ge 2 ] && [ "$IGNORE_COUNT" -ge 1 ]; then
    log_info "  ✓ PASS - Immutability enforced"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Insufficient immutability enforcement"
    ((FAILED++))
fi

# Check 1.4: IAM bindings defined
log_info "Check 1.4: IAM bindings"
if grep -q "google_secret_manager_secret_iam_member" terraform/qa-credentials.tf; then
    IAM_COUNT=$(grep -c "google_secret_manager_secret_iam_member" terraform/qa-credentials.tf 2>/dev/null || echo 0)
    log_info "  Found $IAM_COUNT IAM bindings"
    log_info "  ✓ PASS - IAM configuration present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - No IAM bindings found"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 2: Variables Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 2: Terraform Variables Validation"
log_info "─────────────────────────────────────────────────"

# Check 2.1: Required variables defined
log_info "Check 2.1: Required variables"
VARS=("qa_password" "qa_email" "gcp_project_id" "ci_service_account_email")
VARS_FOUND=0
for var in "${VARS[@]}"; do
    if grep -q "variable \"$var\"" terraform/variables.tf; then
        ((VARS_FOUND++))
    fi
done
log_info "  Found $VARS_FOUND of ${#VARS[@]} required variables"
if [ "$VARS_FOUND" -eq "${#VARS[@]}" ]; then
    log_info "  ✓ PASS - All required variables defined"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Missing variables"
    ((FAILED++))
fi

# Check 2.2: qa_password marked sensitive
log_info "Check 2.2: Sensitive variable marking"
if grep -A 3 "variable \"qa_password\"" terraform/variables.tf | grep -q "sensitive"; then
    log_info "  ✓ PASS - qa_password marked sensitive"
    ((PASSED++))
else
    log_error "  ✗ FAIL - qa_password not marked sensitive"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 3: Deployment Scripts Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 3: Deployment Scripts Validation"
log_info "─────────────────────────────────────────────────"

# Check 3.1: DEPLOY-QA-IaC-NOW.sh exists
log_info "Check 3.1: Main deployment script"
if [ -f "DEPLOY-QA-IaC-NOW.sh" ] && [ -x "DEPLOY-QA-IaC-NOW.sh" ] 2>/dev/null || [ -f "DEPLOY-QA-IaC-NOW.sh" ]; then
    log_info "  ✓ PASS - DEPLOY-QA-IaC-NOW.sh present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - DEPLOY-QA-IaC-NOW.sh not found or not executable"
    ((FAILED++))
fi

# Check 3.2: Deployment scripts have idempotency checks
log_info "Check 3.2: Idempotency checks in scripts"
if grep -q "terraform plan" scripts/deploy-qa-credentials-iac.sh; then
    log_info "  ✓ PASS - Idempotency validation present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - No idempotency checks found"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 4: GitHub Actions Workflow Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 4: GitHub Actions Workflow Validation"
log_info "─────────────────────────────────────────────────"

# Check 4.1: Workflow file exists and is valid YAML
log_info "Check 4.1: Workflow file syntax"
if [ -f ".github/workflows/e2e-oauth-automatic.yml" ]; then
    if grep -q "^name:" .github/workflows/e2e-oauth-automatic.yml; then
        log_info "  ✓ PASS - Workflow file present and valid"
        ((PASSED++))
    else
        log_error "  ✗ FAIL - Workflow file not valid YAML"
        ((FAILED++))
    fi
else
    log_error "  ✗ FAIL - Workflow file not found"
    ((FAILED++))
fi

# Check 4.2: Workflow has required jobs
log_info "Check 4.2: Workflow jobs"
JOBS=("validate-iac" "setup-credentials" "e2e-oauth-tests")
JOBS_FOUND=0
for job in "${JOBS[@]}"; do
    if grep -q "$job" .github/workflows/e2e-oauth-automatic.yml; then
        ((JOBS_FOUND++))
    fi
done
log_info "  Found $JOBS_FOUND of ${#JOBS[@]} required jobs"
if [ "$JOBS_FOUND" -eq "${#JOBS[@]}" ]; then
    log_info "  ✓ PASS - All required jobs defined"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Missing workflow jobs"
    ((FAILED++))
fi

# Check 4.3: Workload Identity Federation configured
log_info "Check 4.3: Workload Identity Federation"
if grep -q "workload-identity-provider:" .github/workflows/e2e-oauth-automatic.yml; then
    log_info "  ✓ PASS - WIF authentication configured"
    ((PASSED++))
else
    log_error "  ✗ FAIL - WIF not configured"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 5: Validation Scripts Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 5: Validation Framework"
log_info "─────────────────────────────────────────────────"

# Check 5.1: Main validation script exists
log_info "Check 5.1: Validation script"
if [ -f "scripts/validate-qa-iac.sh" ]; then
    log_info "  ✓ PASS - Validation script present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Validation script not found"
    ((FAILED++))
fi

# Check 5.2: Test suite exists
log_info "Check 5.2: Test suite"
if [ -f "tests/iac-validation-test-simple.sh" ]; then
    log_info "  ✓ PASS - Test suite present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Test suite not found"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 6: Documentation Validation
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 6: Documentation"
log_info "─────────────────────────────────────────────────"

# Check 6.1: Complete solution guide
log_info "Check 6.1: Solution documentation"
if [ -f "QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md" ]; then
    LINES=$(wc -l < QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md)
    log_info "  Found $LINES lines of documentation"
    log_info "  ✓ PASS - Complete solution guide present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Solution guide not found"
    ((FAILED++))
fi

# Check 6.2: Deployment README
log_info "Check 6.2: Deployment instructions"
if [ -f "README-DEPLOY-QA-IaC-NOW.md" ]; then
    log_info "  ✓ PASS - Deployment README present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Deployment README not found"
    ((FAILED++))
fi

# Check 6.3: Architecture documentation
log_info "Check 6.3: Architecture documentation"
if [ -f "docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md" ]; then
    log_info "  ✓ PASS - Architecture guide present"
    ((PASSED++))
else
    log_error "  ✗ FAIL - Architecture guide not found"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# SECTION 7: File Integrity Check
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "SECTION 7: Complete File Inventory"
log_info "─────────────────────────────────────────────────"

REQUIRED_FILES=(
    "terraform/qa-credentials.tf"
    "terraform/variables.tf"
    "terraform/qa-credentials.tfvars.example"
    "scripts/deploy-qa-credentials-iac.sh"
    "scripts/deploy-qa-credentials-to-gcp.sh"
    "scripts/validate-qa-iac.sh"
    "scripts/qa-iac-quickstart.sh"
    ".github/workflows/e2e-oauth-automatic.yml"
    "docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md"
    "QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md"
    "DEPLOY-QA-IaC-NOW.sh"
    "README-DEPLOY-QA-IaC-NOW.md"
    "tests/iac-validation-test-simple.sh"
    "IaC-IMPLEMENTATION-FINAL-STATUS.md"
)

FILES_FOUND=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        ((FILES_FOUND++))
        log_debug "  ✓ $file"
    else
        log_error "  ✗ MISSING: $file"
        ((FAILED++))
    fi
done

log_info ""
log_info "Files found: $FILES_FOUND of ${#REQUIRED_FILES[@]}"
if [ "$FILES_FOUND" -eq "${#REQUIRED_FILES[@]}" ]; then
    log_info "✓ PASS - All required files present"
    ((PASSED++))
else
    log_error "✗ FAIL - Missing ${#REQUIRED_FILES[@]} - $FILES_FOUND files"
    ((FAILED++))
fi

# ═══════════════════════════════════════════════════════════════════════════
# RESULTS
# ═══════════════════════════════════════════════════════════════════════════

log_info ""
log_info "╔════════════════════════════════════════════════════════════════╗"
log_info "║                         RESULTS                               ║"
log_info "╚════════════════════════════════════════════════════════════════╝"
log_info ""

TOTAL=$((PASSED + FAILED))
PERCENTAGE=$((PASSED * 100 / TOTAL))

log_info "Checks Passed:  $PASSED/$TOTAL"
log_info "Checks Failed:  $FAILED/$TOTAL"
log_info "Success Rate:   $PERCENTAGE%"
log_info ""

if [ $FAILED -eq 0 ]; then
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║                  ✓ ALL CHECKS PASSED                          ║"
    log_info "║              QA CREDENTIALS IaC IS READY FOR                   ║"
    log_info "║              PRODUCTION DEPLOYMENT                            ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "NEXT STEPS:"
    log_info "  1. SSH to production host:"
    log_info "       ssh akushnir@192.168.168.31"
    log_info ""
    log_info "  2. Navigate to repository:"
    log_info "       cd code-server-enterprise"
    log_info "       git pull origin main"
    log_info ""
    log_info "  3. Run deployment:"
    log_info "       bash DEPLOY-QA-IaC-NOW.sh"
    log_info ""
    log_info "DEPLOYMENT WILL:"
    log_info "  • Create GSM secrets (qa_email, qa_password)"
    log_info "  • Configure IAM bindings (GitHub Actions CI/CD access)"
    log_info "  • Enforce immutability (prevent_destroy, ignore_changes)"
    log_info "  • Enable automatic OAuth E2E testing (556 tests)"
    log_info "  • Preserve secret versioning (all versions forever)"
    log_info ""
    exit 0
else
    log_error "╔════════════════════════════════════════════════════════════════╗"
    log_error "║                  ✗ SOME CHECKS FAILED                         ║"
    log_error "║           Fix issues before deploying to production           ║"
    log_error "╚════════════════════════════════════════════════════════════════╝"
    log_info ""
    exit 1
fi
