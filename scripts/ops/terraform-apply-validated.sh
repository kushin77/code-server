#!/usr/bin/env bash
###############################################################################
# @file        scripts/ops/terraform-apply-validated.sh
# @module      ops/terraform-apply-validated
# @description Phase 4: Validated Terraform apply with environment variable sourcing (#1531)
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @automation  Validates drift detection before applying changes
# @prerequisite Must source scripts/_common/init.sh
###############################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT


# Source bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly TERRAFORM_DIR="${REPO_ROOT}/terraform/environments/private"
readonly MODE="${1:-plan}"  # plan or apply

# ==============================================================================
# TERRAFORM CONFIGURATION
# ==============================================================================

export_tf_var() {
  local target_var="$1"
  local source_var="$2"
  local default_value="${3:-}"

  if [ "$#" -ge 3 ]; then
    export "${target_var}=${!source_var:-${default_value}}"
  else
    export "${target_var}=${!source_var}"
  fi
}

# Export environment variables for Terraform
export_terraform_variables() {
  log_info "Exporting Terraform variables from environment..."

  export_tf_var TF_VAR_apex_domain APEX_DOMAIN
  export_tf_var TF_VAR_primary_host PRIMARY_HOST
  export_tf_var TF_VAR_admin_email ADMIN_EMAIL

  export_tf_var TF_VAR_replica_host REPLICA_HOST
  export_tf_var TF_VAR_nas_host NAS_HOST
  export_tf_var TF_VAR_registry_domain REGISTRY_DOMAIN "registry.${APEX_DOMAIN}"
  export_tf_var TF_VAR_enable_tls ENABLE_TLS "false"
  export_tf_var TF_VAR_metrics_retention_days PROMETHEUS_RETENTION_DAYS "30"
  
  log_success "✅ Terraform variables exported"
  log_info "  APEX_DOMAIN: ${TF_VAR_apex_domain}"
  log_info "  PRIMARY_HOST: ${TF_VAR_primary_host}"
}

# Initialize Terraform
terraform_init() {
  log_info "Initializing Terraform..."
  
  cd "$TERRAFORM_DIR"
  
  if ! terraform init -no-color -upgrade; then
    log_error "Terraform initialization failed"
    return 1
  fi
  
  log_success "✅ Terraform initialized"
}

# Generate Terraform plan
terraform_plan() {
  log_info "Generating Terraform plan..."
  
  cd "$TERRAFORM_DIR"
  
  local exit_code=0

  terraform plan -no-color -out=tfplan
  exit_code=$?
  
  # Exit code 0 = no changes, 2 = changes detected
  if [ "$exit_code" -eq 0 ]; then
    log_info "✅ No infrastructure changes (exit code 0)"
  elif [ "$exit_code" -eq 2 ]; then
    log_info "⚠️  Infrastructure changes detected (exit code 2)"
    terraform show -no-color tfplan || true
  else
    log_error "Terraform plan generation failed"
    return 1
  fi
  
  log_success "✅ Terraform plan complete"
  return 0
}

# Validate Terraform configuration
terraform_validate() {
  log_info "Validating Terraform configuration..."
  
  cd "$TERRAFORM_DIR"
  
  if ! terraform validate -no-color; then
    log_error "Terraform validation failed"
    return 1
  fi
  
  log_success "✅ Terraform validation passed"
}

# Apply Terraform plan
terraform_apply() {
  log_info "Applying Terraform plan..."
  
  cd "$TERRAFORM_DIR"
  
  if [ ! -f tfplan ]; then
    log_error "No tfplan file found - run plan first"
    return 1
  fi
  
  if ! terraform apply -no-color -auto-approve tfplan; then
    log_error "Terraform apply failed"
    return 1
  fi
  
  log_success "✅ Terraform apply complete"
}

# Run health check after apply
post_apply_health_check() {
  log_info "Running health checks after Terraform apply..."
  
  if [ ! -f "${REPO_ROOT}/scripts/ops/health-check-and-rollback.sh" ]; then
    log_error "Health check script not found"
    return 1
  fi
  
  if ! bash "${REPO_ROOT}/scripts/ops/health-check-and-rollback.sh"; then
    log_error "Post-apply health check failed"
    return 1
  fi
  
  log_success "✅ Health checks passed"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
  log_info "=========================================="
  log_info "Validated Terraform Execution"
  log_info "Mode: $MODE"
  log_info "=========================================="
  
  # Validate environment
  if ! _validate_required_env 2>/dev/null; then
    log_error "Environment validation failed"
    return 1
  fi
  
  # Export Terraform variables
  export_terraform_variables
  
  case "$MODE" in
    init)
      terraform_init
      ;;
    
    validate)
      terraform_validate
      ;;
    
    plan)
      terraform_init
      terraform_validate
      terraform_plan
      ;;
    
    apply)
      terraform_init
      terraform_validate
      terraform_plan
      terraform_apply
      post_apply_health_check
      ;;
    
    *)
      log_error "Unknown mode: $MODE"
      echo "Usage: $0 {init|validate|plan|apply}"
      exit 1
      ;;
  esac
  
  log_success "✅ Terraform execution complete"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
