#!/bin/bash
# Production Environment Generator - Fully Automated IaC
# Generates production .env with all credentials from environment or secure sources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.production"

echo "====== AUTOMATED PRODUCTION ENVIRONMENT GENERATION ======"
echo ""

# Function to check environment variable or fail
require_env() {
    local var_name=$1
    local var_value="${!var_name}"
    if [ -z "$var_value" ]; then
        echo "ERROR: Required environment variable not set: $var_name"
        echo "Set via: export $var_name=<value>"
        return 1
    fi
    echo "$var_value"
}

# Function to generate secure random value
generate_secret() {
    openssl rand -base64 "${1:-32}"
}

echo "Gathering configuration from environment..."
echo ""

# OAuth Configuration (from environment)
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"

# Domain Configuration
DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_ENV="${DEPLOY_ENV:-production}"

# Generate credentials
CODE_SERVER_PASSWORD=$(generate_secret 16)
OAUTH2_PROXY_COOKIE_SECRET=$(generate_secret 32)
REDIS_PASSWORD=$(generate_secret 16)

echo "Generating .env.production..."
cat > "$ENV_FILE" << EOF
# Code-Server Enterprise - Production Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: automated-env-generator.sh (IaC)
# THIS FILE IS AUTO-GENERATED - DO NOT EDIT MANUALLY

# ========== DOMAIN CONFIGURATION ==========
DOMAIN=${DOMAIN}
DEPLOY_HOST=${DEPLOY_HOST}
DEPLOY_ENV=${DEPLOY_ENV}

# ========== SECURITY CREDENTIALS (auto-generated) ==========
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD}
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
REDIS_PASSWORD=${REDIS_PASSWORD}

# ========== OAUTH CONFIGURATION (from environment) ==========
# Source: Environment variables (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET)
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
OAUTH2_PROXY_OIDC_ISSUER_URL=https://accounts.google.com
OAUTH2_PROXY_REDIRECT_URL=https://${DOMAIN}/oauth2/callback

# ========== GITHUB TOKEN (optional, from environment) ==========
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# ========== SERVICE CONFIGURATION ==========
CODE_SERVER_USER=coder
LOG_LEVEL=info
OLLAMA_NUM_THREAD=6
REDIS_BIND=127.0.0.1
EOF

chmod 600 "$ENV_FILE"
echo "✓ Generated: $ENV_FILE (mode 600)"
echo ""
echo "Configuration Summary:"
echo "  Domain: $DOMAIN"
echo "  Host: $DEPLOY_HOST"
echo "  Environment: $DEPLOY_ENV"
echo "  OAuth: $([ -z "$GOOGLE_CLIENT_ID" ] && echo 'NOT SET (provide via env)' || echo 'CONFIGURED')"
echo ""
echo "To use this configuration:"
echo "  cp $ENV_FILE .env"
echo "  docker-compose up -d"
echo ""
echo "✅ Production environment ready"
