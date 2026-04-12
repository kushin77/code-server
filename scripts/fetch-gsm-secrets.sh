#!/usr/bin/env bash
# fetch-gsm-secrets.sh
# Fetches code-server secrets from Google Secret Manager (elevatediq project)
# Mimics eiq-org pattern: gcloud secrets versions access → env var injection
# Requires: gcloud auth login (or service account activation)
# Usage: source ./fetch-gsm-secrets.sh   (sources env vars into current shell)
#        ./fetch-gsm-secrets.sh > .env    (writes to env file)
set -euo pipefail

readonly GSM_PROJECT="${GSM_PROJECT:-elevatediq}"

fetch_gsm_secret() {
    local secret_id="$1"
    local var_name="$2"
    local value
    value=$(gcloud secrets versions access latest \
        --secret="$secret_id" \
        --project="$GSM_PROJECT" 2>/dev/null) || {
        echo "ERROR: Could not fetch $secret_id from GSM project=$GSM_PROJECT" >&2
        echo "Run: gcloud auth login   then retry" >&2
        return 1
    }
    printf -v "$var_name" '%s' "$value"
    export "$var_name"
    echo "export ${var_name}=<redacted>" >&2
}

echo "Fetching secrets from GSM project=${GSM_PROJECT}..." >&2

# GoDaddy API credentials (DNS management)
fetch_gsm_secret "prod-godaddy-api-key"    GODADDY_KEY
fetch_gsm_secret "prod-godaddy-api-secret" GODADDY_SECRET

# Google OAuth2 credentials (code-server login via oauth2-proxy)
fetch_gsm_secret "prod/portal/google-client-id"     GOOGLE_CLIENT_ID
fetch_gsm_secret "prod/portal/google-client-secret" GOOGLE_CLIENT_SECRET

# Generate oauth2-proxy cookie secret if not already set
if [[ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
    OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32)
    export OAUTH2_PROXY_COOKIE_SECRET
    echo "export OAUTH2_PROXY_COOKIE_SECRET=<generated>" >&2
fi

echo "All secrets fetched successfully." >&2

# Output env file format when not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cat <<EOF
GODADDY_KEY=${GODADDY_KEY}
GODADDY_SECRET=${GODADDY_SECRET}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
EOF
fi
