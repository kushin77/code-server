-- postgres-init.sql — Enterprise PostgreSQL Initialization
-- Creates schemas, roles, and audit infrastructure for production

-- ════════════════════════════════════════════════════════════
-- AUDIT LOG TABLE (for compliance)
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.audit_log (
    audit_id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id TEXT,
    action TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
    user_name TEXT,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    query_text TEXT,
    INDEX idx_audit_table_time (table_name, timestamp DESC),
    INDEX idx_audit_user_time (user_name, timestamp DESC),
    INDEX idx_audit_action (action)
);

-- Audit retention policy: 2 years (GDPR compliant)
CREATE POLICY "audit_retention" ON audit.audit_log
    USING (timestamp > NOW() - INTERVAL '2 years');

-- ════════════════════════════════════════════════════════════
-- SESSION MANAGEMENT TABLE
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS sessions;

CREATE TABLE IF NOT EXISTS sessions.oauth_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_email TEXT NOT NULL,
    user_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_activity TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    ip_address INET,
    user_agent TEXT,
    mfa_verified BOOLEAN DEFAULT FALSE,
    session_data JSONB,
    INDEX idx_sessions_user_email (user_email),
    INDEX idx_sessions_expires (expires_at DESC)
);

-- ════════════════════════════════════════════════════════════
-- CONFIGURATION & PREFERENCES
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS config;

CREATE TABLE IF NOT EXISTS config.user_preferences (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    dark_mode BOOLEAN DEFAULT TRUE,
    theme TEXT DEFAULT 'dracula',
    editor_font_size INT DEFAULT 14,
    editor_line_height FLOAT DEFAULT 1.6,
    extensions_enabled JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    INDEX idx_user_email (email)
);

CREATE TABLE IF NOT EXISTS config.system_settings (
    setting_key TEXT PRIMARY KEY,
    setting_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by TEXT,
    notes TEXT
);

-- ════════════════════════════════════════════════════════════
-- WORKSPACE & PROJECT MANAGEMENT
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS workspace;

CREATE TABLE IF NOT EXISTS workspace.projects (
    project_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES config.user_preferences(user_id) ON DELETE CASCADE,
    project_name TEXT NOT NULL,
    description TEXT,
    language TEXT,
    visibility TEXT DEFAULT 'private',  -- private, shared, public
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_accessed TIMESTAMPTZ,
    INDEX idx_project_user_id (user_id),
    INDEX idx_project_visibility (visibility)
);

