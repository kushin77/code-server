"""
Redis Caching Service for Code-Server Enterprise
Implements multi-layer caching strategy with TTL, event-based, and pattern-based invalidation
"""

import json
import hashlib
import logging
from typing import Any, Optional, Callable, List
from datetime import datetime, timedelta
from functools import wraps

import redis
from redis.connection import ConnectionPool

logger = logging.getLogger(__name__)


class CacheConfig:
    """Cache configuration with TTL policies"""
    
    # Cache key patterns and their default TTL (seconds)
    TTL_POLICIES = {
        'session:*': 86400,              # 24 hours - user sessions
        'user:*': 3600,                  # 1 hour - user data
        'workspace:*': 1800,             # 30 min - workspace configuration
        'embeddings:*': 604800,          # 7 days - embedding vectors (infrequent changes)
        'search:results:*': 300,         # 5 min - search results
        'file:content:*': 3600,          # 1 hour - file content
        'query:*': 900,                  # 15 min - database query results
        'token:*': 600,                  # 10 min - auth tokens
    }
    
    # Event-based invalidation patterns (invalidate on event)
    INVALIDATION_EVENTS = {
        'file_modified': ['file:content:*', 'search:results:*'],
        'user_updated': ['user:*', 'session:*'],
        'workspace_updated': ['workspace:*', 'search:results:*'],
        'embeddings_updated': ['embeddings:*', 'search:results:*'],
    }


