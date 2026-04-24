#!/usr/bin/env bash
# @file        scripts/deploy-enterprise-customer.sh
# @module      deployment/whitelabel
# @description Deploy ElevatedIQ as whitelabel for enterprise customer

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Trap errors
trap 'log_fatal "Deployment failed"' ERR

# Configuration
CUSTOMER_ID="${1:-}"
CUSTOMER_DOMAIN="${2:-}"
CUSTOMER_EMAIL_DOMAIN="${3:-}"
OAUTH_PROVIDER="${4:-google}"  # google, okta, azure-ad

# Validation
if [[ -z "$CUSTOMER_ID" ]] || [[ -z "$CUSTOMER_DOMAIN" ]]; then
    log_error "Usage: $0 <customer-id> <domain> <email-domain> [oauth-provider]"
    log_error "Example: $0 acme-corp acme-corp.com acme-corp.com google"
    exit 1
fi

log_info "Deploying ElevatedIQ for: $CUSTOMER_ID ($CUSTOMER_DOMAIN)"

# Create customer directory
CUSTOMER_DIR="./customers/$CUSTOMER_ID"
mkdir -p "$CUSTOMER_DIR"

log_info "Creating configuration files in $CUSTOMER_DIR"

# 1. Generate branding config
cat > "$CUSTOMER_DIR/branding.yaml" <<EOF
brand:
  name: "$CUSTOMER_ID DevOS"
  ide_title: "$CUSTOMER_ID IDE"
  primary_color: "#0066CC"

domain:
  apex: "$CUSTOMER_DOMAIN"
  ide_subdomain: "ide"
  auth_subdomain: "auth"

oauth2:
  provider: "$OAUTH_PROVIDER"
  allowed_email_domains: "$CUSTOMER_EMAIL_DOMAIN"

data_isolation:
  customer_id: "$CUSTOMER_ID"
  nas_path: "/nas/persistent/$CUSTOMER_ID"
  database_name: "elevatediq_$CUSTOMER_ID"
  redis_prefix: "elevatediq:$CUSTOMER_ID:"
  kafka_prefix: "elevatediq-$CUSTOMER_ID-"
EOF

log_info "✓ Created branding.yaml"

# 2. Generate .env file
cat > "$CUSTOMER_DIR/.env.customer" <<EOF
# Customer: $CUSTOMER_ID
# Domain: $CUSTOMER_DOMAIN
# Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Branding
APEX_DOMAIN=$CUSTOMER_DOMAIN
IDE_DOMAIN=ide.$CUSTOMER_DOMAIN
AUTH_DOMAIN=auth.$CUSTOMER_DOMAIN
API_DOMAIN=api.$CUSTOMER_DOMAIN

# Data Isolation
CUSTOMER_ID=$CUSTOMER_ID
DATABASE_NAME=elevatediq_$CUSTOMER_ID
REDIS_PREFIX=elevatediq:$CUSTOMER_ID:
KAFKA_PREFIX=elevatediq-$CUSTOMER_ID-
NAS_PATH=/nas/persistent/$CUSTOMER_ID

# OAuth2
OAUTH2_PROXY_PROVIDER=$OAUTH_PROVIDER
OAUTH2_PROXY_EMAIL_DOMAIN=$CUSTOMER_EMAIL_DOMAIN

# Load secrets from GSM:
# - OAUTH_CLIENT_ID=\${CUSTOMER_ID}/oauth/client-id
# - OAUTH_CLIENT_SECRET=\${CUSTOMER_ID}/oauth/client-secret
# - DATABASE_PASSWORD=\${CUSTOMER_ID}/postgres/password
# - REDIS_PASSWORD=\${CUSTOMER_ID}/redis/password
EOF

log_info "✓ Created .env.customer"

# 3. Generate Caddyfile
cat > "$CUSTOMER_DIR/Caddyfile" <<EOF
# Caddyfile for customer: $CUSTOMER_ID
# Domain: $CUSTOMER_DOMAIN

# IDE
ide.$CUSTOMER_DOMAIN {
    reverse_proxy localhost:3000
    header X-Powered-By "$CUSTOMER_ID DevOS"
}

# Auth (OAuth2 proxy)
auth.$CUSTOMER_DOMAIN {
    reverse_proxy localhost:4180
}

# API
api.$CUSTOMER_DOMAIN {
    reverse_proxy localhost:8080
    header X-Powered-By "$CUSTOMER_ID DevOS"
}

# Portal
$CUSTOMER_DOMAIN {
    root * /srv/portal
    file_server
    try_files {path} {path}/ /index.html
    header X-Powered-By "$CUSTOMER_ID DevOS"
}
EOF

log_info "✓ Created Caddyfile"

# 4. Generate docker-compose.yml override
cat > "$CUSTOMER_DIR/docker-compose.override.yml" <<EOF
# Docker Compose override for customer: $CUSTOMER_ID

version: '3.8'

services:
  # Override database service
  postgres:
    environment:
      POSTGRES_DB: elevatediq_$CUSTOMER_ID
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password

  # Override Redis service
  redis:
    command: redis-server --requirepass \${REDIS_PASSWORD}
    restart: always

  # Override code-server service
  code-server:
    environment:
      APEX_DOMAIN: $CUSTOMER_DOMAIN
      CUSTOMER_ID: $CUSTOMER_ID
      WELCOME_TEXT: "Welcome to $CUSTOMER_ID DevOS"
    restart: always

secrets:
  postgres_password:
    external: true
    name: elevatediq-\${CUSTOMER_ID}-postgres-password
EOF

log_info "✓ Created docker-compose.override.yml"

