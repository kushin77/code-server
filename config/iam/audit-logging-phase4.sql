-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 4: Audit Logging — Immutable RBAC + Auth Event Trail
-- Database: codeserver (matches docker-compose POSTGRES_DB)
-- User: codeserver (matches docker-compose POSTGRES_USER)
-- Idempotent: safe to run multiple times
-- ═══════════════════════════════════════════════════════════════════════════

-- Idempotent table creation (no DROP — preserves data on re-run)
CREATE TABLE IF NOT EXISTS audit_logs (
  id                  BIGSERIAL PRIMARY KEY,
  timestamp           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id             TEXT NOT NULL,
  user_email          TEXT,
  role                TEXT NOT NULL DEFAULT 'unknown',
  identity_type       TEXT NOT NULL DEFAULT 'human'
                        CHECK (identity_type IN ('human', 'workload', 'automation')),
  method              TEXT NOT NULL DEFAULT 'UNKNOWN',
  path                TEXT NOT NULL DEFAULT '/',
  action              TEXT NOT NULL CHECK (action IN ('allow', 'deny')),
  reason              TEXT,
  status_code         INTEGER,
  ip_address          INET,
  user_agent          TEXT,
  jwt_claims          JSONB,
  policy_applied      TEXT,
  evaluation_time_ms  NUMERIC,
  session_id          TEXT,
  trace_id            TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotent indexes
CREATE INDEX IF NOT EXISTS idx_audit_timestamp    ON audit_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user_id      ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_role         ON audit_logs(role);
CREATE INDEX IF NOT EXISTS idx_audit_action       ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_path         ON audit_logs(path);
CREATE INDEX IF NOT EXISTS idx_audit_identity     ON audit_logs(identity_type);
CREATE INDEX IF NOT EXISTS idx_audit_user_time    ON audit_logs(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_trace        ON audit_logs(trace_id) WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_session      ON audit_logs(session_id) WHERE session_id IS NOT NULL;

-- ── Views ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW audit_denials_last_hour AS
  SELECT
    user_id, role, identity_type, path, method, reason,
    COUNT(*) AS denial_count,
    MAX(timestamp) AS latest_denial
  FROM audit_logs
  WHERE action = 'deny'
    AND timestamp > NOW() - INTERVAL '1 hour'
  GROUP BY user_id, role, identity_type, path, method, reason
  ORDER BY denial_count DESC;

CREATE OR REPLACE VIEW audit_access_by_role_24h AS
  SELECT
    role,
    COUNT(*)                                                              AS total,
    COUNT(CASE WHEN action = 'allow' THEN 1 END)                         AS allow_count,
    COUNT(CASE WHEN action = 'deny' THEN 1 END)                          AS deny_count,
    ROUND(100.0 * COUNT(CASE WHEN action = 'deny' THEN 1 END)
          / NULLIF(COUNT(*), 0), 2)                                       AS deny_pct
  FROM audit_logs
  WHERE timestamp > NOW() - INTERVAL '24 hours'
  GROUP BY role
  ORDER BY total DESC;

CREATE OR REPLACE VIEW audit_suspicious_activity AS
  SELECT
    user_id,
    ip_address,
    COUNT(*)                           AS total_denials,
    COUNT(DISTINCT path)               AS unique_paths_tried,
    MAX(timestamp)                     AS last_attempt
  FROM audit_logs
  WHERE action = 'deny'
    AND timestamp > NOW() - INTERVAL '15 minutes'
  GROUP BY user_id, ip_address
  HAVING COUNT(*) > 5
  ORDER BY total_denials DESC;

-- ── Retention table ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS audit_log_retention (
  id              SERIAL PRIMARY KEY,
  table_name      TEXT NOT NULL UNIQUE,
  retention_days  INTEGER NOT NULL DEFAULT 365,
  last_purge      TIMESTAMPTZ DEFAULT NOW(),
  next_purge      TIMESTAMPTZ DEFAULT NOW() + INTERVAL '1 day'
);

INSERT INTO audit_log_retention (table_name, retention_days)
VALUES ('audit_logs', 365)
ON CONFLICT (table_name) DO NOTHING;

-- ── Retention procedure ──────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE purge_old_audit_logs()
LANGUAGE plpgsql AS $$
DECLARE
  v_retention_days INTEGER;
  v_deleted        INTEGER;
BEGIN
  SELECT retention_days INTO v_retention_days
  FROM audit_log_retention
  WHERE table_name = 'audit_logs';

  DELETE FROM audit_logs
  WHERE timestamp < NOW() - (v_retention_days || ' days')::INTERVAL;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  UPDATE audit_log_retention
  SET last_purge = NOW(),
      next_purge = NOW() + INTERVAL '1 day'
  WHERE table_name = 'audit_logs';

  RAISE NOTICE 'audit_logs: purged % rows older than % days', v_deleted, v_retention_days;
END;
$$;

-- ── Seed test record (verify schema works) ───────────────────────────────────

INSERT INTO audit_logs (user_id, role, identity_type, method, path, action, reason, status_code)
VALUES ('system', 'admin', 'automation', 'POST', '/schema-init', 'allow', 'Phase 4 schema initialized', 200)
ON CONFLICT DO NOTHING;

SELECT 'Phase 4 audit schema installed successfully.' AS status,
       COUNT(*) AS total_records
FROM audit_logs;
