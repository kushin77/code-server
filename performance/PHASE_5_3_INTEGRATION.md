# Phase 5.3: Performance Optimization Integration Guide

## Overview

Phase 5.3 provides a complete performance optimization framework for Code-Server Enterprise:
1. **Load Testing** - Comprehensive k6 benchmark suite
2. **Caching** - Redis-based multi-layer caching with TTL, event-based, and pattern-based invalidation
3. **Database Optimization** - Connection pooling, query optimization patterns, index recommendations
4. **Monitoring** - Performance metrics and slow query analysis

## Load Testing - K6 Benchmarks

### Run Load Tests

```bash
# Install k6
# macOS:  brew install k6
# Linux:  apt-get install k6
# Windows: choco install k6

# Run comprehensive test suite
k6 run performance/benchmarks/k6-comprehensive-load-test.js

# Run with custom base URL
k6 run -e BASE_URL=https://ide.kushnir.cloud \
       -e AGENT_API=https://ide.kushnir.cloud/agent-api \
       -e EMBEDDINGS_API=https://ide.kushnir.cloud/embeddings-api \
       performance/benchmarks/k6-comprehensive-load-test.js

# Run with custom VU (Virtual User) settings
k6 run --vus 100 --duration 5m performance/benchmarks/k6-comprehensive-load-test.js

# Generate HTML report
k6 run --out html=results.html performance/benchmarks/k6-comprehensive-load-test.js
```

### Test Targets

| Service | Target P99 | Target P95 |
|---------|-----------|-----------|
| Health Checks | <100ms | <50ms |
| Agent API | <200ms | <150ms |
| Embeddings | <1000ms | <500ms |
| RBAC API | <100ms | <75ms |
| File Operations | <300ms | <200ms |

## Redis Caching

### Setup

```bash
# Start Redis (Docker)
docker run -d \
  --name redis \
  -p 6379:6379 \
  -v redis-data:/data \
  redis:7-alpine \
  redis-server --appendonly yes

# Or run redis-compose service
docker-compose up -d redis
```

### Python Integration

```python
from services.cache_manager import get_cache_manager

# Get cache manager instance
cache = get_cache_manager()

# ─── Basic Operations ──────────────────────────────────────────────

# Set value with automatic TTL
cache.set('user:123', {'name': 'Alice', 'role': 'admin'})

# Get value
user = cache.get('user:123')

# Set multiple values at once
cache.set_many({
    'user:123': {'name': 'Alice'},
    'user:456': {'name': 'Bob'},
})

# Get multiple values
users = cache.get_many(['user:123', 'user:456'])

# ─── Cache-Aside Pattern (DB fallback) ─────────────────────────────

def fetch_workspace_from_db(ws_id):
    # Query database
    return db.query('SELECT * FROM workspaces WHERE id = ?', ws_id)

# First checks cache, falls back to DB if miss
workspace = cache.get_or_fetch(
    f'workspace:{ws_id}',
    lambda: fetch_workspace_from_db(ws_id),
    ttl=1800  # 30 minutes
)

# ─── Automatic Caching via Decorator ───────────────────────────────

@cache.cached(ttl=3600)
def expensive_computation(dataset_id, format='json'):
    # Expensive calculation
    return compute_report(dataset_id, format)

# Cache key is auto-generated from function name + args
result = expensive_computation('dataset-123', format='csv')

# ─── Pattern-Based Invalidation ────────────────────────────────────

# Clear all search results when embeddings change
cache.invalidate_pattern('search:results:*')

# ─── Event-Based Invalidation ─────────────────────────────────────

# When user updates, invalidate related caches
cache.invalidate_event('user_updated')  # Clears 'user:*' and 'session:*'

# When workspace updates, invalidate related caches  
cache.invalidate_event('workspace_updated')  # Clears workspace and search caches

# ─── Monitoring Performance ───────────────────────────────────────

stats = cache.get_stats()
print(f"Cache hit rate: {stats['hit_rate']}")
print(f"Successful requests: {stats['hits']}")
print(f"Cache misses: {stats['misses']}")
```

### TTL Policies

Cache automatically applies TTLs based on key patterns:

