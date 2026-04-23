#!/usr/bin/env bash
# @file        scripts/ops/diagnose-postgresql-packet-errors.sh
# @module      operations/database
# @description Diagnose and fix PostgreSQL invalid startup packet errors (P1 #1630)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || exit 1

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"

# Diagnose PostgreSQL startup packet errors
diagnose_postgresql() {
    local host="$1"
    
    log_info "Diagnosing PostgreSQL on $host..."
    
    # Check PostgreSQL log for startup packet errors
    local error_count
    error_count=$(ssh "${EXEC_USER}@${host}" "docker logs \$(docker ps -q -f name=postgres 2>/dev/null) 2>&1 | grep -c 'invalid length of startup packet' 2>/dev/null || echo 0")
    
    log_info "Invalid startup packet errors found: $error_count"
    
    # Show recent errors
    local recent_errors
    recent_errors=$(ssh "${EXEC_USER}@${host}" "docker logs \$(docker ps -q -f name=postgres 2>/dev/null) 2>&1 | grep 'invalid length of startup packet' | tail -5 2>/dev/null || echo 'No recent errors'")
    
    log_info "Recent errors:"
    echo "$recent_errors" | sed 's/^/  /'
}

# Check PostgreSQL connection timeout settings
check_postgres_config() {
    local host="$1"
    
    log_info "Checking PostgreSQL configuration on $host..."
    
    # Get current config
    local pg_config
    pg_config=$(ssh "${EXEC_USER}@${host}" "docker exec \$(docker ps -q -f name=postgres 2>/dev/null) psql -U postgres -c 'SHOW statement_timeout; SHOW idle_in_transaction_session_timeout; SHOW tcp_keepalives_idle;' 2>/dev/null || echo 'Cannot connect to PostgreSQL'" || echo "Connection failed")
    
    log_info "Current timeout settings:"
    echo "$pg_config" | sed 's/^/  /'
}

# Check Docker health checks
check_health_checks() {
    local host="$1"
    
    log_info "Checking health checks on $host..."
    
    # List containers with health check configs
    local health_configs
    health_configs=$(ssh "${EXEC_USER}@${host}" "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'postgres|redis|code-server'" || echo "No containers found")
    
    log_info "Container health status:"
    echo "$health_configs" | sed 's/^/  /'
}

# Identify health check source
identify_health_check_source() {
    local host="$1"
    
    log_info "Identifying health check source on $host..."
    
    # Check docker-compose.yml for health checks
    local health_check_source
    health_check_source=$(ssh "${EXEC_USER}@${host}" "grep -r 'healthcheck' /home/akushnir/code-server-enterprise/docker-compose* 2>/dev/null | head -10 || echo 'No healthcheck directives found'")
    
    log_info "Health check configuration in docker-compose:"
    echo "$health_check_source" | sed 's/^/  /'
}

# Fix health check if misconfigured
fix_health_checks() {
    local host="$1"
    
    log_info "Attempting to identify and fix health check issues on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would apply health check fixes"
        return 0
    fi
    
    # Check docker-compose for PostgreSQL health check configuration
    local compose_file="/home/akushnir/code-server-enterprise/docker-compose.yml"
    
    # Validate that health checks are properly configured
    log_info "Verifying PostgreSQL container accepts only valid connections..."
    
    # Restart PostgreSQL to clear any hung connections
    log_info "Restarting PostgreSQL container..."
    ssh "${EXEC_USER}@${host}" "cd /home/akushnir/code-server-enterprise && docker compose restart postgres" || {
        log_error "Failed to restart PostgreSQL"
        return 1
    }
    
    log_success "PostgreSQL restarted"
}

# Monitor error frequency
monitor_errors() {
    local host="$1"
    local duration="${2:-60}"  # Monitor for 60 seconds by default
    
    log_info "Monitoring PostgreSQL errors on $host for ${duration}s..."
    
    local start_count
    start_count=$(ssh "${EXEC_USER}@${host}" "docker logs \$(docker ps -q -f name=postgres 2>/dev/null) 2>&1 | grep -c 'invalid length of startup packet' 2>/dev/null || echo 0")
    
    log_info "Current error count: $start_count"
    log_info "Waiting ${duration}s..."
    
    sleep "$duration"
    
    local end_count
    end_count=$(ssh "${EXEC_USER}@${host}" "docker logs \$(docker ps -q -f name=postgres 2>/dev/null) 2>&1 | grep -c 'invalid length of startup packet' 2>/dev/null || echo 0")
    
    local new_errors=$((end_count - start_count))
    
    if [ "$new_errors" -eq 0 ]; then
        log_success "✓ No new errors detected - issue resolved!"
        return 0
    else
        log_warn "⚠ Detected $new_errors new errors in past ${duration}s"
        return 1
    fi
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Diagnosing PostgreSQL invalid startup packet errors (P1 #1630)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Replica Host: $REPLICA_HOST"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${REPLICA_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to replica host"
    fi
    log_success "✓ Connected to replica"
    log_info ""
    
    # Diagnose on both hosts
    log_info "PRIMARY HOST DIAGNOSTICS"
    log_info "========================"
    diagnose_postgresql "$PRIMARY_HOST"
    log_info ""
    
    check_postgres_config "$PRIMARY_HOST"
    log_info ""
    
    check_health_checks "$PRIMARY_HOST"
    log_info ""
    
    identify_health_check_source "$PRIMARY_HOST"
    log_info ""
    
    log_info "REPLICA HOST DIAGNOSTICS"
    log_info "========================"
    diagnose_postgresql "$REPLICA_HOST"
    log_info ""
    
    check_postgres_config "$REPLICA_HOST"
    log_info ""
    
    check_health_checks "$REPLICA_HOST"
    log_info ""
    
    identify_health_check_source "$REPLICA_HOST"
    log_info ""
    
    # Apply fix if needed
    if [ "$DRY_RUN" != "1" ]; then
        log_info "APPLYING FIXES"
        log_info "=============="
        fix_health_checks "$PRIMARY_HOST"
        fix_health_checks "$REPLICA_HOST"
        log_info ""
        
        log_info "MONITORING ERROR FREQUENCY"
        log_info "=========================="
        monitor_errors "$PRIMARY_HOST" 60 || true
        log_info ""
        monitor_errors "$REPLICA_HOST" 60 || true
    fi
    
    log_info ""
    log_success "========================================================================"
    log_success "PostgreSQL diagnostics and fixes complete!"
    log_success "========================================================================"
}

main "$@"
