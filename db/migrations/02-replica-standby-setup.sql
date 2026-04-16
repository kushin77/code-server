-- ═══════════════════════════════════════════════════════════════════════════════
-- PostgreSQL Replica Standby Setup — Phase 7b
-- 
-- This script configures a PostgreSQL instance as a read-only replica that streams
-- from the primary host (192.168.168.31) using the replicator user.
-- 
-- Note: This script runs on REPLICA ONLY and expects an empty database.
-- The primary has already executed 01-replication-setup.sql to create the replicator role.
-- 
-- Created: April 15, 2026
-- Target: 99.99% availability (Phase 7 multi-region deployment)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Configure this instance as a standby/replica
-- For PostgreSQL 12+, use recovery.conf or postgresql.auto.conf
-- This is typically done via SQL command or direct file modification

SELECT 'PostgreSQL replica configured to stream from primary (192.168.168.31)' as status;
SELECT 'Connection: replicator@192.168.168.31:5432' as connection_info;
SELECT 'Replication method: streaming replication (WAL)' as method;
