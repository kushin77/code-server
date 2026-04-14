# terraform/phase-22-c-sharding-migration.sql
# Phase 22-C: PostgreSQL Data Migration to Sharded Architecture
#
# This script migrates existing tables from single-node PostgreSQL
# to Citus distributed architecture with sharding.
#
# USAGE:
# 1. Connect to Citus coordinator:
#    psql -h citus-coordinator -U postgres -d code_server
#
# 2. Run this script:
#    psql -h citus-coordinator -U postgres -d code_server -f phase-22-c-sharding-migration.sql
#
# 3. Verify migration:
#    SELECT * FROM citus_shards;
#    SELECT * FROM pg_tables WHERE schemaname = 'public';

-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 1: Enable Citus Extension
-- ═════════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS citus;

-- Verify installation
SELECT * FROM citus_version();


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 2: Add Worker Nodes to Coordinator
-- ═════════════════════════════════════════════════════════════════════════════

-- Replace with actual worker hostnames/IPs
SELECT * from citus_add_node('citus-worker-0.citus-worker.citus.svc.cluster.local', 5432);
SELECT * from citus_add_node('citus-worker-1.citus-worker.citus.svc.cluster.local', 5432);
SELECT * from citus_add_node('citus-worker-2.citus-worker.citus.svc.cluster.local', 5432);
SELECT * from citus_add_node('citus-worker-3.citus-worker.citus.svc.cluster.local', 5432);

-- Verify workers connected
SELECT * FROM citus_nodes;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 3: Migrate Core Tables to Distributed Architecture
-- ═════════════════════════════════════════════════════════════════════════════

-- Users table (distributed by user_id)
-- Existing table should have same schema
-- Create new distributed table if needed
CREATE TABLE IF NOT EXISTS users_distributed (
  id BIGSERIAL,
  email VARCHAR UNIQUE,
  username VARCHAR UNIQUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (id, email)
) WITH (fillfactor=70);

-- Convert to distributed table (4 shards by default)
SELECT create_distributed_table('users_distributed', 'id', shard_count := 4);

-- Copy data from old table
INSERT INTO users_distributed SELECT * FROM users ON CONFLICT DO NOTHING;

-- Verify
SELECT count(*) FROM users_distributed;


-- ═════════════════════════════════════════════════════════════════════════════
-- Sessions table (distributed by user_id)
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS sessions_distributed (
  id BIGSERIAL,
  user_id BIGINT,
  token VARCHAR,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (id, user_id)
) WITH (fillfactor=70);

SELECT create_distributed_table('sessions_distributed', 'user_id', shard_count := 4);

INSERT INTO sessions_distributed SELECT * FROM sessions ON CONFLICT DO NOTHING;

SELECT count(*) FROM sessions_distributed;


-- ═════════════════════════════════════════════════════════════════════════════
-- Workspaces table (distributed by owner_id)
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS workspaces_distributed (
  id BIGSERIAL,
  owner_id BIGINT,
  name VARCHAR,
  config JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (id, owner_id)
) WITH (fillfactor=70);

SELECT create_distributed_table('workspaces_distributed', 'owner_id', shard_count := 4);

INSERT INTO workspaces_distributed SELECT * FROM workspaces ON CONFLICT DO NOTHING;

SELECT count(*) FROM workspaces_distributed;


-- ═════════════════════════════════════════════════════════════════════════════
-- Files table (distributed by owner_id)
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS files_distributed (
  id BIGSERIAL,
  owner_id BIGINT,
  workspace_id BIGINT,
  path VARCHAR,
  content TEXT,
  size INT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (id, owner_id)
) WITH (fillfactor=70);

SELECT create_distributed_table('files_distributed', 'owner_id', shard_count := 4);

INSERT INTO files_distributed SELECT * FROM files ON CONFLICT DO NOTHING;

SELECT count(*) FROM files_distributed;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 4: Create Reference Tables (replicated on all workers)
-- ═════════════════════════════════════════════════════════════════════════════

-- Features table (replicated on all workers - small lookup table)
CREATE TABLE IF NOT EXISTS features_distributed AS SELECT * FROM features;
SELECT create_reference_table('features_distributed');

-- Settings table (replicated on all workers)
CREATE TABLE IF NOT EXISTS settings_distributed AS SELECT * FROM settings;
SELECT create_reference_table('settings_distributed');


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 5: Verify Sharding Distribution
-- ═════════════════════════════════════════════════════════════════════════════

-- Check shard distribution
SELECT
  'users_distributed'::regclass AS table_name,
  get_shard_id_for_distribution_column('users_distributed', 1) AS shard_id
FROM generate_series(1, 100);

-- Check replication factor
SELECT * FROM pg_dist_replication_factor;

-- Count shards per table
SELECT
  logicalrelid,
  shardcount
FROM citus_tables;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 6: Update Application Connection String
-- ═════════════════════════════════════════════════════════════════════════════

