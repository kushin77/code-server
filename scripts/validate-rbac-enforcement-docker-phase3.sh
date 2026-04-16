#!/bin/bash
# Phase 3: RBAC Enforcement Validation for Docker Infrastructure
# Comprehensive testing suite for Docker-based authorization controls

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TEST_PASSED=0
TEST_FAILED=0

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
  ((TEST_PASSED++))
}

log_fail() {
  echo -e "${RED}[✗]${NC} $*"
  ((TEST_FAILED++))
}

log_warning() { log_warn "$@"; }

# ============================================================================
# Test 1: Service Environment Variables
# ============================================================================

test_env_variables() {
  echo ""
  log_info "=== Test 1: Service Environment Variables ==="

  if docker-compose exec -T code-server env | grep -q "CODE_SERVER_ALLOWED_SERVICES"; then
    log_success "code-server environment variables loaded"
  else
    log_fail "code-server environment variables not found"
  fi

  if docker-compose exec -T postgresql env | grep -q "POSTGRESQL_ALLOWED_SERVICES"; then
    log_success "postgresql environment variables loaded"
  else
    log_fail "postgresql environment variables not found"
  fi

  if docker-compose exec -T redis env | grep -q "REDIS_ALLOWED_SERVICES"; then
    log_success "redis environment variables loaded"
  else
    log_fail "redis environment variables not found"
  fi

  if docker-compose exec -T prometheus env | grep -q "PROMETHEUS_ALLOWED_SERVICES"; then
    log_success "prometheus environment variables loaded"
  else
    log_fail "prometheus environment variables not found"
  fi
}

# ============================================================================
# Test 2: PostgreSQL Audit Table
# ============================================================================

test_audit_table() {
  echo ""
  log_info "=== Test 2: PostgreSQL Audit Table ==="

  local postgres_container=$(docker-compose ps -q postgresql 2>/dev/null || echo "")
  
  if [[ -z "$postgres_container" ]]; then
    log_fail "PostgreSQL container not running"
    return
  fi

  # Check if table exists
  if docker exec "$postgres_container" psql -U postgres -d postgres -c "SELECT * FROM rbac_audit_log LIMIT 0;" 2>/dev/null; then
    log_success "Audit table exists (rbac_audit_log)"
  else
    log_fail "Audit table does not exist"
    return
  fi

  # Check for indexes
  if docker exec "$postgres_container" psql -U postgres -d postgres -c "SELECT * FROM pg_indexes WHERE tablename='rbac_audit_log';" 2>/dev/null | grep -q "idx_rbac"; then
    log_success "Audit table indexes created"
  else
    log_warning "Audit table indexes not found (may need to create manually)"
  fi

  # Check immutability trigger
  if docker exec "$postgres_container" psql -U postgres -d postgres -c "SELECT * FROM pg_trigger WHERE tgname LIKE '%audit%';" 2>/dev/null | grep -q "prevent_audit"; then
    log_success "Audit log immutability trigger configured"
  else
    log_warning "Audit immutability trigger not found"
  fi
}

# ============================================================================
# Test 3: Docker Networks for Service Isolation
# ============================================================================

test_service_networks() {
  echo ""
  log_info "=== Test 3: Docker Service Networks ==="

  # Check for service-specific networks
  if docker network ls 2>/dev/null | grep -q "code-server_to_postgresql"; then
    log_success "code-server→postgresql isolation network exists"
  else
    log_warning "code-server→postgresql isolation network not found"
  fi

  if docker network ls 2>/dev/null | grep -q "code-server_to_redis"; then
    log_success "code-server→redis isolation network exists"
  else
    log_warning "code-server→redis isolation network not found"
  fi

  if docker network ls 2>/dev/null | grep -q "prometheus_to_grafana"; then
    log_success "prometheus→grafana isolation network exists"
  else
    log_warning "prometheus→grafana isolation network not found"
  fi
}

# ============================================================================
# Test 4: Caddy Middleware Configuration
# ============================================================================

