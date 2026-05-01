#!/bin/bash
# Final Infrastructure Validation - May 1 Deployment Day
# Run this 24 hours before and 1 hour before deployment
# Usage: bash final-infrastructure-validation.sh [verbose]

set -euo pipefail

trap 'echo "Validation failed at line $LINENO"; exit 1' ERR
trap 'echo "Cleanup complete"; true' EXIT

VERBOSE="${1:-false}"
PRIMARY_IP="192.168.168.31"
REPLICA_IP="192.168.168.42"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
REPORT_FILE="infrastructure-validation-report-$(date +%Y%m%d_%H%M%S).txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
WARN=0
FAIL=0

log_header() {
  echo -e "${BLUE}=== $1 ===${NC}"
  echo "=== $1 ===" >> "$REPORT_FILE"
}

log_pass() {
  echo -e "${GREEN}✅ $1${NC}"
  echo "✅ $1" >> "$REPORT_FILE"
  PASS+=1
}

log_warn() {
  echo -e "${YELLOW}⚠️  $1${NC}"
  echo "⚠️  $1" >> "$REPORT_FILE"
  WARN+=1
}

log_fail() {
  echo -e "${RED}❌ $1${NC}"
  echo "❌ $1" >> "$REPORT_FILE"
  FAIL+=1
}

log_info() {
  echo "ℹ️  $1"
  echo "ℹ️  $1" >> "$REPORT_FILE"
}

echo "Infrastructure Validation Report" > "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"
echo "Date: $TIMESTAMP" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# ============================================================================
# SECTION 1: CONNECTIVITY TESTS
# ============================================================================
log_header "SECTION 1: Connectivity Tests"

# Test SSH to primary
if timeout 5 ssh -o ConnectTimeout=5 ubuntu@$PRIMARY_IP "echo 'SSH OK'" &>/dev/null; then
  log_pass "SSH to primary ($PRIMARY_IP)"
else
  log_fail "SSH to primary ($PRIMARY_IP)"
fi

# Test SSH to replica
if timeout 5 ssh -o ConnectTimeout=5 ubuntu@$REPLICA_IP "echo 'SSH OK'" &>/dev/null; then
  log_pass "SSH to replica ($REPLICA_IP)"
else
  log_fail "SSH to replica ($REPLICA_IP)"
fi

# Test cluster VIP
if timeout 5 ping -c 1 192.168.168.250 &>/dev/null; then
  log_pass "Cluster VIP reachable (192.168.168.250)"
else
  log_warn "Cluster VIP not currently responding (may be expected)"
fi

echo ""

# ============================================================================
# SECTION 2: CONTAINER STATUS
# ============================================================================
log_header "SECTION 2: Container Status (Primary)"

