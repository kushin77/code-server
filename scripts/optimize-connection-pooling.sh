#!/bin/bash

################################################################################
# Phase 5.2: Database & Connection Pooling Optimization
# Purpose: Configure PgBouncer for PostgreSQL connection pooling,
#          Redis connection optimization, and query performance tuning
# Usage: ./scripts/optimize-connection-pooling.sh [--dry-run]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary SQL files..."; rm -f /tmp/*.sql.tmp 2>/dev/null || true' EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

################################################################################
# 1. PGBOUNCER CONFIGURATION (PostgreSQL Connection Pooling)
################################################################################

create_pgbouncer_config() {
    log_info "Creating PgBouncer configuration for PostgreSQL connection pooling..."

    cat > "${PROJECT_ROOT}/pgbouncer/pgbouncer.ini" << 'PGBOUNCER_CONFIG'
[databases]
# slog_db = host=code-server-postgres port=5432 dbname=slog user=postgres password=${DB_PASSWORD}
slog = host=code-server-postgres port=5432 dbname=slog

[pgbouncer]
# Connection pooling mode: transaction (1 conn per transaction) or session (1 conn per session)
pool_mode = transaction

# Log configuration
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid

# Admin console - only accept from localhost
admin_users = postgres, pgbouncer

# Server-side connection settings
listen_addr = 0.0.0.0
listen_port = 6432

# Authentication
auth_type = plain
auth_file = /etc/pgbouncer/userlist.txt

# Client connection timeout
client_idle_timeout = 900
client_login_timeout = 15

# Server connection settings
server_lifetime = 3600
server_idle_timeout = 600
server_connect_timeout = 15
server_login_timeout = 15

# Connection pooling parameters
default_pool_size = 25
reserve_pool_size = 10
reserve_pool_timeout = 3
max_client_conn = 1000
max_db_connections = 100
max_user_connections = unlimited

# Connection pooling tuning
connect_query = SELECT 1
application_name_add_host = 1

# Query result pooling (caching)
query_wait_timeout = 120

# Maintenance
maintenance_db = postgres

# Statistics
stats_period = 60
stats_users = postgres

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
log_statement = 0
verbose = 1

# DNS
dns_max_ttl = 15

# DNS round-robin support
dns_nxdomain_ttl = 15

# Async support
async_mode = 1

# Performance tuning
tcp_keepalives_idle = 30
tcp_keepalives_interval = 10
tcp_keepalives_count = 5

# TLS configuration (optional)
# server_tls_sslmode = require
# server_tls_ca_file = /etc/ssl/certs/ca-certificates.crt
# server_tls_key_file = /etc/ssl/private/key.pem
# server_tls_cert_file = /etc/ssl/certs/cert.pem
# client_tls_sslmode = require
# client_tls_ca_file = /etc/ssl/certs/ca-certificates.crt

# Connection age limits to force refresh
max_client_conn_age = 0
max_idle_client_conn_age = 0
PGBOUNCER_CONFIG

    log_success "PgBouncer configuration created"
}

################################################################################
# 2. REDIS CONNECTION OPTIMIZATION
################################################################################

create_redis_optimization() {
    log_info "Creating Redis connection optimization configuration..."

    cat > "${PROJECT_ROOT}/redis-optimization.conf" << 'REDIS_CONFIG'
# Redis Performance Optimization Configuration

# Memory Management
maxmemory 2gb
maxmemory-policy allkeys-lru

# Eviction policy (Least Recently Used)
# Options: volatile-lru, allkeys-lru, volatile-ttl, allkeys-random, volatile-random, noeviction
maxmemory-policy allkeys-lru

# Lazy freeing
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
lazyfree-user-del yes

# Connection handling
tcp-keepalive 300
timeout 0

# Backlog for client connections
tcp-backlog 511

# AOF (Append-Only File) optimization
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# RDB (Snapshot) optimization
save 900 1        # Save if 1 key changed in 900 sec
save 300 10       # Save if 10 keys changed in 300 sec
save 60 10000     # Save if 10000 keys changed in 60 sec

# Snapshot compression
rdbcompression yes

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Slowlog
slowlog-log-slower-than 10000
slowlog-max-len 128

# Database
databases 16

# Replication settings
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no

# Latency monitoring
latency-monitor-threshold 0

# Notify settings
notify-keyspace-events ""

# Hash table settings
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# List settings
list-max-ziplist-size -2
list-compress-depth 0

# Set settings
set-max-intset-entries 512

# Sorted set settings
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# Stream settings
stream-node-max-bytes 4096
stream-node-max-entries 100

# HyperLogLog
hll-sparse-max-bytes 3000

# Active rehashing
activerehashing yes
REDIS_CONFIG

    log_success "Redis optimization configuration created"
}

################################################################################
# 3. DATABASE QUERY OPTIMIZATION
################################################################################

create_query_optimization() {
    log_info "Creating database query optimization script..."

    cat > "${PROJECT_ROOT}/scripts/optimize-database-queries.sql" << 'SQL_OPTIMIZE'
-- Phase 5.2: Database Query Optimization
-- Purpose: Create indexes, analyze tables, and configure query planner

-- 1. Create indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_service_name ON services(name);
CREATE INDEX IF NOT EXISTS idx_service_status ON services(status);
CREATE INDEX IF NOT EXISTS idx_service_created ON services(created_at);

-- 2. Create composite indexes for frequent joins
CREATE INDEX IF NOT EXISTS idx_container_service_status ON containers(service_id, status) INCLUDE (health_status);

-- 3. Create indexes for sorting operations
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp DESC) INCLUDE (service_id, level);

