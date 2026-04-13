# Optimization Guide for On-Premises Deployments

**Phase**: 10 - On-Premises Performance Optimization  
**Focus**: Deep optimization techniques for database, application, and infrastructure  
**Target**: Extract maximum performance from available hardware

## Database Optimization

### 1. Query Optimization

**N+1 Query Problem** (common anti-pattern):
```python
# BAD: N+1 queries (1 main query + N subqueries)
users = User.query.all()  # 1 query
for user in users:
    print(user.posts)  # N additional queries!

# GOOD: Single query with JOIN
users = User.query.options(joinedload(User.posts)).all()  # 1 query with join

# GOOD: Batch loading
users = User.query.all()
user_ids = [u.id for u in users]
posts = Post.query.filter(Post.user_id.in_(user_ids)).all()  # 1 batch query
```

**Query Analysis and Indexing**:
```sql
-- Find slow queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
WHERE mean_time > 10  -- queries taking >10ms
ORDER BY total_time DESC
LIMIT 20;

-- Check query plan
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM embeddings 
WHERE text_hash = md5('example')
LIMIT 1;

-- Create indexes for frequent filters
CREATE INDEX idx_embeddings_text_hash ON embeddings(text_hash);
CREATE INDEX idx_embeddings_created_at ON embeddings(created_at DESC);

-- Multi-column index for common query patterns
CREATE INDEX idx_embeddings_hash_time ON embeddings(text_hash, created_at DESC);

-- Partial index for active records only
CREATE INDEX idx_embeddings_active ON embeddings(id) 
WHERE archived = false;

-- GiST index for vector similarity (if using pgvector)
CREATE INDEX embedded_search ON embeddings USING gist (vector gist_l2_ops);
```

**Query Optimization Examples**:

```sql
-- SLOW: Full table scan
SELECT * FROM embeddings WHERE text_hash LIKE '%value%';

-- FAST: Hash lookup with index
SELECT * FROM embeddings WHERE text_hash = md5('value');

-- SLOW: Multiple OR conditions
SELECT * FROM sessions 
WHERE user_id = 1 OR user_id = 2 OR user_id = 3;

-- FAST: IN clause with index
SELECT * FROM sessions WHERE user_id IN (1, 2, 3);

-- SLOW: Correlated subquery
SELECT u.id, (SELECT COUNT(*) FROM posts WHERE user_id = u.id) 
FROM users u;

-- FAST: JOIN with GROUP BY and HAVING
SELECT u.id, COUNT(p.id) as post_count
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
GROUP BY u.id;
```

### 2. Connection Pooling

**PgBouncer Configuration** (on-premises):
```ini
# pgbouncer.ini
[databases]
code_server = host=localhost port=5432 dbname=code_server user=app

[pgbouncer]
# Pool Configuration
pool_mode = transaction          # Transaction pooling (default)
max_client_conn = 1000           # Max client connections
default_pool_size = 25           # Connections per database
min_pool_size = 10               # Minimum idle connections
reserve_pool_size = 5            # Emergency reserve pool
reserve_pool_timeout = 3         # Timeout for reserve

# Performance
server_lifetime = 3600           # Reuse connection after 1 hour
server_idle_timeout = 600        # Close idle after 10 minutes
hang_timeout = 30                # Hang detection

# Batching for efficiency
batch_size = 5                   # Process multiple clients per loop
sbuf_lookahead = 1024            # Buffer size

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
```

**Django Connection Pooling**:
```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'HOST': 'localhost',
        'PORT': '6432',  # pgbouncer port
        'CONN_MAX_AGE': 60,
        'OPTIONS': {
            'connect_timeout': 10,
            'options': '-c statement_timeout=30000'  # 30s timeout
        }
    }
}

# SQLAlchemy Connection Pooling
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

engine = create_engine(
    'postgresql://user:password@localhost:6432/code_server',
    poolclass=QueuePool,
    pool_size=25,        # Connections in pool
    max_overflow=10,     # Additional connections when needed
    pool_recycle=3600,   # Recycle connections after 1 hour
    pool_pre_ping=True,  # Test connections before using
    echo_pool=False,     # Log pool operations
)
```

### 3. Prepared Statements

**Benefits**: Parse once, execute many times

