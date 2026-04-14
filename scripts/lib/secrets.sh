#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/lib/secrets.sh — Google Secret Manager integration
# Usage: source scripts/lib/secrets.sh && secrets_load_env
#
# Priority:
#  1. GSM (if gcloud is authenticated and SECRET_PROJECT is set)
#  2. Local .env file (on-prem fallback)
#
# Env vars written to stdout or exported — never logged.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SECRET_PROJECT="${SECRET_PROJECT:-}"
GSM_PREFIX="${GSM_PREFIX:-code-server-enterprise}"
ENV_FILE="${ENV_FILE:-.env}"

# ── Helpers ───────────────────────────────────────────────────────────────────

_gsm_available() {
    command -v gcloud &>/dev/null && \
    [[ -n "$SECRET_PROJECT" ]] && \
    gcloud auth application-default print-access-token &>/dev/null 2>&1
}

_gsm_get() {
    local name="$1"
    gcloud secrets versions access latest \
        --secret="${GSM_PREFIX}-${name}" \
        --project="$SECRET_PROJECT" 2>/dev/null
}

_require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "[secrets] FATAL: $var is not set" >&2
        return 1
    fi
}

# ── GSM: pull all secrets into env vars ──────────────────────────────────────

secrets_load_gsm() {
    echo "[secrets] Loading from Google Secret Manager (project: $SECRET_PROJECT)" >&2

    export POSTGRES_PASSWORD="$(_gsm_get postgres-password)"
    export REDIS_PASSWORD="$(_gsm_get redis-password)"
    export CODE_SERVER_PASSWORD="$(_gsm_get code-server-password)"
    export GOOGLE_CLIENT_ID="$(_gsm_get google-client-id)"
    export GOOGLE_CLIENT_SECRET="$(_gsm_get google-client-secret)"
    export OAUTH2_PROXY_COOKIE_SECRET="$(_gsm_get oauth2-cookie-secret)"
    export GRAFANA_ADMIN_PASSWORD="$(_gsm_get grafana-admin-password)"
    export GITHUB_TOKEN="$(_gsm_get github-token)"

    echo "[secrets] GSM secrets loaded" >&2
}

# ── Local .env fallback ──────────────────────────────────────────────────────

secrets_load_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "[secrets] WARN: $ENV_FILE not found — copy .env.example and fill values" >&2
        return 1
    fi
    echo "[secrets] Loading from $ENV_FILE" >&2
    # shellcheck disable=SC1090
    set -a && source "$ENV_FILE" && set +a
    echo "[secrets] .env loaded" >&2
}

# ── GSM: push local .env to GSM (seed) ──────────────────────────────────────

secrets_push_to_gsm() {
    if ! _gsm_available; then
        echo "[secrets] gcloud not available — cannot push to GSM" >&2
        return 1
    fi

    secrets_load_env_file

    local pairs=(
        "postgres-password:${POSTGRES_PASSWORD:-}"
        "redis-password:${REDIS_PASSWORD:-}"
        "code-server-password:${CODE_SERVER_PASSWORD:-}"
        "google-client-id:${GOOGLE_CLIENT_ID:-}"
        "google-client-secret:${GOOGLE_CLIENT_SECRET:-}"
        "oauth2-cookie-secret:${OAUTH2_PROXY_COOKIE_SECRET:-}"
        "grafana-admin-password:${GRAFANA_ADMIN_PASSWORD:-}"
        "github-token:${GITHUB_TOKEN:-}"
    )

    for pair in "${pairs[@]}"; do
        local secret_name="${GSM_PREFIX}-${pair%%:*}"
        local secret_value="${pair#*:}"
        if [[ -z "$secret_value" ]]; then
            echo "[secrets] SKIP $secret_name (empty)" >&2
            continue
        fi
        if gcloud secrets describe "$secret_name" --project="$SECRET_PROJECT" &>/dev/null; then
            echo "$secret_value" | gcloud secrets versions add "$secret_name" \
                --project="$SECRET_PROJECT" --data-file=- &>/dev/null
        else
            echo "$secret_value" | gcloud secrets create "$secret_name" \
                --project="$SECRET_PROJECT" --replication-policy=automatic --data-file=- &>/dev/null
        fi
        echo "[secrets] pushed $secret_name" >&2
    done
}

# ── Main entry point ─────────────────────────────────────────────────────────

secrets_load_env() {
    if _gsm_available; then
        secrets_load_gsm
    else
        echo "[secrets] GSM not available — using .env file" >&2
        secrets_load_env_file
    fi

    # Validate required vars are set
    _require_env POSTGRES_PASSWORD
    _require_env REDIS_PASSWORD
    _require_env CODE_SERVER_PASSWORD
    _require_env GRAFANA_ADMIN_PASSWORD
}

# ── Generate secure secrets for first-time setup ─────────────────────────────

secrets_generate() {
    cat <<EOF
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — fill GOOGLE_* with real OAuth app creds
POSTGRES_PASSWORD=$(openssl rand -hex 24)
REDIS_PASSWORD=$(openssl rand -hex 24)
CODE_SERVER_PASSWORD=$(openssl rand -hex 16)
OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -hex 16)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 16)
GITHUB_TOKEN=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
DOMAIN=ide.kushnir.cloud
ACME_EMAIL=ops@kushnir.cloud
EOF
}
