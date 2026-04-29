#!/bin/bash
# PostgreSQL restore from backup
# Restores database from compressed backup file

set -e
trap 'echo "❌ Restore failed at line $LINENO"; exit 1' ERR

BACKUP_FILE="${1:-.}"
DB_HOST="${DB_HOST:-192.168.168.31}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-code_server}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Usage: $0 <backup_file>"
  echo "Example: $0 /backups/postgres/backup_20260430_020000.sql.gz"
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          PostgreSQL Restore from Backup                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Backup file: $BACKUP_FILE"
echo "Target host: $DB_HOST"
echo "Database: $DB_NAME"
echo ""
echo "⚠️  WARNING: This will OVERWRITE the database!"
echo "Type 'yes' to continue:"
read -r confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Restore cancelled"
  exit 0
fi

echo ""
echo "Starting restore... $(date)"

TIMESTAMP=$(date +%s)

# Upload backup to primary
echo "Uploading backup..."
scp -o BatchMode=yes "$BACKUP_FILE" akushnir@$DB_HOST:/tmp/restore_${TIMESTAMP}.sql.gz

# Execute restore
echo "Restoring database..."
ssh -o BatchMode=yes akushnir@$DB_HOST << RESTORE_EOF
  # Stop dependent services
  echo "Stopping dependent services..."
  docker stop code-server-execution-scheduler code-server-reputation-engine code-server-memory-engine || true
  sleep 5
  
  # Drop existing database
  echo "Dropping existing database..."
  docker exec code-server-postgres psql -U postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
  
  # Restore from backup
  echo "Restoring from backup..."
  gunzip < /tmp/restore_${TIMESTAMP}.sql.gz | docker exec -i code-server-postgres psql -U postgres
  
  # Verify restore
  echo "Verifying restore..."
  docker exec code-server-postgres psql -U postgres -d $DB_NAME -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='public';"
  
  # Restart services
  echo "Restarting services..."
  sleep 5
  docker start code-server-execution-scheduler code-server-reputation-engine code-server-memory-engine
  
  # Cleanup
  rm -f /tmp/restore_${TIMESTAMP}.sql.gz
RESTORE_EOF

echo ""
echo "✅ Restore completed at $(date)"
echo "Services restarting - check platform health in 30 seconds"
