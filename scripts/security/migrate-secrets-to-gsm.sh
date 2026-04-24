#!/usr/bin/env bash
# Upload secrets to Google Secret Manager
# CRITICAL: Run this on a secure machine, never commit output

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:?Error: GCP_PROJECT_ID not set}"

log_info "Uploading secrets to Google Secret Manager..."

# Create secrets if they don't exist, update if they do
upload_secret() {
  local secret_name="$1"
  local secret_value="$2"
  
  if gcloud secrets describe "${secret_name}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log_info "Updating ${secret_name}..."
    echo "${secret_value}" | gcloud secrets versions add "${secret_name}" \
      --data-file=- \
      --project="${PROJECT_ID}"
  else
    log_info "Creating ${secret_name}..."
    echo "${secret_value}" | gcloud secrets create "${secret_name}" \
      --data-file=- \
      --replication-policy="automatic" \
      --project="${PROJECT_ID}"
  fi
  
  log_success "${secret_name} stored in GSM"
}

# Upload each secret (values would be read from secure input, not shown here)
upload_secret "oidc-issuer-signing-key" "${OIDC_ISSUER_SIGNING_KEY}"
upload_secret "oidc-issuer-verification-key" "${OIDC_ISSUER_VERIFICATION_KEY}"
upload_secret "db-password" "${DB_PASSWORD}"
upload_secret "db-replication-password" "${DB_REPLICATION_PASSWORD}"
upload_secret "redis-password" "${REDIS_PASSWORD}"
upload_secret "jwt-signing-key" "${JWT_SIGNING_KEY}"

log_success "All secrets migrated to GSM"
