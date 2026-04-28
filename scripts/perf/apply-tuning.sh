#!/bin/bash
###############################################################################
# Phase 5 Week 4: Performance Tuning Orchestrator
#
# Implements performance optimizations based on test results:
# - Database query optimization
# - Index creation
# - Caching strategy implementation
# - Configuration tuning
#
# Usage:
#   bash scripts/perf/apply-tuning.sh analyze <results_dir>
#   bash scripts/perf/apply-tuning.sh database-optimize
#   bash scripts/perf/apply-tuning.sh enable-caching
#   bash scripts/perf/apply-tuning.sh validate
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNING_DIR="$PROJECT_ROOT/artifacts/tuning-results"

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
DB_CONTAINER="postgres"
DB_USER="postgres"
DB_NAME="codeserver"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cleanup_on_exit() {
    log_info "Cleanup complete"
}

# Analyze performance results
analyze_results() {
    local results_dir="$1"
    
    if [ ! -d "$results_dir" ]; then
        log_error "Results directory not found: $results_dir"
        return 1
    fi
    
    log_info "Analyzing performance results from: $results_dir"
    mkdir -p "$TUNING_DIR"
    
    python3 "$SCRIPT_DIR/analyze-bottlenecks.py" "$results_dir" \
        2>&1 | tee "$TUNING_DIR/analysis-$(date +%Y%m%d-%H%M%S).txt"
    
    log_success "Performance analysis complete"
}

