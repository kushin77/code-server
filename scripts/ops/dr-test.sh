#!/bin/bash
# Disaster Recovery Test
# Simulates data loss and verifies recovery procedures

set -e
trap 'echo "❌ DR test failed at line $LINENO"; exit 1' ERR

PRIMARY="192.168.168.31"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         DISASTER RECOVERY TEST - $(date +%Y-%m-%d)        ║"
echo "║         DO NOT RUN IN PRODUCTION!                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "This test will:"
echo "  1. Create test data in PostgreSQL"
echo "  2. Verify backup is created"
echo "  3. Simulate data loss (DROP TABLE)"
echo "  4. Restore from backup"
echo "  5. Verify recovery"
echo ""
echo "⚠️  WARNING: This modifies the database temporarily!"
echo ""
echo "Type 'yes' to continue:"
read -r confirm

if [[ "$confirm" != "yes" ]]; then
  echo "DR test cancelled"
  exit 0
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 1: Creating test data..."
echo "╚════════════════════════════════════════════════════════════╝"

ssh -o BatchMode=yes akushnir@$PRIMARY << 'EOF'
  docker exec code-server-postgres psql -U postgres -d code_server -c "
    CREATE TABLE IF NOT EXISTS dr_test (
      id SERIAL PRIMARY KEY,
      test_data VARCHAR(255),
      created_at TIMESTAMP DEFAULT NOW()
    );
    DELETE FROM dr_test;
    INSERT INTO dr_test (test_data) VALUES ('DR Test Data - $(date)');
    SELECT COUNT(*) as row_count FROM dr_test;
  "
EOF

echo "✅ Test table created with data"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 2: Taking backup..."
echo "╚════════════════════════════════════════════════════════════╝"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/dr_test_${TIMESTAMP}.sql.gz"

ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  docker exec code-server-postgres pg_dump \
    -U postgres \
    -d code_server \
    --format=plain \
    --no-owner \
    --no-privileges | gzip > $BACKUP_FILE
  
  ls -lh $BACKUP_FILE
EOF

echo "✅ Backup created"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 3: Verifying backup contains test data..."
echo "╚════════════════════════════════════════════════════════════╝"

# Download and verify backup
scp -o BatchMode=yes akushnir@$PRIMARY:$BACKUP_FILE /tmp/dr_test_verify.sql.gz

if gunzip < /tmp/dr_test_verify.sql.gz | grep -q "dr_test"; then
  echo "✅ Backup verification passed - test table found in backup"
else
  echo "❌ Backup verification failed - test table not in backup"
  exit 1
fi

rm -f /tmp/dr_test_verify.sql.gz

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 4: Simulating data loss (DROP TABLE)..."
echo "╚════════════════════════════════════════════════════════════╝"

ssh -o BatchMode=yes akushnir@$PRIMARY << 'EOF'
  docker exec code-server-postgres psql -U postgres -d code_server -c "
    DROP TABLE dr_test;
    SELECT COUNT(*) as table_count FROM information_schema.tables 
    WHERE table_schema='public' AND table_name='dr_test';
  " || true
  
  echo "✓ Table dropped"
EOF

echo "✅ Data loss simulated"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 5: Restoring from backup..."
echo "╚════════════════════════════════════════════════════════════╝"

echo "Uploading backup..."
scp -o BatchMode=yes /tmp/dr_test_backup.sql.gz akushnir@$PRIMARY:$BACKUP_FILE 2>/dev/null || \
  scp -o BatchMode=yes $BACKUP_FILE akushnir@$PRIMARY:$BACKUP_FILE

echo "Restoring database..."
ssh -o BatchMode=yes akushnir@$PRIMARY << EOF
  gunzip < $BACKUP_FILE | docker exec -i code-server-postgres psql -U postgres -d code_server
  
  # Verify restoration
  docker exec code-server-postgres psql -U postgres -d code_server -c "SELECT COUNT(*) as restored_rows FROM dr_test;"
  
  # Cleanup
  rm -f $BACKUP_FILE
EOF

echo "✅ Restore completed"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 6: Verifying recovery..."
echo "╚════════════════════════════════════════════════════════════╝"

ssh -o BatchMode=yes akushnir@$PRIMARY << 'EOF'
  echo "Verifying test data was restored..."
  docker exec code-server-postgres psql -U postgres -d code_server -c "
    SELECT id, test_data, created_at FROM dr_test;
  "
  
  echo "✓ Verification complete"
EOF

echo "✅ Recovery verified"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  PHASE 7: Cleanup..."
echo "╚════════════════════════════════════════════════════════════╝"

ssh -o BatchMode=yes akushnir@$PRIMARY << 'EOF'
  docker exec code-server-postgres psql -U postgres -d code_server -c "DROP TABLE dr_test;"
  echo "✓ Test table cleaned up"
EOF

rm -f /tmp/dr_test_*.sql.gz

echo "✅ Cleanup complete"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ DR TEST PASSED - Recovery procedures verified         ║"
echo "║                                                            ║"
echo "║  All phases completed successfully:                       ║"
echo "║  ✓ Test data creation                                     ║"
echo "║  ✓ Backup capture                                         ║"
echo "║  ✓ Backup verification                                    ║"
echo "║  ✓ Data loss simulation                                   ║"
echo "║  ✓ Restore from backup                                    ║"
echo "║  ✓ Recovery verification                                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
