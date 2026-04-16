-- ═══════════════════════════════════════════════════════════════════════════════
-- PostgreSQL Index Initialization Script  
-- Purpose: Create all necessary indexes for production performance
-- Usage: psql -U codeserver -d codeserver -f scripts/init-database-postgres.sql
-- Status: Production-ready schema optimization
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Audit Events Indexes ─────────────────────────────────────────────────────

-- Primary lookup index on timestamp (DESC for recent events first)
CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp 
  ON audit_events(timestamp DESC);

-- Developer-specific audit queries
CREATE INDEX IF NOT EXISTS idx_audit_events_developer_id
  ON audit_events(developer_id);

-- Composite: developer + timestamp (very common pattern)
CREATE INDEX IF NOT EXISTS idx_audit_events_dev_timestamp
  ON audit_events(developer_id, timestamp DESC);

-- Event type filtering
CREATE INDEX IF NOT EXISTS idx_audit_events_event_type
  ON audit_events(event_type);

-- Status-based compliance queries
CREATE INDEX IF NOT EXISTS idx_audit_events_status
  ON audit_events(status);

-- High-frequency query combo: dev + type + timestamp
CREATE INDEX IF NOT EXISTS idx_audit_events_dev_type_timestamp
  ON audit_events(developer_id, event_type, timestamp DESC);

-- Compliance queries: dev + status + timestamp
CREATE INDEX IF NOT EXISTS idx_audit_events_dev_status_timestamp
  ON audit_events(developer_id, status, timestamp DESC);

-- ─── RBAC & User Indexes ──────────────────────────────────────────────────────

-- User lookup by email (common authentication pattern)
CREATE INDEX IF NOT EXISTS idx_users_email
  ON users(email COLLATE NOCASE);

-- User lookup by username
CREATE INDEX IF NOT EXISTS idx_users_username
  ON users(username COLLATE NOCASE);

-- Role assignment lookups
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id
  ON user_roles(user_id);

CREATE INDEX IF NOT EXISTS idx_user_roles_role_id
  ON user_roles(role_id);

-- Resource permission lookups
CREATE INDEX IF NOT EXISTS idx_resource_permissions_role_id
  ON resource_permissions(role_id);

CREATE INDEX IF NOT EXISTS idx_resource_permissions_resource
  ON resource_permissions(resource);

-- ─── Performance: Analyze and Reindex ──────────────────────────────────────────

-- Update query planner statistics
ANALYZE;

-- Display all created indexes
SELECT 
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename IN ('audit_events', 'users', 'user_roles', 'resource_permissions')
ORDER BY tablename, indexname;
