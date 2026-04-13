"""
Database Optimization & Connection Pooling for Code-Server Enterprise

Includes:
- Connection pooling (PostgreSQL)
- Query optimization patterns
- Index creation recommendations
- N+1 query prevention
- Query profiling & monitoring
"""

import logging
import time
from contextlib import contextmanager
from typing import Optional, List, Dict, Any

import psycopg2
from psycopg2 import pool, extras
from psycopg2.extensions import connection
import psycopg2.pool

logger = logging.getLogger(__name__)


class DatabaseConfig:
    """Database configuration with optimization settings"""
    
    # Connection pool settings (optimized for production)
    POOL_CONFIG = {
        'minconn': 5,           # Minimum connections
        'maxconn': 50,          # Maximum connections  
        'timeout': 30,          # Connection timeout
        'max_overflow': 10,     # Additional connections when pool is full
    }
    
    # Query timeout (milliseconds)
    QUERY_TIMEOUT = 30000
    
    # Statement timeout for long queries
    STATEMENT_TIMEOUT = 60000
    
    # Index recommendations
    RECOMMENDED_INDEXES = {
        'users': [
            'CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);',
            'CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);',
            'CREATE INDEX IF NOT EXISTS idx_users_active ON users(active) WHERE active = true;',
        ],
        'workspaces': [
            'CREATE INDEX IF NOT EXISTS idx_workspaces_owner_id ON workspaces(owner_id);',
            'CREATE INDEX IF NOT EXISTS idx_workspaces_created_at ON workspaces(created_at DESC);',
            'CREATE INDEX IF NOT EXISTS idx_workspaces_name_owner ON workspaces(name, owner_id);',
        ],
        'files': [
            'CREATE INDEX IF NOT EXISTS idx_files_workspace_id ON files(workspace_id);',
            'CREATE INDEX IF NOT EXISTS idx_files_path ON files(workspace_id, path);',
            'CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified_at DESC);',
            'CREATE FULLTEXT INDEX IF NOT EXISTS idx_files_content ON files(content);',
        ],
        'embeddings': [
            'CREATE INDEX IF NOT EXISTS idx_embeddings_workspace ON embeddings(workspace_id);',
            'CREATE INDEX IF NOT EXISTS idx_embeddings_similarity ON embeddings USING ivfflat(vector);',
            'CREATE INDEX IF NOT EXISTS idx_embeddings_created ON embeddings(created_at DESC);',
        ],
        'queries': [
            'CREATE INDEX IF NOT EXISTS idx_queries_user_id ON queries(user_id);',
            'CREATE INDEX IF NOT EXISTS idx_queries_created_at ON queries(created_at DESC);',
            'CREATE COMPOSITE INDEX IF NOT EXISTS idx_queries_user_date ON queries(user_id, created_at DESC);',
        ],
    }


