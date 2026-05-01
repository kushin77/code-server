#!/bin/bash
# Performance bottleneck identification and analysis
# Profiles platform to identify performance issues

set -e
trap 'echo "❌ Analysis failed"; exit 1' ERR

ANALYSIS_DIR="/var/logs/performance-analysis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRIMARY="192.168.168.31"

mkdir -p "$ANALYSIS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Performance Bottleneck Analysis - $TIMESTAMP              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

REPORT_FILE="$ANALYSIS_DIR/bottleneck_${TIMESTAMP}.txt"

{
  echo "Performance Bottleneck Analysis"
  echo "==============================="
  echo "Timestamp: $(date -R)"
  echo ""
  
} > "$REPORT_FILE"

# CPU Analysis
echo "Analyzing CPU usage..."
{
  echo "=== CPU ANALYSIS ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY top -bn2 -d 0.5 | grep "Cpu(s)"
  echo ""
  
  echo "Top CPU consumers:"
  ssh -o BatchMode=yes akushnir@$PRIMARY top -bn1 -o %CPU | head -15
  echo ""
  
} >> "$REPORT_FILE"

# Memory Analysis
echo "Analyzing memory usage..."
{
  echo "=== MEMORY ANALYSIS ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY free -h
  echo ""
  
  echo "Top memory consumers:"
  ssh -o BatchMode=yes akushnir@$PRIMARY top -bn1 -o %MEM | head -15
  echo ""
  
} >> "$REPORT_FILE"

# Disk I/O Analysis
echo "Analyzing disk I/O..."
{
  echo "=== DISK I/O ANALYSIS ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY iostat -dx 1 1 | tail -15
  echo ""
  
} >> "$REPORT_FILE"

# Network Analysis
echo "Analyzing network..."
{
  echo "=== NETWORK ANALYSIS ==="
  echo "Network statistics:"
  ssh -o BatchMode=yes akushnir@$PRIMARY ss -s
  echo ""
  
  echo "Active connections:"
  ssh -o BatchMode=yes akushnir@$PRIMARY ss -tan | grep ESTABLISHED | wc -l
  echo ""
  
} >> "$REPORT_FILE"

# Database Slow Queries
echo "Analyzing slow queries..."
{
  echo "=== DATABASE SLOW QUERIES ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY docker exec code-server-postgres psql -U postgres -c \
    "SELECT
      left(query, 80) as query,
      calls,
      mean_time::numeric(10,2) as mean_ms,
      max_time::numeric(10,2) as max_ms
     FROM pg_stat_statements
     WHERE query NOT LIKE '%pg_stat%'
     ORDER BY mean_time DESC
     LIMIT 10;" 2>/dev/null || echo "  (query stats unavailable)"
  echo ""
  
} >> "$REPORT_FILE"

# Index Analysis
echo "Analyzing indexes..."
{
  echo "=== INDEX ANALYSIS ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY docker exec code-server-postgres psql -U postgres -c \
    "SELECT
      schemaname,
      tablename,
      indexname,
      idx_scan as scans,
      idx_tup_read as tuples_read,
      idx_tup_fetch as tuples_fetched
     FROM pg_stat_user_indexes
     ORDER BY idx_scan DESC
     LIMIT 10;" 2>/dev/null || echo "  (index stats unavailable)"
  echo ""
  
} >> "$REPORT_FILE"

# Container Analysis
echo "Analyzing containers..."
{
  echo "=== CONTAINER RESOURCE USAGE ==="
  ssh -o BatchMode=yes akushnir@$PRIMARY docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | head -15 || echo "  (stats unavailable)"
  echo ""
  
} >> "$REPORT_FILE"

# Bottleneck Summary
{
  echo ""
  echo "=== BOTTLENECK SUMMARY ==="
  echo ""
  echo "High CPU Consumers:"
  ssh -o BatchMode=yes akushnir@$PRIMARY top -bn1 | awk 'NR>7 && $9>50 {print "  "$12": "$9"%"}' | head -5 || echo "  (None detected)"
  echo ""
  
  echo "High Memory Consumers:"
  ssh -o BatchMode=yes akushnir@$PRIMARY ps aux --sort=-%mem | awk 'NR>1 && NR<6 {printf "  %-30s: %.1f%% (%.0fMB)\n", $11, $4, $6/1024}' || echo "  (None detected)"
  echo ""
  
  echo "Recommendations:"
  echo "  1. Review slow query results and add indexes"
  echo "  2. Check memory-heavy containers for leaks"
  echo "  3. Optimize database connection pools"
  echo "  4. Implement caching for high-volume queries"
  echo ""
  
} >> "$REPORT_FILE"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ Bottleneck analysis complete                          ║"
echo "║                                                            ║"
echo "║  Report: $REPORT_FILE"
echo "║  Summary:"
grep "High CPU" "$REPORT_FILE" -A 10 | head -5
echo "╚════════════════════════════════════════════════════════════╝"
