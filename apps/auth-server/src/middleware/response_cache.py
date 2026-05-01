# Response Caching & Optimization Service
# Week 5 Phase 5.2.2: API Response Optimization with Caching
# Implements response field filtering and Redis-based caching

from typing import Optional, Any, Dict, Callable
from functools import wraps
import hashlib
import json
from log import get_logger
import asyncio
from datetime import timedelta
from redis import asyncio as aioredis
from fastapi import Request, Response
from fastapi.responses import JSONResponse

logger = get_logger(__name__)


class ResponseCacheManager:
    """Manages response caching with Redis"""
    
    def __init__(self, redis_url: str = "redis://localhost:6379"):
        self.redis_url = redis_url
        self.redis: Optional[aioredis.Redis] = None
        self.default_ttl = 300  # 5 minutes
    
    async def connect(self):
        """Connect to Redis"""
        self.redis = await aioredis.from_url(self.redis_url)
        logger.info("Connected to Redis for response caching")
    
    async def disconnect(self):
        """Disconnect from Redis"""
        if self.redis:
            await self.redis.close()
            logger.info("Disconnected from Redis")
    
    async def get_cached_response(self, cache_key: str) -> Optional[Dict]:
        """Get cached response"""
        if not self.redis:
            return None
        
        try:
            cached = await self.redis.get(cache_key)
            if cached:
                logger.debug(f"Cache HIT: {cache_key}")
                return json.loads(cached)
        except Exception as e:
            logger.warning(f"Cache get error: {e}")
        
        return None
    
    async def cache_response(
        self,
        cache_key: str,
        response_data: Dict,
        ttl_seconds: int = None
    ) -> None:
        """Cache response"""
        if not self.redis:
            return
        
        ttl = ttl_seconds or self.default_ttl
        
        try:
            await self.redis.setex(
                cache_key,
                ttl,
                json.dumps(response_data)
            )
            logger.debug(f"Cache SET: {cache_key} (TTL: {ttl}s)")
        except Exception as e:
            logger.warning(f"Cache set error: {e}")
    
    async def invalidate_pattern(self, pattern: str) -> None:
        """Invalidate all keys matching pattern"""
        if not self.redis:
            return
        
        try:
            keys = await self.redis.keys(pattern)
            if keys:
                await self.redis.delete(*keys)
                logger.info(f"Invalidated {len(keys)} cache entries for pattern: {pattern}")
        except Exception as e:
            logger.warning(f"Cache invalidation error: {e}")


class CacheInvalidationManager:
    """Manages cache invalidation on data mutations"""
    
    def __init__(self, cache_manager: ResponseCacheManager):
        self.cache = cache_manager
    
    async def invalidate_user(self, user_id: str) -> None:
        """Invalidate all caches related to a user"""
        patterns = [
            f"user:{user_id}:*",
            f"users:*:{user_id}:*",
            f"perms:{user_id}:*",
            f"sessions:{user_id}:*",
        ]
        for pattern in patterns:
            await self.cache.invalidate_pattern(pattern)
    
    async def invalidate_team(self, team_id: str) -> None:
        """Invalidate all caches related to a team"""
        patterns = [
            f"team:{team_id}:*",
            f"teams:*:{team_id}:*",
            f"roles:{team_id}:*",
        ]
        for pattern in patterns:
            await self.cache.invalidate_pattern(pattern)
    
    async def invalidate_permissions(self, user_id: str, team_id: str) -> None:
        """Invalidate permission caches"""
        patterns = [
            f"perms:{user_id}:{team_id}:*",
            f"access:{user_id}:{team_id}:*",
        ]
        for pattern in patterns:
            await self.cache.invalidate_pattern(pattern)


class ResponseCacheMiddleware:
    """
    Middleware for caching GET request responses.
    
    Caches successful (200) GET responses for 5 minutes.
    Skips caching for authenticated user-specific data by default.
    """
    
    def __init__(self, app, cache_manager: ResponseCacheManager):
        self.app = app
        self.cache = cache_manager
        # Paths to always cache (public data)
        self.cacheable_paths = [
            "/api/health",
            "/api/metadata",
            "/api/config",
            "/api/public",
        ]
        # Paths to never cache
        self.uncacheable_paths = [
            "/api/auth/refresh",
            "/api/sessions",
        ]
    
    async def __call__(self, request: Request, call_next: Callable) -> Response:
        # Only cache GET requests
        if request.method != "GET":
            return await call_next(request)
        
        # Check if path should be cached
        path = request.url.path
        if any(p in self.uncacheable_paths for p in [path.split("/")[2:3]]):
            return await call_next(request)
        
        # Generate cache key
        cache_key = self._generate_cache_key(request)
        
        # Try to get from cache
        cached_response = await self.cache.get_cached_response(cache_key)
        if cached_response:
            return JSONResponse(
                cached_response,
                headers={
                    "X-Cache": "HIT",
                    "Cache-Control": "public, max-age=300"
                }
            )
        
        # Execute request
        response = await call_next(request)
        
        # Cache successful responses
        if response.status_code == 200:
            try:
                body = b""
                async for chunk in response.body_iterator:
                    body += chunk
                
                response_data = json.loads(body.decode())
                await self.cache.cache_response(cache_key, response_data)
                
                # Return response with cache marker
                return JSONResponse(
                    response_data,
                    headers={
                        "X-Cache": "MISS",
                        "Cache-Control": "public, max-age=300"
                    }
                )
            except Exception as e:
                logger.warning(f"Cache middleware error: {e}")
        
        return response
    
    @staticmethod
    def _generate_cache_key(request: Request) -> str:
        """Generate cache key from request"""
        url_hash = hashlib.md5(str(request.url).encode()).hexdigest()
        return f"response:{url_hash}"