```python
# SQLAlchemy (automatic prepared statements)
from sqlalchemy.sql import text

# Parameterized query (prevents SQL injection)
query = text("""
    SELECT * FROM embeddings 
    WHERE text_hash = :hash 
    AND created_at > :min_date
""")

result = db.execute(query, {"hash": md5_hash, "min_date": datetime.now()})

# psycopg2 (Python PostgreSQL driver)
import psycopg2

conn = psycopg2.connect("dbname=code_server")
cur = conn.cursor()

# Prepared statement
cur.execute("""
    PREPARE get_embedding AS
    SELECT * FROM embeddings WHERE text_hash = $1
    LIMIT 1
""")

cur.execute("EXECUTE get_embedding (%s)", (hash_value,))
result = cur.fetchone()
```

### 4. Materialized Views (Query Caching)

```sql
-- Create materialized view for expensive computation
CREATE MATERIALIZED VIEW user_embedding_stats AS
SELECT 
    u.id as user_id,
    u.name,
    COUNT(e.id) as total_embeddings,
    AVG(LENGTH(e.text)) as avg_text_length,
    MAX(e.created_at) as latest_embedding
FROM users u
LEFT JOIN embeddings e ON u.id = e.created_by_user
GROUP BY u.id, u.name;

-- Index for fast lookups
CREATE UNIQUE INDEX idx_user_stats_id ON user_embedding_stats(user_id);

-- Refresh periodically (run daily via cron)
REFRESH MATERIALIZED VIEW CONCURRENTLY user_embedding_stats;

-- Query the materialized view (very fast)
SELECT * FROM user_embedding_stats WHERE user_id = 123;

-- Schedule refresh (add to Kubernetes CronJob)
0 2 * * * psql code_server -c \
  "REFRESH MATERIALIZED VIEW CONCURRENTLY user_embedding_stats"
```

## Application Optimization

### 1. Batch Processing

```python
# SLOW: Process one at a time
for item in items:
    process_item(item)

# FAST: Batch processing
BATCH_SIZE = 100
for i in range(0, len(items), BATCH_SIZE):
    batch = items[i:i+BATCH_SIZE]
    process_batch(batch)

# FastAPI batch endpoint
from fastapi import FastAPI
app = FastAPI()

@app.post("/batch/embeddings")
async def batch_embeddings(texts: list[str]):
    """Process multiple texts at once"""
    # Single GPU call for batch
    embeddings = model.encode(texts, batch_size=32, show_progress_bar=False)
    return {"embeddings": embeddings}

# Usage in client
import asyncio

texts = [...]
batch_size = 100
async with aiohttp.ClientSession() as session:
    for i in range(0, len(texts), batch_size):
        batch = texts[i:i+batch_size]
        async with session.post(
            "http://embeddings:5000/batch/embeddings",
            json={"texts": batch}
        ) as resp:
            results = await resp.json()
```

### 2. Async I/O

```python
# FastAPI with async queries
from fastapi import FastAPI
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine

app = FastAPI()
engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/db")

@app.get("/embeddings")
async def get_embeddings(text: str):
    # Non-blocking database query
    async with AsyncSession(engine) as session:
        result = await session.execute(
            select(Embeddings).where(Embeddings.text_hash == md5(text))
        )
        return result.scalars().first()

# Concurrent requests (multiple queries in parallel)
@app.post("/batch-data")
async def get_batch_data(ids: list[int]):
    # Run 10 queries concurrently
    tasks = [
        fetch_user_data(id) for id in ids
    ]
    results = await asyncio.gather(*tasks)
    return results

async def fetch_user_data(user_id: int):
    async with AsyncSession(engine) as session:
        return await session.get(User, user_id)
```

### 3. Memory Efficiency

