-- Appsmith Portal Database Initialization - Phase 1 Implementation
-- Implements: docs/ADR-PORTAL-ARCHITECTURE.md
-- Status: PRODUCTION - Ready for deployment
-- Date: April 16, 2026

-- Create appsmith database user
CREATE USER appsmith WITH ENCRYPTED PASSWORD :'APPSMITH_DB_PASSWORD';

-- Create appsmith database
CREATE DATABASE appsmith OWNER appsmith;

-- Grant permissions
ALTER USER appsmith CREATEDB;

-- Connect to appsmith database for schema setup
\c appsmith

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant schema permissions
GRANT ALL PRIVILEGES ON SCHEMA public TO appsmith;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO appsmith;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO appsmith;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO appsmith;

-- Create initial appsmith schema (Appsmith auto-creates tables on first run)
-- These tables are created by Appsmith application startup, but we pre-allocate space

-- Workspaces table (auto-created by Appsmith)
-- Metadata for portal workspaces (team-level organization)

-- Applications table (auto-created by Appsmith)
-- Portal applications (service catalog, dashboards, etc.)

-- Pages table (auto-created by Appsmith)
-- Application pages (service detail, runbook, etc.)

-- Widgets table (auto-created by Appsmith)
-- UI components (buttons, tables, forms, etc.)

-- Actions table (auto-created by Appsmith)
-- Queries/API calls (PostgreSQL, REST, GraphQL)

-- Datasources table (auto-created by Appsmith)
-- Database connections (PostgreSQL, Redis, APIs)

