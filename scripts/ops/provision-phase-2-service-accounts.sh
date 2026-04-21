#!/usr/bin/env bash
# @file        scripts/ops/provision-phase-2-service-accounts.sh
# @module      operations/setup
# @description Provisions Phase 2 JWT service account credentials in Google Secret Manager
# @status      ACTIVE

set -euo pipefail

# Import shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# Configuration
GCP_PROJECT="${GCP_PROJECT:?GCP_PROJECT must be set}"
DRY_RUN="${DRY_RUN:-1}"

# ────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────────────────

generate_random_secret() {
  local length="${1:-32}"
  python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range($length)))"
}

create_or_update_secret() {
  local secret_name="$1"
  local secret_value="$2"
  
  log_info "Creating/updating secret: $secret_name"
  
  # Check if secret exists
  if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT" > /dev/null 2>&1; then
    log_info "Secret exists, creating new version"
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[DRY_RUN] Would create new version of $secret_name"
    else
      echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
        --data-file=- \
        --project="$GCP_PROJECT" \
        > /dev/null
      log_info "✓ Created new version of $secret_name"
    fi
  else
    log_info "Secret does not exist, creating new secret"
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[DRY_RUN] Would create secret $secret_name"
    else
      echo -n "$secret_value" | gcloud secrets create "$secret_name" \
        --replication-policy=automatic \
        --data-file=- \
        --project="$GCP_PROJECT" \
        > /dev/null
      log_info "✓ Created secret $secret_name"
    fi
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Phase 2 Service Account Provisioning
# ────────────────────────────────────────────────────────────────────────────

provision_service_accounts() {
  log_info "Provisioning Phase 2 JWT service account credentials..."
  
  # Session-Broker Service Account
  local session_broker_secret
  session_broker_secret=$(generate_random_secret 32)
  create_or_update_secret "service-client-session-broker-secret" "$session_broker_secret"
  
  # Backend Service Account
  local backend_secret
  backend_secret=$(generate_random_secret 32)
  create_or_update_secret "service-client-backend-secret" "$backend_secret"
  
  # Load Balancer Session Cookie Secret (64 hex chars = 32 bytes)
  local lb_secret
  lb_secret=$(openssl rand -hex 32)
  create_or_update_secret "ide-session-lb-secret" "$lb_secret"
  
  log_info "✓ Phase 2 service account secrets provisioned"
}

provision_oidc_signing_key() {
  log_info "Provisioning OIDC Issuer RSA signing key..."
  
  # Check if key already exists
  if gcloud secrets describe "oidc-issuer-signing-key" --project="$GCP_PROJECT" > /dev/null 2>&1; then
    log_warn "OIDC signing key already exists, skipping generation"
    return 0
  fi
  
  # Generate RSA 2048-bit key pair
  local temp_dir
  temp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf $temp_dir" EXIT
  
  local private_key_file="$temp_dir/private_key.pem"
  local public_key_file="$temp_dir/public_key.pem"
  
  log_info "Generating RSA 2048-bit key pair..."
  openssl genrsa -out "$private_key_file" 2048 > /dev/null 2>&1
  openssl rsa -in "$private_key_file" -pubout -out "$public_key_file" > /dev/null 2>&1
  
  local private_key
  private_key=$(cat "$private_key_file")
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY_RUN] Would create secret oidc-issuer-signing-key"
    log_info "Public key would be:"
    cat "$public_key_file"
  else
    create_or_update_secret "oidc-issuer-signing-key" "$private_key"
    log_info "✓ OIDC signing key provisioned"
    log_info "Public key:"
    cat "$public_key_file"
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Verification
# ────────────────────────────────────────────────────────────────────────────

verify_secrets_created() {
  log_info "Verifying secrets in GSM..."
  
  local required_secrets=(
    "oidc-issuer-signing-key"
    "service-client-session-broker-secret"
    "service-client-backend-secret"
    "ide-session-lb-secret"
  )
  
  local missing=()
  for secret in "${required_secrets[@]}"; do
    if ! gcloud secrets describe "$secret" --project="$GCP_PROJECT" > /dev/null 2>&1; then
      missing+=("$secret")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing secrets: ${missing[*]}"
    return 1
  fi
  
  log_info "✓ All Phase 2 secrets successfully created in GSM"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Main Execution
# ────────────────────────────────────────────────────────────────────────────

main() {
  log_info "=========================================="
  log_info "Phase 2 Service Account Provisioning"
  log_info "=========================================="
  log_info "GCP Project: $GCP_PROJECT"
  log_info "Dry-run: $DRY_RUN"
  
  # Check gcloud availability
  if ! command -v gcloud &> /dev/null; then
    log_fatal "gcloud CLI not found. Install via: curl https://sdk.cloud.google.com | bash"
  fi
  
  # Check authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_fatal "No active gcloud authentication. Run: gcloud auth login"
  fi
  
  # Provision keys
  provision_oidc_signing_key
  provision_service_accounts
  
  # Verify
  if [[ "$DRY_RUN" == "0" ]]; then
    verify_secrets_created
  else
    log_info "[DRY_RUN] Skipping verification"
  fi
  
  log_info ""
  log_info "Next steps:"
  log_info "1. Run verification: bash scripts/ci/check-phase-2-jwt-readiness.sh"
  log_info "2. Deploy: docker-compose up -d"
  log_info "3. Test token acquisition: curl -X POST http://localhost:4182/oauth2/token ..."
}

main "$@"
