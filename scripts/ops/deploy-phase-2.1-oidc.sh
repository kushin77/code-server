#!/usr/bin/env bash
# @file        scripts/ops/deploy-phase-2.1-oidc.sh
# @module      operations/deployment
# @description Deploy Phase 2.1 OIDC Issuer to production

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

log_info "Phase 2.1 OIDC Issuer Deployment Starting..."

# ────────────────────────────────────────────────────────────────────────────
# Pre-deployment verification
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 1: Pre-deployment verification"

# Check if primary host is reachable
if ! ping -c 1 192.168.168.31 &>/dev/null; then
    log_fatal "Primary host (192.168.168.31) is not reachable"
fi
log_info "✅ Primary host is reachable"

# Check if Docker is running
if ! ssh akushnir@192.168.168.31 'docker ps &>/dev/null'; then
    log_fatal "Docker is not running on primary host"
fi
log_info "✅ Docker is running on primary host"

# ────────────────────────────────────────────────────────────────────────────
# Copy configuration files to primary host
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 2: Copying configuration files to primary host"

scp Caddyfile akushnir@192.168.168.31:/home/akushnir/code-server-enterprise/Caddyfile
log_info "✅ Caddyfile copied"

scp .env.oidc akushnir@192.168.168.31:/home/akushnir/code-server-enterprise/.env.oidc
log_info "✅ .env.oidc copied"

scp docker-compose.yml akushnir@192.168.168.31:/home/akushnir/code-server-enterprise/docker-compose.yml
log_info "✅ docker-compose.yml copied"

# ────────────────────────────────────────────────────────────────────────────
# Merge .env.oidc into .env on primary host
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 3: Integrating OIDC configuration into .env"

ssh akushnir@192.168.168.31 << 'EOF'
    cd /home/akushnir/code-server-enterprise

    # Backup existing .env
    if [ -f .env ]; then
        cp .env .env.backup.$(date +%s)
        log_info "✅ .env backed up"
    fi

    # Merge .env.oidc into .env (remove duplicates, keep new values)
    if [ -f .env.oidc ]; then
        # Extract variable names from .env.oidc that don't start with #
        grep -v '^#' .env.oidc | grep '=' | while IFS='=' read -r key value; do
            # Remove key from .env if it exists (keep new value)
            sed -i "/^${key}=/d" .env || true
            # Add new key=value to .env
            echo "${key}=${value}" >> .env
        done
        log_info "✅ .env.oidc merged into .env"
    fi
EOF

# ────────────────────────────────────────────────────────────────────────────
# Restart Docker Compose with new services
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 4: Restarting Docker Compose services"

ssh akushnir@192.168.168.31 << 'EOF'
    cd /home/akushnir/code-server-enterprise

    # Validate docker-compose.yml
    docker-compose config &>/dev/null || {
        log_fatal "docker-compose.yml validation failed"
    }
    log_info "✅ docker-compose.yml is valid"

    # Restart services
    docker-compose down
    docker-compose up -d
    log_info "✅ Docker Compose services restarted"
EOF

# ────────────────────────────────────────────────────────────────────────────
# Verification phase
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 5: Verifying OIDC Issuer is operational"

sleep 10  # Wait for services to start

# Check oauth2-oidc-issuer health
if ssh akushnir@192.168.168.31 'docker exec oauth2-oidc-issuer curl -fsS http://localhost:4182/.well-known/openid-configuration &>/dev/null'; then
    log_info "✅ oauth2-oidc-issuer is healthy"
else
    log_fatal "oauth2-oidc-issuer health check failed"
fi

# Check Caddy is routing to OIDC issuer
if curl -fsS http://192.168.168.31/.well-known/openid-configuration &>/dev/null; then
    log_info "✅ Caddy is routing .well-known/openid-configuration correctly"
else
    log_warn "Caddy routing test failed (may be blocked by network)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Final status check
# ────────────────────────────────────────────────────────────────────────────

log_info "Step 6: Final service status"

ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "oauth2|caddy"'

log_info "✅ Phase 2.1 OIDC Issuer Deployment Complete"
log_info "Access OIDC configuration at: https://ide.kushnir.cloud/.well-known/openid-configuration"