-- Create indexes for common queries (will be duplicated by Appsmith, that's OK)
CREATE INDEX IF NOT EXISTS idx_workspaces_name ON public.workspace(name);
CREATE INDEX IF NOT EXISTS idx_applications_workspace_id ON public.application(workspace_id);
CREATE INDEX IF NOT EXISTS idx_pages_application_id ON public.page(application_id);

-- Backup configuration table
CREATE TABLE IF NOT EXISTS appsmith_backups (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    backup_type VARCHAR(50) NOT NULL,
    backup_path VARCHAR(512) NOT NULL,
    size_bytes BIGINT,
    status VARCHAR(20) NOT NULL,
    description TEXT
);

-- Portal configuration table
CREATE TABLE IF NOT EXISTS portal_config (
    id SERIAL PRIMARY KEY,
    config_key VARCHAR(100) UNIQUE NOT NULL,
    config_value TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_config CHECK (
        config_key IN (
            'service_catalog_refresh_interval',
            'dashboard_auto_refresh',
            'documentation_repo_url',
            'team_directory_sync',
            'runbook_notification_enabled',
            'status_page_public',
            'max_api_connections',
            'session_timeout_minutes'
        )
    )
);

-- Service catalog table (for internal metadata)
CREATE TABLE IF NOT EXISTS service_catalog (
    id SERIAL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    owner_team VARCHAR(100),
    contact_email VARCHAR(255),
    repository_url VARCHAR(512),
    documentation_url VARCHAR(512),
    health_check_url VARCHAR(512),
    tags TEXT[], -- JSON array: ['api', 'database', 'monitoring']
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for service catalog
CREATE INDEX IF NOT EXISTS idx_service_catalog_name ON service_catalog(service_name);
CREATE INDEX IF NOT EXISTS idx_service_catalog_owner ON service_catalog(owner_team);
CREATE INDEX IF NOT EXISTS idx_service_catalog_tags ON service_catalog USING GIN(tags);

-- Portal audit log table
CREATE TABLE IF NOT EXISTS portal_audit_log (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(255),
    changes JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for audit log
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON portal_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON portal_audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON portal_audit_log(created_at DESC);

-- Grant all permissions to appsmith user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appsmith;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO appsmith;

-- Set default permissions for future tables
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON TABLES TO appsmith;
ALTER DEFAULT PRIVILEGES FOR USER postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO appsmith;

-- Create roles for RBAC (tied to oauth2-proxy groups)
CREATE ROLE appsmith_admin IN ROLE appsmith;
CREATE ROLE appsmith_editor IN ROLE appsmith;
CREATE ROLE appsmith_viewer IN ROLE appsmith;

-- Insert default portal configuration
INSERT INTO portal_config (config_key, config_value) VALUES
    ('service_catalog_refresh_interval', '3600'),
    ('dashboard_auto_refresh', '30'),
    ('documentation_repo_url', 'https://internal.example.com/docs'),
    ('team_directory_sync', 'true'),
    ('runbook_notification_enabled', 'true'),
    ('status_page_public', 'false'),
    ('max_api_connections', '100'),
    ('session_timeout_minutes', '480')
ON CONFLICT (config_key) DO NOTHING;

-- Insert initial service catalog (seed data)
INSERT INTO service_catalog (service_name, description, owner_team, contact_email, repository_url, documentation_url, health_check_url, tags, metadata) VALUES
    ('code-server', 'Web-based IDE and development environment', 'Platform', 'platform@internal.example.com', 'https://github.com/kushin77/code-server', 'https://internal.example.com/docs/code-server', 'http://192.168.168.31:8080/health', ARRAY['dev-env', 'web-ide', 'cloud']::text[], jsonb_build_object('version', '4.115.0', 'repo_type', 'github', 'language', 'TypeScript')),
    ('postgresql', 'Primary relational database', 'Data Platform', 'dba@internal.example.com', null, 'https://www.postgresql.org/docs/', 'http://192.168.168.31:5432/', ARRAY['database', 'sql', 'infrastructure']::text[], jsonb_build_object('version', '15', 'replication', 'streaming', 'backup', 'daily')),
    ('redis', 'In-memory cache and session store', 'Platform', 'platform@internal.example.com', null, 'https://redis.io/documentation', 'http://192.168.168.31:6379/', ARRAY['cache', 'session', 'real-time']::text[], jsonb_build_object('version', '7', 'cluster', 'false', 'persistence', 'rdb')),
    ('prometheus', 'Metrics collection and alerting', 'Observability', 'observability@internal.example.com', null, 'https://prometheus.io/docs/', 'http://192.168.168.31:9090/-/healthy', ARRAY['monitoring', 'metrics', 'alerting']::text[], jsonb_build_object('version', '2.48.0', 'retention', '15d', 'scrape_interval', '15s')),
    ('grafana', 'Visualization and dashboarding', 'Observability', 'observability@internal.example.com', null, 'https://grafana.com/docs/', 'http://192.168.168.31:3000/api/health', ARRAY['monitoring', 'visualization', 'dashboards']::text[], jsonb_build_object('version', '10.2.3', 'auth', 'oauth2', 'plugins', '5')),
    ('loki', 'Log aggregation and analysis', 'Observability', 'observability@internal.example.com', null, 'https://grafana.com/docs/loki/', 'http://192.168.168.31:3100/ready', ARRAY['logging', 'aggregation', 'observability']::text[], jsonb_build_object('version', '2.9.4', 'retention', '504h', 'index_period', '24h')),
    ('oauth2-proxy', 'OAuth2/OIDC authentication gateway', 'Security', 'security@internal.example.com', null, 'https://oauth2-proxy.github.io/', 'http://192.168.168.31:4180/ping', ARRAY['auth', 'security', 'gateway']::text[], jsonb_build_object('version', '7.5.1', 'provider', 'oidc', 'cookie_ttl', '12h'))
ON CONFLICT (service_name) DO NOTHING;

-- Verify database initialization
SELECT
    datname as database,
    usename as owner,
    datacl as permissions
FROM pg_database
LEFT JOIN pg_user ON pg_database.datdba = pg_user.usesysid
WHERE datname = 'appsmith';

GRANT CONNECT ON DATABASE appsmith TO appsmith;

-- Final verification
\dt+ -- Show all tables
\di+ -- Show all indexes
\du+ -- Show all users/roles
