#!/usr/bin/env python3
"""
Phase 5 Week 4: Performance Tuning Analysis Tool

Analyzes performance test results to identify bottlenecks and
recommends optimization strategies.

Usage:
  python3 scripts/perf/analyze-bottlenecks.py results/ --scenario=heavy
  python3 scripts/perf/analyze-bottlenecks.py results/ --compare=baseline.json
"""

import json
import csv
import sys
from pathlib import Path
from datetime import datetime
import statistics
from typing import Dict, List, Tuple

def load_performance_data(results_dir: Path, scenario: str = None) -> Dict:
    """Load all performance test results"""
    results = {}
    
    for csv_file in sorted(results_dir.glob("*.csv")):
        if scenario and scenario not in csv_file.name:
            continue
        
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                endpoint = row.get('Name', 'Unknown')
                try:
                    results[endpoint] = {
                        'requests': int(row.get('# requests', 0)),
                        'failures': int(row.get('# failures', 0)),
                        'avg_response': float(row.get('Average Response Time', 0)),
                        'min_response': float(row.get('Min Response Time', 0)),
                        'max_response': float(row.get('Max Response Time', 0)),
                        'p95': float(row.get('95%', 0)),
                        'p99': float(row.get('99%', 0)),
                    }
                except (ValueError, TypeError):
                    continue
    
    return results

def identify_bottlenecks(results: Dict) -> List[Dict]:
    """Identify performance bottlenecks"""
    bottlenecks = []
    
    # Sort endpoints by response time
    sorted_endpoints = sorted(
        results.items(),
        key=lambda x: x[1]['avg_response'],
        reverse=True
    )
    
    for endpoint, metrics in sorted_endpoints[:5]:  # Top 5 slowest
        if metrics['requests'] > 0:
            error_rate = (metrics['failures'] / metrics['requests'] * 100)
            
            bottleneck = {
                'endpoint': endpoint,
                'avg_response_ms': metrics['avg_response'],
                'p95_response_ms': metrics['p95'],
                'max_response_ms': metrics['max_response'],
                'error_rate_percent': error_rate,
                'requests': metrics['requests'],
                'severity': 'high' if metrics['avg_response'] > 500 else 'medium',
            }
            bottlenecks.append(bottleneck)
    
    return bottlenecks

def generate_optimization_plan(bottlenecks: List[Dict]) -> Dict:
    """Generate optimization recommendations"""
    plan = {
        'timestamp': datetime.now().isoformat(),
        'priority_optimizations': [],
        'general_recommendations': [],
    }
    
    for i, bottleneck in enumerate(bottlenecks[:3], 1):
        endpoint = bottleneck['endpoint']
        
        if 'activities' in endpoint.lower():
            plan['priority_optimizations'].append({
                'priority': i,
                'endpoint': endpoint,
                'issue': 'High activity endpoint latency',
                'root_causes': [
                    'N+1 query problem in activity listing',
                    'Missing database indexes on created_at',
                    'No query result caching',
                ],
                'optimizations': [
                    'Add LIMIT to activity queries',
                    'Create composite index on (user_id, created_at DESC)',
                    'Implement Redis caching for popular activities',
                    'Use database connection pooling (PgBouncer)',
                ],
                'estimated_improvement': '30-50%',
            })
        elif 'reputation' in endpoint.lower():
            plan['priority_optimizations'].append({
                'priority': i,
                'endpoint': endpoint,
                'issue': 'Slow reputation calculation',
                'root_causes': [
                    'Computing reputation on every request',
                    'Querying entire user history for each score',
                    'No query result caching',
                ],
                'optimizations': [
                    'Pre-calculate and cache reputation scores',
                    'Update cache asynchronously every 1 hour',
                    'Add Redis cache layer (TTL: 1 hour)',
                    'Implement background job for score updates',
                ],
                'estimated_improvement': '40-60%',
            })
        else:
            plan['priority_optimizations'].append({
                'priority': i,
                'endpoint': endpoint,
                'issue': f'High latency on {endpoint}',
                'root_causes': [
                    'Missing database indexes',
                    'No query caching',
                    'Slow upstream dependencies',
                ],
                'optimizations': [
                    'Profile database queries using EXPLAIN ANALYZE',
                    'Add missing indexes',
                    'Implement result caching',
                    'Consider query optimization',
                ],
                'estimated_improvement': '25-40%',
            })
    
    # General recommendations
    plan['general_recommendations'] = [
        {
            'category': 'Database Optimization',
            'recommendations': [
                'Run VACUUM ANALYZE on all tables',
                'Verify indexes are being used (EXPLAIN ANALYZE)',
                'Monitor slow query log',
                'Implement connection pooling (PgBouncer or pgpool)',
                'Consider partitioning large tables',
            ],
        },
        {
            'category': 'Caching Strategy',
            'recommendations': [
                'Implement Redis for query result caching',
                'Cache popular searches (TTL: 5 minutes)',
                'Cache user reputation scores (TTL: 1 hour)',
                'Cache activity feed (TTL: 2 minutes)',
                'Use cache-aside pattern',
            ],
        },
        {
            'category': 'Application Code',
            'recommendations': [
                'Batch database queries where possible',
                'Use database aggregation instead of application logic',
                'Implement lazy loading for related data',
                'Add request-level query caching',
                'Consider pagination limits',
            ],
        },
        {
            'category': 'Infrastructure',
            'recommendations': [
                'Monitor container resource usage',
                'Scale horizontally if CPU-bound',
                'Increase memory if memory-bound',
                'Monitor network latency to database',
                'Use CDN for static assets',
            ],
        },
    ]
    
    return plan

