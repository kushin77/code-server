#!/usr/bin/env bash
# @file        scripts/ops/terraform-drift-detect.sh
# @module      ops/iac
# @description Detect drift between local terraform state and production cluster
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

TF_DIR="${SCRIPT_DIR}/terraform"

################################################################################
# DRIFT DETECTION
################################################################################

detect_drift() {
    log_info "🔍 Scanning for Terraform drift in $TF_DIR..."
    
    cd "$TF_DIR"
    
    # Check if terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        log_warn "⚠️ Terraform not initialized. Running init..."
        terraform init -backend=false # Local check only if no remote backend
    fi
    
    log_info "⚡ Running terraform plan..."
    if terraform plan -detailed-exitcode > /dev/null 2>&1; then
        log_info "✅ NO DRIFT DETECTED: Infrastructure is in sync."
    else
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            log_warn "⚠️ DRIFT DETECTED: Local state differs from remote!"
            terraform plan
        else
            log_error "✗ Terraform plan failed with exit code $exit_code"
            return 1
        fi
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    detect_drift
}

main "$@"
