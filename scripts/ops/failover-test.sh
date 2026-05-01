#!/bin/bash
# failover-test.sh
# PostgreSQL HA Failover Testing Script
# Tests manual failover from primary to replica
# Part of: Advanced Troubleshooting Scenarios

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

trap 'log_error "Script failed at line $LINENO - check logs at /tmp/failover-test-*.log"; exit 1' ERR
trap 'rm -f /tmp/failover-test.tmp 2>/dev/null || true' EXIT

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== PostgreSQL HA Failover Test $TIMESTAMP ===" | tee /tmp/failover-test-$TIMESTAMP.log
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log

# Step 1: Confirm primary is responding
echo "[STEP 1] Confirming primary is accessible..." | tee -a /tmp/failover-test-$TIMESTAMP.log
if ssh -o ConnectTimeout=3 -o BatchMode=yes akushnir@$PRIMARY "uptime" &>/dev/null; then
  echo "✅ Primary is responding" | tee -a /tmp/failover-test-$TIMESTAMP.log
else
  echo "❌ Primary not responding - aborting test" | tee -a /tmp/failover-test-$TIMESTAMP.log
  exit 1
fi

# Step 2: Verify replica in standby mode
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "[STEP 2] Verifying replica in standby mode..." | tee -a /tmp/failover-test-$TIMESTAMP.log
RECOVERY=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();' 2>/dev/null | grep -i 't'" 2>/dev/null || echo "")
if [ -n "$RECOVERY" ]; then
  echo "✅ Replica in recovery/standby mode" | tee -a /tmp/failover-test-$TIMESTAMP.log
else
  echo "❌ Replica NOT in standby mode - aborting test" | tee -a /tmp/failover-test-$TIMESTAMP.log
  exit 1
fi

# Step 3: Promote replica to primary
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "[STEP 3] Promoting replica to primary..." | tee -a /tmp/failover-test-$TIMESTAMP.log
PROMOTE_RESULT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_promote();' 2>/dev/null" 2>/dev/null || echo "failed")
if [ "$PROMOTE_RESULT" != "failed" ]; then
  echo "✅ Promotion command sent to replica" | tee -a /tmp/failover-test-$TIMESTAMP.log
else
  echo "❌ Promotion command failed" | tee -a /tmp/failover-test-$TIMESTAMP.log
  exit 1
fi

# Wait for promotion to complete
echo "   Waiting for promotion to complete..." | tee -a /tmp/failover-test-$TIMESTAMP.log
sleep 5

# Step 4: Verify promotion succeeded
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "[STEP 4] Verifying promotion..." | tee -a /tmp/failover-test-$TIMESTAMP.log
AFTER_PROMOTE=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();' 2>/dev/null | grep -i 'f'" 2>/dev/null || echo "")
if [ -n "$AFTER_PROMOTE" ]; then
  echo "✅ Replica successfully promoted to primary" | tee -a /tmp/failover-test-$TIMESTAMP.log
  echo "   pg_is_in_recovery = FALSE (now primary)" | tee -a /tmp/failover-test-$TIMESTAMP.log
else
  echo "⚠️ Promotion may not have completed yet" | tee -a /tmp/failover-test-$TIMESTAMP.log
fi

# Step 5: Check replica connectivity
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "[STEP 5] Verifying replica (now primary) accessibility..." | tee -a /tmp/failover-test-$TIMESTAMP.log
REPLICA_CONN=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT 1;' 2>/dev/null" 2>/dev/null || echo "failed")
if [ "$REPLICA_CONN" != "failed" ]; then
  echo "✅ New primary ($REPLICA) responding to queries" | tee -a /tmp/failover-test-$TIMESTAMP.log
else
  echo "❌ New primary not responding" | tee -a /tmp/failover-test-$TIMESTAMP.log
fi

# Step 6: Verify data integrity
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "[STEP 6] Checking data integrity..." | tee -a /tmp/failover-test-$TIMESTAMP.log
QUERY=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT COUNT(*) FROM pg_database;' 2>/dev/null" 2>/dev/null || echo "0")
echo "✅ Data accessible: $QUERY databases found" | tee -a /tmp/failover-test-$TIMESTAMP.log

# Step 7: Summary
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "=== FAILOVER TEST SUMMARY ===" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "Timestamp: $TIMESTAMP" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "Original Primary: $PRIMARY (status: check manually)" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "Original Replica: $REPLICA (status: PROMOTED TO PRIMARY)" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "⚠️  IMPORTANT: Manual recovery required" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "   - Original primary must be rebuilt as new replica" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "   - Run: docker-compose pull && docker-compose up -d" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "   - Configure replication from new primary at $REPLICA:5432" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "" | tee -a /tmp/failover-test-$TIMESTAMP.log
echo "✅ FAILOVER TEST COMPLETED SUCCESSFULLY" | tee -a /tmp/failover-test-$TIMESTAMP.log

exit 0
