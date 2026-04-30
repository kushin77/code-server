#!/bin/bash
#
# @file monthly-recovery-test.sh
# @module backup
# @description Monthly automated recovery testing from backup
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'log_error "Recovery test failed at line $LINENO"; exit 1' ERR

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily}"
TEST_RECOVERY_DIR="/tmp/code-server-recovery-test"
LOG_FILE="/var/log/code-server-recovery-test.log"

# PostgreSQL settings
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# RECOVERY TEST FUNCTIONS
# ============================================================================

test_postgres_recovery() {
  log_info "Testing PostgreSQL recovery..."
  
  # Find random backup from last 7 days
  local BACKUP=$(find "${BACKUP_DIR}/postgres" -mtime -7 -name "postgres_backup_*.sql.gz" -type f | shuf | head -1)
  
  if [ -z "$BACKUP" ]; then
    log_error "No PostgreSQL backups found from last 7 days"
    return 1
  fi
  
  log_info "Using backup: $(basename $BACKUP)"
  
  # Create test database
  local TEST_DB="restore_test_$(date +%s)"
  log_info "Creating test database: $TEST_DB"
  
  export PGPASSWORD="$POSTGRES_PASSWORD"
  
  if ! createdb -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" "$TEST_DB"; then
    log_error "Failed to create test database"
    return 1
  fi
  
  # Restore backup
  log_info "Restoring backup to test database..."
  if ! pg_restore \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$TEST_DB" \
    --exit-on-error \
    "$BACKUP" 2>&1 | tee -a "$LOG_FILE"; then
    
    log_error "Failed to restore backup"
    dropdb -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" "$TEST_DB" 2>/dev/null || true
    return 1
  fi
  
  # Verify restored data
  log_info "Verifying restored data..."
  local TABLE_COUNT=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
  
  if [ "$TABLE_COUNT" -gt 0 ]; then
    log_success "PostgreSQL recovery test passed: $TABLE_COUNT tables restored"
  else
    log_error "PostgreSQL recovery test failed: no tables found"
    dropdb -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" "$TEST_DB" 2>/dev/null || true
    return 1
  fi
  
  # Cleanup test database
  log_info "Cleaning up test database..."
  dropdb -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" "$TEST_DB"
  
  log_success "PostgreSQL recovery test completed successfully"
  return 0
}

test_redis_recovery() {
  log_info "Testing Redis recovery..."
  
  # Find random backup from last 7 days
  local BACKUP=$(find "${BACKUP_DIR}/redis" -mtime -7 -name "redis_backup_*.rdb.gz" -type f | shuf | head -1)
  
  if [ -z "$BACKUP" ]; then
    log_error "No Redis backups found from last 7 days"
    return 1
  fi
  
  log_info "Using backup: $(basename $BACKUP)"
  
  # Verify backup can be decompressed
  log_info "Verifying Redis backup integrity..."
  if ! gunzip -t "$BACKUP" >/dev/null 2>&1; then
    log_error "Redis backup failed integrity check"
    return 1
  fi
  
  log_success "Redis backup integrity verified"
  return 0
}

test_volume_recovery() {
  log_info "Testing volume recovery..."
  
  # Find random backup from last 7 days
  local BACKUP=$(find "${BACKUP_DIR}/volumes" -mtime -7 -name "*_*.tar.gz" -type f | shuf | head -1)
  
  if [ -z "$BACKUP" ]; then
    log_error "No volume backups found from last 7 days"
    return 1
  fi
  
  log_info "Using backup: $(basename $BACKUP)"
  
  # Verify backup can be extracted
  log_info "Verifying volume backup integrity..."
  
  mkdir -p "$TEST_RECOVERY_DIR"
  
  if ! tar -tzf "$BACKUP" >/dev/null 2>&1; then
    log_error "Volume backup failed integrity check"
    rm -rf "$TEST_RECOVERY_DIR"
    return 1
  fi
  
  log_success "Volume backup integrity verified"
  rm -rf "$TEST_RECOVERY_DIR"
  return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_info "Starting monthly recovery test..."
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Run recovery tests
if test_postgres_recovery; then
  ((TESTS_PASSED++))
else
  ((TESTS_FAILED++))
fi

if test_redis_recovery; then
  ((TESTS_PASSED++))
else
  ((TESTS_FAILED++))
fi

if test_volume_recovery; then
  ((TESTS_PASSED++))
else
  ((TESTS_FAILED++))
fi

# Print summary
echo ""
echo "┌────────────────────────────────────────────┐"
echo "│ Monthly Recovery Test Summary              │"
echo "├────────────────────────────────────────────┤"
echo "│ Tests Passed:   $TESTS_PASSED"
echo "│ Tests Failed:   $TESTS_FAILED"
echo "│ Status:         $([ $TESTS_FAILED -eq 0 ] && echo '✅ SUCCESS' || echo '❌ FAILURE')"
echo "├────────────────────────────────────────────┤"
echo "│ Date:           $(date +'%Y-%m-%d %H:%M:%S')"
echo "│ Log:            $LOG_FILE"
echo "└────────────────────────────────────────────┘"
echo ""

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
  exit 1
else
  exit 0
fi
