"""
API Gateway - Rate Limiting Middleware
Issue #1345 Week 5: API Gateway Integration
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Tuple
from log import get_logger

from fastapi import Request, HTTPException
import redis

logger = get_logger(__name__)


# ============================================================================
# Rate Limiting
# ============================================================================

class RateLimiter:
    """Rate limiting per user/team/org"""
    
    def __init__(self, redis_client: redis.Redis, config):
        self.redis = redis_client
        self.config = config
    
    def check_rate_limit(
        self,
        user_id: str,
        limit_type: str = "user",  # user, team, org, ip
        custom_limit: Optional[int] = None,
    ) -> Tuple[bool, Dict[str, int]]:
        """Check if request is within rate limit"""
        
        try:
            # Get rate limit for user type
            if custom_limit:
                limit = custom_limit
            else:
                limit = self._get_rate_limit(user_id, limit_type)
            
            # Get current count
            key = f"ratelimit:{limit_type}:{user_id}"
            current_count = self.redis.get(key)
            current_count = int(current_count) if current_count else 0
            
            # Check limit
            if current_count >= limit:
                # Get reset time
                ttl = self.redis.ttl(key)
                return False, {
                    "limit": limit,
                    "current": current_count,
                    "reset_in_seconds": ttl if ttl > 0 else 60,
                }
            
            # Increment and set expiry
            self.redis.incr(key)
            self.redis.expire(key, 60)  # 1-minute window
            
            return True, {
                "limit": limit,
                "current": current_count + 1,
                "remaining": limit - (current_count + 1),
            }
        
        except Exception as e:
            logger.error(f"Rate limit check failed: {str(e)}")
            # Fail open on error
            return True, {}
    
    def _get_rate_limit(self, user_id: str, limit_type: str) -> int:
        """Get rate limit for user"""
        
        # Default limits (requests per minute)
        default_limits = {
            "free": 100,
            "pro": 1000,
            "enterprise": 10000,
        }
        
        # Get user plan
        plan = self._get_user_plan(user_id)
        
        return default_limits.get(plan, 100)
    
    def _get_user_plan(self, user_id: str) -> str:
        """Get user's subscription plan"""
        # In production: query User table for plan
        return "free"
    
    def get_rate_limit_headers(
        self,
        limit: int,
        current: int,
        remaining: int,
    ) -> Dict[str, str]:
        """Generate rate limit response headers"""
        
        return {
            "X-RateLimit-Limit": str(limit),
            "X-RateLimit-Current": str(current),
            "X-RateLimit-Remaining": str(remaining),
        }


# ============================================================================
# Rate Limiting Middleware
# ============================================================================

class RateLimitMiddleware:
    """Rate limiting middleware"""
    
    def __init__(self, app, rate_limiter: RateLimiter, config):
        self.app = app
        self.limiter = rate_limiter
        self.config = config
    
    async def __call__(self, request: Request, call_next):
        """Check rate limit before processing request"""
        
        # Get identifier (user ID or IP)
        identifier = self._get_identifier(request)
        if not identifier:
            return await call_next(request)
        
        # Check rate limit
        allowed, stats = self.limiter.check_rate_limit(
            identifier,
            limit_type=self._get_limit_type(request),
        )
        
        if not allowed:
            logger.warning(f"Rate limit exceeded for {identifier}")
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded",
                headers={
                    "X-RateLimit-Limit": str(stats.get("limit")),
                    "X-RateLimit-Remaining": "0",
                    "Retry-After": str(stats.get("reset_in_seconds", 60)),
                }
            )
        
        # Process request
        response = await call_next(request)
        
        # Add rate limit headers
        headers = self.limiter.get_rate_limit_headers(
            stats.get("limit", 0),
            stats.get("current", 0),
            stats.get("remaining", 0),
        )
        for key, value in headers.items():
            response.headers[key] = value
        
        return response
    
    def _get_identifier(self, request: Request) -> Optional[str]:
        """Get identifier for rate limiting"""
        
        # Priority: authenticated user > API key > IP address
        
        # Check if user authenticated
        user = getattr(request.state, "user", None)
        if user:
            return user.get("user_id")
        
        # Check API key
        api_key = self._extract_api_key(request)
        if api_key:
            return api_key
        
        # Fall back to IP
        return request.client.host if request.client else None
    
    def _get_limit_type(self, request: Request) -> str:
        """Determine limit type"""
        
        user = getattr(request.state, "user", None)
        if user:
            return "user"
        
        if self._extract_api_key(request):
            return "api_key"
        
        return "ip"
    
    def _extract_api_key(self, request: Request) -> Optional[str]:
        """Extract API key from request"""
        
        # Check header
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("ApiKey "):
            return auth_header[7:]
        
        # Check query parameter
        return request.query_params.get("api_key")


# ============================================================================
# Quota Management (for teams/orgs)
# ============================================================================

class QuotaManager:
    """Manage usage quotas"""
    
    def __init__(self, redis_client: redis.Redis, db_session):
        self.redis = redis_client
        self.db = db_session
    
    def check_quota(
        self,
        resource_type: str,
        owner_id: str,
        amount: int = 1,
    ) -> Tuple[bool, Dict[str, Any]]:
        """Check if resource usage is within quota"""
        
        try:
            # Get quota limits
            quota_limit = self._get_quota_limit(resource_type, owner_id)
            
            # Get current usage
            key = f"quota:{resource_type}:{owner_id}"
            current_usage = self.redis.get(key)
            current_usage = int(current_usage) if current_usage else 0
            
            # Check quota
            if current_usage + amount > quota_limit:
                return False, {
                    "quota_limit": quota_limit,
                    "current_usage": current_usage,
                    "requested": amount,
                    "exceeded_by": (current_usage + amount) - quota_limit,
                }
            
            # Increment usage
            self.redis.incrby(key, amount)
            # Set yearly expiry (reset on Jan 1)
            self._set_quota_expiry(key)
            
            return True, {
                "quota_limit": quota_limit,
                "current_usage": current_usage + amount,
                "remaining": quota_limit - (current_usage + amount),
            }
        
        except Exception as e:
            logger.error(f"Quota check failed: {str(e)}")
            return True, {}  # Fail open
    
    def _get_quota_limit(self, resource_type: str, owner_id: str) -> int:
        """Get quota limit"""
        
        # Example quotas
        quotas = {
            "api_calls": 1000000,
            "storage_gb": 1000,
            "team_members": 100,
            "projects": 50,
        }
        
        # Could be customized per org/team
        return quotas.get(resource_type, 1000)
    
    def _set_quota_expiry(self, key: str) -> None:
        """Set quota expiry to next Jan 1"""
        
        now = datetime.utcnow()
        next_year = datetime(now.year + 1, 1, 1)
        seconds_until_reset = int((next_year - now).total_seconds())
        
        self.redis.expire(key, seconds_until_reset)
    
    def get_quota_usage(
        self,
        resource_type: str,
        owner_id: str,
    ) -> Dict[str, int]:
        """Get quota usage for resource"""
        
        key = f"quota:{resource_type}:{owner_id}"
        current_usage = self.redis.get(key)
        current_usage = int(current_usage) if current_usage else 0
        
        quota_limit = self._get_quota_limit(resource_type, owner_id)
        
        return {
            "quota_limit": quota_limit,
            "current_usage": current_usage,
            "remaining": quota_limit - current_usage,
            "percent_used": int((current_usage / quota_limit) * 100) if quota_limit > 0 else 0,
        }