def generate_sql_optimizations() -> str:
    """Generate SQL optimization scripts"""
    return """
-- SQL Optimization Scripts for Performance Tuning

-- 1. Create missing indexes
CREATE INDEX IF NOT EXISTS idx_activities_user_created 
  ON activities(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_activities_created 
  ON activities(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reputation_scores_user 
  ON reputation_scores(user_id);

CREATE INDEX IF NOT EXISTS idx_executions_status 
  ON executions(status, created_at DESC);

-- 2. Analyze table statistics
ANALYZE activities;
ANALYZE reputation_scores;
ANALYZE executions;
ANALYZE users;

-- 3. Vacuum to reclaim space and update statistics
VACUUM ANALYZE activities;
VACUUM ANALYZE reputation_scores;
VACUUM ANALYZE executions;

-- 4. Enable parallelization for large queries
ALTER DATABASE codeserver SET max_parallel_workers_per_gather = 4;
ALTER DATABASE codeserver SET max_parallel_workers = 4;

-- 5. Optimize connection settings
SHOW max_connections;  -- Should be sufficient for load
SHOW shared_buffers;   -- Should be 25% of RAM
SHOW effective_cache_size;  -- Should be 75% of RAM
SHOW work_mem;  -- Should be (RAM - shared_buffers) / (max_connections * 2)

-- 6. Create covering indexes for common queries
CREATE INDEX IF NOT EXISTS idx_activities_user_type 
  ON activities(user_id, type, created_at DESC) 
  INCLUDE (description, status);

-- 7. Configure connection pooling (PgBouncer)
-- Add to pgbouncer.ini:
-- [databases]
-- codeserver = host=localhost port=5432 dbname=codeserver

-- 8. Query performance monitoring
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;
"""

def generate_redis_config() -> str:
    """Generate Redis caching configuration"""
    return """
# Redis Caching Configuration for Performance Optimization

# Cache Key Patterns
# activities:user:{user_id}:list = List of recent activities for user
# reputation:user:{user_id} = Reputation score for user  
# executions:status:{status} = Executions with specific status
# query:{hash} = Generic query result cache

# TTL Configuration (in seconds)
ACTIVITY_LIST_TTL = 120          # 2 minutes
REPUTATION_SCORE_TTL = 3600      # 1 hour
EXECUTION_STATUS_TTL = 300       # 5 minutes
QUERY_RESULT_TTL = 300           # 5 minutes

# Cache Invalidation Triggers
# - User updates activity → Invalidate activities:user:{user_id}:list
# - Reputation updated → Invalidate reputation:user:{user_id}
# - Execution status changes → Invalidate executions:status:{status}

# Redis Configuration Settings
maxmemory 2gb
maxmemory-policy allkeys-lru
timeout 0
tcp-backlog 511
databases 16

# Persistence
save 900 1      # Save every 15 minutes if 1+ keys changed
save 300 10     # Save every 5 minutes if 10+ keys changed
save 60 10000   # Save every 60 seconds if 10000+ keys changed

# Replication for HA
# slaveof <ip> <port>

# Monitoring
slowlog-log-slower-than 10000  # Log queries slower than 10ms
slowlog-max-len 128
"""

