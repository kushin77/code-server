#!/bin/bash
# Collect comprehensive performance baseline for ElevatedIQ platform
# Establishes baseline metrics for performance optimization

set -e
trap 'echo "❌ Collection failed"; exit 1' ERR

REPORT_DIR="/var/logs/performance-baseline"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

mkdir -p "$REPORT_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Performance Baseline Collection - $TIMESTAMP              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

REPORT_FILE="$REPORT_DIR/baseline_${TIMESTAMP}.txt"

{
  echo "ElevatedIQ Platform Performance Baseline"
  echo "========================================"
  echo "Timestamp: $(date -R)"
  echo ""
  
  echo "=== SYSTEM INFORMATION ==="
  echo "Primary Host: $PRIMARY"
  echo "Replica Host: $REPLICA"
  echo ""
  
} > "$REPORT_FILE"

# Collect from primary
echo "Collecting metrics from primary ($PRIMARY)..."
ssh -o BatchMode=yes akushnir@$PRIMARY << 'PRIMARY_EOF' >> "$REPORT_FILE"
echo "=== PRIMARY HOST METRICS ==="
echo ""

echo "CPU Information:"
nproc
grep "model name" /proc/cpuinfo | head -1
echo ""

echo "Memory:"
free -h | head -2
echo ""

echo "Disk:"
df -h / | tail -1
echo ""

echo "Top Processes:"
top -bn1 | head -n 15 | tail -10
echo ""

echo "Docker Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -15
echo ""

echo "Container Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -10 || echo "(stats unavailable)"
echo ""

echo "Network Connections:"
ss -s
echo ""

PRIMARY_EOF

# Collect from replica
echo "Collecting metrics from replica ($REPLICA)..."
ssh -o BatchMode=yes akushnir@$REPLICA << 'REPLICA_EOF' >> "$REPORT_FILE"
echo "=== REPLICA HOST METRICS ==="
echo ""

echo "Memory:"
free -h | head -2
echo ""

echo "Docker Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -15
echo ""

REPLICA_EOF

# Database performance
echo "Collecting database metrics..."
ssh -o BatchMode=yes akushnir@$PRIMARY << 'DB_EOF' >> "$REPORT_FILE"
echo "=== DATABASE PERFORMANCE ==="
echo ""

echo "Active Connections:"
docker exec code-server-postgres psql -U postgres -c "SELECT count(*) as active_connections FROM pg_stat_activity;" 2>/dev/null || echo "(query unavailable)"
echo ""

echo "Cache Hit Ratio:"
docker exec code-server-postgres psql -U postgres -c \
  "SELECT
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    CASE WHEN (sum(heap_blks_hit) + sum(heap_blks_read)) > 0
      THEN round(100 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)), 2)
      ELSE 0
    END as hit_ratio
   FROM pg_statio_user_tables;" 2>/dev/null || echo "(query unavailable)"
echo ""

DB_EOF

# Application metrics
echo "Collecting application health..."
ssh -o BatchMode=yes akushnir@$PRIMARY << 'APP_EOF' >> "$REPORT_FILE"
echo "=== APPLICATION HEALTH ==="
echo ""

# Test health checks
for PORT in 8080 8081 8082; do
  echo "Health check on port $PORT:"
  curl -s http://localhost:$PORT/health 2>/dev/null | head -c 100 || echo "  (unavailable)"
  echo ""
done

APP_EOF

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ Baseline collection complete                          ║"
echo "║                                                            ║"
echo "║  Report: $REPORT_FILE              ║"
echo "║  Size: $(wc -l < "$REPORT_FILE") lines                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Summary
echo "Performance Baseline Summary:"
tail -30 "$REPORT_FILE"