class RedisCacheManager:
    """
    Unified Redis caching manager with:
    - Connection pooling for efficiency
    - TTL policies for automatic expiration
    - Event-based invalidation
    - Pattern-based bulk operations
    - Cache statistics and monitoring
    """
    
    def __init__(self, redis_url: str = 'redis://localhost:6379/0'):
        """Initialize Redis cache manager with connection pool"""
        self.redis_url = redis_url
        self.pool = self._create_connection_pool()
        self.client = redis.Redis(connection_pool=self.pool)
        self.config = CacheConfig()
        self.stats = {'hits': 0, 'misses': 0, 'errors': 0}
        
        # Verify connection
        try:
            self.client.ping()
            logger.info(f"Redis cache connected: {redis_url}")
        except redis.ConnectionError as e:
            logger.error(f"Redis connection failed: {e}")
            raise

    def _create_connection_pool(self, **kwargs) -> ConnectionPool:
        """Create optimized connection pool"""
        pool_config = {
            'max_connections': 50,
            'socket_connect_timeout': 5,
            'socket_keepalive': True,
            'socket_keepalive_options': {
                'TCP_KEEPIDLE': 60,
                'TCP_KEEPINTVL': 10,
                'TCP_KEEPCNT': 5,
            },
            **kwargs
        }
        return redis.ConnectionPool.from_url(self.redis_url, **pool_config)

    def _get_ttl(self, key: str) -> int:
        """Get TTL for a key based on pattern matching"""
        for pattern, ttl in self.config.TTL_POLICIES.items():
            if self._pattern_match(key, pattern):
                return ttl
        return 3600  # Default 1 hour

    @staticmethod
    def _pattern_match(key: str, pattern: str) -> bool:
        """Simple glob-like pattern matching"""
        if '*' not in pattern:
            return key == pattern
        
        parts = pattern.split('*')
        if len(parts) == 2:
            return key.startswith(parts[0]) and key.endswith(parts[1])
        return False

    def _make_key(self, namespace: str, *args) -> str:
        """Generate cache key with namespace and multiple arguments"""
        key_parts = [namespace] + [str(arg) for arg in args]
        return ':'.join(key_parts)

    # ─── GET/SET OPERATIONS ──────────────────────────────────────────────

    def get(self, key: str) -> Optional[Any]:
        """Get value from cache with cache hit/miss tracking"""
        try:
            value = self.client.get(key)
            if value:
                self.stats['hits'] += 1
                return json.loads(value)
            else:
                self.stats['misses'] += 1
                return None
        except Exception as e:
            logger.error(f"Cache GET failed for {key}: {e}")
            self.stats['errors'] += 1
            return None

    def set(self, key: str, value: Any, ttl: Optional[int] = None, **kwargs):
        """Set value in cache with automatic TTL"""
        try:
            if ttl is None:
                ttl = self._get_ttl(key)
            
            serialized = json.dumps(value)
            self.client.setex(key, ttl, serialized)
            logger.debug(f"Cache SET {key} (TTL: {ttl}s)")
        except Exception as e:
            logger.error(f"Cache SET failed for {key}: {e}")
            self.stats['errors'] += 1

    def delete(self, *keys: str) -> int:
        """Delete one or more cache keys"""
        try:
            deleted = self.client.delete(*keys)
            logger.debug(f"Cache DELETE {len(keys)} keys, {deleted} deleted")
            return deleted
        except Exception as e:
            logger.error(f"Cache DELETE failed: {e}")
            self.stats['errors'] += 1
            return 0

    def exists(self, key: str) -> bool:
        """Check if key exists in cache"""
        try:
            return self.client.exists(key) > 0
        except Exception as e:
            logger.error(f"Cache EXISTS failed for {key}: {e}")
            return False

    # ─── OPERATIONS WITH DATABASE FALLBACK ────────────────────────────

    def get_or_fetch(self, key: str, fetch_fn: Callable, ttl: Optional[int] = None) -> Any:
        """
        Get value from cache or fetch from database if not cached.
        Useful pattern for database query caching.
        """
        # Try cache first
        cached = self.get(key)
        if cached is not None:
            logger.debug(f"Cache HIT {key}")
            return cached
        
        logger.debug(f"Cache MISS {key}, fetching from source")
        
        # Fetch from source
        value = fetch_fn()
        
        # Cache the result
        if value is not None:
            self.set(key, value, ttl)
        
        return value

    def get_many(self, keys: List[str]) -> dict:
        """Get multiple values at once"""
        try:
            values = self.client.mget(keys)
            result = {}
            for key, value in zip(keys, values):
                if value:
                    result[key] = json.loads(value)
            return result
        except Exception as e:
            logger.error(f"Cache MGET failed: {e}")
            self.stats['errors'] += 1
            return {}

    def set_many(self, mapping: dict, ttl: Optional[int] = None):
        """Set multiple values at once"""
        try:
            pipe = self.client.pipeline()
            for key, value in mapping.items():
                key_ttl = ttl or self._get_ttl(key)
                serialized = json.dumps(value)
                pipe.setex(key, key_ttl, serialized)
            pipe.execute()
            logger.debug(f"Cache MSET {len(mapping)} keys")
        except Exception as e:
            logger.error(f"Cache MSET failed: {e}")
            self.stats['errors'] += 1

    # ─── PATTERN-BASED INVALIDATION ───────────────────────────────────

    def invalidate_pattern(self, pattern: str) -> int:
        """Invalidate all keys matching a pattern (pattern-based invalidation)"""
        try:
            keys = self.client.keys(pattern)
            if keys:
                deleted = self.client.delete(*keys)
                logger.info(f"Pattern invalidation {pattern}: {deleted} keys deleted")
                return deleted
            return 0
        except Exception as e:
            logger.error(f"Pattern invalidation failed for {pattern}: {e}")
            self.stats['errors'] += 1
            return 0

    def invalidate_event(self, event_type: str) -> int:
        """Invalidate all keys related to an event (event-based invalidation)"""
        if event_type not in self.config.INVALIDATION_EVENTS:
            logger.warning(f"Unknown invalidation event: {event_type}")
            return 0
        
        patterns = self.config.INVALIDATION_EVENTS[event_type]
        total_deleted = 0
        
        for pattern in patterns:
            deleted = self.invalidate_pattern(pattern)
            total_deleted += deleted
        
        logger.info(f"Event invalidation {event_type}: {total_deleted} total keys deleted")
        return total_deleted

    # ─── CACHE WARMING ─────────────────────────────────────────────────

    def warm_cache(self, data: dict):
        """Pre-populate cache (cache warming strategy)"""
        try:
            self.set_many(data)
            logger.info(f"Cache warmed with {len(data)} entries")
        except Exception as e:
            logger.error(f"Cache warming failed: {e}")
            self.stats['errors'] += 1

    # ─── MONITORING & STATISTICS ───────────────────────────────────────

    def get_stats(self) -> dict:
        """Get cache performance statistics"""
        total = self.stats['hits'] + self.stats['misses']
        hit_rate = (self.stats['hits'] / total * 100) if total > 0 else 0
        
        return {
            'hits': self.stats['hits'],
            'misses': self.stats['misses'],
            'errors': self.stats['errors'],
            'hit_rate': f"{hit_rate:.2f}%",
            'total_requests': total,
        }

    def get_redis_stats(self) -> dict:
        """Get Redis internal statistics"""
        try:
            info = self.client.info()
            return {
                'connected_clients': info.get('connected_clients', 0),
                'used_memory': f"{info.get('used_memory_human', 'N/A')}",
                'evicted_keys': info.get('evicted_keys', 0),
                'total_commands': info.get('total_commands_processed', 0),
            }
        except Exception as e:
            logger.error(f"Failed to get Redis stats: {e}")
            return {}

    def flush_all(self):
        """Clear entire cache (use with caution!)"""
        try:
            self.client.flushall()
            logger.warning("Cache flushed completely")
        except Exception as e:
            logger.error(f"Flush failed: {e}")

    # ─── DECORATOR FOR AUTOMATIC CACHING ───────────────────────────────

    def cached(self, ttl: Optional[int] = None, key_prefix: str = ''):
        """Decorator for automatic function result caching"""
        def decorator(func):
            @wraps(func)
            def wrapper(*args, **kwargs):
                # Generate cache key from function name and arguments
                cache_key = f"{key_prefix or func.__name__}:{hashlib.md5(json.dumps([args, kwargs], default=str).encode()).hexdigest()}"
                
                # Try cache
                cached_result = self.get(cache_key)
                if cached_result is not None:
                    return cached_result
                
                # Execute function
                result = func(*args, **kwargs)
                
                # Cache result
                self.set(cache_key, result, ttl)
                return result
            
            return wrapper
        return decorator

    def close(self):
        """Close Redis connection"""
        try:
            self.client.close()
            logger.info("Redis cache connection closed")
        except Exception as e:
            logger.error(f"Error closing Redis connection: {e}")