| Pattern | TTL | Use Case |
|---------|-----|----------|
| `session:*` | 24 hours | User sessions |
| `user:*` | 1 hour | User profile data |
| `workspace:*` | 30 minutes | Workspace configuration |
| `embeddings:*` | 7 days | Vector embeddings (infrequent changes) |
| `search:results:*` | 5 minutes | Search result pages |
| `file:content:*` | 1 hour | File content cache |
| `query:*` | 15 minutes | Database query results |
| `token:*` | 10 minutes | Auth tokens |

### Cache Invalidation Events

```python
# After user update
cache.invalidate_event('user_updated')
# → Clears: user:*, session:*

# After workspace update
cache.invalidate_event('workspace_updated')
# → Clears: workspace:*, search:results:*

# After embeddings update
cache.invalidate_event('embeddings_updated')
# → Clears: embeddings:*, search:results:*

# After file modification
cache.invalidate_event('file_modified')
# → Clears: file:content:*, search:results:*
```

## Database Optimization

### Connection Pooling Setup

```python
from performance.database_optimization import get_db_pool, QueryOptimizations

# Initialize pool (auto-creates singleton)
db = get_db_pool(
    dsn='postgresql://user:pass@localhost/code-server-enterprise'
)

# Use pooled connections (auto cleanup)
with db.get_connection() as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        result = cur.fetchone()
```

### Pool Configuration (optimized for production)

- **Min connections**: 5 (maintain baseline)
- **Max connections**: 50 (handle peak load)
- **Connection timeout**: 30s
- **Max overflow**: 10 (allow temp exceeding max)
- **Statement timeout**: 60 seconds (prevent hanging queries)

### Prevent N+1 Queries

```python
# ❌ BAD: N+1 Query Pattern
workspace = db.execute_query(
    "SELECT * FROM workspaces WHERE id = %s",
    (ws_id,), fetch_one=True
)
files = db.execute_query(
    "SELECT * FROM files WHERE workspace_id = %s",
    (ws_id,), fetch_all=True
)
# 2 queries total, scales to N+1 if in a loop

# ✓ GOOD: Optimized Single Query
workspace_data = QueryOptimizations.get_workspace_with_files(db, ws_id)
# 1 query, includes all related data
```

### Create Recommended Indexes

```python
db = get_db_pool()

# Create all recommended indexes
db.create_indexes()

# This creates optimizations for:
# - User lookups by email, creation date, active status
# - Workspace queries by owner and date
# - File queries by path, modification date
# - Embedding similarity searches
# - Query logs by user and date
```

### Monitor Slow Queries

```python
# Get statistics
stats = db.get_stats()
print(f"Slow query rate: {stats['slow_query_rate']}")
print(f"Total queries: {stats['total_queries']}")

# Analyze slow queries
slow_queries = db.analyze_slow_queries()
for query in slow_queries:
    print(f"Query: {query['query']}")
    print(f"  Avg time: {query['mean_time']}ms")
    print(f"  Max time: {query['max_time']}ms")
    print(f"  Total time: {query['total_time']}ms")

# Get table statistics
stats = db.get_table_stats('users')
print(f"Live rows: {stats['live_rows']}")
print(f"Dead rows: {stats['dead_rows']}")  # Candidates for VACUUM
print(f"Table size: {stats['table_size']}")
```

## Integration Example: Complete Caching + DB Stack

```python
from services.cache_manager import get_cache_manager
from performance.database_optimization import get_db_pool, QueryOptimizations

class WorkspaceService:
    def __init__(self):
        self.cache = get_cache_manager()
        self.db = get_db_pool()
    
    def get_workspace(self, workspace_id: str, force_refresh: bool = False):
        """Get workspace with caching layer"""
        cache_key = f'workspace:{workspace_id}:full'
        
        # Return cached if available and not forcing refresh
        if not force_refresh:
            cached = self.cache.get(cache_key)
            if cached:
                return cached
        
        # Fetch from DB using optimized query (prevents N+1)
        workspace_data = QueryOptimizations.get_workspace_with_files(
            self.db, workspace_id
        )
        
        # Cache the result (auto-applies 30 min TTL based on pattern)
        self.cache.set(cache_key, workspace_data)
        
        return workspace_data
    
    def update_workspace(self, workspace_id: str, updates: dict):
        """Update workspace and invalidate caches"""
        # Update database
        self.db.execute_query(
            "UPDATE workspaces SET name = %s, description = %s WHERE id = %s",
            (updates['name'], updates['description'], workspace_id)
        )
        
        # Invalidate all workspace-related caches
        self.cache.invalidate_event('workspace_updated')

service = WorkspaceService()

# Get workspace (from cache on 2nd call)
ws = service.get_workspace('ws-123')

# Update workspace (invalidates cache)
service.update_workspace('ws-123', {'name': 'New Name'})

# Next get will re-fetch from DB
ws = service.get_workspace('ws-123')
```

