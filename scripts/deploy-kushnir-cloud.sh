#!/usr/bin/env bash
# deploy-kushnir-cloud.sh
# Master deploy script for kushnir.cloud/ide
# Orchestrates: GSM → GoDaddy DNS → oauth2-proxy → Caddy → code-server
#
# Prerequisites:
#   1. gcloud auth login (or service account activated)
#   2. docker / docker-compose installed in WSL
#   3. Port 443 forwarded from router to this machine (173.77.179.148:443)
#   4. Windows port-forward: scripts/windows-port-forward.ps1 (first-time only)
#
# Usage:
#   ./scripts/deploy-kushnir-cloud.sh [--skip-dns] [--skip-docker]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

readonly PUBLIC_IP="173.77.179.148"
readonly DOMAIN="kushnir.cloud"

SKIP_DNS=false
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-dns)    SKIP_DNS=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

log() { echo "[$(date -u '+%H:%M:%S')] $*"; }

# ── Step 1: Fetch secrets from GSM ──────────────────────────────────────────
log "Step 1/5: Fetching secrets from Google Secret Manager..."
# shellcheck source=scripts/fetch-gsm-secrets.sh
source "${SCRIPT_DIR}/fetch-gsm-secrets.sh"
export GODADDY_KEY GODADDY_SECRET GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET OAUTH2_PROXY_COOKIE_SECRET

# ── Step 2: Set GoDaddy DNS A record ────────────────────────────────────────
if [[ "$SKIP_DNS" == false ]]; then
    log "Step 2/5: Setting GoDaddy DNS A record for ${DOMAIN} → ${PUBLIC_IP}..."
    PUBLIC_IP="$PUBLIC_IP" bash "${SCRIPT_DIR}/set-godaddy-dns.sh"
    log "DNS set. Propagation may take up to 5 minutes."
else
    log "Step 2/5: Skipping DNS (--skip-dns)."
fi

# ── Step 3: Update code-server config with base-path ────────────────────────
log "Step 3/5: Updating code-server config for base-path /ide..."
CONFIG_FILE="$HOME/.config/code-server/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
    # Add/update base-path in config.yaml
    if grep -q "^base-path:" "$CONFIG_FILE"; then
        sed -i 's|^base-path:.*|base-path: /ide|' "$CONFIG_FILE"
    else
        echo "base-path: /ide" >> "$CONFIG_FILE"
    fi
    # Switch to HTTP internally (TLS handled by Caddy)
    sed -i 's|^cert: true|cert: false|' "$CONFIG_FILE"
    log "code-server config updated. Restarting..."
    # Restart code-server if running as systemd service
    systemctl --user restart code-server 2>/dev/null || \
        pkill -HUP code-server 2>/dev/null || \
        log "Warning: could not restart code-server — restart manually"
else
    log "Warning: code-server config not found at ${CONFIG_FILE}"
fi

# ── Step 4: Start Docker Compose stack (oauth2-proxy + Caddy) ───────────────
if [[ "$SKIP_DOCKER" == false ]]; then
    log "Step 4/5: Starting oauth2-proxy + Caddy via Docker Compose..."
    cd "$REPO_DIR"

    # Write env file for docker-compose (never committed to git)
    cat > .env <<EOF
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:-$(openssl rand -hex 16)}
ALLOWED_EMAIL_DOMAINS=${ALLOWED_EMAIL_DOMAINS:-*}
EOF
    chmod 600 .env

    docker compose pull oauth2-proxy caddy
    docker compose up -d oauth2-proxy caddy
    log "Services started."
    docker compose ps
else
    log "Step 4/5: Skipping Docker Compose (--skip-docker)."
fi

# ── Step 5: Verify ──────────────────────────────────────────────────────────
log "Step 5/5: Verifying deployment..."
sleep 5

# Check oauth2-proxy health
if curl -sf "http://localhost:4180/ping" > /dev/null 2>&1; then
    log "✅ oauth2-proxy: healthy"
else
    log "⚠️  oauth2-proxy: not responding on :4180 — check: docker compose logs oauth2-proxy"
fi

# Check Caddy health
if curl -sf -o /dev/null -w "%{http_code}" "http://localhost:80" 2>/dev/null | grep -q "301\|200"; then
    log "✅ Caddy: healthy"
else
    log "⚠️  Caddy: not responding — check: docker compose logs caddy"
fi

# DNS check
log "DNS check (may not be propagated yet):"
dig +short "${DOMAIN}" A 2>/dev/null || host "${DOMAIN}" 2>/dev/null || echo "  (dig/host not available)"

log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Deployment complete!"
log ""
log "  IDE URL:     https://${DOMAIN}/ide"
log "  Auth:        Google OAuth (https://kushnir.cloud/oauth2/start)"
log "  Local URL:   https://localhost:443   (direct, password auth)"
log ""
log "  Next steps if first deploy:"
log "    1. Ensure port 443 is open on your router → ${PUBLIC_IP}"
log "    2. Run (Windows Admin):  .\\scripts\\windows-port-forward.ps1"
log "    3. Create Google OAuth app at:"
log "       https://console.cloud.google.com/apis/credentials"
log "       Authorized redirect URI: https://${DOMAIN}/oauth2/callback"
log "       Store client ID/secret in GSM as:"
log "         prod/portal/google-client-id"
log "         prod/portal/google-client-secret"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
