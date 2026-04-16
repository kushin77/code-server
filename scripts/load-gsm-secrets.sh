#!/bin/bash
################################################################################
# Google Secret Manager (GSM) Secrets Loader
# Purpose: Load secrets from GSM instead of hardcoding in .env
# Usage: source ./scripts/load-gsm-secrets.sh
# Status: Production-ready for GCP deployments
################################################################################

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
GSM_PROJECT_ID="${GCP_PROJECT_ID:-code-server-prod}"
GSM_SECRETS=(
    "postgres-password"
    "redis-password"
    "code-server-password"
    "github-token"
    "google-oauth-client-id"
    "google-oauth-client-secret"
)

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "[GSM-LOADER] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ─── Check Prerequisites ──────────────────────────────────────────────────────
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI not installed. Install via: curl https://sdk.cloud.google.com | bash"
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
        error "Not authenticated with gcloud. Run: gcloud auth login"
    fi
    
    log "✓ gcloud CLI ready"
}

check_project() {
    local active_project=$(gcloud config get-value project)
    
    if [[ "$active_project" != "$GSM_PROJECT_ID" ]]; then
        log "Setting gcloud project to $GSM_PROJECT_ID..."
        gcloud config set project "$GSM_PROJECT_ID"
    fi
    
    log "✓ Project: $GSM_PROJECT_ID"
}

# ─── Load Secrets from GSM ────────────────────────────────────────────────────
load_secret() {
    local secret_name=$1
    local env_var_name=$(echo "$secret_name" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    
    log "Loading secret: $secret_name → $env_var_name"
    
    if ! value=$(gcloud secrets versions access latest --secret="$secret_name" 2>/dev/null); then
        error "Failed to load secret '$secret_name'. Ensure it exists in GSM."
    fi
    
    # Export the variable
    export "$env_var_name"="$value"
    log "  ✓ $env_var_name loaded (${#value} chars)"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    log "Starting GSM Secrets Loader..."
    
    check_gcloud
    check_project
    
    log "Loading ${#GSM_SECRETS[@]} secrets from GSM..."
    
    for secret in "${GSM_SECRETS[@]}"; do
        load_secret "$secret"
    done
    
    log "✅ All secrets loaded successfully"
    log "Export .env with these variables:"
    log "  export POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
    log "  export REDIS_PASSWORD=$REDIS_PASSWORD"
    log "  export CODE_SERVER_PASSWORD=$CODE_SERVER_PASSWORD"
}

main "$@"