# ─── SINGLETON INSTANCE ──────────────────────────────────────────────────────

_cache_instance = None


def get_cache_manager() -> RedisCacheManager:
    """Get or create singleton cache manager"""
    global _cache_instance
    if _cache_instance is None:
        _cache_instance = RedisCacheManager()
    return _cache_instance


# ─── USAGE EXAMPLES ──────────────────────────────────────────────────────────

"""
# Example 1: Simple cache operations
cache = get_cache_manager()
cache.set('user:123', {'name': 'Alice', 'role': 'admin'})
user = cache.get('user:123')

# Example 2: Cache with database fallback
def fetch_workspace_from_db(ws_id):
    return database.query('SELECT * FROM workspaces WHERE id = ?', ws_id)

workspace = cache.get_or_fetch(
    f'workspace:{ws_id}',
    lambda: fetch_workspace_from_db(ws_id)
)

# Example 3: Decorator for automatic caching
@cache.cached(ttl=3600)
def expensive_computation(x, y):
    return x ** y  # Some expensive calculation

# Example 4: Event-based invalidation (when user updates)
cache.invalidate_event('user_updated')

# Example 5: Pattern-based invalidation (clear all search results)
cache.invalidate_pattern('search:results:*')

# Example 6: Monitor performance
stats = cache.get_stats()
print(f"Cache hit rate: {stats['hit_rate']}")
"""