**Generator Functions** (don't load all data at once):
```python
# MEMORY INTENSIVE: Load all data into list
def get_all_embeddings():
    return [e for e in db.query(Embeddings).all()]

# MEMORY EFFICIENT: Use generator
def get_all_embeddings():
    for embedding in db.query(Embeddings).yield_per(1000):
        yield embedding

# Usage
for embedding in get_all_embeddings():
    process_embedding(embedding)  # Process one at a time

# In FastAPI streaming response
from fastapi.responses import StreamingResponse

@app.get("/embeddings/stream")
async def stream_embeddings():
    async def generate():
        for embedding in get_all_embeddings():
            yield f"{embedding.id},{embedding.vector}\n"
    
    return StreamingResponse(generate(), media_type="text/csv")
```

**Object Pool Pattern**:
```python
from collections import deque
import threading

class ObjectPool:
    def __init__(self, factory, size=10):
        self.pool = deque([factory() for _ in range(size)])
        self.lock = threading.Lock()
    
    def acquire(self):
        with self.lock:
            if self.pool:
                return self.pool.popleft()
            return None
    
    def release(self, obj):
        with self.lock:
            self.pool.append(obj)

# Usage with database connections
conn_pool = ObjectPool(lambda: psycopg2.connect("dbname=code_server"), size=25)

conn = conn_pool.acquire()
try:
    # Use connection
    cur = conn.cursor()
    cur.execute("SELECT...")
finally:
    conn_pool.release(conn)
```

## Infrastructure Optimization

### 1. Kubernetes Resource Limits

**Right-sizing Requests and Limits**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent-api
spec:
  template:
    spec:
      containers:
      - name: agent-api
        image: agent-api:latest
        resources:
          requests:
            cpu: 1000m        # Guaranteed allocation
            memory: 1Gi
          limits:
            cpu: 2000m        # Maximum allowed
            memory: 2Gi
        # Quality of Service: Burstable (requests < limits)
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 1
```

### 2. Storage Optimization

**Local SSD vs Network Storage**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fast-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-local
  local:
    path: /mnt/nvme          # Fast local SSD
  # Bind to specific node
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: disk
          operator: In
          values: ["nvme"]
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: shared-pv
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteMany          # NFS (shared across nodes)
  storageClassName: shared
  nfs:
    server: nas.internal
    path: "/code-server-data"
```

## Monitoring & Profiling

### 1. CPU Profiling (Python)

```python
import cProfile
import pstats
import io

def profile_function():
    pr = cProfile.Profile()
    pr.enable()
    
    # Run expensive operation
    result = expensive_computation()
    
    pr.disable()
    s = io.StringIO()
    ps = pstats.Stats(pr, stream=s).sort_stats('cumulative')
    ps.print_stats(20)  # Top 20 functions
    print(s.getvalue())
    
    return result

# Or use decorator
from functools import wraps

def profile(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        pr = cProfile.Profile()
        pr.enable()
        result = func(*args, **kwargs)
        pr.disable()
        
        s = io.StringIO()
        ps = pstats.Stats(pr, stream=s).sort_stats('cumulative')
        ps.print_stats(10)
        print(f"Profile for {func.__name__}:")
        print(s.getvalue())
        
        return result
    return wrapper

@profile
def my_expensive_function():
    pass
```

### 2. Memory Profiling

```python
from memory_profiler import profile

@profile
def memory_intensive_function():
    large_list = [str(i) for i in range(10000000)]
    return sum(len(s) for s in large_list)

# Run with: python -m memory_profiler script.py
# Shows line-by-line memory usage
```

### 3. Prometheus Metrics

```python
from prometheus_client import Counter, Histogram, Gauge
import time

# Define metrics
request_count = Counter('api_requests_total', 'Total requests', ['method', 'endpoint'])
request_duration = Histogram('api_request_duration_seconds', 'Request duration', ['endpoint'])
db_connections = Gauge('db_connections_active', 'Active DB connections')

# Use in code
@app.get("/embeddings")
async def get_embeddings(text: str):
    start = time.time()
    request_count.labels(method='GET', endpoint='/embeddings').inc()
    
    try:
        # Business logic
        result = await fetch_embeddings(text)
        return result
    finally:
        duration = time.time() - start
        request_duration.labels(endpoint='/embeddings').observe(duration)
```

## Performance Checklist

### Before Production Deployment

- [ ] Database Connection Pooling (PgBouncer)
- [ ] Query Optimization (explain analyze)
- [ ] Prepared Statements (parameterized queries)
- [ ] Materialized Views (expensive aggregations)
- [ ] Batch Processing (bulk operations)
- [ ] Async I/O (FastAPI, aiohttp)
- [ ] Memory Profiling (identify leaks)
- [ ] CPU Profiling (find bottlenecks)
- [ ] Caching Strategy (multi-layer)
- [ ] Resource Limits (Kubernetes)
- [ ] Health Probes (readiness/liveness)
- [ ] Monitoring Dashboards (Prometheus/Grafana)

### Optimization Priorities

1. **Database queries** (biggest impact, 50-80% improvement)
2. **Caching strategy** (30-60% improvement)
3. **Connection pooling** (20-40% improvement)
4. **Batch processing** (20-50% improvement)
5. **Resource allocation** (10-30% improvement)
6. **Async I/O** (5-20% improvement)

---

**Phase 10**: Optimization Guide  
**Status**: ✅ Complete  
**Next**: Configuration Profiles
