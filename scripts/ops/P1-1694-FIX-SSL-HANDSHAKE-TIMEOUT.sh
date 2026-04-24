#!/usr/bin/env bash
# @file        scripts/ops/P1-1694-FIX-SSL-HANDSHAKE-TIMEOUT.sh
# @module      ops/infrastructure
# @description Fixes SSL handshake timeouts for ide.kushnir.cloud and kushnir.cloud by switching to explicit TLS and adding 'ask' endpoint.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"
init_repo

BASE_DOMAIN="${BASE_DOMAIN:-kushnir.cloud}"
IDE_DOMAIN="${IDE_DOMAIN:-ide.${BASE_DOMAIN}}"
PORTAL_DOMAIN="${PORTAL_DOMAIN:-${BASE_DOMAIN}}"
SAAS_API_VALIDATE_HOST="${SAAS_API_VALIDATE_HOST:-saas-api:5000}"
HTTP_SCHEME="http"
HTTPS_SCHEME="https"

# 1. Archival of pre-fix Caddyfile
cp Caddyfile Caddyfile.pre-ssl-fix

# 2. Apply Caddyfile changes
# - Add global email and ask endpoint
# - Switch on_demand to explicit certs for core domains (managed by Caddy)
# - Keep on_demand for wildcards but link to local validator

cat <<EOF > Caddyfile
# Production Caddyfile — ${PORTAL_DOMAIN} / ${IDE_DOMAIN}
# Caddy 2.7.6 — direct TLS termination with existing Let's Encrypt certs
# Certs stored in enterprise_caddy-data volume (valid until 2026-07-19)
# NOTE: Caddy must run as root (user 0) to access root-owned cert files.

{
    email devops@kushnir.cloud
    on_demand_tls {
        # Saas-api provides domain validation for custom whitelabel domains
        ask ${HTTP_SCHEME}://${SAAS_API_VALIDATE_HOST}/api/v1/validate-domain
    }
}

# HTTP listener for health checks (bypass TLS, allow DAST scans)
${HTTP_SCHEME}://${IDE_DOMAIN} {
    @health path /health /healthz /ping
    handle @health {
        respond "OK" 200
    }

    # Redirect other traffic to HTTPS
    handle {
        redir ${HTTPS_SCHEME}://{host}{uri}
    }
}

# HTTPS listener for ide.kushnir.cloud (Explicit certs with self-signed fallback)
${IDE_DOMAIN} {
    # Reference the local certs generated via scripts/ops/p1-1694-tls-recovery.sh
    tls /etc/caddy/tls.crt /etc/caddy/tls.key

    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        -Server
    }

    @health path /health /healthz /ping
    respond @health "OK" 200

    reverse_proxy oauth2-proxy:4180 {
        header_up Host ${IDE_DOMAIN}
        header_up X-Forwarded-Proto ${HTTPS_SCHEME}
        header_up X-Real-IP {remote_host}
        fail_duration 5s
        max_fails 3
        health_uri /ping
    }
}

# HTTP listener for kushnir.cloud health checks
${HTTP_SCHEME}://${PORTAL_DOMAIN} {
    @health path /health /healthz /ping
    handle @health {
        respond "OK" 200
    }

    handle {
        redir ${HTTPS_SCHEME}://{host}{uri}
    }
}

# HTTPS listener for kushnir.cloud (Explicit certs)
${PORTAL_DOMAIN} {
    tls /etc/caddy/tls.crt /etc/caddy/tls.key

    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        -Server
    }

    @health path /health /healthz /ping
    respond @health "OK" 200

    reverse_proxy appsmith:80 {
        header_up Host ${PORTAL_DOMAIN}
        header_up X-Forwarded-Proto ${HTTPS_SCHEME}
        header_up X-Real-IP {remote_host}
        fail_duration 5s
        max_fails 3
    }
}

# Catch-all HTTP health listener
:80 {
    @health path /health /healthz /ping
    respond @health "OK" 200
    respond "Not Found" 404
}

# ════════════════════════════════════════════════════════════════════════════════
# Custom Domain Routing — Dynamic Whitelabel Domains
# ════════════════════════════════════════════════════════════════════════════════

*.${BASE_DOMAIN} {
    tls {
        on_demand
    }

    encode gzip

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        -Server
    }

    @health path /health /healthz /ping
    respond @health "OK" 200

    reverse_proxy saas-api:5000 {
        header_up Host {http.request.host}
        header_up X-Forwarded-Proto https
        header_up X-Real-IP {remote_host}
    }
}
EOF

echo "[INFO] Caddyfile updated with local cert references."
