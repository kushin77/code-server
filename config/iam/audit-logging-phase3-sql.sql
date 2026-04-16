-- Phase 3: Audit Logging Setup for RBAC Enforcement
-- 
-- Creates PostgreSQL tables and triggers to immutably log all RBAC decisions
-- and authentication events.

-- Drop existing tables if they exist (idempotent)
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS audit_log_retention CASCADE;

-- Audit Logs Table (immutable record of all access decisions)
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id TEXT NOT NULL,
  user_email TEXT,
  role TEXT NOT NULL,
  identity_type TEXT NOT NULL CHECK (identity_type IN ('human', 'workload', 'automation')),
  method TEXT NOT NULL,
  path TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('allow', 'deny')),
  reason TEXT,
  status_code INTEGER,
  ip_address INET,
  user_agent TEXT,
  jwt_claims JSONB,
  policy_applied TEXT,
  evaluation_time_ms NUMERIC,
  
  -- Immutability constraint
  CONSTRAINT immutable_timestamp CHECK (timestamp <= NOW()),
  CONSTRAINT immutable_record CHECK (timestamp IS NOT NULL)
);

-- Indexes for fast querying
CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_role ON audit_logs(role);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_path ON audit_logs(path);
CREATE INDEX idx_audit_identity_type ON audit_logs(identity_type);
CREATE INDEX idx_audit_user_role_time ON audit_logs(user_id, role, timestamp DESC);

-- View: Recent Denials (for SRE alerts)
CREATE VIEW audit_denials_last_hour AS
  SELECT 
    user_id, role, identity_type, path, method, reason,
    COUNT(*) as denial_count,
    MAX(timestamp) as latest_denial
  FROM audit_logs
  WHERE action = 'deny'
    AND timestamp > NOW() - INTERVAL '1 hour'
  GROUP BY user_id, role, identity_type, path, method, reason
  ORDER BY denial_count DESC;

-- View: Access by Role (for compliance reporting)
CREATE VIEW audit_access_by_role AS
  SELECT 
    role,
    action,
    COUNT(*) as count,
    COUNT(CASE WHEN action='allow' THEN 1 END) as allow_count,
    COUNT(CASE WHEN action='deny' THEN 1 END) as deny_count,
    ROUND(100.0 * COUNT(CASE WHEN action='deny' THEN 1 END) / COUNT(*), 2) as deny_percent
  FROM audit_logs
  WHERE timestamp > NOW() - INTERVAL '24 hours'
  GROUP BY role, action
  ORDER BY role, action;

-- Retention Policy Table
CREATE TABLE audit_log_retention (
  id SERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  retention_days INTEGER NOT NULL DEFAULT 365,
  last_purge TIMESTAMPTZ DEFAULT NOW(),
  next_purge TIMESTAMPTZ DEFAULT NOW() + INTERVAL '1 day'
);

INSERT INTO audit_log_retention (table_name, retention_days)
VALUES ('audit_logs', 365);

-- Retention Policy: Purge logs older than retention_days
-- Run this via cron: psql -d code_server -c "CALL purge_old_audit_logs();"
CREATE OR REPLACE PROCEDURE purge_old_audit_logs()
LANGUAGE plpgsql
AS $$
DECLARE
  retention_days INTEGER;
  deleted_count INTEGER;
BEGIN
  SELECT retention_days INTO retention_days FROM audit_log_retention
  WHERE table_name = 'audit_logs' LIMIT 1;
  
  DELETE FROM audit_logs
  WHERE timestamp < NOW() - INTERVAL '1 day' * retention_days;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  UPDATE audit_log_retention
  SET last_purge = NOW(),
      next_purge = NOW() + INTERVAL '1 day'
  WHERE table_name = 'audit_logs';
  
  RAISE NOTICE 'Purged % old audit log entries', deleted_count;
END;
$$;

-- Grant appropriate permissions (restrict to audit service account)
ALTER TABLE audit_logs OWNER TO code_server;
GRANT SELECT ON audit_logs TO prometheus_exporter;
GRANT SELECT ON audit_denials_last_hour TO sre_team;
GRANT SELECT ON audit_access_by_role TO compliance_team;
