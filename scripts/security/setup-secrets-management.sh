#!/bin/bash
# Setup secrets management infrastructure for code-server enterprise

trap 'log_error "Setup failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up..."; rm -f /tmp/secrets-setup.* 2>/dev/null || true' EXIT

source scripts/_common/init.sh

log_info "Setting up secrets management infrastructure"

# 1. Create secrets directory structure
log_info "Creating secrets directory structure"
mkdir -p .secrets/dev
mkdir -p .secrets/staging
mkdir -p .secrets/production
mkdir -p terraform/secrets
chmod 700 .secrets
chmod 700 terraform/secrets

# 2. Create .secrets/.gitignore
cat > .secrets/.gitignore << 'GITIGNORE'
# Ignore all secret files
*
!/.gitignore
!README.md

# Except documentation
!*.example
!*.template
GITIGNORE

log_success "Created .secrets directory structure"

# 3. Create secrets template file
cat > .secrets/dev/.env.secrets.template << 'TEMPLATE'
# Database Secrets
DB_PASSWORD=<generate-strong-password>
DB_REPLICATION_PASSWORD=<generate-strong-password>

# Redis Secrets
REDIS_PASSWORD=<generate-strong-password>
REDIS_TLS_PASSWORD=<generate-strong-password>

# OAuth2 Secrets
OAUTH2_CLIENT_SECRET=<generate-client-secret>
OAUTH2_COOKIE_SECRET=<generate-cookie-secret>

# API Keys
SCHEDULER_API_KEY=<generate-api-key>
QDRANT_API_KEY=<generate-api-key>
GRAFANA_ADMIN_PASSWORD=<generate-strong-password>

# Encryption Keys
ENCRYPTION_KEY=<generate-32-char-hex>
SIGNING_KEY=<generate-32-char-hex>

# External Services
APEX_DOMAIN=example.com
ADMIN_EMAIL=admin@example.com

# Infrastructure
PRIMARY_HOST=192.168.168.31
REPLICA_HOST=192.168.168.42
NAS_HOST=192.168.168.50
REGISTRY_URL=registry.kushnir.cloud:5000

# Deployment
DEPLOYMENT_MODE=production
TEMPLATE

log_success "Created secrets template"

# 4. Create secrets validation script
cat > scripts/security/validate-secrets.sh << 'VALIDATE'
#!/bin/bash
# Validate all required secrets are present and meet security standards

source scripts/_common/init.sh

log_info "Validating secrets..."

SECRETS_FILE="${1:-.secrets/production/.env.secrets}"

if [ ! -f "$SECRETS_FILE" ]; then
    log_error "Secrets file not found: $SECRETS_FILE"
    exit 1
fi

# Check required secrets
REQUIRED_SECRETS=(
    "DB_PASSWORD"
    "REDIS_PASSWORD"
    "OAUTH2_COOKIE_SECRET"
    "SCHEDULER_API_KEY"
    "QDRANT_API_KEY"
    "APEX_DOMAIN"
)

missing=0
for secret in "${REQUIRED_SECRETS[@]}"; do
    if ! grep -q "^$secret=" "$SECRETS_FILE"; then
        log_error "Missing required secret: $secret"
        missing=$((missing + 1))
    fi
done

if [ $missing -gt 0 ]; then
    log_error "Missing $missing required secrets"
    exit 1
fi

# Validate password strength (minimum 16 characters)
while IFS='=' read -r key value; do
    if [[ "$key" == *"PASSWORD"* ]] || [[ "$key" == *"SECRET"* ]]; then
        if [ ${#value} -lt 16 ]; then
            log_warn "$key is too short (${#value} < 16 chars)"
        fi
    fi
done < "$SECRETS_FILE"

log_success "Secrets validation passed"
VALIDATE

chmod +x scripts/security/validate-secrets.sh
log_success "Created secrets validation script"

# 5. Create secrets rotation guide
cat > docs/SECRETS_ROTATION.md << 'ROTATION'
# Secrets Rotation Procedure

## Quarterly Rotation Schedule

### Database Passwords
1. Update DB_PASSWORD in .secrets/production/.env.secrets
2. Run: terraform apply -target=module.database.docker_container.postgres
3. Update PostgreSQL password with new value
4. Verify all apps reconnect successfully
5. Document rotation in audit log

### API Keys
1. Generate new API key
2. Update in .secrets/production/.env.secrets
3. Deploy new containers: docker-compose up -d
4. Verify services authenticate with new key
5. Revoke old API key after verification window (24h)

### OAuth2 Secrets
1. Generate new OAuth2_COOKIE_SECRET
2. Update in .secrets/production/.env.secrets
3. Restart auth-server: docker-compose restart auth-server
4. Existing sessions will require re-authentication
5. Document change in changelog

### Encryption Keys
⚠️  WARNING: Encryption key rotation requires data re-encryption
    Contact security team before rotating

## Emergency Rotation

If a secret is compromised:
1. Immediately update in .secrets/production/.env.secrets
2. Run: bash scripts/security/validate-secrets.sh
3. Deploy changes: terraform apply
4. Notify all team members
5. Document incident in security log

## Automation

Set calendar reminders for:
- DB Password: Every 90 days
- API Keys: Every 60 days
- OAuth2 Secrets: Every 120 days
ROTATION

log_success "Created secrets rotation guide"

# 6. Create GitHub Actions secrets setup guide
cat > docs/GITHUB_SECRETS_SETUP.md << 'GITHUB'
# GitHub Secrets Configuration

## Required Secrets in GitHub Repository Settings

### Production Secrets
```
TF_VAR_db_password
TF_VAR_db_replication_password
TF_VAR_redis_password
TF_VAR_oauth2_client_secret
TF_VAR_oauth2_cookie_secret
TF_VAR_scheduler_api_key
TF_VAR_qdrant_api_key
TF_VAR_grafana_admin_password
TF_VAR_encryption_key
TF_VAR_signing_key
TF_VAR_apex_domain
TF_VAR_admin_email
TF_VAR_primary_host
TF_VAR_replica_host
TF_VAR_deployment_mode
```

### Access Tokens
```
GITHUB_TOKEN        # For automated releases
TERRAFORM_CLOUD_TOKEN  # For remote state
REGISTRY_USERNAME   # For container registry
REGISTRY_PASSWORD   # For container registry
```

## Setup Instructions

1. Navigate to: Settings → Secrets and variables → Actions

2. Add each secret:
   - Click "New repository secret"
   - Enter name (exact match above)
   - Enter value from .secrets/production/.env.secrets
   - Click "Add secret"

3. Verify secrets are masked in action logs

4. Update CI/CD workflows to use secrets:
   ```yaml
   env:
     TF_VAR_db_password: ${{ secrets.TF_VAR_db_password }}
   ```

## Security Best Practices

- Never commit .secrets/ directory
- Use separate secrets for dev/staging/prod
- Rotate secrets quarterly
- Audit secret access in GitHub logs
- Use fine-grained tokens where possible
GITHUB

log_success "Created GitHub secrets setup guide"

log_success "Secrets management infrastructure setup complete"
log_info "Next steps:"
log_info "  1. Copy .secrets/dev/.env.secrets.template to .secrets/production/.env.secrets"
log_info "  2. Fill in all secrets with actual values"
log_info "  3. Run: bash scripts/security/validate-secrets.sh .secrets/production/.env.secrets"
log_info "  4. Follow docs/GITHUB_SECRETS_SETUP.md to configure GitHub"
log_info "  5. Review docs/SECRETS_ROTATION.md for ongoing maintenance"