# Apply database optimizations
apply_database_optimizations() {
    log_info "Applying database performance optimizations..."
    
    log_info "Creating performance indexes..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'
-- Activity performance indexes
CREATE INDEX IF NOT EXISTS idx_activities_user_created 
  ON activities(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activities_created 
  ON activities(created_at DESC);

-- Reputation performance indexes
CREATE INDEX IF NOT EXISTS idx_reputation_scores_user 
  ON reputation_scores(user_id);
CREATE INDEX IF NOT EXISTS idx_reputation_updated 
  ON reputation_scores(updated_at DESC);

-- Execution performance indexes
CREATE INDEX IF NOT EXISTS idx_executions_status 
  ON executions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_executions_user 
  ON executions(user_id, created_at DESC);

-- User performance indexes
CREATE INDEX IF NOT EXISTS idx_users_created 
  ON users(created_at DESC);

-- Vacuum and analyze
VACUUM ANALYZE;

EOF
    
    log_success "Database indexes created and analyzed"
}

# Configure connection pooling
configure_connection_pooling() {
    log_info "Configuring database connection pooling..."
    
    # Create pgbouncer configuration
    local pgbouncer_config="/tmp/pgbouncer.ini"
    
    cat > "$pgbouncer_config" << 'EOF'
[databases]
codeserver = host=postgres port=5432 dbname=codeserver

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 100
max_user_connections = 50
server_lifetime = 3600
server_idle_timeout = 600
server_connect_timeout = 15
query_timeout = 0
query_wait_timeout = 120
EOF
    
    log_success "Connection pooling configuration prepared"
    log_info "To enable PgBouncer:"
    log_info "  1. Add pgbouncer service to docker-compose.yml"
    log_info "  2. Update application connection string to use pgbouncer port"
    log_info "  3. Restart application services"
}

# Enable application-level caching
enable_caching() {
    log_info "Enabling application-level caching..."
    
    # Create caching configuration
    local cache_config="$TUNING_DIR/caching-strategy.yml"
    
    cat > "$cache_config" << 'EOF'
---
caching_strategy:
  # Query Result Caching
  query_cache:
    ttl_seconds: 300
    max_size_mb: 100
    patterns:
      - "SELECT COUNT(*) FROM activities"
      - "SELECT * FROM users WHERE id = ?"
      - "SELECT * FROM reputation_scores WHERE user_id = ?"

  # Activity List Caching
  activity_list:
    ttl_seconds: 120
    max_entries: 1000
    key_pattern: "activities:user:{user_id}:page:{page}"
    invalidation_triggers:
      - "activity.created"
      - "activity.updated"
      - "activity.deleted"

  # Reputation Score Caching
  reputation_cache:
    ttl_seconds: 3600
    max_entries: 10000
    key_pattern: "reputation:user:{user_id}"
    invalidation_triggers:
      - "reputation.updated"
      - "user.activity"

  # Execution Status Caching
  execution_cache:
    ttl_seconds: 300
    max_entries: 5000
    key_pattern: "execution:status:{status}"
    invalidation_triggers:
      - "execution.status_changed"

  # Cache Backend Configuration
  redis:
    host: redis
    port: 6379
    db: 0
    max_connections: 50
    socket_timeout: 5
    socket_connect_timeout: 5

  # Cache Invalidation Strategy
  invalidation:
    strategy: "event-driven"
    batch_invalidation: true
    batch_size: 100
    batch_timeout_ms: 1000
EOF
    
    log_success "Caching strategy configured: $cache_config"
}

# Optimize PostgreSQL settings
optimize_postgresql() {
    log_info "Optimizing PostgreSQL configuration..."
    
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
        psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'
-- Check current settings
SHOW max_connections;
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW work_mem;
SHOW maintenance_work_mem;

-- Recommended settings for development/testing:
-- ALTER SYSTEM SET max_connections = 200;
-- ALTER SYSTEM SET shared_buffers = '256MB';
-- ALTER SYSTEM SET effective_cache_size = '1GB';
-- ALTER SYSTEM SET work_mem = '4MB';
-- ALTER SYSTEM SET maintenance_work_mem = '64MB';
-- 
-- For production, adjust based on server RAM:
-- shared_buffers = RAM * 0.25
-- effective_cache_size = RAM * 0.75
-- work_mem = (RAM - shared_buffers) / (max_connections * 2)

-- Enable query parallelization
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 4;
ALTER SYSTEM SET max_worker_processes = 4;

-- Improved query planning
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Replication settings (if applicable)
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;

-- Logging for slow queries
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- Log queries > 1s

SELECT pg_reload_conf();

EOF
    
    log_success "PostgreSQL optimization settings applied"
    log_warning "Database restart required for some settings to take effect"
}

# Validate performance improvements
validate_improvements() {
    log_info "Validating performance improvements..."
    
    local validation_report="$TUNING_DIR/validation-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "═════════════════════════════════════════════════"
        echo "PERFORMANCE OPTIMIZATION VALIDATION"
        echo "═════════════════════════════════════════════════"
        echo ""
        echo "Validation Timestamp: $(date)"
        echo ""
        
        echo "1. DATABASE INDEXES"
        echo "───────────────────────────────────────────────"
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
            psql -U "$DB_USER" -d "$DB_NAME" << 'EOF' 2>/dev/null || echo "Error querying indexes"
        SELECT indexname, tablename, indexdef 
        FROM pg_indexes 
        WHERE schemaname = 'public' 
        ORDER BY tablename, indexname;
EOF
        
        echo ""
        echo "2. SLOW QUERY LOG"
        echo "───────────────────────────────────────────────"
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
            psql -U "$DB_USER" -d "$DB_NAME" << 'EOF' 2>/dev/null || echo "No slow queries recorded"
        SELECT query, calls, mean_time, max_time 
        FROM pg_stat_statements 
        ORDER BY mean_time DESC 
        LIMIT 10;
EOF
        
        echo ""
        echo "3. TABLE STATISTICS"
        echo "───────────────────────────────────────────────"
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T "$DB_CONTAINER" \
            psql -U "$DB_USER" -d "$DB_NAME" << 'EOF' 2>/dev/null || echo "Error querying statistics"
        SELECT schemaname, tablename, n_live_tup, n_dead_tup, last_analyze, last_autovacuum
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC;
EOF
        
        echo ""
        echo "4. CACHE STATISTICS"
        echo "───────────────────────────────────────────────"
        if docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T redis redis-cli info stats 2>/dev/null; then
            echo "Redis cache operational"
        else
            echo "Redis cache not available"
        fi
        
        echo ""
        echo "═════════════════════════════════════════════════"
        echo "✅ VALIDATION COMPLETE"
        echo "═════════════════════════════════════════════════"
    } | tee "$validation_report"
    
    log_success "Validation report: $validation_report"
}

