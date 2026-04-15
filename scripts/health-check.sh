#!/bin/bash
# scripts/health-check.sh
# Comprehensive health check for all production services
# Runs every 10 seconds via systemd timer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

# Configuration
METRICS_FILE="/var/log/health-metrics.prom"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FAILED_SERVICES=()
HEALTH_STATUS="HEALTHY"
WARNING_COUNT=0

# Initialize metrics file
> "$METRICS_FILE"

# ============================================================================
# Helper Functions
# ============================================================================

log_metric() {
  local metric=$1
  local value=$2
  local labels=$3
  echo "${metric}${labels} ${value}" >> "$METRICS_FILE"
}

check_tcp() {
  local service=$1
  local host=$2
  local port=$3
  
  if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} $service TCP:$port"
    log_metric "health_service_up" 1 "{service=\"$service\"}"
    return 0
  else
    echo -e "${RED}✗${NC} $service TCP:$port FAILED"
    FAILED_SERVICES+=("$service")
    HEALTH_STATUS="UNHEALTHY"
    log_metric "health_service_up" 0 "{service=\"$service\"}"
    return 1
  fi
}

check_http() {
  local service=$1
  local url=$2
  local expected_code=${3:-200}
  
  http_code=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  
  if [[ "$http_code" == "$expected_code" ]]; then
    echo -e "${GREEN}✓${NC} $service HTTP:$http_code"
    log_metric "health_http_status" "$http_code" "{service=\"$service\"}"
    return 0
  else
    echo -e "${RED}✗${NC} $service HTTP:$http_code (expected $expected_code)"
    FAILED_SERVICES+=("$service")
    HEALTH_STATUS="UNHEALTHY"
    log_metric "health_http_status" "$http_code" "{service=\"$service\"}"
    return 1
  fi
}

check_database() {
  local service=$1
  local check_cmd=$2
  
  if eval "$check_cmd" &>/dev/null; then
    echo -e "${GREEN}✓${NC} $service connection"
    log_metric "health_database_connected" 1 "{service=\"$service\"}"
    return 0
  else
    echo -e "${RED}✗${NC} $service connection FAILED"
    FAILED_SERVICES+=("$service")
    HEALTH_STATUS="UNHEALTHY"
    log_metric "health_database_connected" 0 "{service=\"$service\"}"
    return 1
  fi
}

check_resource() {
  local metric=$1
  local current=$2
  local threshold=$3
  local unit=$4
  
  if [[ $current -lt $threshold ]]; then
    echo -e "${GREEN}✓${NC} $metric: $current$unit (threshold: $threshold$unit)"
    log_metric "health_${metric}_percent" "$current" ""
    return 0
  else
    echo -e "${YELLOW}⚠${NC} $metric: $current$unit (threshold: $threshold$unit)"
    HEALTH_STATUS="DEGRADED"
    WARNING_COUNT=$((WARNING_COUNT + 1))
    log_metric "health_${metric}_percent" "$current" ""
    return 1
  fi
}

# ============================================================================
# Health Check Execution
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  HEALTH CHECK REPORT - $TIMESTAMP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Service connectivity checks
echo -e "${YELLOW}→ Service Connectivity Checks:${NC}"
check_tcp "PostgreSQL" "localhost" 5432
check_tcp "Redis" "localhost" 6379
check_tcp "Code-Server" "localhost" 8080
check_tcp "Caddy" "localhost" 80
check_tcp "Prometheus" "localhost" 9090
check_tcp "Grafana" "localhost" 3000
check_tcp "Jaeger" "localhost" 16686
check_tcp "AlertManager" "localhost" 9093
echo ""

# Database connectivity checks
echo -e "${YELLOW}→ Database Connectivity:${NC}"
check_database "PostgreSQL" "docker-compose exec -T postgres psql -U codeserver -d codeserver -c 'SELECT 1;' 2>/dev/null"
check_database "Redis" "docker-compose exec -T redis redis-cli -a \"${REDIS_PASSWORD}\" ping | grep -q PONG"
echo ""

