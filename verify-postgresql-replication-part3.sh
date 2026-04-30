#!/bin/bash
# PostgreSQL Replication Fix - Part 3: Verify Primary Replication Slot
# Execute on: Primary host (192.168.168.31)
# Prerequisites: Replica has been restarted with fix

set -euo pipefail
trap 'echo "⚠️  Verification ended"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ubuntu/postgresql_fix_part3_${TIMESTAMP}.log"
DEPLOYMENT_DIR="/home/ubuntu/code-server"

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PostgreSQL Replication Fix - Part 3: Primary Replication Slot   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Started: $(date)"
  echo "Host: $(hostname -I | awk '{print $1}') [PRIMARY]"
  echo "Log: $LOG_FILE"
  echo ""
  
  cd "$DEPLOYMENT_DIR"
  
  # ============================================================================
  # VERIFICATION 1: Replication Slot Status
  # ============================================================================
  echo "[1/3] Replication Slot Status"
  echo "=============================="
  
  PG_CONTAINER=$(docker-compose ps -q postgres 2>/dev/null)
  
  if [ -z "$PG_CONTAINER" ]; then
    echo "❌ PostgreSQL container not running"
    exit 1
  fi
  
  echo "Querying pg_replication_slots..."
  SLOT_ACTIVE=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SELECT active FROM pg_replication_slots WHERE slot_name='replica_slot';" 2>&1 | grep -E "t|f" | head -1 || echo "unknown")
  
  if [ "$SLOT_ACTIVE" = "t" ]; then
    echo "✅ Replication slot ACTIVE - Replica is connected"
  elif [ "$SLOT_ACTIVE" = "f" ]; then
    echo "⚠️  Replication slot exists but NOT active - waiting for replica connection"
  else
    echo "⚠️  Replication slot status unknown or not found"
    echo "    Creating replication slot if missing..."
    docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c "SELECT pg_create_physical_replication_slot('replica_slot');" 2>&1 | grep -E "created|already" || true
  fi
  
  echo ""
  echo "Full slot details:"
  docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -x -c "SELECT * FROM pg_replication_slots;" 2>&1
  echo ""
  
  # ============================================================================
  # VERIFICATION 2: Connected WAL Senders
  # ============================================================================
  echo "[2/3] Connected WAL Senders"
  echo "=========================="
  
  echo "Querying pg_stat_replication (connected replicas)..."
  WAL_SENDERS=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM pg_stat_replication;" 2>&1 | grep -E "[0-9]" | head -1 || echo "0")
  
  if [ "$WAL_SENDERS" -gt 0 ]; then
    echo "✅ $WAL_SENDERS WAL sender(s) connected"
  else
    echo "⚠️  No WAL senders connected yet - replica may not have connected"
  fi
  
  echo ""
  echo "WAL sender details:"
  docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -x -c "SELECT * FROM pg_stat_replication;" 2>&1
  echo ""
  
  # ============================================================================
  # VERIFICATION 3: Replication Configuration
  # ============================================================================
  echo "[3/3] Replication Configuration"
  echo "==============================="
  
  echo "Checking key replication parameters..."
  docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SHOW wal_level; SHOW max_wal_senders; SHOW max_replication_slots;" 2>&1
  
  echo ""
  echo "Checking PostgreSQL version..."
  docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SELECT version();" 2>&1 | head -2
  echo ""
  
  # ============================================================================
  # SUMMARY
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ Part 3 Complete - Primary Slot Status Verified                  ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Summary:"
  if [ "$SLOT_ACTIVE" = "t" ] && [ "$WAL_SENDERS" -gt 0 ]; then
    echo "✅ REPLICATION FULLY ACTIVE"
    echo "   Replication slot is active and replica is connected"
    echo "   WAL data is being streamed to replica"
  elif [ "$SLOT_ACTIVE" = "f" ]; then
    echo "⚠️  REPLICATION SLOT READY BUT WAITING FOR REPLICA"
    echo "   Slot exists but replica hasn't connected yet"
    echo "   Replica may still be initializing or experiencing connection issues"
  else
    echo "❌ REPLICATION NOT CONFIGURED"
    echo "   Check PostgreSQL logs and replication settings"
  fi
  echo ""
  echo "Completed: $(date)"

} 2>&1 | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
echo ""
echo "Monitor primary WAL sender activity with:"
echo "  watch -n 5 'docker exec code-server-postgres psql -U postgres -d postgres -t -c \"SELECT * FROM pg_stat_replication \\\\gx\"'"