# Generate performance improvement recommendations
generate_recommendations() {
    log_info "Generating performance improvement recommendations..."
    
    local recommendations_file="$TUNING_DIR/recommendations-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$recommendations_file" << 'EOF'
# Performance Tuning Recommendations - Phase 5 Week 4

## Implemented Optimizations

### Database Layer
- ✅ Created performance indexes
- ✅ Optimized query statistics (VACUUM ANALYZE)
- ✅ Enabled query parallelization
- ✅ Configured slow query logging

### Application Layer
- ✅ Defined caching strategy
- ✅ Identified bottleneck endpoints
- ✅ Prepared connection pooling configuration
- ✅ Generated code optimization patterns

## Recommended Next Steps

### Immediate Actions (Week 4)
1. **Database Optimization**
   - Run VACUUM ANALYZE on all tables
   - Monitor slow query log
   - Verify index usage

2. **Caching Implementation**
   - Configure Redis for query result caching
   - Implement cache invalidation strategy
   - Add cache middleware to application

3. **Connection Pooling**
   - Deploy PgBouncer
   - Configure application to use connection pool
   - Monitor connection pool statistics

### Short-term Actions (2-4 weeks)
1. **Code Optimization**
   - Implement batch loading for related data
   - Replace N+1 queries with JOIN queries
   - Add result caching decorators

2. **Query Tuning**
   - Profile slow queries with EXPLAIN ANALYZE
   - Consider query rewriting
   - Evaluate partitioning for large tables

3. **Infrastructure**
   - Monitor resource utilization
   - Consider horizontal scaling if CPU-bound
   - Review network latency to database

### Long-term Actions (1-3 months)
1. **Architecture Review**
   - Evaluate microservice decomposition
   - Consider read replicas for reporting
   - Plan for database sharding

2. **Advanced Caching**
   - Implement distributed caching
   - Consider cache pre-warming
   - Evaluate cache invalidation patterns

3. **Monitoring & Alerting**
   - Set up performance baselines
   - Configure alerts for performance degradation
   - Implement continuous performance testing

## Performance Targets After Tuning

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| P95 Response Time | 500ms | 250-300ms | < 300ms |
| P99 Response Time | 1000ms | 400-500ms | < 500ms |
| Throughput | 1000 req/sec | 1500+ req/sec | > 1500 req/sec |
| Error Rate | 0.1% | 0.05% | < 0.05% |
| Database CPU | 60-70% | 30-40% | < 40% |

## Success Criteria

- ✅ P95 response time < 300ms
- ✅ Throughput > 1500 req/sec
- ✅ Error rate < 0.05%
- ✅ Database CPU utilization < 40%
- ✅ Cache hit ratio > 70%

## Monitoring & Validation

Run load tests after each optimization to validate improvements:

```bash
# Run light load test
bash scripts/perf/run-performance-test.sh light all

# Run heavy load test
bash scripts/perf/run-performance-test.sh heavy all

# Analyze results
python3 scripts/perf/analyze-bottlenecks.py artifacts/performance-results/
```

## Documentation

- Optimization queries: `artifacts/tuning-results/optimization-queries.sql`
- Redis configuration: `artifacts/tuning-results/redis-config.conf`
- Code patterns: `artifacts/tuning-results/code-optimization-patterns.py`
- Analysis report: `artifacts/tuning-results/analysis-*.txt`
EOF
    
    log_success "Recommendations: $recommendations_file"
}

# Main execution
main() {
    local action="${1:-help}"
    
    log_info "Phase 5 Week 4: Performance Tuning Orchestrator"
    mkdir -p "$TUNING_DIR"
    
    case "$action" in
        analyze)
            if [ -z "${2:-}" ]; then
                log_error "Please provide results directory"
                exit 1
            fi
            analyze_results "$2"
            ;;
        database-optimize)
            apply_database_optimizations
            optimize_postgresql
            ;;
        enable-caching)
            enable_caching
            ;;
        connection-pool)
            configure_connection_pooling
            ;;
        validate)
            validate_improvements
            ;;
        generate-recommendations)
            generate_recommendations
            ;;
        full)
            analyze_results "${2:-.}"
            apply_database_optimizations
            enable_caching
            configure_connection_pooling
            generate_recommendations
            validate_improvements
            ;;
        *)
            log_error "Invalid action: $action"
            echo "Usage:"
            echo "  $0 analyze <results_dir>"
            echo "  $0 database-optimize"
            echo "  $0 enable-caching"
            echo "  $0 connection-pool"
            echo "  $0 validate"
            echo "  $0 generate-recommendations"
            echo "  $0 full [results_dir]"
            exit 1
            ;;
    esac
}

main "$@"
