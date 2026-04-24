#!/usr/bin/env bash
# @file        scripts/migrations/002-custom-domains-schema.sql
# @description PostgreSQL schema extension for P3-1675 Whitelabel & Custom Domain support
#
-- Create custom_domains table for org-specific domain provisioning
CREATE TABLE IF NOT EXISTS custom_domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    domain VARCHAR(255) NOT NULL UNIQUE,
    is_verified BOOLEAN DEFAULT false,
    txt_record_value VARCHAR(255) NOT NULL,
    tls_certificate_expires_at TIMESTAMP,
    branding_logo_url VARCHAR(2048),
    branding_primary_color VARCHAR(7) DEFAULT '#007bff',
    branding_secondary_color VARCHAR(7) DEFAULT '#f8f9fa',
    is_active BOOLEAN DEFAULT true,
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(org_id, domain)
);

-- Create domain_verification_attempts for audit trail
CREATE TABLE IF NOT EXISTS domain_verification_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    custom_domain_id UUID NOT NULL REFERENCES custom_domains(id) ON DELETE CASCADE,
    attempt_number INTEGER,
    result VARCHAR(50) CHECK (result IN ('pending', 'success', 'failed')),
    error_message TEXT,
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create dns_cache for DNS lookup optimization (30-min TTL)
CREATE TABLE IF NOT EXISTS dns_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain VARCHAR(255) NOT NULL UNIQUE,
    dns_result JSONB,
    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP + INTERVAL '30 minutes'
);

-- Create indexes for performance
CREATE INDEX idx_custom_domains_org_id ON custom_domains(org_id);
CREATE INDEX idx_custom_domains_is_verified ON custom_domains(is_verified);
CREATE INDEX idx_custom_domains_is_active ON custom_domains(is_active);
CREATE INDEX idx_domain_verification_custom_domain_id ON domain_verification_attempts(custom_domain_id);
CREATE INDEX idx_dns_cache_expires_at ON dns_cache(expires_at);
