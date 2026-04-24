-- @file        migrations/002_custom_domains_schema.sql
-- @module      saas/custom-domains
-- @description Custom domain management schema for Whitelabel support (Phase 4 #1674)
-- IaC: Idempotent, Immutable, Infrastructure as Code
-- Safe to run multiple times - only creates objects if they don't exist

-- ════════════════════════════════════════════════════════════════════════════
-- Custom Domains Table
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS custom_domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  domain_name VARCHAR(255) NOT NULL,
  verification_token VARCHAR(255) NOT NULL,
  verification_token_created_at TIMESTAMP DEFAULT NOW(),
  is_verified BOOLEAN DEFAULT false,
  verified_at TIMESTAMP,
  dns_txt_record VARCHAR(1024),
  tls_cert_path VARCHAR(500),
  tls_cert_expiry TIMESTAMP,
  acme_order_id VARCHAR(255),
  acme_challenge_id VARCHAR(255),
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'verifying', 'verified', 'issuing', 'active', 'expired', 'failed', 'revoked')),
  error_message TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP,
  CONSTRAINT domain_format CHECK (domain_name ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$'),
  CONSTRAINT domain_length CHECK (char_length(domain_name) >= 4 AND char_length(domain_name) <= 255),
  CONSTRAINT unique_active_domains UNIQUE (org_id, domain_name) WHERE deleted_at IS NULL
);

-- ════════════════════════════════════════════════════════════════════════════
-- Indexes for Query Performance
-- ════════════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_custom_domains_org_id ON custom_domains(org_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_custom_domains_status ON custom_domains(status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_custom_domains_verified ON custom_domains(is_verified, deleted_at);
CREATE INDEX IF NOT EXISTS idx_custom_domains_verification_token ON custom_domains(verification_token) WHERE is_verified = false AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_custom_domains_tls_expiry ON custom_domains(tls_cert_expiry) WHERE status = 'active' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_custom_domains_created_at ON custom_domains(created_at DESC);

-- ════════════════════════════════════════════════════════════════════════════
-- Domain Verification Events Table (Audit Trail)
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS domain_verification_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES custom_domains(id) ON DELETE CASCADE,
  event_type VARCHAR(100) NOT NULL CHECK (event_type IN ('token_generated', 'dns_verified', 'verification_failed', 'tls_provisioned', 'tls_renewal', 'tls_revoked', 'routing_activated')),
  event_data JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_domain_verification_events_domain_id ON domain_verification_events(domain_id);
CREATE INDEX IF NOT EXISTS idx_domain_verification_events_type ON domain_verification_events(event_type);
CREATE INDEX IF NOT EXISTS idx_domain_verification_events_created_at ON domain_verification_events(created_at DESC);

-- ════════════════════════════════════════════════════════════════════════════
-- Custom Domain Routing Table
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS custom_domain_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_id UUID NOT NULL REFERENCES custom_domains(id) ON DELETE CASCADE,
  target_service VARCHAR(100) NOT NULL,
  target_path VARCHAR(500),
  route_type VARCHAR(50) DEFAULT 'portal' CHECK (route_type IN ('portal', 'api', 'static', 'webhook')),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_custom_domain_routes_domain_id ON custom_domain_routes(domain_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_custom_domain_routes_service ON custom_domain_routes(target_service, is_active);

-- ════════════════════════════════════════════════════════════════════════════
-- Trigger: Auto-update updated_at on custom_domains
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_custom_domains_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_custom_domains_updated_at ON custom_domains;
CREATE TRIGGER trg_custom_domains_updated_at
  BEFORE UPDATE ON custom_domains
  FOR EACH ROW
  EXECUTE FUNCTION update_custom_domains_updated_at();

-- ════════════════════════════════════════════════════════════════════════════
-- Trigger: Log domain verification events
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION log_domain_verification_event()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_verified AND NOT OLD.is_verified THEN
    INSERT INTO domain_verification_events (domain_id, event_type, event_data)
    VALUES (NEW.id, 'dns_verified', jsonb_build_object('verified_at', NOW(), 'dns_txt', NEW.dns_txt_record));
  END IF;
  
  IF NEW.status = 'active' AND OLD.status != 'active' THEN
    INSERT INTO domain_verification_events (domain_id, event_type, event_data)
    VALUES (NEW.id, 'routing_activated', jsonb_build_object('activated_at', NOW()));
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_domain_verification_event ON custom_domains;
CREATE TRIGGER trg_log_domain_verification_event
  AFTER UPDATE ON custom_domains
  FOR EACH ROW
  EXECUTE FUNCTION log_domain_verification_event();

-- ════════════════════════════════════════════════════════════════════════════
-- Grant Permissions (IaC: Defined in code, not manual GRANT statements)
-- ════════════════════════════════════════════════════════════════════════════
GRANT SELECT, INSERT, UPDATE ON custom_domains TO codeserver;
GRANT SELECT, INSERT ON domain_verification_events TO codeserver;
GRANT SELECT, INSERT, UPDATE ON custom_domain_routes TO codeserver;

-- ════════════════════════════════════════════════════════════════════════════
-- Final Verification
-- ════════════════════════════════════════════════════════════════════════════
-- Confirm tables created
SELECT 
  schemaname,
  tablename,
  CASE WHEN schemaname = 'public' THEN '✅' ELSE '❌' END as status
FROM pg_tables
WHERE tablename IN ('custom_domains', 'domain_verification_events', 'custom_domain_routes')
ORDER BY tablename;
