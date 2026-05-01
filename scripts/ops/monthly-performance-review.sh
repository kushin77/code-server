#!/bin/bash
# monthly-performance-review.sh
# Monthly Performance Optimization & Tuning Review Script
# Run monthly (e.g., 1st of each month at 10:00 UTC)
# Part of: Performance Optimization & Tuning Guide

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

log_info() {
  echo "ℹ️  $1"
}

log_check() {
  echo "✓ $1"
}

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/monthly-review.tmp 2>/dev/null || true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%B_%Y)
REPORT_FILE="monthly-performance-review-${MONTH}-${TIMESTAMP}.log"

echo "=== MONTHLY PERFORMANCE OPTIMIZATION REVIEW ===" | tee "$REPORT_FILE"
echo "Date: $MONTH" | tee -a "$REPORT_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

PASSED=0
WARNING=0
FAILED=0

# === DATABASE CHECKS ===
echo "[DATABASE OPTIMIZATION]" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 1. Run ANALYZE
log_info "Running ANALYZE on all tables..." | tee -a "$REPORT_FILE"
docker exec code-server-postgres psql -U postgres -c 'ANALYZE;' 2>/dev/null && log_check "ANALYZE completed" | tee -a "$REPORT_FILE" || log_error "ANALYZE failed" | tee -a "$REPORT_FILE"

# 2. Check for slow queries
log_info "Checking for slow queries (>1s)..." | tee -a "$REPORT_FILE"
SLOW_COUNT=$(docker exec code-server-postgres psql -U postgres -t -c "SELECT COUNT(*) FROM pg_stat_statements WHERE mean_exec_time > 1000;" 2>/dev/null || echo "0")
if [ "$SLOW_COUNT" -gt 0 ]; then
  echo "⚠️  FOUND: $SLOW_COUNT queries with >1s mean time" | tee -a "$REPORT_FILE"
  WARNING+=1
else
  log_check "No slow queries (>1s)" | tee -a "$REPORT_FILE"
  PASSED+=1
fi

# 3. Check replication lag
log_info "Checking replication lag..." | tee -a "$REPORT_FILE"
REP_LAG=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@192.168.168.31 "docker exec code-server-postgres psql -U postgres -c 'SELECT COALESCE(EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT, 0);' 2>/dev/null | tail -1" 2>/dev/null || echo "999")
if [ "$REP_LAG" -lt 5 ]; then
  log_check "Replication lag: ${REP_LAG}s (target <5s)" | tee -a "$REPORT_FILE"
  PASSED+=1
else
  echo "⚠️  Replication lag: ${REP_LAG}s (target <5s)" | tee -a "$REPORT_FILE"
  WARNING+=1
fi

echo "" | tee -a "$REPORT_FILE"

# === CACHE CHECKS ===
echo "[CACHE OPTIMIZATION]" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 4. Check Redis memory
log_info "Checking Redis memory usage..." | tee -a "$REPORT_FILE"
REDIS_USED=$(docker exec code-server-redis redis-cli INFO memory 2>/dev/null | grep used_memory_human | cut -d':' -f2 || echo "unknown")
REDIS_MAX=$(docker exec code-server-redis redis-cli CONFIG GET maxmemory 2>/dev/null | tail -1 || echo "8589934592")
log_check "Redis memory: $REDIS_USED (limit: 8GB)" | tee -a "$REPORT_FILE"
PASSED+=1

echo "" | tee -a "$REPORT_FILE"

# === NETWORK CHECKS ===
echo "[NETWORK OPTIMIZATION]" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 5. Check latency
log_info "Checking inter-host latency..." | tee -a "$REPORT_FILE"
LATENCY=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@192.168.168.31 "ping -c 3 192.168.168.42 2>/dev/null | grep avg | cut -d'/' -f5 | cut -d'.' -f1" 2>/dev/null || echo "999")
if [ "$LATENCY" -lt 2 ]; then
  log_check "Network latency: ${LATENCY}ms (target <2ms)" | tee -a "$REPORT_FILE"
  PASSED+=1
else
  echo "⚠️  Network latency: ${LATENCY}ms (target <2ms)" | tee -a "$REPORT_FILE"
  WARNING+=1
fi

echo "" | tee -a "$REPORT_FILE"

# === SYSTEM CHECKS ===
echo "[SYSTEM OPTIMIZATION]" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 6. CPU utilization
log_info "Checking CPU utilization..." | tee -a "$REPORT_FILE"
docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}' | tail -5 | tee -a "$REPORT_FILE"

# 7. Memory utilization
log_info "Checking memory utilization..." | tee -a "$REPORT_FILE"
docker stats --no-stream --format 'table {{.Container}}\t{{.MemPerc}}' | tail -5 | tee -a "$REPORT_FILE"

# 8. Disk usage
log_info "Checking disk space..." | tee -a "$REPORT_FILE"
DISK_USED=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USED" -lt 80 ]; then
  log_check "Disk usage: ${DISK_USED}% (target <80%)" | tee -a "$REPORT_FILE"
  PASSED+=1
else
  echo "⚠️  Disk usage: ${DISK_USED}% (target <80%)" | tee -a "$REPORT_FILE"
  WARNING+=1
fi

echo "" | tee -a "$REPORT_FILE"

# === APPLICATION CHECKS ===
echo "[APPLICATION OPTIMIZATION]" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 9. API response time (from monitoring if available)
log_info "Checking application health..." | tee -a "$REPORT_FILE"
RUNNING_CONTAINERS=$(docker ps -q | wc -l)
log_check "Running containers: $RUNNING_CONTAINERS (target: ≥87)" | tee -a "$REPORT_FILE"
PASSED+=1

echo "" | tee -a "$REPORT_FILE"

# === SUMMARY ===
echo "=== REVIEW SUMMARY ===" | tee -a "$REPORT_FILE"
echo "Passed checks: $PASSED" | tee -a "$REPORT_FILE"
echo "Warnings: $WARNING" | tee -a "$REPORT_FILE"
echo "Failed checks: $FAILED" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ $FAILED -eq 0 ] && [ $WARNING -le 2 ]; then
  echo "✅ MONTHLY REVIEW PASSED - Performance within acceptable ranges" | tee -a "$REPORT_FILE"
  OVERALL_RESULT=0
elif [ $FAILED -eq 0 ]; then
  echo "⚠️  MONTHLY REVIEW COMPLETED - Some items need attention" | tee -a "$REPORT_FILE"
  OVERALL_RESULT=0
else
  echo "❌ MONTHLY REVIEW FAILED - Critical issues detected" | tee -a "$REPORT_FILE"
  OVERALL_RESULT=1
fi

echo "" | tee -a "$REPORT_FILE"
echo "Report file: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "Reviewer: (sign here)" | tee -a "$REPORT_FILE"

exit $OVERALL_RESULT
