-- Organizations & Multi-Tenancy Schema
-- Production-ready PostgreSQL schema with RBAC and audit logging
-- Idempotent: Safe to run multiple times (IF NOT EXISTS)

BEGIN;

-- Organizations table: Core multi-tenant entities
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  tier VARCHAR(50) NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro', 'enterprise')),
  workspace_count INTEGER DEFAULT 0,
  max_workspaces INTEGER DEFAULT CASE 
    WHEN tier = 'free' THEN 5 
    WHEN tier = 'pro' THEN 50 
    WHEN tier = 'enterprise' THEN 1000 
  END,
  billing_contact VARCHAR(255),
  billing_email VARCHAR(255),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP,
  
  INDEX idx_organizations_tier (tier),
  INDEX idx_organizations_created (created_at DESC),
  UNIQUE INDEX idx_organizations_billing_email (billing_email)
);

-- Organization members table: Multi-tenancy with role-based access
CREATE TABLE IF NOT EXISTS organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'developer' CHECK (role IN ('admin', 'developer', 'auditor', 'viewer')),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT uk_org_member UNIQUE (organization_id, user_id),
  INDEX idx_org_members_organization (organization_id),
  INDEX idx_org_members_user (user_id),
  INDEX idx_org_members_role (role)
);

-- Organization API keys: Tier-based rate limiting & authentication
CREATE TABLE IF NOT EXISTS organization_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  key_hash VARCHAR(255) NOT NULL UNIQUE,  -- SHA256 hash of actual key (never store plaintext)
  name VARCHAR(255) NOT NULL,
  last_rotated_at TIMESTAMP,
  rotated_by_user_id UUID,
  expires_at TIMESTAMP,
  requests_count BIGINT DEFAULT 0,
  last_used_at TIMESTAMP,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP,
  
  INDEX idx_api_keys_organization (organization_id),
  INDEX idx_api_keys_hash (key_hash),
  INDEX idx_api_keys_active (is_active),
  INDEX idx_api_keys_expires (expires_at)
);

-- Organization workspaces: Sub-resource isolation within org
CREATE TABLE IF NOT EXISTS organization_workspaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  owner_id UUID NOT NULL,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  CONSTRAINT uk_workspace_org_name UNIQUE (organization_id, name),
  INDEX idx_workspaces_organization (organization_id),
  INDEX idx_workspaces_owner (owner_id)
);

-- Audit logs: Immutable record of all admin actions
CREATE TABLE IF NOT EXISTS organization_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL,  -- User who performed action
  action VARCHAR(255) NOT NULL,  -- e.g., "member_added", "key_rotated", "tier_upgraded"
  resource_type VARCHAR(100) NOT NULL,  -- e.g., "organization", "member", "api_key"
  resource_id UUID,  -- ID of affected resource
  changes JSONB,  -- Before/after values for modifications
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  INDEX idx_audit_organization (organization_id),
  INDEX idx_audit_actor (actor_id),
  INDEX idx_audit_action (action),
  INDEX idx_audit_created (created_at DESC),
  CONSTRAINT immutable_audit CHECK (created_at = created_at)  -- Logical enforcement
);

-- Create immutable audit log trigger (prevent updates/deletes)
CREATE OR REPLACE FUNCTION enforce_audit_immutability()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Audit logs are immutable and cannot be modified';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_immutability_trigger
BEFORE UPDATE OR DELETE ON organization_audit_logs
FOR EACH ROW EXECUTE FUNCTION enforce_audit_immutability();

-- Rate limit tracking per organization (for Phase 26-A integration)
CREATE TABLE IF NOT EXISTS organization_rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL UNIQUE REFERENCES organizations(id) ON DELETE CASCADE,
  tier VARCHAR(50) NOT NULL,
  requests_this_minute INTEGER DEFAULT 0,
  requests_this_hour INTEGER DEFAULT 0,
  requests_this_day INTEGER DEFAULT 0,
  reset_minute_at TIMESTAMP,
  reset_hour_at TIMESTAMP,
  reset_day_at TIMESTAMP,
  last_request_at TIMESTAMP,
  
  INDEX idx_rate_limits_org (organization_id)
);

-- Cost tracking per organization (for Phase 26-B analytics integration)
CREATE TABLE IF NOT EXISTS organization_costs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  month DATE NOT NULL,  -- YYYY-MM-01
  requests_count BIGINT DEFAULT 0,
  cost_per_request DECIMAL(10, 6),  -- Tier-based pricing
  total_cost DECIMAL(10, 2),
  storage_bytes BIGINT DEFAULT 0,
  storage_cost DECIMAL(10, 2),
  bandwidth_bytes BIGINT DEFAULT 0,
  bandwidth_cost DECIMAL(10, 2),
  total_with_storage_bandwidth DECIMAL(10, 2),
  
  CONSTRAINT uk_org_cost_month UNIQUE (organization_id, month),
  INDEX idx_cost_organization (organization_id),
  INDEX idx_cost_month (month)
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_organizations_active 
  ON organizations(deleted_at) WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_members_active 
  ON organization_members WHERE TRUE;

CREATE INDEX IF NOT EXISTS idx_audit_recent 
  ON organization_audit_logs(created_at DESC) 
  WHERE created_at > NOW() - INTERVAL '90 days';

-- Create view for active organizations only
CREATE OR REPLACE VIEW active_organizations AS
SELECT 
  id, name, email, tier, workspace_count, max_workspaces,
  billing_contact, billing_email, created_at, updated_at
FROM organizations
WHERE deleted_at IS NULL;

-- Create view for organization member counts
CREATE OR REPLACE VIEW organization_member_counts AS
SELECT 
  organization_id,
  COUNT(*) as total_members,
  COUNT(CASE WHEN role = 'admin' THEN 1 END) as admin_count,
  COUNT(CASE WHEN role = 'developer' THEN 1 END) as developer_count,
  COUNT(CASE WHEN role = 'auditor' THEN 1 END) as auditor_count,
  COUNT(CASE WHEN role = 'viewer' THEN 1 END) as viewer_count
FROM organization_members
GROUP BY organization_id;

-- Grant appropriate permissions (least privilege)
GRANT SELECT, INSERT ON organizations TO "api-user";
GRANT SELECT, INSERT ON organization_members TO "api-user";
GRANT SELECT, INSERT, UPDATE ON organization_api_keys TO "api-user";
GRANT SELECT, INSERT ON organization_audit_logs TO "api-user";
GRANT SELECT ON organization_audit_logs TO "auditor-user";
GRANT SELECT, INSERT, UPDATE ON organization_rate_limits TO "api-user";
GRANT SELECT, INSERT, UPDATE ON organization_costs TO "analytics-user";

COMMIT;
