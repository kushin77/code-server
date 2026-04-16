-- ═══════════════════════════════════════════════════════════════════════════════
-- Database Index Initialization Script
-- Purpose: Create all necessary indexes for production performance
-- Usage: sqlite3 audit_events.db < scripts/init-database-indexes.sql
-- Status: Production-ready schema optimization
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Primary Key & ROWID Indexes ──────────────────────────────────────────────

-- Ensure audit_events table uses explicit ROWID (for faster lookups)
CREATE INDEX IF NOT EXISTS ix_audit_events_rowid 
  ON audit_events(ROWID);

-- ─── Timestamp Indexes (Critical for time-range queries) ──────────────────────

-- Primary timestamp index (most common query pattern)
CREATE INDEX IF NOT EXISTS ix_audit_timestamp_desc 
  ON audit_events(timestamp DESC);

-- Timestamp with status composite index
CREATE INDEX IF NOT EXISTS ix_audit_timestamp_status 
  ON audit_events(timestamp DESC, status);

-- ─── Developer/User Indexes ───────────────────────────────────────────────────

-- Developer ID index (for user-specific queries)  
CREATE INDEX IF NOT EXISTS ix_audit_developer_id
  ON audit_events(developer_id);

-- Composite: developer + timestamp (frequent pattern)
CREATE INDEX IF NOT EXISTS ix_audit_developer_timestamp
  ON audit_events(developer_id, timestamp DESC);

-- ─── Event Type Indexes ─────────────────────────────────────────────────────

-- Event type index
CREATE INDEX IF NOT EXISTS ix_audit_event_type
  ON audit_events(event_type);

-- Composite: event_type + timestamp
CREATE INDEX IF NOT EXISTS ix_audit_event_type_timestamp
  ON audit_events(event_type, timestamp DESC);

-- ─── Status/Compliance Indexes ────────────────────────────────────────────────

-- Status index (for compliance reports)
CREATE INDEX IF NOT EXISTS ix_audit_status
  ON audit_events(status);

-- Composite: status filter + timestamp
CREATE INDEX IF NOT EXISTS ix_audit_status_timestamp
  ON audit_events(status, timestamp DESC);

-- ─── Filtering Combinations (High-frequency query patterns) ──────────────────

-- Developer + Event type + Timestamp (common filter combination)
CREATE INDEX IF NOT EXISTS ix_audit_dev_type_time
  ON audit_events(developer_id, event_type, timestamp DESC);

-- Developer + Status + Timestamp (compliance queries)
CREATE INDEX IF NOT EXISTS ix_audit_dev_status_time
  ON audit_events(developer_id, status, timestamp DESC);

-- ─── Verify Index Creation ────────────────────────────────────────────────────

-- Display created indexes
.mode list
.headers on
SELECT 
  name as index_name,
  tbl_name as table_name,
  sql as definition
FROM sqlite_master
WHERE type = 'index' 
  AND tbl_name = 'audit_events'
ORDER BY name;

-- ─── Analyze for Query Optimization ───────────────────────────────────────────

ANALYZE;
