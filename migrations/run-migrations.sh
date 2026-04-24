#!/bin/bash
set -euo pipefail

DB_HOST="${POSTGRES_HOST:-postgres}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-codeserver}"
DB_USER="${POSTGRES_USER:-codeserver}"
POSTGRES_ROOT_USER="${POSTGRES_ROOT_USER:-postgres}"

echo "Starting SaaS API database migrations..."
echo "Connecting as root user to create codeserver user..."

# Wait for postgres to be ready
sleep 8

# Create codeserver user and grant privileges (idempotent)
psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$POSTGRES_ROOT_USER" \
  -d postgres \
  -v ON_ERROR_STOP=0 \
  << CREATE_USER
DO \$\$ BEGIN
  CREATE ROLE "$DB_USER" WITH LOGIN PASSWORD '${PGPASSWORD}';
  GRANT CREATEDB TO "$DB_USER";
EXCEPTION WHEN OTHERS THEN
  NULL;
END \$\$;
CREATE_USER

echo "Creating database (if needed)..."
psql \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$POSTGRES_ROOT_USER" \
  -d postgres \
  -v ON_ERROR_STOP=0 \
  -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\"" || true

echo "Running migrations as codeserver user..."

# Run all migrations as codeserver user
for migration_file in /migrations/*.sql; do
  if [ -f "$migration_file" ]; then
    echo "Running migration: $(basename $migration_file)"
    PGPASSWORD="${PGPASSWORD}" psql \
      -h "$DB_HOST" \
      -p "$DB_PORT" \
      -U "$DB_USER" \
      -d "$DB_NAME" \
      -v ON_ERROR_STOP=1 \
      -f "$migration_file" || exit 1
    echo "✓ Migration complete: $(basename $migration_file)"
  fi
done

echo "✓ All migrations complete"
exit 0
