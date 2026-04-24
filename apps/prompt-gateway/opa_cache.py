#!/usr/bin/env python3
# @file        apps/prompt-gateway/opa_cache.py
# @module      prompt-gateway/policy
# @description OPA policy decision caching with Redis backend
#
# Caches OPA policy evaluation results to reduce latency on repeated policy checks
# Supports pattern-based cache invalidation for dynamic policies

import hashlib
import json
import time
from typing import Optional, Dict, Any, Tuple
import redis
from dataclasses import dataclass, asdict
from datetime import datetime


@dataclass
class PolicyDecisionCache:
    """Cached policy decision result"""
    policy_path: str
    input_hash: str
    input_original: Dict[str, Any]
    decision: bool
    reason: Optional[str]
    cached_at: float
    accessed_at: float
    hit_count: int
    ttl_seconds: int


class OpaPolicyCache:
    """
    Cache layer for OPA policy decisions.
    
    Features:
    - Result caching for repeated policy checks
    - TTL-based expiration (configurable per policy)
    - Pattern-based invalidation (e.g., invalidate all user-related policies)
    - Hit/miss metrics
    - Automatic cleanup
    """
    
    def __init__(self, redis_client: redis.Redis, default_ttl_seconds: int = 3600):
        self.redis = redis_client
        self.default_ttl = default_ttl_seconds
        self.metrics = {"hits": 0, "misses": 0, "invalidations": 0}
        
        # Per-policy TTLs
        self.policy_ttls = {
            "ai/prompt-safety": 300,  # 5 minutes (changes frequently)
            "core/secrets": 3600,  # 1 hour (secrets patterns stable)
            "core/production-gate": 7200,  # 2 hours (approval rules stable)
            "core/audit": 3600,  # 1 hour
            "ai/model-allowlist": 1800,  # 30 minutes (model allowlist updates)
        }
    
    def _input_hash(self, policy_input: Dict[str, Any]) -> str:
        """SHA256 hash of policy input"""
        input_json = json.dumps(policy_input, sort_keys=True)
        return hashlib.sha256(input_json.encode()).hexdigest()
    
    def _cache_key(self, policy_path: str, input_hash: str) -> str:
        """Redis key pattern: opa_cache:policy:{path}:input:{hash}"""
        safe_path = policy_path.replace("/", ":")
        return f"opa_cache:policy:{safe_path}:input:{input_hash}"
    
    def get_ttl_for_policy(self, policy_path: str) -> int:
        """Get TTL for policy, with fallback to default"""
        return self.policy_ttls.get(policy_path, self.default_ttl)
    
    def get(self, policy_path: str, policy_input: Dict[str, Any]) -> Optional[Tuple[bool, Optional[str]]]:
        """
        Get cached policy decision if available.
        
        Returns:
            Tuple of (decision_bool, reason_str) or None if not cached
        """
        input_hash = self._input_hash(policy_input)
        key = self._cache_key(policy_path, input_hash)
        
        cached_data = self.redis.get(key)
        if cached_data:
            cached_obj = json.loads(cached_data)
            
            # Update access metadata
            cached_obj["accessed_at"] = time.time()
            cached_obj["hit_count"] += 1
            
            ttl = self.get_ttl_for_policy(policy_path)
            self.redis.setex(key, ttl, json.dumps(cached_obj))
            
            self.metrics["hits"] += 1
            return (cached_obj["decision"], cached_obj["reason"])
        
        self.metrics["misses"] += 1
        return None
    
    def set(self, policy_path: str, policy_input: Dict[str, Any], 
            decision: bool, reason: Optional[str] = None) -> None:
        """Cache a new policy decision"""
        input_hash = self._input_hash(policy_input)
        key = self._cache_key(policy_path, input_hash)
        
        ttl = self.get_ttl_for_policy(policy_path)
        
        cache_entry = PolicyDecisionCache(
            policy_path=policy_path,
            input_hash=input_hash,
            input_original=policy_input,
            decision=decision,
            reason=reason,
            cached_at=time.time(),
            accessed_at=time.time(),
            hit_count=0,
            ttl_seconds=ttl
        )
        
        self.redis.setex(key, ttl, json.dumps(asdict(cache_entry)))
    
    def invalidate_by_policy(self, policy_path: str) -> int:
        """Invalidate all cache entries for a policy. Returns count deleted."""
        pattern = f"opa_cache:policy:{policy_path.replace('/', ':')}:input:*"
        keys = self.redis.keys(pattern)
        
        if keys:
            self.redis.delete(*keys)
            self.metrics["invalidations"] += len(keys)
        
        return len(keys)
    
    def invalidate_by_pattern(self, pattern: str) -> int:
        """
        Invalidate cache entries matching pattern.
        
        Examples:
        - "opa_cache:policy:ai:*" -> invalidate all AI policies
        - "opa_cache:policy:*:user:alice" -> invalidate all entries with user alice
        """
        full_pattern = f"opa_cache:{pattern}" if not pattern.startswith("opa_cache") else pattern
        keys = self.redis.keys(full_pattern)
        
        if keys:
            self.redis.delete(*keys)
            self.metrics["invalidations"] += len(keys)
        
        return len(keys)
    
    def invalidate_by_user(self, user_id: str) -> int:
        """Invalidate all cache entries for a specific user"""
        return self.invalidate_by_pattern(f"*:user:{user_id}")
    
    def clear_all(self) -> int:
        """Clear all OPA cache entries. Returns count deleted."""
        keys = self.redis.keys("opa_cache:*")
        
        if keys:
            self.redis.delete(*keys)
        
        return len(keys)
    
    def get_metrics(self) -> Dict:
        """Return cache statistics"""
        total = self.metrics["hits"] + self.metrics["misses"]
        hit_rate = (self.metrics["hits"] / total * 100) if total > 0 else 0
        
        return {
            "hits": self.metrics["hits"],
            "misses": self.metrics["misses"],
            "invalidations": self.metrics["invalidations"],
            "hit_rate_percent": round(hit_rate, 2),
            "total_requests": total
        }
    
    def get_cache_size(self) -> Dict[str, int]:
        """Get cache size statistics"""
        policy_sizes = {}
        
        for policy_path in self.policy_ttls.keys():
            pattern = f"opa_cache:policy:{policy_path.replace('/', ':')}:input:*"
            keys = self.redis.keys(pattern)
            policy_sizes[policy_path] = len(keys)
        
        # Also count unknown policies
        all_keys = self.redis.keys("opa_cache:policy:*:input:*")
        unknown_count = len(all_keys) - sum(policy_sizes.values())
        
        if unknown_count > 0:
            policy_sizes["unknown"] = unknown_count
        
        return {
            "total_entries": len(all_keys),
            "by_policy": policy_sizes
        }


