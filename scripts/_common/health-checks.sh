#!/bin/bash
# ==============================================================================
# SHARED HEALTH CHECK FUNCTIONS
# ==============================================================================
# This file consolidates health check logic that was previously duplicated
# across scripts/ops/deploy.sh, scripts/ops/rollback-safe.sh,
# scripts/perf/e2e-load-test.sh, tests/chaos/chaos-test.sh
#
# Usage: source scripts/_common/health-checks.sh
# ==============================================================================

# Source guards
[[ "${_HEALTH_CHECKS_SOURCED:-0}" == "1" ]] && return 0
readonly _HEALTH_CHECKS_SOURCED=1

# Ensure init.sh has been sourced for logging functions
[[ "${_SCRIPT_INIT_SOURCED:-0}" == "0" ]] && source "${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/init.sh"

# ==============================================================================
# GENERIC HEALTH CHECKS
# ==============================================================================

# Check if a TCP service is responding
check_tcp_endpoint() {
  local host="$1"
  local port="$2"
  local timeout="${3:-5}"
  
  if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
    log_info "✓ TCP endpoint $host:$port is reachable"
    return 0
  else
    log_error "✗ TCP endpoint $host:$port is not reachable"
    return 1
  fi
}

# Check if an HTTP endpoint returns healthy status
check_http_health() {
  local endpoint="$1"
  local timeout="${2:-5}"
  
  if curl -sf --max-time "$timeout" "$endpoint" >/dev/null 2>&1; then
    log_info "✓ HTTP health check passed: $endpoint"
    return 0
  else
    log_error "✗ HTTP health check failed: $endpoint"
    return 1
  fi
}

# Wait for an HTTP endpoint to become healthy
wait_for_http_health() {
  local endpoint="$1"
  local max_attempts="${2:-30}"
  local interval="${3:-10}"
  
  for attempt in $(seq 1 "$max_attempts"); do
    if check_http_health "$endpoint" 5; then
      log_success "Service became healthy after attempt $attempt"
      return 0
    fi
    
    if [[ $attempt -lt $max_attempts ]]; then
      log_info "Attempt $attempt/$max_attempts failed. Waiting ${interval}s..."
      sleep "$interval"
    fi
  done
  
  log_error "Service health check failed after $max_attempts attempts"
  return 1
}

# ==============================================================================
# SERVICE-SPECIFIC HEALTH CHECKS
# ==============================================================================

# Check PostgreSQL health
check_postgres_health() {
  local host="${1:-localhost}"
  local port="${2:-5432}"
  local user="${3:-postgres}"
  local db="${4:-postgres}"
  
  if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$host" -p "$port" -U "$user" -d "$db" -c "SELECT 1" >/dev/null 2>&1; then
    log_info "✓ PostgreSQL is healthy"
    return 0
  else
    log_error "✗ PostgreSQL health check failed"
    return 1
  fi
}

# Check Redis health
check_redis_health() {
  local host="${1:-localhost}"
  local port="${2:-6379}"
  
  if redis-cli -h "$host" -p "$port" ping >/dev/null 2>&1; then
    log_info "✓ Redis is healthy"
    return 0
  else
    log_error "✗ Redis health check failed"
    return 1
  fi
}

# Check Redpanda/Kafka broker
check_kafka_broker_health() {
  local bootstrap_servers="${1:-localhost:9092}"
  
  if rpk cluster info --brokers "$bootstrap_servers" >/dev/null 2>&1; then
    log_info "✓ Kafka broker is healthy"
    return 0
  else
    log_error "✗ Kafka broker health check failed"
    return 1
  fi
}

# Check Qdrant vector database
check_qdrant_health() {
  local endpoint="${1:-http://localhost:6333}"
  
  if curl -sf "$endpoint/health" >/dev/null 2>&1; then
    log_info "✓ Qdrant is healthy"
    return 0
  else
    log_error "✗ Qdrant health check failed"
    return 1
  fi
}

# Check OPA policy engine
check_opa_health() {
  local endpoint="${1:-http://localhost:8181}"
  
  if curl -sf "$endpoint/health?bundles" >/dev/null 2>&1; then
    log_info "✓ OPA is healthy"
    return 0
  else
    log_error "✗ OPA health check failed"
    return 1
  fi
}

# ==============================================================================
# DEPLOYMENT-WIDE HEALTH CHECKS
# ==============================================================================

# Check all critical services are running
check_all_services() {
  local failed=0
  
  log_info "Checking all critical services..."
  
  check_postgres_health || failed+=1
  check_redis_health || failed+=1
  check_kafka_broker_health || failed+=1
  check_qdrant_health || failed+=1
  check_opa_health || failed+=1
  
  if [[ $failed -eq 0 ]]; then
    log_success "All services are healthy"
    return 0
  else
    log_error "$failed services failed health checks"
    return 1
  fi
}

# Wait for all services to become healthy
wait_for_all_services() {
  local max_attempts="${1:-30}"
  local interval="${2:-10}"
  
  log_info "Waiting for all services to become healthy (max $max_attempts attempts, interval ${interval}s)..."
  
  for attempt in $(seq 1 "$max_attempts"); do
    if check_all_services; then
      return 0
    fi
    
    if [[ $attempt -lt $max_attempts ]]; then
      log_info "Attempt $attempt/$max_attempts - services not yet healthy. Waiting..."
      sleep "$interval"
    fi
  done
  
  log_error "Services failed to become healthy after $max_attempts attempts"
  return 1
}

# ==============================================================================
# IDEMPOTENCY & DEPLOYMENT VALIDATION
# ==============================================================================

# Verify deployment is idempotent (can re-run without issues)
verify_deployment_idempotency() {
  local docker_compose_file="${1:-docker-compose.yml}"
  local max_attempts="${2:-3}"
  
  log_info "Verifying deployment idempotency (running $max_attempts times)..."
  
  for attempt in $(seq 1 "$max_attempts"); do
    log_info "Deployment run $attempt/$max_attempts..."
    
    docker-compose -f "$docker_compose_file" up -d --force-recreate || {
      log_error "Deployment failed on attempt $attempt"
      return 1
    }
    
    wait_for_all_services || {
      log_error "Services failed to become healthy on attempt $attempt"
      return 1
    }
  done
  
  log_success "Deployment verified as idempotent"
  return 0
}

# ==============================================================================
# EXPORT ALL FUNCTIONS
# ==============================================================================

export -f check_tcp_endpoint check_http_health wait_for_http_health
export -f check_postgres_health check_redis_health check_kafka_broker_health
export -f check_qdrant_health check_opa_health
export -f check_all_services wait_for_all_services
export -f verify_deployment_idempotency
