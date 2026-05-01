#!/bin/bash
# Validate all required secrets are present and meet security standards

trap 'log_error "Validation failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up..."; rm -f /tmp/secrets-validate.* 2>/dev/null || true' EXIT

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
