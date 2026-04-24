#!/usr/bin/env bash
# @file        scripts/db/create-custom-domains-table.sh
# @module      database/schema
# @description Creates PostgreSQL custom_domains table for whitelabel domain provisioning
# @owner       engineering/platform
# @status      production-ready
#
# Idempotent schema initialization for custom domain management.
# Safe to run multiple times - uses CREATE TABLE IF NOT EXISTS pattern.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_common/init.sh"

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-code_server}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

log_info "Creating custom_domains table (idempotent)"

# Create SQL migration
MIGRATION_SQL=$(cat <<'EOF'
-- Create custom_domains table for whitelabel support
CREATE TABLE IF NOT EXISTS custom_domains (
    id SERIAL PRIMARY KEY,
    org_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    domain VARCHAR(255) NOT NULL UNIQUE,
    is_verified BOOLEAN DEFAULT FALSE,
    txt_record_value VARCHAR(255) NOT NULL,
    tls_certificate_status VARCHAR(50) DEFAULT 'pending', -- pending, active, expired, error
    tls_expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT unique_org_domain UNIQUE(org_id, domain)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_custom_domains_org_id 
    ON custom_domains(org_id) 
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_custom_domains_domain 
    ON custom_domains(domain) 
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_custom_domains_verified 
    ON custom_domains(is_verified, org_id) 
    WHERE deleted_at IS NULL;

-- Create table for DNS verification history (audit trail)
CREATE TABLE IF NOT EXISTS custom_domain_dns_verifications (
    id SERIAL PRIMARY KEY,
    domain_id INTEGER NOT NULL REFERENCES custom_domains(id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    dns_record_found BOOLEAN DEFAULT FALSE,
    dns_response TEXT,
    error_message TEXT,
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for verification history
CREATE INDEX IF NOT EXISTS idx_custom_domain_dns_verifications_domain_id 
    ON custom_domain_dns_verifications(domain_id);

-- Create audit trigger (auto-update updated_at)
CREATE OR REPLACE FUNCTION update_custom_domains_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_custom_domains_updated_at ON custom_domains;
CREATE TRIGGER trigger_custom_domains_updated_at
    BEFORE UPDATE ON custom_domains
    FOR EACH ROW
    EXECUTE FUNCTION update_custom_domains_updated_at();
EOF
)

# Execute migration with error handling
if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<< "$MIGRATION_SQL"; then
    log_info "✅ custom_domains table created successfully (idempotent)"
    log_info "   Tables: custom_domains, custom_domain_dns_verifications"
    log_info "   Indexes: 3x on custom_domains, 1x on dns_verifications"
    log_info "   Audit: auto-update trigger installed"
else
    log_error "Failed to create custom_domains schema"
    exit 1
fi

log_info "✅ Schema initialization complete"