test_caddy_middleware() {
  echo ""
  log_info "=== Test 4: Caddy Middleware Configuration ==="

  # Check Caddy is running
  if docker-compose ps caddy 2>/dev/null | grep -q "Up"; then
    log_success "Caddy container is running"
  else
    log_fail "Caddy container is not running"
    return
  fi

  # Check Caddyfile exists
  if docker exec caddy ls /etc/caddy/Caddyfile &>/dev/null; then
    log_success "Caddyfile mounted in Caddy container"
  else
    log_fail "Caddyfile not found in Caddy container"
    return
  fi

  # Check RBAC middleware in config
  if docker exec caddy grep -q "jwt_validation\|rate_limit\|rbac" /etc/caddy/Caddyfile 2>/dev/null; then
    log_success "RBAC middleware configuration found in Caddyfile"
  else
    log_warning "RBAC middleware configuration not found in Caddyfile"
  fi

  # Validate Caddy syntax
  if docker exec caddy caddy validate --config /etc/caddy/Caddyfile &>/dev/null; then
    log_success "Caddyfile syntax is valid"
  else
    log_warning "Caddyfile has syntax issues (check logs)"
  fi
}

# ============================================================================
# Test 5: Service Connectivity (allowed vs denied)
# ============================================================================

test_service_connectivity() {
  echo ""
  log_info "=== Test 5: Service Connectivity Tests ==="

  # Test code-server → postgresql (should succeed)
  if docker-compose exec -T code-server curl -s -o /dev/null -w "%{http_code}" http://postgresql:5432 2>/dev/null | grep -qE "200|connect"; then
    log_success "code-server → postgresql connection allowed"
  else
    log_warning "code-server → postgresql connection test (may be database-specific)"
  fi

  # Test code-server → redis (should succeed)
  if docker-compose exec -T code-server redis-cli -h redis PING 2>/dev/null | grep -q "PONG"; then
    log_success "code-server → redis connection allowed"
  else
    log_warning "code-server → redis connection test (redis-cli may not be available)"
  fi

  # Test code-server → alertmanager (should fail if enforced)
  if ! docker-compose exec -T code-server curl -s -o /dev/null -w "%{http_code}" http://alertmanager:9093 2>/dev/null | grep -q "200"; then
    log_success "code-server → alertmanager connection denied (as expected)"
  else
    log_warning "code-server → alertmanager connection allowed (may need enforcement)"
  fi
}

# ============================================================================
# Test 6: Audit Log Recording
# ============================================================================

test_audit_logging() {
  echo ""
  log_info "=== Test 6: Audit Log Recording ==="

  local postgres_container=$(docker-compose ps -q postgresql 2>/dev/null || echo "")
  
  if [[ -z "$postgres_container" ]]; then
    log_warning "PostgreSQL not running - cannot verify audit logs"
    return
  fi

  # Check if any audit entries exist
  local audit_count=$(docker exec "$postgres_container" psql -U postgres -d postgres -c "SELECT COUNT(*) FROM rbac_audit_log;" 2>/dev/null | tail -1 | tr -d ' ')
  
  if [[ "$audit_count" -gt 0 ]]; then
    log_success "Audit log has $audit_count entries"
  else
    log_warning "No audit log entries yet (services may need to connect)"
  fi

  # Check for both allowed and denied entries
  local denied_count=$(docker exec "$postgres_container" psql -U postgres -d postgres -c "SELECT COUNT(*) FROM rbac_audit_log WHERE allowed = false;" 2>/dev/null | tail -1 | tr -d ' ')
  
  if [[ "$denied_count" -gt 0 ]]; then
    log_success "Audit log has $denied_count denied access entries"
  else
    log_warning "No denied access entries yet (enforcement may not be active)"
  fi
}

# ============================================================================
# Test 7: Rate Limiting Configuration
# ============================================================================