# 5. Create onboarding checklist
cat > "$CUSTOMER_DIR/ONBOARDING.md" <<EOF
# ElevatedIQ Enterprise Onboarding — $CUSTOMER_ID

**Customer**: $CUSTOMER_ID  
**Domain**: $CUSTOMER_DOMAIN  
**Email Domain**: $CUSTOMER_EMAIL_DOMAIN  
**OAuth Provider**: $OAUTH_PROVIDER  
**Deployment Date**: $(date -u +'%Y-%m-%d')

## Pre-Deployment Checklist

### 1. Domain & DNS
- [ ] DNS A record or CNAME for \`$CUSTOMER_DOMAIN\` → your load balancer
- [ ] DNS A record or CNAME for \`ide.$CUSTOMER_DOMAIN\`
- [ ] DNS A record or CNAME for \`auth.$CUSTOMER_DOMAIN\`
- [ ] Verify DNS propagation: \`nslookup ide.$CUSTOMER_DOMAIN\`

### 2. OAuth Setup (Provider: $OAUTH_PROVIDER)

**If using Google Workspace**:
- [ ] Create OAuth 2.0 Consent Screen in Google Cloud Console
- [ ] Create OAuth 2.0 Client ID (Web application)
- [ ] Authorized redirect URI: \`https://auth.$CUSTOMER_DOMAIN/oauth2/callback\`
- [ ] Copy Client ID and Client Secret → save to GSM

**If using Okta**:
- [ ] Create new OIDC app in Okta
- [ ] Sign-in redirect URI: \`https://auth.$CUSTOMER_DOMAIN/oauth2/callback\`
- [ ] Copy Client ID and Client Secret → save to GSM

**If using Azure AD**:
- [ ] Register app in Azure AD
- [ ] Redirect URI: \`https://auth.$CUSTOMER_DOMAIN/auth/callback\`
- [ ] Create client secret → save to GSM

### 3. Infrastructure Setup
- [ ] Create NAS directory: \`/nas/persistent/$CUSTOMER_ID/\`
- [ ] Create PostgreSQL database: \`elevatediq_$CUSTOMER_ID\`
- [ ] Create Redis instance (or use shared with namespace)
- [ ] Set up Kafka topics with prefix: \`elevatediq-$CUSTOMER_ID-\`

### 4. Secrets Management (Google Secret Manager)
- [ ] Secret: \`$CUSTOMER_ID/oauth/client-id\`
- [ ] Secret: \`$CUSTOMER_ID/oauth/client-secret\`
- [ ] Secret: \`$CUSTOMER_ID/postgres/password\`
- [ ] Secret: \`$CUSTOMER_ID/redis/password\`
- [ ] Secret: \`$CUSTOMER_ID/session/secret\` (generate: \`openssl rand -base64 32\`)

### 5. Deployment
- [ ] Pull latest code: \`git pull origin main\`
- [ ] Deploy customer stack: \`docker compose -f docker-compose.yml -f customers/$CUSTOMER_ID/docker-compose.override.yml up -d\`
- [ ] Verify health: \`curl https://ide.$CUSTOMER_DOMAIN/health\`
- [ ] Test OAuth login: Open \`https://ide.$CUSTOMER_DOMAIN\` and authenticate

## Post-Deployment Verification

- [ ] IDE accessible: https://ide.$CUSTOMER_DOMAIN
- [ ] Custom branding visible (logo, colors, title)
- [ ] OAuth login works
- [ ] User data isolated from other customers
- [ ] Logs verify customer_id in all entries
- [ ] Knowledge graph populated with customer components
- [ ] Replay engine captures customer-specific CI failures

## Support & Troubleshooting

**Logs**:
\`\`\`bash
docker compose logs -f code-server | grep $CUSTOMER_ID
docker compose logs -f oauth2-proxy
docker compose logs -f caddy
\`\`\`

**Database**:
\`\`\`bash
# Connect to customer database
psql -h localhost -U postgres -d elevatediq_$CUSTOMER_ID
\`\`\`

**Contact**: support@kushnir.cloud

---

**Status**: ☐ Pre-Deploy | ☑ Deployed | ☐ Verified | ☐ Production
EOF

log_info "✓ Created ONBOARDING.md"

# 6. Generate Terraform module
cat > "$CUSTOMER_DIR/terraform.tfvars" <<EOF
# Terraform variables for customer: $CUSTOMER_ID

customer_id        = "$CUSTOMER_ID"
apex_domain        = "$CUSTOMER_DOMAIN"
email_domain       = "$CUSTOMER_EMAIL_DOMAIN"
oauth_provider     = "$OAUTH_PROVIDER"
nas_path           = "/nas/persistent/$CUSTOMER_ID"
database_name      = "elevatediq_$CUSTOMER_ID"
replicas           = 2
ha_enabled         = true
EOF

log_info "✓ Created terraform.tfvars"

# Summary
log_info ""
log_info "=========================================="
log_info "✅ Customer deployment files generated"
log_info "=========================================="
log_info "Customer: $CUSTOMER_ID"
log_info "Domain: $CUSTOMER_DOMAIN"
log_info "Directory: $CUSTOMER_DIR/"
log_info ""
log_info "Next steps:"
log_info "1. Review config files in $CUSTOMER_DIR/"
log_info "2. Configure secrets in Google Secret Manager"
log_info "3. Set up DNS records for $CUSTOMER_DOMAIN"
log_info "4. Run: docker compose -f docker-compose.yml -f $CUSTOMER_DIR/docker-compose.override.yml up -d"
log_info ""
log_info "For full onboarding guide, see: $CUSTOMER_DIR/ONBOARDING.md"
log_info "=========================================="
