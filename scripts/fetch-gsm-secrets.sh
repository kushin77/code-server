#!/usr/bin/env bash
# @file        scripts/fetch-gsm-secrets.sh
# @module      operations
# @description fetch gsm secrets — on-prem code-server
# @owner       platform
# @status      active
# fetch-gsm-secrets.sh
# Fetches code-server secrets from Google Secret Manager (gcp-eiq project)
# Mimics eiq-org pattern: gcloud secrets versions access → env var injection
# Requires: gcloud auth login (or service account activation)
# Usage: source ./fetch-gsm-secrets.sh   (sources env vars into current shell)
#        ./fetch-gsm-secrets.sh > .env    (writes to env file)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

readonly GSM_PROJECT="${GSM_PROJECT:-gcp-eiq}"
NON_INTERACTIVE="false"
SHOW_HELP="false"

usage() {
    cat <<'EOF'
Usage:
  source scripts/fetch-gsm-secrets.sh [--non-interactive]
  bash scripts/fetch-gsm-secrets.sh [--non-interactive]

Options:
  --non-interactive  Fail fast without any interactive auth expectation.
                     If no active gcloud account is present, attempts service-account auth
                     using GOOGLE_APPLICATION_CREDENTIALS and exits non-zero on failure.
  -h, --help         Show this help text.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive)
                NON_INTERACTIVE="true"
                shift
                ;;
            -h|--help)
                SHOW_HELP="true"
                shift
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                usage >&2
                return 1
                ;;
        esac
    done
}

ensure_gcloud_auth_noninteractive() {
    if gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q '.'; then
        return 0
    fi

    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" && -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
        echo "No active gcloud account found; activating service account from GOOGLE_APPLICATION_CREDENTIALS" >&2
        CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet auth activate-service-account --key-file="${GOOGLE_APPLICATION_CREDENTIALS}" >/dev/null
        if [[ -n "${GSM_PROJECT:-}" ]]; then
            CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet config set project "${GSM_PROJECT}" >/dev/null
        fi
        return 0
    fi

    echo "ERROR: Non-interactive GSM mode requires active gcloud auth or GOOGLE_APPLICATION_CREDENTIALS" >&2
    return 1
}

fetch_gsm_secret() {
    local secret_id="$1"
    local var_name="$2"
    local value
    value=$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet secrets versions access latest \
        --secret="$secret_id" \
        --project="$GSM_PROJECT" 2>/dev/null) || {
        echo "ERROR: Could not fetch $secret_id from GSM project=$GSM_PROJECT" >&2
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo "Non-interactive mode is enabled. Ensure GOOGLE_APPLICATION_CREDENTIALS or workload identity auth is configured." >&2
        else
            echo "Run: gcloud auth login   then retry" >&2
        fi
        return 1
    }
    printf -v "$var_name" '%s' "$value"
    export "$var_name"
    echo "export ${var_name}=<redacted>" >&2
}

fetch_gsm_secret_optional() {
    local secret_id="$1"
    local var_name="$2"
    local value

    value=$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet secrets versions access latest \
        --secret="$secret_id" \
        --project="$GSM_PROJECT" 2>/dev/null) || return 1

    printf -v "$var_name" '%s' "$value"
    export "$var_name"
    echo "export ${var_name}=<redacted> (from $secret_id)" >&2
    return 0
}

fetch_first_available_secret() {
    local var_name="$1"
    shift

    local secret_id
    for secret_id in "$@"; do
        if fetch_gsm_secret_optional "$secret_id" "$var_name"; then
            return 0
        fi
    done

    return 1
}

parse_args "$@"

if [[ "$SHOW_HELP" == "true" ]]; then
    usage
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        exit 0
    fi
    return 0
fi

echo "Fetching secrets from GSM project=${GSM_PROJECT}..." >&2

if [[ "$NON_INTERACTIVE" == "true" ]]; then
    if ! ensure_gcloud_auth_noninteractive; then
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            exit 1
        fi
        return 1
    fi
fi

# GoDaddy API credentials (DNS management)
fetch_gsm_secret "prod-godaddy-api-key"    GODADDY_KEY
fetch_gsm_secret "prod-godaddy-api-secret" GODADDY_SECRET

# Google OAuth2 credentials (code-server login via oauth2-proxy)
fetch_gsm_secret "prod-portal-google-oauth-client-id"     GOOGLE_CLIENT_ID
fetch_gsm_secret "prod-portal-google-oauth-client-secret" GOOGLE_CLIENT_SECRET

# oauth2-proxy cookie secre
fetch_gsm_secret "prod-portal-oauth2-cookie-secret" OAUTH2_PROXY_COOKIE_SECRET

# GitHub PAT (optional): default auth token for GitHub API/gh CLI calls.
# Canonical secret is github-token. GSM_GITHUB_TOKEN_SECRET is legacy fallback.
if ! fetch_first_available_secret "GITHUB_TOKEN" \
    "${GSM_SECRET_NAME:-github-token}" \
    "${GSM_GITHUB_TOKEN_SECRET:-}" \
    "github-token" \
    "prod-github-pat" \
    "prod-code-server-github-token" \
    "prod-github-token"; then
    echo "WARN: No GitHub PAT found in GSM (continuing without GITHUB_TOKEN)" >&2
fi

# Keep gh CLI compatibility: GH_TOKEN is honored by gh for API/auth calls.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GH_TOKEN="$GITHUB_TOKEN"
fi

echo "All secrets fetched successfully." >&2

# Output env file format when not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cat <<EOF
# Generated by fetch-gsm-secrets.sh — DO NOT COMMI
# Domain from config.sh (sourced via init.sh)
GODADDY_KEY=${GODADDY_KEY}
GODADDY_SECRET=${GODADDY_SECRET}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:-}
ALLOWED_EMAIL_DOMAINS=${ALLOWED_EMAIL_DOMAINS:-*}
WORKSPACE_PATH=${WORKSPACE_PATH:-/mnt/nas-56/kushin77/applications/code-server-enterprise}
CODER_DATA_PATH=${CODER_DATA_PATH:-/mnt/nas-56/code-server}
OLLAMA_DATA_PATH=${OLLAMA_DATA_PATH:-/mnt/nas-56/ollama}
EOF
fi

