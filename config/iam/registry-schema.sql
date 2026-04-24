-- config/iam/registry-schema.sql
-- Idempotent database migration for Open VSIX Registry (Issue #1047)
-- Creates tables for extension metadata, versions, publishers, and audit logs
-- Safe to run multiple times (uses CREATE IF NOT EXISTS)

BEGIN;

-- Create registry schema
CREATE SCHEMA IF NOT EXISTS registry;

-- ── Publishers table ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.publishers (
  id SERIAL PRIMARY KEY,
  publisher_id VARCHAR(255) UNIQUE NOT NULL,
  display_name VARCHAR(512) NOT NULL,
  description TEXT,
  verified BOOLEAN DEFAULT false,
  verification_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_publishers_id ON registry.publishers(publisher_id);
CREATE INDEX IF NOT EXISTS idx_publishers_verified ON registry.publishers(verified);

-- ── Extensions table ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.extensions (
  id SERIAL PRIMARY KEY,
  publisher_id INTEGER NOT NULL REFERENCES registry.publishers(id) ON DELETE CASCADE,
  extension_id VARCHAR(255) NOT NULL,
  display_name VARCHAR(512) NOT NULL,
  description TEXT,
  icon_url TEXT,
  repository_url TEXT,
  license VARCHAR(50),
  homepage TEXT,
  tier VARCHAR(50) DEFAULT 'T3-Optional',
  blocklisted BOOLEAN DEFAULT false,
  blocklist_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(publisher_id, extension_id)
);

CREATE INDEX IF NOT EXISTS idx_extensions_publisher ON registry.extensions(publisher_id);
CREATE INDEX IF NOT EXISTS idx_extensions_id ON registry.extensions(extension_id);
CREATE INDEX IF NOT EXISTS idx_extensions_blocklisted ON registry.extensions(blocklisted);
CREATE INDEX IF NOT EXISTS idx_extensions_tier ON registry.extensions(tier);

-- ── Extension versions table ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.extension_versions (
  id SERIAL PRIMARY KEY,
  extension_id INTEGER NOT NULL REFERENCES registry.extensions(id) ON DELETE CASCADE,
  version VARCHAR(50) NOT NULL,
  release_notes TEXT,
  download_url TEXT NOT NULL,
  download_count INTEGER DEFAULT 0,
  file_size_bytes BIGINT,
  file_hash_sha256 VARCHAR(64),
  manifest JSONB,
  dependencies JSONB,
  engine_version VARCHAR(50),
  published_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(extension_id, version)
);

CREATE INDEX IF NOT EXISTS idx_extension_versions_extension ON registry.extension_versions(extension_id);
CREATE INDEX IF NOT EXISTS idx_extension_versions_published ON registry.extension_versions(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_extension_versions_hash ON registry.extension_versions(file_hash_sha256);

-- ── Installation logs table (audit trail) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.installation_logs (
  id SERIAL PRIMARY KEY,
  version_id INTEGER NOT NULL REFERENCES registry.extension_versions(id) ON DELETE CASCADE,
  user_id VARCHAR(255),
  session_id VARCHAR(255),
  install_status VARCHAR(50) NOT NULL,
  install_duration_ms INTEGER,
  error_message TEXT,
  user_agent TEXT,
  ip_address VARCHAR(45),
  installed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_installation_logs_version ON registry.installation_logs(version_id);
CREATE INDEX IF NOT EXISTS idx_installation_logs_user ON registry.installation_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_installation_logs_status ON registry.installation_logs(install_status);
CREATE INDEX IF NOT EXISTS idx_installation_logs_timestamp ON registry.installation_logs(installed_at DESC);

-- ── Blocklist entries table ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.blocklist_entries (
  id SERIAL PRIMARY KEY,
  pattern VARCHAR(512) NOT NULL UNIQUE,
  reason TEXT NOT NULL,
  severity VARCHAR(50) NOT NULL,
  cve VARCHAR(50),
  policy_violation VARCHAR(255),
  alternatives TEXT[],
  added_at TIMESTAMPTZ DEFAULT NOW(),
  removed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_blocklist_pattern ON registry.blocklist_entries(pattern);
CREATE INDEX IF NOT EXISTS idx_blocklist_severity ON registry.blocklist_entries(severity);
CREATE INDEX IF NOT EXISTS idx_blocklist_active ON registry.blocklist_entries(removed_at);

-- ── Registry health check table ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registry.health_checks (
  id SERIAL PRIMARY KEY,
  check_type VARCHAR(100) NOT NULL,
  status VARCHAR(50) NOT NULL,
  response_time_ms INTEGER,
  details JSONB,
  checked_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_health_checks_type ON registry.health_checks(check_type);
CREATE INDEX IF NOT EXISTS idx_health_checks_timestamp ON registry.health_checks(checked_at DESC);

-- ── Trigger for updated_at timestamps ────────────────────────────────────────
CREATE OR REPLACE FUNCTION registry.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_publishers_timestamp ON registry.publishers;
CREATE TRIGGER update_publishers_timestamp
BEFORE UPDATE ON registry.publishers
FOR EACH ROW
EXECUTE FUNCTION registry.update_timestamp();

DROP TRIGGER IF EXISTS update_extensions_timestamp ON registry.extensions;
CREATE TRIGGER update_extensions_timestamp
BEFORE UPDATE ON registry.extensions
FOR EACH ROW
EXECUTE FUNCTION registry.update_timestamp();

DROP TRIGGER IF EXISTS update_extension_versions_timestamp ON registry.extension_versions;
CREATE TRIGGER update_extension_versions_timestamp
BEFORE UPDATE ON registry.extension_versions
FOR EACH ROW
EXECUTE FUNCTION registry.update_timestamp();

COMMIT;
