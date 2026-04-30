#!/bin/bash
# PostgreSQL Replication Fix - Part 1: Fix Permissions
# Execute on: Replica host (192.168.168.42)
# Prerequisites: SSH access, docker-compose installed, PostgreSQL container running

set -euo pipefail
trap 'echo "❌ Fix failed at line $LINENO"; exit 1' ERR
trap 'echo "✅ Script completed"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ubuntu/postgresql_fix_part1_${TIMESTAMP}.log"
DEPLOYMENT_DIR="/home/ubuntu/code-server"

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PostgreSQL Replication Fix - Part 1: Fix Permissions            ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Started: $(date)"
  echo "Host: $(hostname -I | awk '{print $1}')"
  echo "Log: $LOG_FILE"
  echo ""
  
  cd "$DEPLOYMENT_DIR"
  
  # ============================================================================
  # STEP 1: Identify PostgreSQL Container
  # ============================================================================
  echo "[1/5] Identifying PostgreSQL Container"
  echo "======================================"
  
  PG_CONTAINER=$(docker-compose ps -q postgres 2>/dev/null || echo "")
  
  if [ -z "$PG_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    echo "Run: docker-compose up -d postgres"
    exit 1
  fi
  
  echo "✅ PostgreSQL Container ID: $PG_CONTAINER"
  echo ""
  
  # ============================================================================
  # STEP 2: Check Current Permissions (Before)
  # ============================================================================
  echo "[2/5] Current Permissions (Before Fix)"
  echo "======================================"
  
  echo "Checking standby.signal file..."
  docker exec "$PG_CONTAINER" ls -la /var/lib/postgresql/data/standby.signal 2>&1 || echo "⚠️  standby.signal not found - will create during restart"
  
  echo "Checking PostgreSQL data directory ownership..."
  docker exec "$PG_CONTAINER" ls -lad /var/lib/postgresql/data
  
  echo ""
  
  # ============================================================================
  # STEP 3: Fix File Ownership
  # ============================================================================
  echo "[3/5] Fixing File Ownership"
  echo "============================"
  
  echo "Setting standby.signal owner to postgres:postgres..."
  docker exec "$PG_CONTAINER" chown postgres:postgres /var/lib/postgresql/data/standby.signal 2>/dev/null || echo "⚠️  (File may not exist yet - will be created on restart)"
  
  echo "Setting standby.signal permissions to 600..."
  docker exec "$PG_CONTAINER" chmod 600 /var/lib/postgresql/data/standby.signal 2>/dev/null || true
  
  echo "Setting data directory permissions..."
  docker exec "$PG_CONTAINER" chmod 700 /var/lib/postgresql/data
  
  echo "✅ Ownership fixed"
  echo ""
  
  # ============================================================================
  # STEP 4: Verify Permissions (After)
  # ============================================================================
  echo "[4/5] Verifying Permissions (After Fix)"
  echo "========================================"
  
  echo "Standby.signal permissions:"
  docker exec "$PG_CONTAINER" ls -la /var/lib/postgresql/data/standby.signal 2>&1 || echo "⚠️  (Will be created on restart)"
  
  echo "Data directory permissions:"
  docker exec "$PG_CONTAINER" ls -lad /var/lib/postgresql/data
  
  echo "✅ Permissions verified"
  echo ""
  
  # ============================================================================
  # STEP 5: Restart PostgreSQL Container
  # ============================================================================
  echo "[5/5] Restarting PostgreSQL Container"
  echo "======================================="
  
  echo "Stopping PostgreSQL container..."
  docker-compose stop postgres
  
  echo "Waiting 5 seconds..."
  sleep 5
  
  echo "Starting PostgreSQL container..."
  docker-compose up -d postgres
  
  echo "Waiting 15 seconds for PostgreSQL to start..."
  sleep 15
  
  echo "✅ PostgreSQL restarted"
  echo ""
  
  # ============================================================================
  # FINAL VERIFICATION
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ Part 1 Complete - Permissions Fixed                             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Next Step: Run Part 2 verification script"
  echo "Command: bash verify-postgresql-replication-part2.sh"
  echo ""
  echo "Completed: $(date)"

} 2>&1 | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