PRIMARY_CONTAINERS=$(ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker-compose ps 2>/dev/null | grep -c Up || echo 0")
if [ "$PRIMARY_CONTAINERS" -ge 43 ]; then
  log_pass "Primary containers running: $PRIMARY_CONTAINERS (expected ≥ 43)"
else
  log_fail "Primary containers running: $PRIMARY_CONTAINERS (expected ≥ 43)"
fi

REPLICA_CONTAINERS=$(ssh ubuntu@$REPLICA_IP "cd /home/ubuntu/code-server && docker-compose ps 2>/dev/null | grep -c Up || echo 0")
if [ "$REPLICA_CONTAINERS" -ge 44 ]; then
  log_pass "Replica containers running: $REPLICA_CONTAINERS (expected ≥ 44)"
else
  log_fail "Replica containers running: $REPLICA_CONTAINERS (expected ≥ 44)"
fi

TOTAL=$((PRIMARY_CONTAINERS + REPLICA_CONTAINERS))
if [ "$TOTAL" -ge 87 ]; then
  log_pass "Total containers: $TOTAL (expected ≥ 87)"
else
  log_warn "Total containers: $TOTAL (expected ≥ 87)"
fi

echo ""

# ============================================================================
# SECTION 3: POSTGRESQL REPLICATION
# ============================================================================
log_header "SECTION 3: PostgreSQL Replication Status"

# Check replica in recovery mode
REPLICA_RECOVERY=$(ssh ubuntu@$REPLICA_IP "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -t -c 'SELECT pg_is_in_recovery();' 2>/dev/null | tr -d ' ' || echo 'error'")
if [ "$REPLICA_RECOVERY" = "t" ]; then
  log_pass "Replica in recovery mode (streaming replication active)"
else
  log_fail "Replica not in recovery mode (replication inactive): $REPLICA_RECOVERY"
fi

# Check replication slots on primary
PRIMARY_SLOTS=$(ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -t -c 'SELECT COUNT(*) FROM pg_replication_slots WHERE active = true;' 2>/dev/null | tr -d ' ' || echo '0'")
if [ "$PRIMARY_SLOTS" -gt 0 ]; then
  log_pass "Primary replication slots active: $PRIMARY_SLOTS"
else
  log_warn "Primary replication slots active: $PRIMARY_SLOTS (expected > 0)"
fi

# Check replication lag
REPL_LAG=$(ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -t -c 'SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) FROM pg_stat_replication;' 2>/dev/null | head -1 | tr -d ' ' || echo 'error'")
if [[ "$REPL_LAG" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  LAG_INT=${REPL_LAG%.*}
  if [ "$LAG_INT" -lt 5 ]; then
    log_pass "Replication lag: ${REPL_LAG}s (good, < 5s)"
  elif [ "$LAG_INT" -lt 30 ]; then
    log_warn "Replication lag: ${REPL_LAG}s (acceptable, < 30s)"
  else
    log_fail "Replication lag: ${REPL_LAG}s (high, > 30s)"
  fi
else
  log_warn "Could not determine replication lag"
fi

# Check PostgreSQL connectivity on both servers
if ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -c 'SELECT 1;' &>/dev/null"; then
  log_pass "PostgreSQL primary responsive"
else
  log_fail "PostgreSQL primary not responsive"
fi

if ssh ubuntu@$REPLICA_IP "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -c 'SELECT 1;' &>/dev/null"; then
  log_pass "PostgreSQL replica responsive"
else
  log_fail "PostgreSQL replica not responsive"
fi

echo ""

# ============================================================================
# SECTION 4: REDIS STATUS
# ============================================================================
log_header "SECTION 4: Redis Status"

# Primary Redis
if ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker-compose exec -T redis redis-cli PING 2>/dev/null | grep -q PONG"; then
  log_pass "Redis primary responding (PING OK)"
else
  log_fail "Redis primary not responding to PING"
fi

# Replica Redis
if ssh ubuntu@$REPLICA_IP "cd /home/ubuntu/code-server && docker-compose exec -T redis redis-cli PING 2>/dev/null | grep -q PONG"; then
  log_pass "Redis replica responding (PING OK)"
else
  log_fail "Redis replica not responding to PING"
fi

# Redis memory check (primary)
REDIS_MEM=$(ssh ubuntu@$PRIMARY_IP "cd /home/ubuntu/code-server && docker-compose exec -T redis redis-cli INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 || echo 'error'")
if [[ ! "$REDIS_MEM" =~ "error" ]]; then
  log_pass "Redis primary memory: $REDIS_MEM"
else
  log_warn "Could not determine Redis memory usage"
fi

echo ""

# ============================================================================
# SECTION 5: API SERVER STATUS
# ============================================================================
log_header "SECTION 5: API Server Status"

# Health check
API_HEALTH=$(curl -s http://$PRIMARY_IP:8000/health 2>/dev/null | grep -o 'healthy\|unhealthy\|error' || echo 'error')
if [ "$API_HEALTH" = "healthy" ]; then
  log_pass "API health check: healthy"
else
  log_warn "API health check: $API_HEALTH"
fi

# Response time test
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$PRIMARY_IP:8000/health 2>/dev/null || echo '000')
if [ "$API_RESPONSE" = "200" ]; then
  log_pass "API HTTP response: 200 OK"
else
  log_warn "API HTTP response: $API_RESPONSE"
fi

echo ""

# ============================================================================
# SECTION 6: MONITORING & ALERTING
# ============================================================================
log_header "SECTION 6: Monitoring & Alerting"

# Prometheus targets
PROM_TARGETS=$(curl -s http://$PRIMARY_IP:9090/api/v1/targets 2>/dev/null | grep -o '"health":"up"' | wc -l || echo '0')
if [ "$PROM_TARGETS" -gt 0 ]; then
  log_pass "Prometheus targets up: $PROM_TARGETS"
else
  log_warn "Prometheus targets: Unable to verify"
fi

# Grafana accessibility
if curl -s http://$PRIMARY_IP:3000 2>/dev/null | grep -q "Grafana"; then
  log_pass "Grafana dashboard accessible"
else
  log_warn "Grafana dashboard: Unable to verify"
fi

# AlertManager accessibility
if curl -s http://$PRIMARY_IP:9093 2>/dev/null | grep -q "Alertmanager"; then
  log_pass "AlertManager accessible"
else
  log_warn "AlertManager: Unable to verify"
fi

echo ""

# ============================================================================
# SECTION 7: BACKUP STATUS
# ============================================================================
log_header "SECTION 7: Backup Status"

# Check backup script existence
if ssh ubuntu@$PRIMARY_IP "test -f /home/ubuntu/code-server/backup-postgresql.sh && test -x /home/ubuntu/code-server/backup-postgresql.sh"; then
  log_pass "PostgreSQL backup script exists and is executable"
else
  log_fail "PostgreSQL backup script missing or not executable"
fi

if ssh ubuntu@$PRIMARY_IP "test -f /home/ubuntu/code-server/backup-redis.sh && test -x /home/ubuntu/code-server/backup-redis.sh"; then
  log_pass "Redis backup script exists and is executable"
else
  log_fail "Redis backup script missing or not executable"
fi

# Check backup directories
if ssh ubuntu@$PRIMARY_IP "test -d /backups/postgresql && test -d /backups/redis"; then
  log_pass "Backup directories exist"
else
  log_warn "Backup directories may not be properly initialized"
fi

# Check recent backups
RECENT_PG_BACKUP=$(ssh ubuntu@$PRIMARY_IP "find /backups/postgresql -name 'backup_*.dump' -mtime -1 2>/dev/null | wc -l || echo 0")
if [ "$RECENT_PG_BACKUP" -gt 0 ]; then
  log_pass "Recent PostgreSQL backups found: $RECENT_PG_BACKUP"
else
  log_warn "No recent PostgreSQL backups found (check if scheduled)"
fi

echo ""

# ============================================================================
# SECTION 8: DISK SPACE
# ============================================================================
log_header "SECTION 8: Disk Space"

# Primary root disk
PRIMARY_DISK=$(ssh ubuntu@$PRIMARY_IP "df -h / 2>/dev/null | tail -1 | awk '{print \$5}' | sed 's/%//' || echo '999'")
if [ "$PRIMARY_DISK" -lt 80 ]; then
  log_pass "Primary root disk usage: ${PRIMARY_DISK}% (good)"
elif [ "$PRIMARY_DISK" -lt 90 ]; then
  log_warn "Primary root disk usage: ${PRIMARY_DISK}% (monitor)"
else
  log_fail "Primary root disk usage: ${PRIMARY_DISK}% (critical)"
fi

# Replica root disk
REPLICA_DISK=$(ssh ubuntu@$REPLICA_IP "df -h / 2>/dev/null | tail -1 | awk '{print \$5}' | sed 's/%//' || echo '999'")
if [ "$REPLICA_DISK" -lt 80 ]; then
  log_pass "Replica root disk usage: ${REPLICA_DISK}% (good)"
elif [ "$REPLICA_DISK" -lt 90 ]; then
  log_warn "Replica root disk usage: ${REPLICA_DISK}% (monitor)"
else
  log_fail "Replica root disk usage: ${REPLICA_DISK}% (critical)"
fi

echo ""

# ============================================================================
# SECTION 9: MEMORY & CPU
# ============================================================================
log_header "SECTION 9: Memory & CPU"

# Primary memory
PRIMARY_MEM=$(ssh ubuntu@$PRIMARY_IP "free -h 2>/dev/null | grep Mem | awk '{print \$3\"/\"\$2}' || echo 'unknown'")
log_info "Primary memory usage: $PRIMARY_MEM"

# Replica memory
REPLICA_MEM=$(ssh ubuntu@$REPLICA_IP "free -h 2>/dev/null | grep Mem | awk '{print \$3\"/\"\$2}' || echo 'unknown'")
log_info "Replica memory usage: $REPLICA_MEM"

# Primary load
PRIMARY_LOAD=$(ssh ubuntu@$PRIMARY_IP "uptime 2>/dev/null | awk -F'load average:' '{print \$2}' || echo 'unknown'")
log_info "Primary load average: $PRIMARY_LOAD"

# Replica load
REPLICA_LOAD=$(ssh ubuntu@$REPLICA_IP "uptime 2>/dev/null | awk -F'load average:' '{print \$2}' || echo 'unknown'")
log_info "Replica load average: $REPLICA_LOAD"

echo ""

# ============================================================================
# SECTION 10: FINAL SUMMARY
# ============================================================================
log_header "FINAL VALIDATION SUMMARY"

TOTAL_CHECKS=$((PASS + WARN + FAIL))
echo ""
echo -e "${GREEN}✅ Passed: $PASS${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARN${NC}"
echo -e "${RED}❌ Failed: $FAIL${NC}"
echo "Total checks: $TOTAL_CHECKS"
echo ""

echo "✅ Passed: $PASS" >> "$REPORT_FILE"
echo "⚠️  Warnings: $WARN" >> "$REPORT_FILE"
echo "❌ Failed: $FAIL" >> "$REPORT_FILE"
echo "Total checks: $TOTAL_CHECKS" >> "$REPORT_FILE"

# Determine overall status
if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo -e "${GREEN}🚀 Infrastructure Status: READY FOR DEPLOYMENT${NC}"
  echo "" >> "$REPORT_FILE"
  echo "🚀 Infrastructure Status: READY FOR DEPLOYMENT" >> "$REPORT_FILE"
  EXIT_CODE=0
elif [ "$FAIL" -lt 3 ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Infrastructure Status: PROCEED WITH CAUTION${NC}"
  echo "Investigate failed items before proceeding"
  echo "" >> "$REPORT_FILE"
  echo "⚠️  Infrastructure Status: PROCEED WITH CAUTION" >> "$REPORT_FILE"
  EXIT_CODE=1
else
  echo ""
  echo -e "${RED}❌ Infrastructure Status: DO NOT DEPLOY${NC}"
  echo "Fix critical issues before proceeding"
  echo "" >> "$REPORT_FILE"
  echo "❌ Infrastructure Status: DO NOT DEPLOY" >> "$REPORT_FILE"
  EXIT_CODE=1
fi

echo ""
echo "Report saved: $REPORT_FILE"
echo "Report saved: $REPORT_FILE" >> "$REPORT_FILE"

exit $EXIT_CODE