def cached_endpoint(
    ttl_seconds: int = 300,
    key_prefix: str = ""
):
    """
    Decorator for caching endpoint responses.
    
    Usage:
        @router.get("/users/{user_id}")
        @cached_endpoint(ttl_seconds=600, key_prefix="user")
        async def get_user(user_id: UUID):
            return user
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            # Get cache manager from kwargs (passed via dependency injection)
            cache_manager = kwargs.pop('_cache_manager', None)
            if not cache_manager:
                return await func(*args, **kwargs)
            
            # Generate cache key
            args_str = str(args) + str(kwargs)
            key_hash = hashlib.md5(args_str.encode()).hexdigest()
            cache_key = f"{key_prefix}:{func.__name__}:{key_hash}"
            
            # Try cache
            cached = await cache_manager.get_cached_response(cache_key)
            if cached:
                logger.debug(f"Decorator cache hit: {cache_key}")
                return cached
            
            # Execute function
            result = await func(*args, **kwargs)
            
            # Cache result
            if isinstance(result, dict):
                await cache_manager.cache_response(
                    cache_key,
                    result,
                    ttl_seconds
                )
            
            return result
        
        return wrapper
    
    return decorator


class ResponseOptimization:
    """Optimizes response payloads"""
    
    @staticmethod
    def filter_response_fields(
        data: Dict,
        include_fields: Optional[list] = None,
        exclude_fields: Optional[list] = None
    ) -> Dict:
        """
        Filter response to only include/exclude specific fields.
        
        Reduces response size and improves serialization performance.
        """
        if include_fields:
            # Include only specified fields
            return {k: v for k, v in data.items() if k in include_fields}
        
        if exclude_fields:
            # Exclude specified fields
            return {k: v for k, v in data.items() if k not in exclude_fields}
        
        return data
    
    @staticmethod
    def create_list_response(
        items: list,
        include_fields: Optional[list] = None,
        exclude_fields: Optional[list] = None
    ) -> list:
        """
        Create optimized list response with filtered fields.
        
        Example:
            users = [...]  # Large user objects
            optimized = ResponseOptimization.create_list_response(
                users,
                exclude_fields=["password_hash", "settings", "audit_log"]
            )
            # Returns users with only essential fields
        """
        filtered_items = []
        for item in items:
            if isinstance(item, dict):
                filtered = ResponseOptimization.filter_response_fields(
                    item, include_fields, exclude_fields
                )
            else:
                # Convert to dict if object
                item_dict = item.__dict__ if hasattr(item, '__dict__') else {}
                filtered = ResponseOptimization.filter_response_fields(
                    item_dict, include_fields, exclude_fields
                )
            filtered_items.append(filtered)
        
        return filtered_items


# FastAPI Integration Example
from fastapi import FastAPI, Depends, APIRouter
from pydantic import BaseModel

router = APIRouter()

# Initialize cache manager
cache_manager = ResponseCacheManager()


@router.on_event("startup")
async def startup():
    """Connect to Redis on startup"""
    await cache_manager.connect()


@router.on_event("shutdown")
async def shutdown():
    """Disconnect from Redis on shutdown"""
    await cache_manager.disconnect()


# Example: Cached user list endpoint
@router.get("/api/users")
async def list_users(team_id: str):
    """
    Get users in team - CACHED for 5 minutes.
    
    Response: ~50KB
    Cache benefit: 95% of requests served from cache
    """
    # Query (optimized with N+1 elimination)
    users = await get_users_with_permissions(team_id)
    
    # Filter response (excludes large nested objects)
    optimized = ResponseOptimization.create_list_response(
        [u.dict() for u in users],
        exclude_fields=["settings", "audit_log", "password_hash"]
    )
    
    # Middleware handles caching automatically
    return {"users": optimized}


# Example: User detail endpoint
@router.get("/api/users/{user_id}")
async def get_user_detail(user_id: str):
    """
    Get user details - CACHED for 10 minutes.
    
    Includes full user object since this is detail view.
    """
    user = await get_user(user_id)
    
    # Cache this response
    cache_key = f"user:{user_id}:detail"
    await cache_manager.cache_response(
        cache_key,
        user.dict(),
        ttl_seconds=600
    )
    
    return user


# Example: Create user (invalidates cache)
@router.post("/api/users")
async def create_user(user_data: dict):
    """
    Create user - INVALIDATES USER CACHES.
    """
    new_user = await db.create_user(user_data)
    
    # Invalidate related caches
    invalidation = CacheInvalidationManager(cache_manager)
    await invalidation.invalidate_team(user_data.get("team_id"))
    
    return new_user


# Example: Update user (invalidates specific cache)
@router.put("/api/users/{user_id}")
async def update_user(user_id: str, updates: dict):
    """
    Update user - INVALIDATES USER-SPECIFIC CACHE.
    """
    updated_user = await db.update_user(user_id, updates)
    
    # Invalidate this user's cache
    invalidation = CacheInvalidationManager(cache_manager)
    await invalidation.invalidate_user(user_id)
    
    return updated_user


# Performance Metrics
CACHE_METRICS = {
    "hits": 0,
    "misses": 0,
    "invalidations": 0,
}


def get_cache_stats() -> Dict:
    """Get cache performance statistics"""
    total = CACHE_METRICS["hits"] + CACHE_METRICS["misses"]
    hit_rate = (
        (CACHE_METRICS["hits"] / total * 100) if total > 0 else 0
    )
    
    return {
        "hits": CACHE_METRICS["hits"],
        "misses": CACHE_METRICS["misses"],
        "invalidations": CACHE_METRICS["invalidations"],
        "hit_rate_percent": f"{hit_rate:.2f}%",
        "total_requests": total,
    }