## Performance Targets & SLOs

### Target Metrics (Phase 5.3)

| Service | Baseline | Target | SLO |
|---------|----------|--------|-----|
| Code Server P99 | 750ms | <500ms | 99.9% |
| Agent API P99 | 250ms | <200ms | 99.9% |
| Embeddings P95 | 2.5s | <1s | 99.5% |
| RBAC P99 | 150ms | <100ms | 99.9% |
| File Ops P99 | 500ms | <300ms | 99.9% |

### Cache Hit Rate Target

- **Minimum**: 60% overall hit rate
- **Target**: 80% overall hit rate
- **Optimal**: >85% hit rate

### Database Query Performance

- **P95**: <100ms for index queries
- **P99**: <300ms for complex joins
- **Slow query rate**: <5% of all queries

## Deployment with Kubernetes Auto-Scaling

See `performance/scaling/k8s-deployment.yaml` for:
- Horizontal Pod Autoscaler (HPA) configuration
- Resource requests/limits
- Readiness/liveness probes
- Service definitions

### Key auto-scaling thresholds:
- **Scale up**: CPU >70% or Memory >80%
- **Min replicas**: 3
- **Max replicas**: 10
- **Scale down cooldown**: 5 minutes

## Monitoring & Observability

### Prometheus Metrics

The system exports metrics for:
- Request latency (histogram percentiles)
- Cache hit/miss rates
- Database connection pool usage
- Slow query counters
- Error rates by service

### Grafana Dashboards

- `agent-farm-overview.json`: Overall system health
- Query performance dashboard
- Cache statistics dashboard
- Database connection pool status

### Health Checks

All services expose health endpoints:
- Code Server: `GET /healthz` (<50ms)
- Agent API: `GET /health` (<50ms)
- Embeddings: `GET /api/v1/heartbeat` (<50ms)
- Ollama: `GET /api/tags` (<100ms)

## Next Steps

1. **Run baseline tests**: `k6 run performance/benchmarks/k6-comprehensive-load-test.js`
2. **Deploy Redis**: `docker-compose up -d redis`
3. **Create indexes**: `python -c "from performance.database_optimization import get_db_pool; get_db_pool().create_indexes()"`
4. **Integrate caching**: Add cache decorators to hot paths
5. **Monitor performance**: Review Grafana dashboards
6. **Optimize queries**: Use QueryOptimizations patterns
7. **Deploy with auto-scaling**: Update Kubernetes deployment

## Files in Phase 5.3

- `performance/PERFORMANCE_OPTIMIZATION.md` - Overall strategy
- `performance/benchmarks/k6-comprehensive-load-test.js` - Load testing suite
- `services/cache_manager.py` - Redis caching implementation
- `performance/database_optimization.py` - DB pooling & optimization
- `performance/caching/redis.conf` - Redis configuration
- `performance/optimization/database-optimization.sql` - SQL optimizations
- `performance/scaling/k8s-deployment.yaml` - Kubernetes config
- `config/recommended-models.yaml` - Ollama model recommendations

## Troubleshooting

**Cache not warming up?**
```python
# Manually warm cache before peak hours
cache_data = {
    'workspace:ws-123': workspace_obj,
    'user:u-456': user_obj,
}
cache.warm_cache(cache_data)
```

**Slow queries not appearing?**
```python
# Ensure pg_stat_statements extension is enabled
db.execute_query("CREATE EXTENSION IF NOT EXISTS pg_stat_statements;")
```

**Connection pool exhaustion?**
Increase maxconn in DatabaseConfig.POOL_CONFIG or add read replicas for SELECT queries.

**High cache eviction rate?**
Increase Redis memory limit or adjust TTL policies to reduce cache bloat.
