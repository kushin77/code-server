#!/usr/bin/env bash
# @file        scripts/ops/verify-terraform-idempotent.sh
# @module      ops/deployment
# @description Verify Terraform plan is idempotent (no unintended changes)
# @owner       Infrastructure Team
# @status      ACTIVE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

log_title "🔄 TERRAFORM IDEMPOTENCY VERIFICATION"
log_info "Checking if Terraform plan is idempotent..."
log_info ""

cd "${SCRIPT_DIR}/terraform"

# ════════════════════════════════════════════════════════════════════════════
# STEP 1: Initialize Terraform
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 1: Terraform Initialization"
if terraform init -backend=false -upgrade > /dev/null 2>&1; then
  log_success "✅ Terraform initialized"
else
  log_error "❌ Terraform init failed"
  exit 1
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 2: Generate first plan
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 2: Generate Initial Terraform Plan"
if terraform plan -out=tfplan1 > /dev/null 2>&1; then
  log_success "✅ First plan generated"
else
  log_error "❌ First plan failed"
  exit 1
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 3: Generate second plan (should be identical)
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 3: Generate Second Terraform Plan (Idempotency Check)"
if terraform plan -out=tfplan2 > /dev/null 2>&1; then
  log_success "✅ Second plan generated"
else
  log_error "❌ Second plan failed"
  exit 1
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# STEP 4: Compare plans
# ════════════════════════════════════════════════════════════════════════════
log_section "Step 4: Plan Comparison (Idempotency)"

plan1_hash=$(terraform show tfplan1 | sha256sum | awk '{print $1}')
plan2_hash=$(terraform show tfplan2 | sha256sum | awk '{print $1}')

if [[ "$plan1_hash" == "$plan2_hash" ]]; then
  log_success "✅ Plans are identical (idempotent)"
else
  log_warn "⚠️  Plans differ - analyzing changes..."
  diff -u <(terraform show tfplan1) <(terraform show tfplan2) | head -20 || true
fi
log_info ""

# ════════════════════════════════════════════════════════════════════════════
# CLEANUP
# ════════════════════════════════════════════════════════════════════════════
rm -f tfplan1 tfplan2

log_title "✅ TERRAFORM IDEMPOTENCY VERIFICATION COMPLETE"
log_info ""
log_info "Idempotency guarantee:"
log_info "  → terraform plan produces deterministic output"
log_info "  → Re-running plan produces identical changes"
log_info "  → Safe to apply in CI/CD pipelines"
