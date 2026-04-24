#!/usr/bin/env bash
# @file        scripts/performance/analyze-query-performance.sh
# @module      performance/analysis
# @description Phase 8 — PostgreSQL slow query analysis via pg_stat_statements
#
# Usage: bash scripts/performance/analyze-query-performance.sh [--top N] [--reset]
# Requires: pg_stat_statements extension installed (config/postgres/postgres-tuning.sql)
# On-prem: ssh akushnir@192.168.168.31 'cd code-server-enterprise && bash scripts/performance/analyze-query-performance.sh'
#
set -euo pipefail

# shellcheck source=scripts/_common/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../_common/logging.sh"

# ─── Config ──────────────────────────────────────────────────────────────────
TOP_N="${TOP_N:-20}"
RESET_STATS="${RESET_STATS:-false}"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${POSTGRES_USER:-codeserver}"
PG_DB="${POSTGRES_DB:-codeserver}"
PG_PASSWORD="${POSTGRES_PASSWORD:-}"
OUTPUT_DIR="/tmp/perf-reports"
REPORT_FILE="${OUTPUT_DIR}/query-analysis-$(date +%Y%m%d-%H%M%S).txt"

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --top) TOP_N="$2"; shift 2 ;;
    --reset) RESET_STATS="true"; shift ;;
    --host) PG_HOST="$2"; shift 2 ;;
    *) log_warn "Unknown arg: $1"; shift ;;
  esac
done

# ─── Verify running on correct host ──────────────────────────────────────────
EXPECTED_HOST="192.168.168.31"
ACTUAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
if [[ "${ACTUAL_IP}" != "${EXPECTED_HOST}" ]]; then
  log_warn "Not on production host (${ACTUAL_IP}). Run via SSH: ssh akushnir@${EXPECTED_HOST}"
  log_info "Continuing anyway — using PG_HOST=${PG_HOST}"
fi

# ─── PGPASSWORD for non-interactive psql ─────────────────────────────────────
export PGPASSWORD="${PG_PASSWORD}"
PSQL="docker exec -e PGPASSWORD=${PGPASSWORD} postgres psql -U ${PG_USER} -d ${PG_DB} -t -A"

mkdir -p "${OUTPUT_DIR}"

# ─── Check pg_stat_statements ────────────────────────────────────────────────
log_info "Checking pg_stat_statements availability..."
EXT_CHECK=$($PSQL -c "SELECT COUNT(*) FROM pg_extension WHERE extname='pg_stat_statements';" 2>&1 || echo "0")
if [[ "${EXT_CHECK}" == "0" || "${EXT_CHECK}" =~ "error" ]]; then
  log_error "pg_stat_statements not installed. Run: psql -f config/postgres/postgres-tuning.sql"
  exit 1
fi
log_info "pg_stat_statements available."

# ─── Report header ───────────────────────────────────────────────────────────
{
  echo "═══════════════════════════════════════════════════════════════"
  echo " PostgreSQL Query Performance Report"
  echo " Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo " Host: ${PG_HOST}:${PG_PORT} DB: ${PG_DB}"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
} | tee "${REPORT_FILE}"

