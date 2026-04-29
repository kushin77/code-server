#!/bin/bash
# baseline-performance-collection.sh
# Performance Baseline Snapshot Script
# Run on Day 1 after deployment to establish baseline metrics
# Part of: Performance Optimization & Tuning Guide

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/baseline-collection.tmp 2>/dev/null || true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASELINE_FILE="baseline-performance-${TIMESTAMP}.log"

echo "=== Performance Baseline Snapshot $TIMESTAMP ===" | tee "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

# === DATABASE METRICS ===
echo "[DATABASE] Collecting database metrics..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker exec code-server-postgres psql -U postgres -c '
  SELECT 
    datname,
    pg_database_size(datname) / 1024 / 1024 / 1024 as size_gb,
    numbackends as connections
  FROM pg_stat_database
  ORDER BY size_gb DESC;
' 2>/dev/null | tee -a "$BASELINE_FILE" || echo "⚠️ Database query failed" | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === QUERY PERFORMANCE BASELINE ===
echo "[QUERIES] Top 20 slow queries..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker exec code-server-postgres psql -U postgres -c '
  SELECT 
    substring(query, 1, 50) as query_short,
    mean_exec_time::numeric(10,2) as mean_ms,
    calls,
    total_exec_time::numeric(15,2) as total_ms
  FROM pg_stat_statements
  WHERE calls > 10
  ORDER BY mean_exec_time DESC
  LIMIT 20;
' 2>/dev/null | tee -a "$BASELINE_FILE" || echo "⚠️ Query stats not available" | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === REPLICATION STATUS ===
echo "[REPLICATION] Checking replication status..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker exec code-server-postgres psql -U postgres -c '
  SELECT 
    slot_name,
    slot_type,
    active,
    wal_status
  FROM pg_replication_slots;
' 2>/dev/null | tee -a "$BASELINE_FILE" || echo "⚠️ Replication status unavailable" | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === CONTAINER STATS ===
echo "[CONTAINERS] Docker container statistics..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}' | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === SYSTEM RESOURCES ===
echo "[SYSTEM] Disk usage..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

df -h | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"
echo "[SYSTEM] Memory usage..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

free -h | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === REDIS STATS ===
echo "[REDIS] Redis memory and performance stats..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker exec code-server-redis redis-cli INFO stats 2>/dev/null | tee -a "$BASELINE_FILE" || echo "⚠️ Redis stats unavailable" | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"
echo "[REDIS] Redis memory usage..." | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"

docker exec code-server-redis redis-cli INFO memory 2>/dev/null | grep -E 'used_memory|used_memory_human|maxmemory' | tee -a "$BASELINE_FILE" || echo "⚠️ Redis memory info unavailable" | tee -a "$BASELINE_FILE"

echo "" | tee -a "$BASELINE_FILE"

# === SUMMARY ===
echo "✅ Baseline snapshot complete" | tee -a "$BASELINE_FILE"
echo "Output file: $BASELINE_FILE" | tee -a "$BASELINE_FILE"
echo "" | tee -a "$BASELINE_FILE"
echo "Use this baseline for comparison in monthly performance reviews." | tee -a "$BASELINE_FILE"
