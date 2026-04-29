#!/usr/bin/env bash
###############################################################################
# @file scripts/ops/post-deployment-validation.sh
# @module operations
# @description Comprehensive post-deployment validation suite
# @governance GOV-002: All deployments must pass validation
# @author Infrastructure Audit Bot
# @date 2026-04-28
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Load common functions
source "${SCRIPT_DIR}/../_common/init.sh" 2>/dev/null || {
  log_info() { echo "[INFO] $*"; }
  log_error() { echo "[ERROR] $*" >&2; }
  log_success() { echo "[SUCCESS] $*"; }
}

# Counters
CHECKS_TOTAL=0
CHECKS_PASS=0
CHECKS_FAIL=0
CHECKS_WARN=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

###############################################################################
# Validation Functions
###############################################################################

check_service_running() {
  local service=$1
  ((CHECKS_TOTAL++))
  
  if docker-compose ps | grep -q "^.*$service.*Up"; then
    log_success "Service running: $service"
    ((CHECKS_PASS++))
    return 0
  else
    log_error "Service not running: $service"
    ((CHECKS_FAIL++))
    return 1
  fi
}

check_port_listening() {
  local port=$1
  local service=$2
  ((CHECKS_TOTAL++))
  
  if nc -zv localhost "$port" &>/dev/null; then
    log_success "Port listening: $port ($service)"
    ((CHECKS_PASS++))
    return 0
  else
    log_error "Port not listening: $port ($service)"
    ((CHECKS_FAIL++))
    return 1
  fi
}

check_endpoint_healthy() {
  local url=$1
  local expected_code=${2:-200}
  local description=$3
  ((CHECKS_TOTAL++))
  
  local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  
  if [[ "$response" == "$expected_code" ]]; then
    log_success "Endpoint healthy: $description"
    ((CHECKS_PASS++))
    return 0
  else
    log_error "Endpoint unhealthy: $description (got $response, expected $expected_code)"
    ((CHECKS_FAIL++))
    return 1
  fi
}

check_service_logs() {
  local service=$1
  ((CHECKS_TOTAL++))
  
  local error_count=$(docker-compose logs "$service" 2>/dev/null | grep -iE "ERROR|FATAL|PANIC" | wc -l)
  
  if [[ $error_count -eq 0 ]]; then
    log_success "Service logs clean: $service"
    ((CHECKS_PASS++))
    return 0
  else
    log_error "Service logs contain errors: $service ($error_count errors found)"
    ((CHECKS_FAIL++))
    return 1
  fi
}

###############################################################################
# Main Validation Suite
###############################################################################

main() {
  log_info "=== Post-Deployment Validation Suite ==="
  log_info "Starting comprehensive deployment validation..."
  echo ""
  
  # Check Docker daemon
  if ! docker ps > /dev/null 2>&1; then
    log_error "Docker daemon not accessible"
    return 1
  fi
  
  # Check docker-compose file
  if ! docker-compose config > /dev/null 2>&1; then
    log_error "Docker Compose configuration invalid"
    return 1
  fi
  
  log_info "=== Service Running Checks ==="
  check_service_running "code-server-caddy"
  check_service_running "code-server-postgres-db"
  check_service_running "code-server-redis-cache"
  check_service_running "code-server-redpanda-broker"
  check_service_running "code-server-prometheus"
  check_service_running "code-server-grafana"
  check_service_running "code-server-opa-service"
  check_service_running "code-server-oauth2-proxy"
  
  echo ""
  log_info "=== Port Availability Checks ==="
  check_port_listening 80 "HTTP"
  check_port_listening 443 "HTTPS"
  check_port_listening 5432 "PostgreSQL"
  check_port_listening 6379 "Redis"
  check_port_listening 9090 "Prometheus"
  check_port_listening 3000 "Grafana"
  check_port_listening 8181 "OPA"
  
  echo ""
  log_info "=== Endpoint Health Checks ==="
  check_endpoint_healthy "http://localhost/health" 200 "Caddy Gateway"
  check_endpoint_healthy "http://localhost:9090/-/healthy" 200 "Prometheus"
  check_endpoint_healthy "http://localhost:3000/api/health" 200 "Grafana"
  check_endpoint_healthy "http://localhost:8181/health" 200 "OPA Service"
  
  echo ""
  log_info "=== Service Log Checks ==="
  check_service_logs "code-server-caddy" || true
  check_service_logs "code-server-prometheus" || true
  check_service_logs "code-server-grafana" || true
  
  echo ""
  log_info "=== Storage Checks ==="
  ((CHECKS_TOTAL++))
  local used_percent=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [[ $used_percent -lt 80 ]]; then
    log_success "Disk usage acceptable: ${used_percent}%"
    ((CHECKS_PASS++))
  else
    log_error "Disk usage high: ${used_percent}%"
    ((CHECKS_FAIL++))
  fi
  
  echo ""
  log_info "=== Summary Report ==="
  echo -e "Total checks: ${CHECKS_TOTAL}"
  echo -e "${GREEN}Passed: ${CHECKS_PASS}${NC}"
  echo -e "${RED}Failed: ${CHECKS_FAIL}${NC}"
  echo -e "${YELLOW}Warnings: ${CHECKS_WARN}${NC}"
  
  echo ""
  if [[ $CHECKS_FAIL -eq 0 ]]; then
    log_success "✅ All post-deployment validation checks PASSED!"
    return 0
  else
    log_error "❌ Post-deployment validation FAILED"
    return 1
  fi
}

main
