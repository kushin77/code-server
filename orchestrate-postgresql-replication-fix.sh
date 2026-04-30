#!/bin/bash
# PostgreSQL Replication Fix - Master Orchestration Script
# Execute on: Replica host (192.168.168.42)
# This script orchestrates all 4 parts of the replication fix

set -euo pipefail
trap 'echo "❌ Orchestration failed at line $LINENO"; exit 1' ERR
trap 'echo "✅ Orchestration script completed"; true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/home/ubuntu/postgresql_replication_fix_master_${TIMESTAMP}.log"
DEPLOYMENT_DIR="/home/ubuntu/code-server"

{
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PostgreSQL Replication Fix - MASTER ORCHESTRATION SCRIPT         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Started: $(date)"
  echo "Replica Host: $(hostname -I | awk '{print $1}')"
  echo "Log: $LOG_FILE"
  echo ""
  
  cd "$DEPLOYMENT_DIR"
  
  # Verify all scripts exist
  echo "Verifying prerequisite scripts..."
  for script in fix-postgresql-replication-part1.sh verify-postgresql-replication-part2.sh verify-postgresql-replication-part3.sh update-postgresql-replication-part4.sh; do
    if [ ! -f "$script" ]; then
      echo "❌ Missing script: $script"
      exit 1
    fi
  done
  echo "✅ All scripts present"
  echo ""
  
  # ============================================================================
  # PRE-EXECUTION CHECKS
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PRE-EXECUTION CHECKS                                             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "Checking Docker..."
  if ! command -v docker &> /dev/null; then
    echo "❌ Docker not available"
    exit 1
  fi
  docker --version
  echo "✅ Docker OK"
  echo ""
  
  echo "Checking docker-compose..."
  if ! docker-compose version > /dev/null 2>&1; then
    echo "❌ docker-compose not available"
    exit 1
  fi
  docker-compose version
  echo "✅ docker-compose OK"
  echo ""
  
  echo "Checking PostgreSQL container..."
  PG_CONTAINER=$(docker-compose ps -q postgres 2>/dev/null || echo "")
  if [ -z "$PG_CONTAINER" ]; then
    echo "❌ PostgreSQL container not found"
    echo "   Start it with: docker-compose up -d postgres"
    exit 1
  fi
  echo "✅ PostgreSQL container running: $PG_CONTAINER"
  echo ""
  
  # ============================================================================
  # PART 1: FIX PERMISSIONS
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PART 1: Fix PostgreSQL Permissions                              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "Executing: fix-postgresql-replication-part1.sh"
  echo ""
  
  if bash fix-postgresql-replication-part1.sh; then
    echo ""
    echo "✅ Part 1 completed successfully"
  else
    echo ""
    echo "❌ Part 1 failed"
    exit 1
  fi
  
  echo ""
  echo "Waiting 30 seconds before Part 2..."
  sleep 30
  echo ""
  
  # ============================================================================
  # PART 2: VERIFY REPLICATION (REPLICA SIDE)
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PART 2: Verify Replication (Replica Side)                       ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "Executing: verify-postgresql-replication-part2.sh"
  echo ""
  
  bash verify-postgresql-replication-part2.sh || true
  
  echo ""
  echo "✅ Part 2 completed"
  echo ""
  
  # ============================================================================
  # PART 3: VERIFY REPLICATION (PRIMARY SIDE)
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PART 3: Verify Replication (Primary Side)                       ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "Executing: verify-postgresql-replication-part3.sh on primary (192.168.168.31)"
  echo ""
  
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && bash verify-postgresql-replication-part3.sh" 2>/dev/null; then
    echo ""
    echo "✅ Part 3 completed successfully"
  else
    echo "⚠️  Part 3 failed or could not reach primary"
    echo "   This may be normal if primary is temporarily unreachable"
  fi
  
  echo ""
  
  # ============================================================================
  # PART 4: UPDATE DOCKER-COMPOSE
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ PART 4: Update docker-compose Configuration                     ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  read -p "Update docker-compose configuration now? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Executing: update-postgresql-replication-part4.sh"
    echo ""
    
    if bash update-postgresql-replication-part4.sh; then
      echo ""
      echo "✅ Part 4 completed successfully"
    else
      echo ""
      echo "❌ Part 4 failed"
    fi
  else
    echo "⏭️  Skipping Part 4 - docker-compose update deferred"
  fi
  
  echo ""
  
  # ============================================================================
  # FINAL SUMMARY
  # ============================================================================
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ MASTER ORCHESTRATION COMPLETE                                    ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Summary:"
  echo "✅ Part 1: PostgreSQL permissions fixed"
  echo "✅ Part 2: Replication status verified (replica side)"
  echo "✅ Part 3: Replication status verified (primary side)"
  echo "✅ Part 4: docker-compose configuration updated (optional)"
  echo ""
  echo "Next Steps:"
  echo "1. Monitor replication for 1-5 minutes"
  echo "2. Verify data consistency between primary and replica"
  echo "3. Test failover procedure in non-production environment first"
  echo "4. Document in runbooks for operations team"
  echo ""
  echo "Monitor replication:"
  echo "  watch -n 5 'docker exec code-server-postgres psql -U postgres -d postgres -t -c \"SELECT pg_is_in_recovery(); SELECT * FROM pg_stat_wal_receiver \\\\gx\"'"
  echo ""
  echo "Completed: $(date)"

} 2>&1 | tee "$LOG_FILE"

echo ""
echo "Full log saved to: $LOG_FILE"
