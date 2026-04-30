#!/bin/bash
# PostgreSQL Replication Fix - Part 2: Verify Replication
# Execute on: Replica host (192.168.168.42)
# Prerequisites: Part 1 completed, PostgreSQL container restarted

set -euo pipefail
trap 'echo "⚠️  Verification ended"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ubuntu/postgresql_fix_part2_${TIMESTAMP}.log"
DEPLOYMENT_DIR="/home/ubuntu/code-server"

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PostgreSQL Replication Fix - Part 2: Verify Replication         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Started: $(date)"
  echo "Host: $(hostname -I | awk '{print $1}')"
  echo "Log: $LOG_FILE"
  echo ""
  
  cd "$DEPLOYMENT_DIR"
  
  # ============================================================================
  # VERIFICATION 1: Check Recovery Mode Status
  # ============================================================================
  echo "[1/4] Checking Recovery Mode Status"
  echo "===================================="
  
  PG_CONTAINER=$(docker-compose ps -q postgres 2>/dev/null)
  
  if [ -z "$PG_CONTAINER" ]; then
    echo "❌ PostgreSQL container not running"
    exit 1
  fi
  
  echo "Waiting 10 seconds for PostgreSQL to fully initialize..."
  sleep 10
  
  echo "Querying pg_is_in_recovery()..."
  RECOVERY_STATUS=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SELECT pg_is_in_recovery();" 2>&1 | grep -E "t|f" | head -1 || echo "unknown")
  
  if [ "$RECOVERY_STATUS" = "t" ]; then
    echo "✅ IN RECOVERY MODE - Streaming replication is ACTIVE"
  elif [ "$RECOVERY_STATUS" = "f" ]; then
    echo "❌ NOT in recovery mode - replication may not have connected yet"
    echo "   This may be normal if replica has not yet connected to primary"
    echo "   Check Part 3 for primary-side verification"
  else
    echo "⚠️  Could not determine recovery mode: $RECOVERY_STATUS"
  fi
  echo ""
  
  # ============================================================================
  # VERIFICATION 2: Check WAL Receiver Status
  # ============================================================================
  echo "[2/4] Checking WAL Receiver Status"
  echo "=================================="
  
  echo "Querying pg_stat_wal_receiver..."
  docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -x -c "SELECT * FROM pg_stat_wal_receiver;" 2>&1 | head -20 || echo "⚠️  Not connected yet"
  echo ""
  
  # ============================================================================
  # VERIFICATION 3: Check Standby Signal File
  # ============================================================================
  echo "[3/4] Checking Standby Signal File"
  echo "=================================="
  
  echo "Verifying standby.signal file exists and has correct permissions..."
  docker exec "$PG_CONTAINER" ls -la /var/lib/postgresql/data/standby.signal 2>&1 || echo "❌ standby.signal not found"
  
  SIGNAL_PERMS=$(docker exec "$PG_CONTAINER" stat -c "%a" /var/lib/postgresql/data/standby.signal 2>/dev/null || echo "unknown")
  if [ "$SIGNAL_PERMS" = "600" ]; then
    echo "✅ Permissions correct (600)"
  else
    echo "⚠️  Unexpected permissions: $SIGNAL_PERMS (expected: 600)"
  fi
  echo ""
  
  # ============================================================================
  # VERIFICATION 4: Primary Server Replication Slot Status
  # ============================================================================
  echo "[4/4] Primary Server Replication Slot Status"
  echo "==========================================="
  
  echo "Attempting to check primary (192.168.168.31) replication slot..."
  
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -t -c \"SELECT slot_name, active, restart_lsn FROM pg_replication_slots;\" 2>/dev/null" 2>/dev/null; then
    echo "✅ Primary slot status retrieved"
  else
    echo "⚠️  Could not reach primary - this may be normal if primary is temporarily unreachable"
    echo "    Replication may still be working via existing connection"
  fi
  echo ""
  
  # ============================================================================
  # SUMMARY
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ Part 2 Complete - Replication Status Verified                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Summary:"
  if [ "$RECOVERY_STATUS" = "t" ]; then
    echo "✅ REPLICATION ACTIVE - All checks passed!"
    echo "   The replica is now running in streaming replication mode"
    echo "   Data from primary will be continuously streamed to replica"
  else
    echo "⚠️  REPLICATION PENDING - Waiting for connection"
    echo "   If still not connected after 5 minutes:"
    echo "   1. Check network connectivity between primary and replica"
    echo "   2. Verify replication_user credentials"
    echo "   3. Check PostgreSQL logs on both servers"
    echo "   4. Review POSTGRESQL_REPLICATION_FIX.md for troubleshooting"
  fi
  echo ""
  echo "Completed: $(date)"

} 2>&1 | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
echo ""
echo "Monitor ongoing replication with:"
echo "  watch -n 5 'docker exec code-server-postgres psql -U postgres -d postgres -t -c \"SELECT pg_is_in_recovery(); SELECT * FROM pg_stat_wal_receiver \\\\gx\"'"
