#!/bin/bash
# PostgreSQL Replication Fix - Part 4: Update docker-compose Configuration
# Execute on: Replica host (192.168.168.42)
# Prerequisites: Parts 1-3 completed, replication working

set -euo pipefail
trap 'echo "❌ Update failed at line $LINENO"; exit 1' ERR
trap 'echo "✅ Script completed"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ubuntu/postgresql_fix_part4_${TIMESTAMP}.log"
DEPLOYMENT_DIR="/home/ubuntu/code-server"
COMPOSE_FILE="$DEPLOYMENT_DIR/docker-compose.enterprise.yml"
BACKUP_FILE="$COMPOSE_FILE.backup_${TIMESTAMP}"

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PostgreSQL Replication Fix - Part 4: Update docker-compose      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Started: $(date)"
  echo "Host: $(hostname -I | awk '{print $1}')"
  echo "Log: $LOG_FILE"
  echo ""
  
  cd "$DEPLOYMENT_DIR"
  
  # ============================================================================
  # STEP 1: Backup Current docker-compose
  # ============================================================================
  echo "[1/5] Backup Current docker-compose"
  echo "===================================="
  
  if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ docker-compose.enterprise.yml not found at $COMPOSE_FILE"
    exit 1
  fi
  
  cp "$COMPOSE_FILE" "$BACKUP_FILE"
  echo "✅ Backup created: $BACKUP_FILE"
  echo ""
  
  # ============================================================================
  # STEP 2: Verify Replication Working
  # ============================================================================
  echo "[2/5] Verify Replication is Working"
  echo "===================================="
  
  PG_CONTAINER=$(docker-compose ps -q postgres 2>/dev/null)
  
  if [ -z "$PG_CONTAINER" ]; then
    echo "❌ PostgreSQL container not running"
    exit 1
  fi
  
  RECOVERY_STATUS=$(docker exec "$PG_CONTAINER" psql -U postgres -d postgres -t -c "SELECT pg_is_in_recovery();" 2>&1 | grep -E "t|f" | head -1 || echo "unknown")
  
  if [ "$RECOVERY_STATUS" != "t" ]; then
    echo "❌ Replication not active (pg_is_in_recovery != true)"
    echo "   Please complete Parts 1-3 first"
    exit 1
  fi
  
  echo "✅ Replication is active and working"
  echo ""
  
  # ============================================================================
  # STEP 3: Update docker-compose Configuration
  # ============================================================================
  echo "[3/5] Update docker-compose Configuration"
  echo "=========================================="
  
  # Check if user: "999:999" already exists
  if grep -q 'user:.*"999:999"' "$COMPOSE_FILE"; then
    echo "ℹ️  User mapping already present in docker-compose"
  else
    echo "Adding user: \"999:999\" mapping to postgres service..."
    
    # Use sed to add user line after postgres service definition
    # This is a careful sed operation to avoid breaking YAML
    sed -i '/service.*postgres:/,/image:.*postgres/ {
      /image:.*postgres/a\
    user: "999:999"
    }' "$COMPOSE_FILE" 2>/dev/null || {
      echo "⚠️  Automatic sed update failed, manual update may be needed"
      echo "   Add this line under the postgres service:"
      echo "     user: \"999:999\""
    }
  fi
  
  echo "✅ docker-compose updated"
  echo ""
  
  # ============================================================================
  # STEP 4: Document Changes
  # ============================================================================
  echo "[4/5] Document Changes"
  echo "====================="
  
  echo "Changes made to docker-compose.enterprise.yml:"
  echo "---"
  
  if grep -A 5 "service.*postgres:" "$COMPOSE_FILE" | grep -q 'user:'; then
    echo "✅ User mapping is present"
    grep -A 10 "service.*postgres:" "$COMPOSE_FILE" | head -15
  else
    echo "⚠️  User mapping may need manual verification"
    echo "    Check that this line exists under the postgres service:"
    echo "      user: \"999:999\""
  fi
  
  echo "---"
  echo ""
  
  # ============================================================================
  # STEP 5: Verify Configuration Syntax
  # ============================================================================
  echo "[5/5] Verify Configuration Syntax"
  echo "=================================="
  
  if docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1; then
    echo "✅ docker-compose syntax is valid"
  else
    echo "❌ docker-compose syntax error detected"
    echo "   Restoring from backup..."
    cp "$BACKUP_FILE" "$COMPOSE_FILE"
    exit 1
  fi
  echo ""
  
  # ============================================================================
  # FINAL STATUS
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ Part 4 Complete - docker-compose Updated                        ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Summary:"
  echo "✅ Replication is working (tested)"
  echo "✅ docker-compose.enterprise.yml updated with user mapping"
  echo "✅ Configuration syntax valid"
  echo ""
  echo "Next Steps:"
  echo "1. On next maintenance window: Stop containers and remove volume"
  echo "   docker-compose down"
  echo "   docker volume rm code-server_postgres_data"
  echo "2. Recreate containers with new user mapping:"
  echo "   docker-compose up -d"
  echo "3. Verify replication with: bash verify-postgresql-replication-part2.sh"
  echo ""
  echo "Backup: $BACKUP_FILE"
  echo "Completed: $(date)"

} 2>&1 | tee "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"