CREATE TABLE IF NOT EXISTS workspace.file_cache (
    file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES workspace.projects(project_id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    file_content BYTEA,
    file_size INT,
    last_modified TIMESTAMPTZ DEFAULT NOW(),
    hash TEXT,  -- SHA256 for deduplication
    UNIQUE(project_id, file_path),
    INDEX idx_file_project (project_id),
    INDEX idx_file_hash (hash)
);

-- ════════════════════════════════════════════════════════════
-- PERMISSIONS & RBAC
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS rbac;

CREATE TABLE IF NOT EXISTS rbac.roles (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rbac.permissions (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_name TEXT UNIQUE NOT NULL,
    resource TEXT NOT NULL,
    action TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rbac.role_permissions (
    role_id UUID NOT NULL REFERENCES rbac.roles(role_id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES rbac.permissions(permission_id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ════════════════════════════════════════════════════════════
-- MONITORING & HEALTH
-- ════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS monitoring;

CREATE TABLE IF NOT EXISTS monitoring.service_health (
    health_id BIGSERIAL PRIMARY KEY,
    service_name TEXT NOT NULL,
    status TEXT NOT NULL,  -- healthy, degraded, unhealthy
    last_check TIMESTAMPTZ DEFAULT NOW(),
    response_time_ms INT,
    error_message TEXT,
    INDEX idx_health_service_time (service_name, last_check DESC)
);

CREATE TABLE IF NOT EXISTS monitoring.performance_metrics (
    metric_id BIGSERIAL PRIMARY KEY,
    metric_name TEXT NOT NULL,
    metric_value FLOAT NOT NULL,
    tags JSONB,
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    INDEX idx_perf_metric_time (metric_name, recorded_at DESC)
);

-- ════════════════════════════════════════════════════════════
-- DATABASE USERS & SECURITY
-- ════════════════════════════════════════════════════════════

-- Application user (minimal permissions)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ide_app') THEN
        CREATE ROLE ide_app WITH LOGIN PASSWORD 'auto-generated-password';
    END IF;
END
$$;

-- Read-only user (for reporting)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ide_readonly') THEN
        CREATE ROLE ide_readonly WITH LOGIN PASSWORD 'auto-generated-password';
    END IF;
END
$$;

-- Audit user (for compliance)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ide_audit') THEN
        CREATE ROLE ide_audit WITH LOGIN PASSWORD 'auto-generated-password';
    END IF;
END
$$;

-- ════════════════════════════════════════════════════════════
-- GRANT PERMISSIONS
-- ════════════════════════════════════════════════════════════

-- Application user: read/write application tables
GRANT USAGE ON SCHEMA audit, sessions, config, workspace, rbac, monitoring TO ide_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA sessions, config, workspace TO ide_app;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA audit TO ide_app;

-- Read-only user: read-only access for reporting
GRANT USAGE ON SCHEMA sessions, config, workspace, monitoring TO ide_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA sessions, config, workspace, monitoring TO ide_readonly;

-- Audit user: read-only access to audit logs
GRANT USAGE ON SCHEMA audit TO ide_audit;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO ide_audit;

-- ════════════════════════════════════════════════════════════
-- DEFAULT ROLES & SETTINGS
-- ════════════════════════════════════════════════════════════

INSERT INTO rbac.roles (role_name, description) VALUES
    ('admin', 'Full system access'),
    ('user', 'Standard user access'),
    ('viewer', 'Read-only access'),
    ('guest', 'Limited guest access')
ON CONFLICT (role_name) DO NOTHING;

INSERT INTO rbac.permissions (permission_name, resource, action, description) VALUES
    ('view_dashboard', 'dashboard', 'read', 'View dashboard'),
    ('edit_code', 'editor', 'write', 'Edit code files'),
    ('run_terminal', 'terminal', 'execute', 'Run terminal commands'),
    ('view_logs', 'logs', 'read', 'View application logs'),
    ('manage_users', 'users', 'admin', 'Manage user accounts'),
    ('manage_settings', 'settings', 'admin', 'Modify system settings')
ON CONFLICT (permission_name) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- INITIAL SYSTEM SETTINGS
-- ════════════════════════════════════════════════════════════

INSERT INTO config.system_settings (setting_key, setting_value, notes) VALUES
    ('max_sessions_per_user', '{"value": 5}', 'Maximum concurrent sessions'),
    ('session_timeout', '{"minutes": 1440}', 'Session timeout in minutes (24h)'),
    ('password_policy', '{"min_length": 12, "require_numbers": true, "require_symbols": true}', 'Password requirements'),
    ('mfa_required', '{"enabled": true, "grace_period_days": 7}', 'MFA enforcement'),
    ('audit_retention_days', '{"value": 730}', 'Audit log retention (2 years)'),
    ('backup_schedule', '{"frequency": "hourly", "retention_days": 30}', 'Backup configuration'),
    ('rate_limit', '{"requests_per_minute": 1000}', 'API rate limiting')
ON CONFLICT (setting_key) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- INDEXES FOR PERFORMANCE
-- ════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_sessions_expires_cleanup ON sessions.oauth_sessions(expires_at) WHERE expires_at < NOW();
CREATE INDEX IF NOT EXISTS idx_projects_updated ON workspace.projects(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_projects_accessed ON workspace.projects(last_accessed DESC);

-- ════════════════════════════════════════════════════════════
-- VACUUM & ANALYZE SCHEDULE
-- ════════════════════════════════════════════════════════════

-- Note: Configure in postgresql.conf or via ALTER TABLE:
-- ALTER TABLE audit.audit_log SET (autovacuum_vacuum_scale_factor = 0.01);
-- ALTER TABLE sessions.oauth_sessions SET (autovacuum_vacuum_scale_factor = 0.01);

VACUUM ANALYZE;

-- ════════════════════════════════════════════════════════════
-- VERIFY INSTALLATION
-- ════════════════════════════════════════════════════════════

SELECT 'PostgreSQL Enterprise Setup Complete' as status,
       current_database() as database,
       current_user as user,
       NOW() as timestamp;