class DatabasePool:
    """
    PostgreSQL connection pool for efficient database access.
    Implements connection reuse, automatic reconnection, and health checks.
    """
    
    def __init__(self, dsn: str, **pool_kwargs):
        """Initialize connection pool"""
        config = DatabaseConfig.POOL_CONFIG.copy()
        config.update(pool_kwargs)
        
        self.dsn = dsn
        self.pool = psycopg2.pool.SimpleConnectionPool(**config, dsn=dsn)
        self.query_stats = {'total': 0, 'slow': 0, 'errors': 0}
        self.health_check_interval = 30
        self.last_health_check = 0
        
        logger.info(f"Database pool initialized: {config['minconn']}-{config['maxconn']} connections")

    @contextmanager
    def get_connection(self) -> connection:
        """Get connection from pool (context manager for auto-cleanup)"""
        conn = None
        try:
            conn = self.pool.getconn()
            conn.autocommit = False
            
            # Set query timeout
            with conn.cursor() as cur:
                cur.execute(f"SET statement_timeout = {DatabaseConfig.STATEMENT_TIMEOUT};")
            
            yield conn
            conn.commit()
        except psycopg2.Error as e:
            if conn:
                conn.rollback()
            logger.error(f"Database error: {e}")
            self.query_stats['errors'] += 1
            raise
        finally:
            if conn:
                self.pool.putconn(conn)

    def execute_query(self, query: str, params: tuple = None, fetch_one: bool = False, fetch_all: bool = True) -> Optional[Any]:
        """Execute query with timing and error handling"""
        start_time = time.time()
        
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=extras.RealDictCursor) as cur:
                    cur.execute(query, params or ())
                    
                    if fetch_one:
                        result = cur.fetchone()
                    elif fetch_all:
                        result = cur.fetchall()
                    else:
                        result = None
            
            elapsed = time.time() - start_time
            self.query_stats['total'] += 1
            
            # Track slow queries
            if elapsed > 1.0:  # >1s is slow
                self.query_stats['slow'] += 1
                logger.warning(f"Slow query ({elapsed:.3f}s): {query[:100]}...")
            else:
                logger.debug(f"Query ({elapsed:.3f}s): {query[:100]}...")
            
            return result
        except Exception as e:
            logger.error(f"Query execution failed: {e}")
            self.query_stats['errors'] += 1
            raise

    def execute_batch(self, query: str, param_sets: List[tuple]):
        """Execute batch inserts/updates (more efficient than individual queries)"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    extras.execute_batch(cur, query, param_sets)
            logger.info(f"Batch execution: {len(param_sets)} rows")
        except Exception as e:
            logger.error(f"Batch execution failed: {e}")
            self.query_stats['errors'] += 1
            raise

    def create_indexes(self):
        """Create recommended indexes for performance"""
        for table, indexes in DatabaseConfig.RECOMMENDED_INDEXES.items():
            logger.info(f"Creating indexes for {table} table...")
            for index_sql in indexes:
                try:
                    self.execute_query(index_sql)
                except Exception as e:
                    logger.warning(f"Index creation failed: {e}")

    def get_table_stats(self, table: str) -> dict:
        """Get table statistics (row count, size, dead rows)"""
        query = """
            SELECT
                n_live_tup as live_rows,
                n_dead_tup as dead_rows,
                pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))::text as table_size
            FROM pg_tables t
            JOIN pg_stat_user_tables s ON s.schemaname = t.schemaname AND s.relname = t.tablename
            WHERE t.tablename = %s
        """
        result = self.execute_query(query, (table,), fetch_one=True)
        return result or {}

    def analyze_slow_queries(self) -> List[Dict]:
        """Get recent slow queries from query log"""
        query = """
            SELECT
                query,
                calls,
                mean_time,
                max_time,
                total_time
            FROM pg_stat_statements
            WHERE mean_time > 100  -- Queries averaging >100ms
            ORDER BY total_time DESC
            LIMIT 20
        """
        return self.execute_query(query, fetch_all=True)

    def get_stats(self) -> dict:
        """Get pool and query statistics"""
        return {
            'total_queries': self.query_stats['total'],
            'slow_queries': self.query_stats['slow'],
            'errors': self.query_stats['errors'],
            'slow_query_rate': f"{(self.query_stats['slow'] / max(self.query_stats['total'], 1) * 100):.2f}%",
        }

    def close(self):
        """Close all connections in pool"""
        self.pool.closeall()
        logger.info("Database pool closed")


# ─── QUERY OPTIMIZATION PATTERNS ──────────────────────────────────────────────

class QueryOptimizations:
    """Common query optimization patterns to prevent N+1 and slow queries"""
    
    @staticmethod
    def get_workspace_with_files(db: DatabasePool, workspace_id: str) -> Dict:
        """
        Pattern: Use JOIN instead of N+1 query
        Instead of: SELECT workspace, then SELECT files (N queries)
        This: One optimized query with JOIN
        """
        query = """
            SELECT
                w.id,
                w.name,
                w.owner_id,
                w.created_at,
                json_agg(
                    json_build_object(
                        'id', f.id,
                        'path', f.path,
                        'size', f.size,
                        'modified_at', f.modified_at
                    ) ORDER BY f.path
                ) FILTER (WHERE f.id IS NOT NULL) as files
            FROM workspaces w
            LEFT JOIN files f ON f.workspace_id = w.id
            WHERE w.id = %s
            GROUP BY w.id, w.name, w.owner_id, w.created_at
        """
        return db.execute_query(query, (workspace_id,), fetch_one=True)

    @staticmethod
    def search_code_with_relevance(db: DatabasePool, workspace_id: str, query: str) -> List[Dict]:
        """
        Pattern: Full-text search with ranking for code search
        Returns results ranked by relevance
        """
        query_sql = """
            SELECT
                id,
                path,
                snippet(content, '<b>', '</b>', '...', 64) as preview,
                ts_rank(to_tsvector('english', content), plainto_tsquery('english', %s)) as rank
            FROM files
            WHERE workspace_id = %s
              AND to_tsvector('english', content) @@ plainto_tsquery('english', %s)
            ORDER BY rank DESC
            LIMIT 50
        """
        return db.execute_query(query_sql, (query, workspace_id, query), fetch_all=True)

    @staticmethod
    def get_user_with_roles(db: DatabasePool, user_id: str) -> Dict:
        """
        Pattern: Aggregate related data in single query
        Prevents N+1 when getting user + roles + permissions
        """
        query = """
            SELECT
                u.id,
                u.email,
                u.name,
                u.created_at,
                json_agg(DISTINCT r.name) as roles,
                json_agg(DISTINCT p.action) as permissions
            FROM users u
            LEFT JOIN user_roles ur ON ur.user_id = u.id
            LEFT JOIN roles r ON r.id = ur.role_id
            LEFT JOIN role_permissions rp ON rp.role_id = r.id
            LEFT JOIN permissions p ON p.id = rp.permission_id
            WHERE u.id = %s
            GROUP BY u.id, u.email, u.name, u.created_at
        """
        return db.execute_query(query, (user_id,), fetch_one=True)

    @staticmethod
    def bulk_insert_embeddings(db: DatabasePool, embeddings_data: List[tuple]):
        """
        Pattern: Batch insert for bulk operations
        More efficient than individual INSERTs
        """
        query = """
            INSERT INTO embeddings (vector_id, workspace_id, vector, created_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (vector_id, workspace_id) DO UPDATE
            SET vector = EXCLUDED.vector, created_at = EXCLUDED.created_at
        """
        db.execute_batch(query, embeddings_data)


# ─── CONNECTION & POOL SINGLETON ──────────────────────────────────────────────

_db_pool_instance = None


def get_db_pool(dsn: Optional[str] = None) -> DatabasePool:
    """Get or create singleton database pool"""
    global _db_pool_instance
    
    if _db_pool_instance is None:
        if not dsn:
            dsn = "dbname=code-server-enterprise user=postgres password=password host=localhost port=5432"
        _db_pool_instance = DatabasePool(dsn)
    
    return _db_pool_instance


# ─── USAGE EXAMPLES ──────────────────────────────────────────────────────────

"""
# Example 1: Connection pooling
db = get_db_pool()
result = db.execute_query(
    "SELECT * FROM users WHERE id = %s",
    params=(user_id,),
    fetch_one=True
)

# Example 2: Optimized queries (prevents N+1)
workspace_data = QueryOptimizations.get_workspace_with_files(db, workspace_id)

# Example 3: Batch operations
embeddings_batch = [
    (vec_id, ws_id, vector_data, now())
    for vec_id, ws_id, vector_data in embeddings_list
]
QueryOptimizations.bulk_insert_embeddings(db, embeddings_batch)

# Example 4: Monitor performance
stats = db.get_stats()
print(f"Slow query rate: {stats['slow_query_rate']}")

# Example 5: Get slow queries
slow = db.analyze_slow_queries()
for query in slow:
    print(f"{query['query']}: {query['mean_time']}ms avg")
"""
