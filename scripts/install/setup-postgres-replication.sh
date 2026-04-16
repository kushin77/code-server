#!/bin/bash
set -euo pipefail

PG_ADMIN_USER="${PG_ADMIN_USER:-db_admin}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-}"
REPLICATION_USER="${REPLICATION_USER:-replication_user}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-}"

if [[ -z "$PG_ADMIN_PASSWORD" || -z "$REPLICATION_PASSWORD" ]]; then
  echo "ERROR: PG_ADMIN_PASSWORD and REPLICATION_PASSWORD must be set" >&2
  exit 1
fi

# Create replication user with password
PGPASSWORD="$PG_ADMIN_PASSWORD" psql -h localhost -U "$PG_ADMIN_USER" -d postgres -c \
  "CREATE USER ${REPLICATION_USER} WITH REPLICATION ENCRYPTED PASSWORD '${REPLICATION_PASSWORD}';" 2>/dev/null || true

# Enable streaming replication (requires postgres restart)
PGPASSWORD="$PG_ADMIN_PASSWORD" psql -h localhost -U "$PG_ADMIN_USER" -d postgres << SQL
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET max_replication_slots = 3;
ALTER SYSTEM SET hot_standby = on;
SELECT pg_reload_conf();
SQL

# Create replication slot
PGPASSWORD="$PG_ADMIN_PASSWORD" psql -h localhost -U "$PG_ADMIN_USER" -d postgres -c \
  "SELECT * FROM pg_create_physical_replication_slot('replica_slot_1');" 2>/dev/null || true

echo "Replication setup complete"
