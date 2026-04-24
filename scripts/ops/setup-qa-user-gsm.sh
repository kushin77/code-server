#!/usr/bin/env bash
# @file        scripts/ops/setup-qa-user-gsm.sh
# @module      ops/credentials
# @description Specific bootstrap for QA user in Google Secret Manager
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

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-kushnir-cloud}"
SECRET_NAME="qa-automated-user-credentials"

################################################################################
# MAIN
################################################################################

main() {
    log_info "Bootstrapping QA user credentials in GSM..."
    
    require_command gcloud
    
    # Check if secret exists
    if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_info "Creating secret $SECRET_NAME..."
        gcloud secrets create "$SECRET_NAME" --project="$PROJECT_ID" --replication-policy="automatic"
    else
        log_info "Secret $SECRET_NAME already exists"
    fi
    
    log_info "✅ GSM QA user bootstrap complete"
}

main "$@"
