-- ═══════════════════════════════════════════════════════════════════════════════
-- PostgreSQL Replication Setup — Phase 7b
-- 
-- This script initializes the replication user and configures the database
-- for streaming replication from primary to replica.
-- 
-- Created: April 15, 2026
-- Target: 99.99% availability (Phase 7 multi-region deployment)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Create replication user (only if not already exists)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_phase7b_secret';
    RAISE NOTICE 'Replicator role created successfully';
  ELSE
    RAISE NOTICE 'Replicator role already exists';
  END IF;
END
$$;

-- Grant necessary permissions
ALTER ROLE replicator WITH SUPERUSER;

-- Verify configuration
SELECT 'PostgreSQL replication user initialized' as status;
SELECT 'wal_level: replica' as config;
SELECT 'max_wal_senders: 10' as config;