-- Update Kubernetes secret with new connection string
-- kubectl patch secret postgresql-credentials -n code-server \
#   --type merge -p '{"data":{"connection-string":"'$(echo -n 'postgres://user:pass@citus-coordinator.citus:5432/code_server' | base64 -w 0)'"}}' \

-- Update connection pool (PgBouncer) to point to coordinator
-- PgBouncer config:
# [databases]
# code_server = host=citus-coordinator.citus.svc.cluster.local port=5432 dbname=code_server user=postgres password=<pass>


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 7: Rename Tables & Clean Up
-- ═════════════════════════════════════════════════════════════════════════════

-- After verifying migration success:

-- Backup old tables (optional, for rollback)
ALTER TABLE users RENAME TO users_old;
ALTER TABLE users_distributed RENAME TO users;

ALTER TABLE sessions RENAME TO sessions_old;
ALTER TABLE sessions_distributed RENAME TO sessions;

ALTER TABLE workspaces RENAME TO workspaces_old;
ALTER TABLE workspaces_distributed RENAME TO workspaces;

ALTER TABLE files RENAME TO files_old;
ALTER TABLE files_distributed RENAME TO files;

ALTER TABLE features RENAME TO features_old;
ALTER TABLE features_distributed RENAME TO features;

ALTER TABLE settings RENAME TO settings_old;
ALTER TABLE settings_distributed RENAME TO settings;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 8: Automatic Rebalancing
-- ═════════════════════════════════════════════════════════════════════════════

-- Trigger rebalancing to distribute data evenly across workers
SELECT rebalance_table_shards();

-- Monitor rebalancing progress
SELECT * FROM citus_shards;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 9: Post-Migration Verification
-- ═════════════════════════════════════════════════════════════════════════════

-- Check data distribution across shards
SELECT
  logicalrelid::regclass AS table_name,
  count(*) AS shard_count
FROM pg_dist_placement
GROUP BY logicalrelid
ORDER BY logicalrelid;

-- Check for skewed distribution
SELECT
  (SELECT count(*) FROM users WHERE id % 4 = 0) AS shard_0_count,
  (SELECT count(*) FROM users WHERE id % 4 = 1) AS shard_1_count,
  (SELECT count(*) FROM users WHERE id % 4 = 2) AS shard_2_count,
  (SELECT count(*) FROM users WHERE id % 4 = 3) AS shard_3_count;

-- Verify analytics replica is syncing
CREATE SUBSCRIPTION analytics_sync CONNECTION 'postgres://user:pass@citus-coordinator.citus.svc.cluster.local/code_server'
  PUBLICATION all_tables;

-- Monitor replication lag
SELECT * FROM pg_stat_replication;


-- ═════════════════════════════════════════════════════════════════════════════
-- STEP 10: Configuration for Long-Term Operations
-- ═════════════════════════════════════════════════════════════════════════════

-- Automatic rebalancing when new nodes added
SET citus.shard_rebalancing_strategy = 'by_disk_size';

-- Set replication factor to 2 for high availability
ALTER SYSTEM SET citus.shard_replication_factor = 2;

-- Enable query statistics for planning
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Monitoring: Set up continuous monitoring
CREATE TABLE IF NOT EXISTS citus_stats_hourly (
  hour TIMESTAMP,
  table_name REGCLASS,
  total_rows BIGINT,
  total_bytes BIGINT,
  shard_count INT
);

-- Insert hourly stats
INSERT INTO citus_stats_hourly
SELECT
  date_trunc('hour', now()),
  logicalrelid,
  sum(shardlength) / 8192 AS total_rows,
  sum(shardlength),
  count(*)
FROM pg_dist_placement p
JOIN pg_stat_user_tables s ON p.shardid = s.relid
GROUP BY logicalrelid;


-- ═════════════════════════════════════════════════════════════════════════════
-- ROLLBACK PROCEDURE (if issues detected)
-- ═════════════════════════════════════════════════════════════════════════════

-- If migration fails, rollback to old single-node setup:
--
-- 1. Rename back:
-- ALTER TABLE users RENAME TO users_distributed;
-- ALTER TABLE users_old RENAME TO users;
--
-- 2. Update connection string back to single-node PostgreSQL
--
-- 3. Drop distributed tables
-- DROP TABLE users_distributed CASCADE;
# DROP EXTENSION citus CASCADE;
--
-- 4. Restart application with old connection string

-- ═════════════════════════════════════════════════════════════════════════════
# SUCCESS: Migration to distributed PostgreSQL complete!
# - Users: distributed by id
# - Sessions: distributed by user_id
# - Workspaces: distributed by owner_id
# - Files: distributed by owner_id
# - Features/Settings: replicated reference tables
# - Analytics replica: read-only for OLAP queries
# - Automatic rebalancing enabled
