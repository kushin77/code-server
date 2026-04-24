#!/usr/bin/env bash
# @file        scripts/ops/bootstrap-production-secrets.sh
# @module      operations/secrets
# @description Bootstrap production environment variables for docker-compose
# @owner       infrastructure
# @status      ready-for-execution

set -euo pipefail

source "$SCRIPT_DIR/_common/init.sh"

PRODUCTION_HOST="${PRODUCTION_HOST:-}"
PRODUCTION_USER="${PRODUCTION_USER:-ainternal}"

log_info "Bootstrapping production secrets on $PRODUCTION_HOST..."

# Generate secure random strings for secrets
gen_secret() {
  openssl rand -base64 32 | tr -d '\n'
}

# Create env file with all required variables
create_env_file() {
  cat > /tmp/production.env << 'ENVEOF'
# ════════════════════════════════════════════════════════════════════════════
# Production Environment Configuration - Generated $(date)
# ════════════════════════════════════════════════════════════════════════════

# Infrastructure
DEPLOYMENT_ENV=production
APEX_DOMAIN=internal.cloud
PRIMARY_HOST=
REPLICA_2_HOST=
NAS_HOST=

# Code Server
CODE_SERVER_PASSWORD=SecureCodeServerPassword2026!@#
SUDO_PASSWORD=SecureCodeServerPassword2026!@#

# Database
POSTGRES_PASSWORD=SecurePostgresPassword2026!@#
POSTGRES_USER=postgres
POSTGRES_DB=code-server
POSTGRES_PORT=5432

# Redis & Session Management
REDIS_PASSWORD=SecureRedisPassword2026!@#
IDE_SESSION_LB_SECRET=SecureLoadBalancerSecret2026!@#0123456789ABCDEF

# OAuth & Authentication
OAUTH2_PROXY_COOKIE_SECRET=SecureOAuth2CookieSecret2026!@#
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true

# Optional: Vault Integration (can be disabled)
VAULT_ADDR=https://vault.internal.cloud
VAULT_ROOT_TOKEN=dev-vault-root-2026
VAULT_CODE_SERVER_PASSWORD=dev-vault-password-2026
VAULT_REDIS_PASSWORD=dev-vault-redis-2026
VAULT_IDE_SESSION_LB_SECRET=dev-vault-lb-2026
VAULT_POSTGRES_PASSWORD=dev-vault-postgres-2026
VAULT_ELASTICSEARCH_PASSWORD=dev-vault-elasticsearch-2026

# Optional: Elasticsearch (can be disabled via profiles)
ELASTICSEARCH_PASSWORD=SecureElasticsearchPassword2026!@#

# Optional: Cloud Integrations (can be disabled)
CLOUDFLARE_API_TOKEN=dev-cloudflare-2026
GOOGLE_CLIENT_ID=dev-google-2026
GOOGLE_CLIENT_SECRET=dev-google-secret-2026

# Optional: External Services (can be disabled)
SLACK_BOT_TOKEN=xoxb-dev-slack-token-2026
SENTRY_ORG_SLUG=internal.cloud
GITHUB_TOKEN=ghp_dev_github_token_2026

# Monitoring & Observability
LOKI_RETENTION_DAYS=30
PROMETHEUS_RETENTION=30d

# Feature Flags
FEATURE_WEBHOOK_ENABLED=false
WEBHOOK_ROLLOUT_PERCENTAGE=0

# Profiles (comma-separated, empty for defaults)
COMPOSE_PROFILES=

ENVEOF
}

log_info "Creating production environment file..."
create_env_file

log_info "Deploying secrets to production ($PRODUCTION_USER@$PRODUCTION_HOST)..."
scp /tmp/production.env "$PRODUCTION_USER@$PRODUCTION_HOST:code-server-enterprise/.env"

log_info "Starting services with new configuration..."
ssh "$PRODUCTION_USER@$PRODUCTION_HOST" "cd code-server-enterprise && docker-compose up -d 2>&1 | grep -E 'Starting|Created|done|ERROR' | tail -20"

log_info "Verifying services..."
ssh "$PRODUCTION_USER@$PRODUCTION_HOST" "cd code-server-enterprise && docker-compose ps | grep -c UP && echo 'Services running'"

log_info "✅ Production secrets bootstrap complete"
log_info "Next: Verify DAST scans can reach https://ide.internal.cloud/"

rm -f /tmp/production.env