# ─── Section 1: Top slow queries by total time ───────────────────────────────
log_info "Section 1: Top ${TOP_N} queries by total execution time..."
{
  echo "── TOP ${TOP_N} QUERIES BY TOTAL TIME ──────────────────────────────────────"
  $PSQL -c "
    SELECT
      calls,
      ROUND(total_exec_time::numeric, 2) AS total_ms,
      ROUND(mean_exec_time::numeric, 2)  AS mean_ms,
      ROUND(stddev_exec_time::numeric, 2) AS stddev_ms,
      ROUND((total_exec_time / sum(total_exec_time) OVER ()) * 100, 1) AS pct_total,
      LEFT(query, 120) AS query_snippet
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT ${TOP_N};
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 2: Top slow queries by mean time ────────────────────────────────
log_info "Section 2: Top ${TOP_N} queries by mean execution time..."
{
  echo "── TOP ${TOP_N} QUERIES BY MEAN TIME (min 10 calls) ────────────────────────"
  $PSQL -c "
    SELECT
      calls,
      ROUND(mean_exec_time::numeric, 2) AS mean_ms,
      ROUND(min_exec_time::numeric, 2)  AS min_ms,
      ROUND(max_exec_time::numeric, 2)  AS max_ms,
      LEFT(query, 120) AS query_snippet
    FROM pg_stat_statements
    WHERE calls >= 10
    ORDER BY mean_exec_time DESC
    LIMIT ${TOP_N};
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 3: High row scan queries (index candidates) ─────────────────────
log_info "Section 3: Queries with high row scans (index candidates)..."
{
  echo "── HIGH ROW SCAN QUERIES (index optimization candidates) ───────────────────"
  $PSQL -c "
    SELECT
      calls,
      ROUND(rows::numeric / NULLIF(calls, 0), 0) AS avg_rows,
      rows AS total_rows,
      LEFT(query, 120) AS query_snippet
    FROM pg_stat_statements
    WHERE calls > 5
    ORDER BY rows DESC
    LIMIT ${TOP_N};
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 4: Cache hit ratio ──────────────────────────────────────────────
log_info "Section 4: Buffer cache hit ratio..."
{
  echo "── BUFFER CACHE HIT RATIO ──────────────────────────────────────────────────"
  $PSQL -c "
    SELECT
      schemaname,
      relname AS table_name,
      heap_blks_hit AS cache_hits,
      heap_blks_read AS disk_reads,
      CASE
        WHEN (heap_blks_hit + heap_blks_read) > 0
        THEN ROUND(heap_blks_hit::numeric / (heap_blks_hit + heap_blks_read) * 100, 2)
        ELSE 100
      END AS cache_hit_pct
    FROM pg_statio_user_tables
    WHERE (heap_blks_hit + heap_blks_read) > 0
    ORDER BY cache_hit_pct ASC
    LIMIT 20;
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 5: Index usage ───────────────────────────────────────────────────
log_info "Section 5: Tables missing or underusing indexes..."
{
  echo "── SEQUENTIAL SCAN CANDIDATES (no or unused indexes) ──────────────────────"
  $PSQL -c "
    SELECT
      schemaname,
      relname AS table_name,
      seq_scan,
      idx_scan,
      seq_tup_read,
      CASE
        WHEN (seq_scan + idx_scan) > 0
        THEN ROUND(idx_scan::numeric / (seq_scan + idx_scan) * 100, 1)
        ELSE 0
      END AS idx_use_pct
    FROM pg_stat_user_tables
    WHERE seq_scan > 0
    ORDER BY seq_scan DESC
    LIMIT 20;
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 6: Connection stats ──────────────────────────────────────────────
{
  echo "── CURRENT CONNECTION STATS ────────────────────────────────────────────────"
  $PSQL -c "
    SELECT
      state,
      wait_event_type,
      wait_event,
      COUNT(*) AS count
    FROM pg_stat_activity
    WHERE datname = '${PG_DB}'
    GROUP BY state, wait_event_type, wait_event
    ORDER BY count DESC;
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Section 7: Bloat estimate ────────────────────────────────────────────────
{
  echo "── TABLE BLOAT ESTIMATE ────────────────────────────────────────────────────"
  $PSQL -c "
    SELECT
      schemaname,
      relname AS table_name,
      n_dead_tup AS dead_tuples,
      n_live_tup AS live_tuples,
      CASE
        WHEN n_live_tup > 0
        THEN ROUND(n_dead_tup::numeric / n_live_tup * 100, 1)
        ELSE 0
      END AS bloat_pct,
      last_autovacuum,
      last_autoanalyze
    FROM pg_stat_user_tables
    WHERE n_live_tup > 100
    ORDER BY bloat_pct DESC
    LIMIT 10;
  " 2>&1
  echo ""
} | tee -a "${REPORT_FILE}"

# ─── Optional: Reset stats ────────────────────────────────────────────────────
if [[ "${RESET_STATS}" == "true" ]]; then
  log_warn "Resetting pg_stat_statements (--reset flag set)..."
  $PSQL -c "SELECT pg_stat_statements_reset();" 2>&1
  log_info "Stats reset."
fi

# ─── Footer ───────────────────────────────────────────────────────────────────
{
  echo "═══════════════════════════════════════════════════════════════"
  echo " Report complete. Full output: ${REPORT_FILE}"
  echo " Next step: review slow queries and run EXPLAIN ANALYZE on top offenders"
  echo "═══════════════════════════════════════════════════════════════"
} | tee -a "${REPORT_FILE}"

log_info "Query analysis saved to ${REPORT_FILE}"
