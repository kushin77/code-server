-- ─────────────────────────────────────────────────────────────────────────────
-- Phase 8 Post-HA: PostgreSQL Performance Tuning
-- Apply via: psql -U <user> -d <db> -f config/postgres/postgres-tuning.sql
-- Or via scripts/performance/apply-postgres-tuning.sh
-- ─────────────────────────────────────────────────────────────────────────────
-- Target: postgres:15-alpine on 192.168.168.31 (assume 4GB RAM, 4 vCPU)
-- Adjust shared_buffers/effective_cache_size for actual host RAM
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Memory settings ──────────────────────────────────────────────────────────
-- shared_buffers: 25% of total RAM (1GB for 4GB host)
ALTER SYSTEM SET shared_buffers = '256MB';

-- effective_cache_size: 75% of total RAM — planner hint, not an allocation
ALTER SYSTEM SET effective_cache_size = '768MB';

-- work_mem: per-sort / per-hash memory; 4MB × (max_connections / expected_concurrent)
ALTER SYSTEM SET work_mem = '16MB';

-- maintenance_work_mem: VACUUM, ANALYZE, CREATE INDEX
ALTER SYSTEM SET maintenance_work_mem = '128MB';

-- ── WAL / Checkpoint tuning ───────────────────────────────────────────────────
-- wal_buffers: 3% of shared_buffers (min 1MB, max 64MB)
ALTER SYSTEM SET wal_buffers = '8MB';

-- checkpoint_completion_target: spread checkpoint I/O over 90% of interval
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- max_wal_size: tolerate larger WAL files before forcing checkpoint (reduces I/O spikes)
ALTER SYSTEM SET max_wal_size = '2GB';

-- min_wal_size: keep this much WAL pre-allocated
ALTER SYSTEM SET min_wal_size = '256MB';

-- ── Query planner ────────────────────────────────────────────────────────────
-- random_page_cost: 1.1 for SSD/NVMe; 4.0 for spinning disk (default)
ALTER SYSTEM SET random_page_cost = 1.1;

-- effective_io_concurrency: parallel prefetch for bitmap scans (SSDs: 200)
ALTER SYSTEM SET effective_io_concurrency = 200;

-- ── Connection tuning ────────────────────────────────────────────────────────
-- max_connections: keep low; PgBouncer handles the fan-out
ALTER SYSTEM SET max_connections = 100;

-- ── Logging & observability ──────────────────────────────────────────────────
-- Enable slow query logging (queries > 500ms)
ALTER SYSTEM SET log_min_duration_statement = 500;

-- Log lock waits > 200ms
ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM SET deadlock_timeout = '200ms';

-- Log checkpoint activity
ALTER SYSTEM SET log_checkpoints = on;

-- ── pg_stat_statements (query profiling) ─────────────────────────────────────
-- Requires: shared_preload_libraries='pg_stat_statements' in postgresql.conf
-- Then: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET pg_stat_statements.max = 5000;
ALTER SYSTEM SET pg_stat_statements.track_utility = off;

-- ── Auto-vacuum tuning ───────────────────────────────────────────────────────
-- More aggressive autovacuum to keep table bloat low
ALTER SYSTEM SET autovacuum_vacuum_cost_delay = '2ms';
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.05;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.02;

-- ── Apply settings (requires superuser + pg reload) ──────────────────────────
SELECT pg_reload_conf();

-- ── Verify settings applied ──────────────────────────────────────────────────
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
  'shared_buffers', 'effective_cache_size', 'work_mem',
  'maintenance_work_mem', 'wal_buffers', 'checkpoint_completion_target',
  'max_wal_size', 'random_page_cost', 'effective_io_concurrency',
  'max_connections', 'log_min_duration_statement',
  'shared_preload_libraries', 'autovacuum_vacuum_scale_factor'
)
ORDER BY name;

-- ── Install pg_stat_statements extension (run once per DB) ───────────────────
-- Uncomment on first run after adding shared_preload_libraries + pg restart:
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
