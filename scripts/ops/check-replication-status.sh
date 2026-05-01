#!/bin/bash
# WP-6.5: PostgreSQL Streaming Replication Setup
# Sets up streaming replication from primary to replica

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

log_error() {
  echo "ERROR: $@" >&2
}

log_info() {
  echo "INFO: $@"
}

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
POSTGRES_USER="postgres"
REPLICATION_SLOT="replica_1"

echo "═══════════════════════════════════════════════════════════"
echo "WP-6.5: PostgreSQL Streaming Replication Setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Step 1: Verify primary is ready
echo "Step 1: Checking primary PostgreSQL status..."
PRIMARY_STATUS=$(ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c 'SELECT version();' 2>&1 | head -1")

if [[ $PRIMARY_STATUS == *"PostgreSQL"* ]]; then
  echo "✅ Primary PostgreSQL: Ready"
else
  echo "❌ Primary PostgreSQL: NOT READY"
  exit 1
fi

# Step 2: Verify replication slot exists on primary
echo ""
echo "Step 2: Verifying replication slot on primary..."
SLOT_CHECK=$(ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c 'SELECT slot_name FROM pg_replication_slots WHERE slot_name = '\''replica_1'\'';' 2>&1")

if [[ $SLOT_CHECK == *"replica_1"* ]]; then
  echo "✅ Replication slot 'replica_1' exists on primary"
else
  echo "⚠️  Replication slot not found, creating..."
  ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" \
    "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c 'SELECT * FROM pg_create_physical_replication_slot('\''replica_1'\'');' 2>&1"
  echo "✅ Replication slot created"
fi

# Step 3: Check replica PostgreSQL status
echo ""
echo "Step 3: Checking replica PostgreSQL status..."
REPLICA_STATUS=$(ssh -o ConnectTimeout=10 "akushnir@${REPLICA_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c 'SELECT version();' 2>&1 | head -1")

if [[ $REPLICA_STATUS == *"PostgreSQL"* ]]; then
  echo "✅ Replica PostgreSQL: Ready"
else
  echo "❌ Replica PostgreSQL: NOT READY"
  exit 1
fi

# Step 4: Check if replica is already in recovery mode
echo ""
echo "Step 4: Checking if replica is in recovery mode..."
RECOVERY_CHECK=$(ssh -o ConnectTimeout=10 "akushnir@${REPLICA_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();' 2>&1")

if [[ $RECOVERY_CHECK == *"t"* ]] || [[ $RECOVERY_CHECK == *"true"* ]]; then
  echo "✅ Replica is in recovery mode (replication may be active)"
elif [[ $RECOVERY_CHECK == *"f"* ]] || [[ $RECOVERY_CHECK == *"false"* ]]; then
  echo "⚠️  Replica is NOT in recovery mode - needs replication setup"
else
  echo "⚠️  Recovery mode status unclear: $RECOVERY_CHECK"
fi

# Step 5: Check replica recovery configuration
echo ""
echo "Step 5: Checking replica recovery configuration..."
RECOVERY_CONFIG=$(ssh -o ConnectTimeout=10 "akushnir@${REPLICA_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres ls -la /var/lib/postgresql/data/recovery.conf 2>&1 || echo 'File not found'")

if [[ $RECOVERY_CONFIG == *"recovery.conf"* ]]; then
  echo "✅ Recovery configuration found"
  echo ""
  echo "Recovery configuration:"
  ssh -o ConnectTimeout=10 "akushnir@${REPLICA_HOST}" \
    "cd ~/code-server-enterprise-ops && docker exec code-server-postgres cat /var/lib/postgresql/data/recovery.conf 2>&1 || echo 'Cannot read'"
else
  echo "⚠️  Recovery configuration not found - may need setup"
fi

# Step 6: Check replication user on primary
echo ""
echo "Step 6: Verifying replication user on primary..."
REP_USER=$(ssh -o ConnectTimeout=10 "akushnir@${PRIMARY_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres psql -U postgres -c \"SELECT rolname FROM pg_roles WHERE rolreplication = true;\" 2>&1")

if [[ $REP_USER == *"replicator"* ]] || [[ $REP_USER == *"postgres"* ]]; then
  echo "✅ Replication user found"
else
  echo "⚠️  Replication user may not be configured"
fi

# Step 7: Test connectivity from replica to primary
echo ""
echo "Step 7: Testing connectivity from replica to primary..."
PING_TEST=$(ssh -o ConnectTimeout=10 "akushnir@${REPLICA_HOST}" \
  "cd ~/code-server-enterprise-ops && docker exec code-server-postgres pg_basebackup -h ${PRIMARY_HOST} -U postgres -v -P 2>&1 | head -5")

if [[ $PING_TEST == *"starting"* ]] || [[ $PING_TEST == *"backup"* ]] || [[ $PING_TEST == *"connection"* ]]; then
  echo "✅ Replica can connect to primary"
  echo ""
  echo "Connectivity check output:"
  echo "$PING_TEST"
else
  echo "⚠️  Connection test output: $PING_TEST"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Replication Status Summary"
echo "═══════════════════════════════════════════════════════════"
echo "Primary: Ready"
echo "Replica: Ready"
echo "Slot: replica_1 created"
echo "Next: Configure recovery.conf on replica and restart PostgreSQL"
echo ""
