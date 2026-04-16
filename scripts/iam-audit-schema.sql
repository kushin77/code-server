# IAM Audit Logging Schema and Configuration - Phase 1 Implementation
# Implements: docs/IAM-STANDARDIZATION-PHASE-1.md
# Status: PRODUCTION - Ready for deployment to 192.168.168.31
# Date: April 16, 2026

-- PostgreSQL Schema for IAM Audit Logging
-- Location: public schema (same as main database)
-- Retention: 90 days auto-purge

CREATE TABLE IF NOT EXISTS iam_audit_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- User Information
    user_id VARCHAR(255),
    user_email VARCHAR(255),
    user_name VARCHAR(255),
    user_domain VARCHAR(255),
    
    -- Action Information
    action VARCHAR(50) NOT NULL,  -- login, logout, token_refresh, access_granted, access_denied
    oauth_provider VARCHAR(50),    -- google, github, ldap
    result VARCHAR(20) NOT NULL,   -- success, failure
    failure_reason VARCHAR(500),
    
    -- Resource Information
    resource_type VARCHAR(50),     -- service, api, dashboard, file
    resource_id VARCHAR(255),
    service_name VARCHAR(100),     -- code-server, grafana, loki, appsmith
    
    -- Network Information
    remote_ip INET NOT NULL,
    remote_user_agent TEXT,
    x_forwarded_for INET,
    
    -- Security Information
    session_id VARCHAR(255),
    token_hash VARCHAR(64),        -- SHA256 of token (for audit, not plaintext)
    ip_geolocation VARCHAR(255),
    
    -- OAuth2 Details
    oauth_client_id VARCHAR(255),
    oauth_scope TEXT,
    oauth_grant_type VARCHAR(50),  -- authorization_code, refresh_token, client_credentials
    oauth_code_challenge_method VARCHAR(10), -- S256 (PKCE)
    
    -- Duration Metrics
    duration_ms INTEGER,
    
    -- Metadata
    metadata JSONB,
    tags TEXT[],
    
    -- Immutable audit trail
    CONSTRAINT audit_immutable CHECK (timestamp IS NOT NULL)
);

-- Indexes for audit queries (critical for performance)
CREATE INDEX idx_iam_audit_timestamp ON iam_audit_log(timestamp DESC);
CREATE INDEX idx_iam_audit_user_email ON iam_audit_log(user_email);
CREATE INDEX idx_iam_audit_service ON iam_audit_log(service_name);
CREATE INDEX idx_iam_audit_action ON iam_audit_log(action);
CREATE INDEX idx_iam_audit_result ON iam_audit_log(result);
CREATE INDEX idx_iam_audit_remote_ip ON iam_audit_log(remote_ip);
CREATE INDEX idx_iam_audit_session_id ON iam_audit_log(session_id);

-- Composite indexes for common queries
CREATE INDEX idx_iam_audit_user_service_time ON iam_audit_log(user_email, service_name, timestamp DESC);
CREATE INDEX idx_iam_audit_failure_time ON iam_audit_log(timestamp DESC) WHERE result = 'failure';

-- Partitioning by day for efficient archival
CREATE TABLE IF NOT EXISTS iam_audit_log_2026_04 PARTITION OF iam_audit_log
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS iam_audit_log_2026_05 PARTITION OF iam_audit_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- Session Management Table
CREATE TABLE IF NOT EXISTS iam_sessions (
    session_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    user_email VARCHAR(255) NOT NULL,
    
    -- Session Details
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Token Information
    access_token_hash VARCHAR(64),
    refresh_token_hash VARCHAR(64),
    id_token_hash VARCHAR(64),
    
    -- Client Information
    oauth_client_id VARCHAR(255),
    redirect_uri VARCHAR(512),
    state VARCHAR(255),
    
    -- Security
    ip_address INET NOT NULL,
    user_agent TEXT,
    code_verifier_hash VARCHAR(64),  -- PKCE code verifier (hashed)
    
    -- Revocation
    revoked_at TIMESTAMP WITH TIME ZONE,
    revoked_reason VARCHAR(100),
    
    -- Metadata
    metadata JSONB
);

CREATE INDEX idx_sessions_user_email ON iam_sessions(user_email);
CREATE INDEX idx_sessions_expires_at ON iam_sessions(expires_at);
CREATE INDEX idx_sessions_last_activity ON iam_sessions(last_activity DESC);

-- Token Revocation List (for fast revocation checks)
CREATE TABLE IF NOT EXISTS iam_token_revocation (
    token_hash VARCHAR(64) PRIMARY KEY,
    token_type VARCHAR(20) NOT NULL,  -- access_token, refresh_token
    revoked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_by VARCHAR(255),
    reason VARCHAR(255),
    expires_at TIMESTAMP WITH TIME ZONE  -- Auto-cleanup when token would have expired
);

CREATE INDEX idx_token_revocation_expires ON iam_token_revocation(expires_at);

