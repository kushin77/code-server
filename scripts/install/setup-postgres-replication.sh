#!/bin/bash
set -e

# Create replication user with password
PGPASSWORD="replication_user_pwd" psql -h localhost -U db_admin -d postgres -c \
  "CREATE USER replication_user WITH REPLICATION ENCRYPTED PASSWORD 'replication_user_pwd';" 2>/dev/null || true

# Enable streaming replication (requires postgres restart)
psql -h localhost -U db_admin -d postgres << SQL
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET max_replication_slots = 3;
ALTER SYSTEM SET hot_standby = on;
SELECT pg_reload_conf();
SQL

# Create replication slot
psql -h localhost -U db_admin -d postgres -c \
  "SELECT * FROM pg_create_physical_replication_slot('replica_slot_1');" 2>/dev/null || true

echo "Replication setup complete"