def generate_application_code_hints() -> str:
    """Generate application code optimization hints"""
    return """
# Application Code Optimization Patterns

## Pattern 1: Query Caching
```python
from functools import lru_cache
import hashlib

@lru_cache(maxsize=1024)
def get_user_activities(user_id: int, limit: int = 50):
    return db.query(Activity).filter_by(user_id=user_id).limit(limit).all()
```

## Pattern 2: Redis Cache Integration
```python
import redis

cache = redis.Redis(host='localhost', port=6379, db=0)

def get_reputation_score(user_id: int):
    cache_key = f'reputation:user:{user_id}'
    
    # Try cache first
    cached = cache.get(cache_key)
    if cached:
        return float(cached)
    
    # Calculate if not in cache
    score = calculate_reputation(user_id)
    cache.setex(cache_key, 3600, score)  # Cache for 1 hour
    return score
```

## Pattern 3: Batch Loading
```python
def get_multiple_activities(activity_ids: List[int]):
    # Bad: N+1 queries
    # activities = [get_activity(id) for id in activity_ids]
    
    # Good: Single query
    activities = db.query(Activity).filter(Activity.id.in_(activity_ids)).all()
    return {a.id: a for a in activities}
```

## Pattern 4: Database Aggregation
```python
def get_user_activity_count(user_id: int):
    # Bad: Load all and count in Python
    # return len(db.query(Activity).filter_by(user_id=user_id).all())
    
    # Good: Use SQL COUNT
    from sqlalchemy import func
    return db.query(func.count(Activity.id)).filter_by(user_id=user_id).scalar()
```

## Pattern 5: Pagination
```python
def get_activities_paginated(page: int = 1, page_size: int = 50):
    offset = (page - 1) * page_size
    return db.query(Activity)\
        .order_by(Activity.created_at.desc())\
        .offset(offset)\
        .limit(page_size)\
        .all()
```

## Pattern 6: Lazy Loading
```python
from sqlalchemy import joinedload

def get_users_with_activities():
    # Avoid N+1: explicitly load relationships
    return db.query(User)\
        .options(joinedload(User.activities))\
        .all()
```
"""

def main():
    if len(sys.argv) < 2:
        print("Usage: analyze-bottlenecks.py <results_directory> [--scenario=scenario]")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    scenario = sys.argv[2].split('=')[1] if len(sys.argv) > 2 else None
    
    # Load performance data
    print("Loading performance results...")
    results = load_performance_data(results_dir, scenario)
    
    if not results:
        print("No results found")
        sys.exit(1)
    
    # Identify bottlenecks
    print("\nIdentifying performance bottlenecks...")
    bottlenecks = identify_bottlenecks(results)
    
    # Generate optimization plan
    print("Generating optimization recommendations...")
    plan = generate_optimization_plan(bottlenecks)
    
    # Output results
    print("\n" + "="*70)
    print("PERFORMANCE BOTTLENECK ANALYSIS")
    print("="*70)
    
    print("\nTOP SLOW ENDPOINTS:")
    for bn in bottlenecks:
        print(f"\n{bn['endpoint']}:")
        print(f"  Avg Response: {bn['avg_response_ms']:.0f}ms")
        print(f"  P95 Response: {bn['p95_response_ms']:.0f}ms")
        print(f"  Max Response: {bn['max_response_ms']:.0f}ms")
        print(f"  Error Rate: {bn['error_rate_percent']:.2f}%")
    
    print("\n" + "="*70)
    print("OPTIMIZATION RECOMMENDATIONS")
    print("="*70)
    
    for opt in plan['priority_optimizations']:
        print(f"\nPriority {opt['priority']}: {opt['endpoint']}")
        print(f"Issue: {opt['issue']}")
        print(f"Root Causes:")
        for cause in opt['root_causes']:
            print(f"  - {cause}")
        print(f"Optimizations:")
        for optimization in opt['optimizations']:
            print(f"  • {optimization}")
        print(f"Estimated Improvement: {opt['estimated_improvement']}")
    
    print("\n" + "="*70)
    print("GENERAL RECOMMENDATIONS")
    print("="*70)
    
    for recommendation_set in plan['general_recommendations']:
        print(f"\n{recommendation_set['category']}:")
        for rec in recommendation_set['recommendations']:
            print(f"  • {rec}")
    
    # Save SQL optimization script
    sql_script = Path(sys.argv[1]).parent / "optimization-queries.sql"
    with open(sql_script, 'w') as f:
        f.write(generate_sql_optimizations())
    print(f"\nSQL optimization script saved: {sql_script}")
    
    # Save Redis configuration
    redis_config = Path(sys.argv[1]).parent / "redis-config.conf"
    with open(redis_config, 'w') as f:
        f.write(generate_redis_config())
    print(f"Redis configuration saved: {redis_config}")
    
    # Save application code hints
    code_hints = Path(sys.argv[1]).parent / "code-optimization-patterns.py"
    with open(code_hints, 'w') as f:
        f.write(generate_application_code_hints())
    print(f"Application code patterns saved: {code_hints}")
    
    # Save JSON plan
    json_plan = Path(sys.argv[1]).parent / f"optimization-plan-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    with open(json_plan, 'w') as f:
        json.dump(plan, f, indent=2)
    print(f"Optimization plan saved: {json_plan}")

if __name__ == '__main__':
    main()