class PolicyCachingMiddleware:
    """
    Middleware for transparent policy caching in OPA evaluation.
    
    Wraps OPA client to automatically cache decisions:
    - Check cache before calling OPA
    - Call OPA if miss
    - Cache result
    - Return result
    """
    
    def __init__(self, opa_cache: OpaPolicyCache, opa_client):
        self.cache = opa_cache
        self.opa_client = opa_client
        self.cache_bypass_policies = set()  # Policies to never cache
    
    async def evaluate_policy(self, policy_path: str, policy_input: Dict[str, Any]) -> Dict:
        """
        Evaluate policy with transparent caching.
        
        Returns:
            {"allowed": bool, "reason": str, "from_cache": bool}
        """
        
        # Check if caching enabled for this policy
        if policy_path in self.cache_bypass_policies:
            result = await self.opa_client.check_policy(policy_path, policy_input)
            return {**result, "from_cache": False}
        
        # Try cache
        cached = self.cache.get(policy_path, policy_input)
        if cached is not None:
            decision, reason = cached
            return {
                "allowed": decision,
                "reason": reason,
                "from_cache": True
            }
        
        # Cache miss - call OPA
        result = await self.opa_client.check_policy(policy_path, policy_input)
        
        # Cache result
        self.cache.set(
            policy_path,
            policy_input,
            result.get("allowed", True),
            result.get("reason")
        )
        
        return {**result, "from_cache": False}
    
    def set_cache_bypass(self, policy_path: str, bypass: bool = True) -> None:
        """Enable/disable caching for specific policy"""
        if bypass:
            self.cache_bypass_policies.add(policy_path)
        else:
            self.cache_bypass_policies.discard(policy_path)
    
    async def invalidate_for_user(self, user_id: str) -> int:
        """Invalidate cache for user (e.g., after permission change)"""
        return self.cache.invalidate_by_user(user_id)
    
    def get_cache_stats(self) -> Dict:
        """Get cache statistics"""
        return {
            "cache_metrics": self.cache.get_metrics(),
            "cache_size": self.cache.get_cache_size(),
            "bypass_policies": list(self.cache_bypass_policies)
        }