# HTTP endpoint checks
echo -e "${YELLOW}→ HTTP Endpoint Health:${NC}"
check_http "Caddy Health" "http://localhost/healthz" 200
check_http "Prometheus Health" "http://localhost:9090/-/healthy" 200
check_http "Grafana Health" "http://localhost:3000/api/health" 200
check_http "AlertManager Health" "http://localhost:9093/-/healthy" 200
echo ""

# Resource utilization checks
echo -e "${YELLOW}→ System Resources:${NC}"

# Disk usage
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
check_resource "disk_usage" "$disk_usage" "80" "%"

# Memory usage
memory_total=$(free | awk 'NR==2 {print $2}')
memory_used=$(free | awk 'NR==2 {print $3}')
memory_percent=$((memory_used * 100 / memory_total))
check_resource "memory_usage" "$memory_percent" "90" "%"

# CPU load
cpu_load=$(cat /proc/loadavg | awk '{print int($1*100)}')
check_resource "cpu_load" "$cpu_load" "85" "%"

echo ""

# Load balancer health check
echo -e "${YELLOW}→ Load Balancer (HAProxy):${NC}"
if curl -s http://localhost:8404/stats > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} HAProxy admin socket responding"
  log_metric "health_haproxy_up" 1 ""
else
  echo -e "${RED}✗${NC} HAProxy admin socket not responding"
  log_metric "health_haproxy_up" 0 ""
fi

# Check backend servers
primary_down=$(curl -s http://localhost:8404/stats | grep "primary.*DOWN" | wc -l)
replica_down=$(curl -s http://localhost:8404/stats | grep "replica.*DOWN" | wc -l)

if [[ $primary_down -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} Primary backend is UP"
  log_metric "health_backend_primary" 1 ""
else
  echo -e "${RED}✗${NC} Primary backend is DOWN"
  FAILED_SERVICES+=("primary-backend")
  HEALTH_STATUS="UNHEALTHY"
  log_metric "health_backend_primary" 0 ""
fi

if [[ $replica_down -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} Replica backend is UP"
  log_metric "health_backend_replica" 1 ""
else
  echo -e "${YELLOW}⚠${NC} Replica backend is DOWN"
  log_metric "health_backend_replica" 0 ""
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ "$HEALTH_STATUS" == "HEALTHY" ]]; then
  echo -e "${GREEN}✓ OVERALL STATUS: HEALTHY${NC}"
  echo "  All services operational, resources nominal"
  log_metric "health_status" 1 "{status=\"healthy\"}"
elif [[ "$HEALTH_STATUS" == "DEGRADED" ]]; then
  echo -e "${YELLOW}⚠ OVERALL STATUS: DEGRADED${NC}"
  echo "  Warnings: $WARNING_COUNT (see above)"
  log_metric "health_status" 2 "{status=\"degraded\"}"
else
  echo -e "${RED}✗ OVERALL STATUS: UNHEALTHY${NC}"
  echo "  Failed services: ${#FAILED_SERVICES[@]}"
  if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
    echo "  Details:"
    for service in "${FAILED_SERVICES[@]}"; do
      echo "    - $service"
    done
  fi
  log_metric "health_status" 0 "{status=\"unhealthy\"}"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Alerting
# ============================================================================

if [[ "$HEALTH_STATUS" != "HEALTHY" ]]; then
  # Only alert on unhealthy status (not degraded)
  if [[ "$HEALTH_STATUS" == "UNHEALTHY" ]]; then
    # Log to syslog
    logger -t health-check -p local0.err "Health check failed: ${#FAILED_SERVICES[@]} service(s) down"
    
    # Send Slack alert if webhook configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
      curl -X POST "$SLACK_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d @- <<EOF
{
  "text": "🚨 Health Check Alert",
  "attachments": [{
    "color": "danger",
    "title": "Services Down",
    "text": "Failed services: $(IFS=', '; echo "${FAILED_SERVICES[*]}")",
    "ts": $(date +%s)
  }]
}
EOF
    fi
  fi
fi

# Exit with appropriate code
if [[ "$HEALTH_STATUS" == "UNHEALTHY" ]]; then
  exit 1
else
  exit 0
fi
