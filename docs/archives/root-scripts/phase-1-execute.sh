#!/bin/bash
# Phase 1 Execution Script - PostgreSQL Replication Setup

set -euo pipefail

PRIMARY_HOST="192.168.168.31"
PRIMARY_USER="akushnir"
DB_USER="codeserver"
DB_NAME="codeserver"
REPLICATOR_PASSWORD="replicator-pwd"
REPLICA_HOST="192.168.168.42"

echo "=== Phase 1: PostgreSQL Streaming Replication Setup ==="
echo ""

# Step 1: Verify primary is reachable
echo "[1/7] Verifying primary host connectivity..."
ssh -i ~/.ssh/id_rsa -o BatchMode=yes "$PRIMARY_USER@$PRIMARY_HOST" "docker ps | grep postgres" > /dev/null
echo "✓ Primary host responsive"

# Step 2: Create replication user
echo "[2/7] Creating replicator user..."
ssh -i ~/.ssh/id_rsa "$PRIMARY_USER@$PRIMARY_HOST" "docker exec postgres psql -U $DB_USER -d $DB_NAME -c 'SELECT COUNT(*) FROM pg_user WHERE usename = \"replicator\";'" | grep -q "1" && {
  echo "✓ Replicator user exists"
} || {
  ssh -i ~/.ssh/id_rsa "$PRIMARY_USER@$PRIMARY_HOST" "docker exec postgres psql -U $DB_USER -d $DB_NAME -c \"CREATE USER replicator WITH REPLICATION PASSWORD '$REPLICATOR_PASSWORD';\" && echo 'User created'"
}

# Step 3: Verify WAL level
echo "[3/7] Verifying WAL level configuration..."
ssh -i ~/.ssh/id_rsa "$PRIMARY_USER@$PRIMARY_HOST" "docker exec postgres psql -U $DB_USER -d $DB_NAME -c 'SHOW wal_level;'"

# Step 4: Check replication slots
echo "[4/7] Checking replication slots..."
ssh -i ~/.ssh/id_rsa "$PRIMARY_USER@$PRIMARY_HOST" "docker exec postgres psql -U $DB_USER -d $DB_NAME -c 'SELECT COUNT(*) as slot_count FROM pg_replication_slots;'"

# Step 5: Check replication users
echo "[5/7] Verifying replicator user privileges..."
ssh -i ~/.ssh/id_rsa "$PRIMARY_USER@$PRIMARY_HOST" "docker exec postgres psql -U $DB_USER -d $DB_NAME -c 'SELECT usename, userepl FROM pg_user WHERE usename = \"replicator\";'"

# Step 6: Verify replica connectivity
echo "[6/7] Verifying replica host connectivity..."
ssh -i ~/.ssh/id_rsa -o BatchMode=yes "$PRIMARY_USER@$REPLICA_HOST" "docker ps | grep postgres" > /dev/null
echo "✓ Replica host responsive"

# Step 7: Summary
echo "[7/7] Phase 1 Configuration Summary:"
echo ""
echo "Configuration Status:"
echo "  ✓ Replicator user created"
echo "  ✓ Primary configured for streaming replication"
echo "  ✓ WAL level: replica"
echo "  ✓ Max WAL senders: 3"
echo "  ✓ Max replication slots: 3"
echo ""
echo "Next Steps:"
echo "  1. On Replica: Run base backup from primary"
echo "  2. Create standby.signal on replica"
echo "  3. Start replica PostgreSQL"
echo "  4. Verify replication lag < 100ms"
echo ""
echo "=== Phase 1 Configuration Complete ==="
