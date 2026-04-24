-- Migration: 001_initial_saas_schema.sql
-- Description: Create initial SaaS tables for user/group/org management (Phase 3 #1674)
-- Date: April 24, 2026
-- Status: Idempotent (safe to run multiple times)

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════
-- Organizations Table
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    admin_id UUID,
    logo_url TEXT,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CONSTRAINT org_name_not_empty CHECK (name != '')
);

CREATE INDEX IF NOT EXISTS idx_organizations_active ON organizations(is_active);
CREATE INDEX IF NOT EXISTS idx_organizations_created_at ON organizations(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- Users Table
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CONSTRAINT email_not_empty CHECK (email != ''),
    CONSTRAINT valid_email CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- Groups Table
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CONSTRAINT group_name_not_empty CHECK (name != ''),
    CONSTRAINT group_org_fk FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE,
    UNIQUE(org_id, name)
);

CREATE INDEX IF NOT EXISTS idx_groups_org_id ON groups(org_id);
CREATE INDEX IF NOT EXISTS idx_groups_created_at ON groups(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- Memberships Table (Users → Groups & Organizations)
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    group_id UUID,
    role VARCHAR(50) DEFAULT 'member',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CONSTRAINT valid_role CHECK (role IN ('admin', 'member', 'viewer')),
    CONSTRAINT membership_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT membership_org_fk FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT membership_group_fk FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL,
    UNIQUE(user_id, org_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_user_id ON memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_org_id ON memberships(org_id);
CREATE INDEX IF NOT EXISTS idx_memberships_group_id ON memberships(group_id);
CREATE INDEX IF NOT EXISTS idx_memberships_role ON memberships(role);
CREATE INDEX IF NOT EXISTS idx_memberships_created_at ON memberships(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- API Keys Table (for self-service API access)
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL,
    user_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    scope VARCHAR(1000),
    expires_at TIMESTAMP,
    last_used_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP,
    CONSTRAINT apikey_name_not_empty CHECK (name != ''),
    CONSTRAINT apikey_org_fk FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT apikey_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_keys_org_id ON api_keys(org_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(is_active);
CREATE INDEX IF NOT EXISTS idx_api_keys_created_at ON api_keys(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- Audit Log Table (for compliance & debugging)
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID,
    user_id UUID,
    action VARCHAR(255) NOT NULL,
    resource_type VARCHAR(255),
    resource_id UUID,
    changes JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT auditlog_org_fk FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE SET NULL,
    CONSTRAINT auditlog_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_id ON audit_logs(org_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);

-- ════════════════════════════════════════════════════════════════════════════
-- Update Timestamps Trigger Function
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables with updated_at
CREATE TRIGGER organizations_update_trigger
BEFORE UPDATE ON organizations
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER users_update_trigger
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER groups_update_trigger
BEFORE UPDATE ON groups
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER memberships_update_trigger
BEFORE UPDATE ON memberships
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER api_keys_update_trigger
BEFORE UPDATE ON api_keys
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

COMMIT;