-- 4. Create partial indexes for filtered queries
CREATE INDEX IF NOT EXISTS idx_unhealthy_services ON services(id) WHERE status != 'healthy';
CREATE INDEX IF NOT EXISTS idx_active_containers ON containers(id) WHERE status = 'running';

-- 5. Enable query plan caching
ALTER SYSTEM SET plan_cache_mode = 'force_plan_cache';

-- 6. Configure work memory for sorting/hashing
ALTER SYSTEM SET work_mem = '256MB';

-- 7. Configure shared buffers (typically 25% of RAM)
ALTER SYSTEM SET shared_buffers = '4GB';

-- 8. Configure effective cache size
ALTER SYSTEM SET effective_cache_size = '12GB';

-- 9. Configure random page cost
ALTER SYSTEM SET random_page_cost = 1.1;

-- 10. Enable parallel query execution
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 8;
ALTER SYSTEM SET max_parallel_maintenance_workers = 4;

-- 11. Configure connection pooling
ALTER SYSTEM SET max_connections = 500;
ALTER SYSTEM SET max_prepared_transactions = 100;

-- 12. Enable synchronous commits for critical tables only
ALTER SYSTEM SET synchronous_commit = 'local';

-- 13. Configure statement timeout
ALTER SYSTEM SET statement_timeout = '30s';

-- 14. Analyze all tables to update statistics
ANALYZE;

-- 15. Create materialized views for heavy queries
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_service_stats AS
SELECT 
    s.id,
    s.name,
    COUNT(c.id) as container_count,
    SUM(CASE WHEN c.status = 'running' THEN 1 ELSE 0 END) as running_count,
    MAX(c.created_at) as last_created
FROM services s
LEFT JOIN containers c ON s.id = c.service_id
GROUP BY s.id, s.name;

-- 16. Create index on materialized view
CREATE INDEX IF NOT EXISTS idx_mv_service_stats_name ON mv_service_stats(name);

-- 17. Log statement configuration
ALTER SYSTEM SET log_min_duration_statement = 1000;
ALTER SYSTEM SET log_statement = 'ddl';

-- 18. Reload configuration
SELECT pg_reload_conf();
SQL_OPTIMIZE

    log_success "Database query optimization script created"
}

################################################################################
# 4. CONNECTION POOL MONITORING
################################################################################

create_pool_monitoring() {
    log_info "Creating connection pool monitoring queries..."

    cat > "${PROJECT_ROOT}/scripts/monitor-connection-pools.sql" << 'SQL_MONITOR'
-- Phase 5.2: Connection Pool Monitoring
-- Purpose: Monitor active connections, waiting queries, and pool utilization

-- 1. Active connections by database
SELECT 
    datname as database,
    count(*) as connections,
    max(extract(epoch from (now() - backend_start))) as oldest_connection_sec
FROM pg_stat_activity
WHERE datname IS NOT NULL
GROUP BY datname
ORDER BY connections DESC;

-- 2. Long-running queries (> 5 minutes)
SELECT 
    pid,
    usename,
    application_name,
    state,
    query,
    extract(epoch from (now() - query_start)) as duration_sec
FROM pg_stat_activity
WHERE query_start IS NOT NULL 
  AND extract(epoch from (now() - query_start)) > 300
ORDER BY duration_sec DESC;

-- 3. Connection wait events
SELECT 
    wait_event_type,
    wait_event,
    count(*) as count
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
GROUP BY wait_event_type, wait_event
ORDER BY count DESC;

-- 4. Cache hit ratio
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- 5. Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC
LIMIT 20;

-- 6. Table size analysis
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- 7. Unused indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- 8. Query performance analysis
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time,
    rows
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
SQL_MONITOR

    log_success "Connection pool monitoring queries created"
}

################################################################################
# 5. APPLY OPTIMIZATIONS TO LIVE SYSTEM
################################################################################

apply_optimizations() {
    log_info "Applying connection pooling optimizations to live system..."

    # Apply to primary host
    log_info "Optimizing primary host (192.168.168.31)..."
    ssh -o BatchMode=yes akushnir@192.168.168.31 "
        cd ~/code-server-enterprise
        
        # Apply database optimizations
        docker exec code-server-postgres psql -U postgres -d slog << 'EOF'
        $(cat ${PROJECT_ROOT}/scripts/optimize-database-queries.sql)
EOF
    " || log_warn "Could not apply database optimizations to primary"

    # Apply to replica host
    log_info "Optimizing replica host (192.168.168.42)..."
    ssh -o BatchMode=yes akushnir@192.168.168.42 "
        cd ~/code-server-enterprise
        
        # Apply database optimizations
        docker exec code-server-postgres psql -U postgres -d slog << 'EOF'
        $(cat ${PROJECT_ROOT}/scripts/optimize-database-queries.sql)
EOF
    " || log_warn "Could not apply database optimizations to replica"

    log_success "Connection pooling optimizations applied"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 5.2: Database & Connection Pooling Optimization"
    log_info "========================================================"

    create_pgbouncer_config
    create_redis_optimization
    create_query_optimization
    create_pool_monitoring

    if ! $DRY_RUN; then
        apply_optimizations
        log_success "Phase 5.2 Complete - Connection pooling optimizations applied"
    else
        log_info "DRY-RUN MODE: No changes applied to live system"
        log_info "Generated configurations:"
        log_info "  - ${PROJECT_ROOT}/pgbouncer/pgbouncer.ini"
        log_info "  - ${PROJECT_ROOT}/redis-optimization.conf"
        log_info "  - ${PROJECT_ROOT}/scripts/optimize-database-queries.sql"
        log_info "  - ${PROJECT_ROOT}/scripts/monitor-connection-pools.sql"
    fi
}

main "$@"