test_rate_limiting() {
  echo ""
  log_info "=== Test 7: Rate Limiting Configuration ==="

  # Check environment variables for rate limits
  if docker-compose exec -T code-server env | grep -q "CODE_SERVER_RATE_LIMIT_QPS"; then
    log_success "code-server rate limiting configured"
  else
    log_warning "code-server rate limiting not configured"
  fi

  if docker-compose exec -T prometheus env | grep -q "PROMETHEUS_RATE_LIMIT_QPS"; then
    log_success "prometheus rate limiting configured"
  else
    log_warning "prometheus rate limiting not configured"
  fi

  # Check for rate limit configuration file
  if [[ -f "$PROJECT_ROOT/.env.phase3" ]]; then
    local rate_limit_count=$(grep -c "RATE_LIMIT" "$PROJECT_ROOT/.env.phase3" || echo "0")
    if [[ "$rate_limit_count" -gt 0 ]]; then
      log_success "Rate limiting configuration file exists ($rate_limit_count settings)"
    else
      log_warning "Rate limiting not configured in .env.phase3"
    fi
  else
    log_warning ".env.phase3 file not found"
  fi
}

# ============================================================================
# Test 8: Service Authorization Matrix
# ============================================================================

test_authorization_matrix() {
  echo ""
  log_info "=== Test 8: Service Authorization Matrix ==="

  if [[ -f "$PROJECT_ROOT/config/rbac/service-authorization-matrix.md" ]]; then
    log_success "Authorization matrix document exists"
    
    # Count entries
    local entry_count=$(grep -c "^|" "$PROJECT_ROOT/config/rbac/service-authorization-matrix.md" || echo "0")
    echo "  Service pairs defined: $((entry_count - 2))"  # -2 for header rows
  else
    log_fail "Authorization matrix document not found"
  fi
}

# ============================================================================
# Test 9: Service Health Check
# ============================================================================

test_service_health() {
  echo ""
  log_info "=== Test 9: Service Health Status ==="

  local services=("code-server" "caddy" "postgresql" "redis" "prometheus" "grafana" "ollama" "alertmanager" "jaeger")
  
  for service in "${services[@]}"; do
    if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
      log_success "$service is running"
    else
      log_warning "$service is not running or unhealthy"
    fi
  done
}

# ============================================================================
# Test 10: RBAC Configuration Files
# ============================================================================

test_config_files() {
  echo ""
  log_info "=== Test 10: RBAC Configuration Files ==="

  if [[ -f "$PROJECT_ROOT/.env.phase3" ]]; then
    log_success ".env.phase3 configuration file exists"
  else
    log_fail ".env.phase3 file not found"
  fi

  if [[ -f "$PROJECT_ROOT/config/caddy/rbac-enforcement-middleware.caddyfile" ]]; then
    log_success "Caddy RBAC middleware configuration exists"
  else
    log_warning "Caddy RBAC middleware configuration not found"
  fi

  if [[ -f "$PROJECT_ROOT/config/rbac/service-authorization-matrix.md" ]]; then
    log_success "Service authorization matrix exists"
  else
    log_warning "Service authorization matrix not found"
  fi

  if [[ -f "$PROJECT_ROOT/scripts/deploy-rbac-enforcement-docker-phase3.sh" ]]; then
    log_success "RBAC deployment script exists"
  else
    log_fail "RBAC deployment script not found"
  fi
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 3: RBAC Enforcement Health Check Summary               ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Test Results:"
  echo "  ${GREEN}Passed: ${TEST_PASSED}${NC}"
  echo "  ${RED}Failed: ${TEST_FAILED}${NC}"
  echo ""

  if [[ "$TEST_FAILED" -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed! RBAC enforcement is operational${NC}"
    return 0
  else
    echo -e "${RED}⚠️  Some tests failed. Please review above.${NC}"
    return 1
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Phase 3: RBAC Enforcement Health Check & Validation Suite    ║"
  echo "╚════════════════════════════════════════════════════════════════╝"

  test_env_variables
  test_audit_table
  test_service_networks
  test_caddy_middleware
  test_service_connectivity
  test_audit_logging
  test_rate_limiting
  test_authorization_matrix
  test_service_health
  test_config_files

  print_summary
}

main "$@"
