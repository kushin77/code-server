#!/usr/bin/env bash
# @file        scripts/ops/setup-ci-qa-credentials.sh
# @module      ops/credentials
# @description Initialize CI/QA credentials in Google Secret Manager
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
SECRET_NAME="${QA_CREDENTIALS_SECRET:-qa-automated-user-credentials}"

################################################################################
# CREDENTIAL GENERATION
################################################################################

generate_credentials() {
    log_info "Generating random credentials for QA user..."
    
    local password
    password=$(openssl rand -base64 24)
    
    local credentials_json
    credentials_json=$(cat <<EOF
{
  "username": "qa-automated@kushnir.cloud",
  "password": "$password",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "created_by": "setup-ci-qa-credentials.sh"
}
EOF
)
    echo "$credentials_json"
}

################################################################################
# GSM INTEGRATION
################################################################################

update_gsm_secret() {
    local payload="$1"
    
    log_info "Updating GSM secret: $SECRET_NAME..."
    
    if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
        echo "$payload" | gcloud secrets versions add "$SECRET_NAME" --project="$PROJECT_ID" --data-file=-
    else
        log_info "Creating new GSM secret..."
        echo "$payload" | gcloud secrets create "$SECRET_NAME" --project="$PROJECT_ID" --replication-policy="automatic" --data-file=-
    fi
    
    log_info "✅ GSM secret $SECRET_NAME updated successfully"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting CI/QA Credential Setup..."
    
    require_command gcloud
    require_command openssl
    
    local creds
    creds=$(generate_credentials)
    
    update_gsm_secret "$creds"
    
    log_info "✅ CI/QA security bootstrap complete"
}

main "$@"