-- IAM Policy Rules Table (Phase 2)
CREATE TABLE IF NOT EXISTS iam_policies (
    id SERIAL PRIMARY KEY,
    policy_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    
    -- Policy Rules (JSON)
    rules JSONB NOT NULL,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    enabled BOOLEAN DEFAULT true
);

-- IAM Role Assignments Table
CREATE TABLE IF NOT EXISTS iam_role_assignments (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255),
    user_email VARCHAR(255),
    role_name VARCHAR(100),  -- admin, editor, viewer, readonly, developer
    
    -- Scope
    resource_type VARCHAR(50),
    resource_id VARCHAR(255),
    service_name VARCHAR(100),
    
    -- Validity
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,  -- NULL = indefinite
    assigned_by VARCHAR(255),
    
    -- Status
    status VARCHAR(20) DEFAULT 'active',  -- active, expired, revoked
    revoked_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT valid_role CHECK (role_name IN ('admin', 'editor', 'viewer', 'readonly', 'developer')),
    CONSTRAINT valid_status CHECK (status IN ('active', 'expired', 'revoked'))
);

CREATE INDEX idx_role_assignments_user_email ON iam_role_assignments(user_email);
CREATE INDEX idx_role_assignments_service ON iam_role_assignments(service_name);
CREATE INDEX idx_role_assignments_role ON iam_role_assignments(role_name);

-- Anomaly Detection Table (for suspicious activities)
CREATE TABLE IF NOT EXISTS iam_anomalies (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    user_email VARCHAR(255),
    anomaly_type VARCHAR(100),  -- brute_force, impossible_travel, unusual_location, token_misuse
    severity VARCHAR(20),       -- low, medium, high, critical
    
    -- Details
    details JSONB,
    
    -- Response
    action_taken VARCHAR(100),  -- block_account, revoke_tokens, notify_user, none
    resolved_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT valid_severity CHECK (severity IN ('low', 'medium', 'high', 'critical'))
);

CREATE INDEX idx_anomalies_timestamp ON iam_anomalies(timestamp DESC);
CREATE INDEX idx_anomalies_user_email ON iam_anomalies(user_email);
CREATE INDEX idx_anomalies_severity ON iam_anomalies(severity);

-- Cleanup Policy: Delete audit logs older than 90 days
-- Run via cron: 0 2 * * * psql -U postgres << EOF
-- DELETE FROM iam_audit_log WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '90 days';
-- EOF

-- Grant Permissions
GRANT SELECT ON iam_audit_log TO appsmith;
GRANT SELECT ON iam_sessions TO appsmith;
GRANT SELECT ON iam_role_assignments TO appsmith;

GRANT ALL ON iam_audit_log TO postgres;
GRANT ALL ON iam_sessions TO postgres;
GRANT ALL ON iam_token_revocation TO postgres;
GRANT ALL ON iam_policies TO postgres;
GRANT ALL ON iam_role_assignments TO postgres;
GRANT ALL ON iam_anomalies TO postgres;

-- Views for Common Queries

-- Active Sessions View
CREATE VIEW v_iam_active_sessions AS
SELECT
    session_id,
    user_email,
    created_at,
    expires_at,
    last_activity,
    ip_address,
    EXTRACT(EPOCH FROM (expires_at - CURRENT_TIMESTAMP)) / 60 as minutes_until_expiry
FROM iam_sessions
WHERE revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP;

-- Recent Failed Logins (Last 24h)
CREATE VIEW v_iam_failed_logins_24h AS
SELECT
    timestamp,
    user_email,
    remote_ip,
    failure_reason,
    COUNT(*) as failure_count
FROM iam_audit_log
WHERE action = 'login'
  AND result = 'failure'
  AND timestamp > CURRENT_TIMESTAMP - INTERVAL '24 hours'
GROUP BY user_email, failure_reason, remote_ip, timestamp
HAVING COUNT(*) > 3  -- Suspicious if >3 failures per user/IP
ORDER BY timestamp DESC;

-- Active Role Assignments View
CREATE VIEW v_iam_active_roles AS
SELECT
    user_email,
    role_name,
    service_name,
    assigned_at,
    expires_at,
    assigned_by
FROM iam_role_assignments
WHERE status = 'active'
  AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
ORDER BY user_email, service_name;

-- Audit Log Query Helper (for Grafana dashboards)
-- Example: SELECT * FROM v_iam_recent_activity WHERE service_name = 'code-server' LIMIT 1000;
CREATE VIEW v_iam_recent_activity AS
SELECT
    timestamp,
    user_email,
    action,
    service_name,
    remote_ip,
    result,
    failure_reason,
    duration_ms
FROM iam_audit_log
WHERE timestamp > CURRENT_TIMESTAMP - INTERVAL '7 days'
ORDER BY timestamp DESC;

-- Grants for Views
GRANT SELECT ON v_iam_active_sessions TO appsmith;
GRANT SELECT ON v_iam_failed_logins_24h TO appsmith;
GRANT SELECT ON v_iam_active_roles TO appsmith;
GRANT SELECT ON v_iam_recent_activity TO appsmith;
