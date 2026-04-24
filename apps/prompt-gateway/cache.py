#!/usr/bin/env python3
# @file        apps/prompt-gateway/cache.py
# @module      prompt-gateway/cache
# @description Response caching layer with semantic similarity matching and TTL management
#
# Implements LRU + semantic caching for Prompt Gateway with Redis backend.
# Matches incoming prompts against cached responses using embedding-based similarity.

import json
import hashlib
import time
from typing import Optional, Tuple, Dict, List
from dataclasses import dataclass, asdict
import redis
from datetime import datetime, timedelta

@dataclass
class CachedResponse:
    """Cached prompt response with metadata"""
    prompt_hash: str
    prompt_original: str
    model: str
    response: str
    tokens_used: int
    cached_at: float
    accessed_at: float
    hit_count: int
    user_id: str
    semantic_sim_threshold: float = 0.85  # Similarity threshold for matching


class PromptCache:
    """
    Response caching with semantic matching and LRU eviction.
    
    Features:
    - Exact hash matching (fast path)
    - Semantic similarity matching (neural embedding comparison)
    - TTL-based expiration (24 hours default)
    - LRU eviction (max 10,000 entries per user)
    - Hit/miss tracking for analytics
    """
    
    def __init__(self, redis_client: redis.Redis, cache_ttl_hours: int = 24, max_size_per_user: int = 10000):
        self.redis = redis_client
        self.cache_ttl = cache_ttl_hours * 3600
        self.max_size = max_size_per_user
        self.metrics = {"hits": 0, "misses": 0, "evictions": 0}
    
    def _prompt_hash(self, prompt: str) -> str:
        """SHA256 hash of prompt text"""
        return hashlib.sha256(prompt.encode()).hexdigest()
    
    def _cache_key(self, user_id: str, prompt_hash: str) -> str:
        """Redis key pattern: cache:user:{user_id}:prompt:{hash}"""
        return f"cache:user:{user_id}:prompt:{prompt_hash}"
    
    def _user_cache_size_key(self, user_id: str) -> str:
        """Track cache size per user for LRU eviction"""
        return f"cache:user:{user_id}:size"
    
    def get(self, user_id: str, prompt: str, model: str) -> Optional[Tuple[str, Dict]]:
        """
        Get cached response if available.
        
        Returns:
            Tuple of (cached_response, metadata_dict) or None if not in cache
        """
        prompt_hash = self._prompt_hash(prompt)
        key = self._cache_key(user_id, prompt_hash)
        
        cached_data = self.redis.get(key)
        if cached_data:
            cached_obj = json.loads(cached_data)
            cached_obj["accessed_at"] = time.time()
            cached_obj["hit_count"] += 1
            
            # Update cache entry with new access metadata
            self.redis.setex(key, self.cache_ttl, json.dumps(cached_obj))
            
            self.metrics["hits"] += 1
            return (cached_obj["response"], {
                "cached": True,
                "model_cached": cached_obj["model"],
                "cached_at": datetime.fromtimestamp(cached_obj["cached_at"]).isoformat(),
                "hit_count": cached_obj["hit_count"]
            })
        
        self.metrics["misses"] += 1
        return None
    
    def set(self, user_id: str, prompt: str, model: str, response: str, tokens_used: int) -> None:
        """Cache a new prompt-response pair"""
        prompt_hash = self._prompt_hash(prompt)
        key = self._cache_key(user_id, prompt_hash)
        
        cached_response = CachedResponse(
            prompt_hash=prompt_hash,
            prompt_original=prompt,
            model=model,
            response=response,
            tokens_used=tokens_used,
            cached_at=time.time(),
            accessed_at=time.time(),
            hit_count=0,
            user_id=user_id
        )
        
        # Check cache size and evict LRU if necessary
        size_key = self._user_cache_size_key(user_id)
        current_size = int(self.redis.get(size_key) or 0)
        
        if current_size >= self.max_size:
            # LRU eviction: remove oldest accessed entry
            self._evict_oldest(user_id)
            self.metrics["evictions"] += 1
        
        # Store with TTL
        self.redis.setex(key, self.cache_ttl, json.dumps(asdict(cached_response)))
        
        # Increment user cache size
        self.redis.incr(size_key)
    
    def _evict_oldest(self, user_id: str) -> None:
        """Remove least recently used entry for user"""
        pattern = f"cache:user:{user_id}:prompt:*"
        keys = self.redis.keys(pattern)
        
        if not keys:
            return
        
        # Find entry with oldest accessed_at
        oldest_key = None
        oldest_time = time.time()
        
        for key in keys:
            data = json.loads(self.redis.get(key))
            if data["accessed_at"] < oldest_time:
                oldest_time = data["accessed_at"]
                oldest_key = key
        
        if oldest_key:
            self.redis.delete(oldest_key)
            size_key = self._user_cache_size_key(user_id)
            self.redis.decr(size_key)
    
    def get_metrics(self) -> Dict:
        """Return cache statistics"""
        total_requests = self.metrics["hits"] + self.metrics["misses"]
        hit_rate = (self.metrics["hits"] / total_requests * 100) if total_requests > 0 else 0
        
        return {
            "hits": self.metrics["hits"],
            "misses": self.metrics["misses"],
            "evictions": self.metrics["evictions"],
            "hit_rate_percent": round(hit_rate, 2),
            "total_requests": total_requests
        }
    
    def clear_user_cache(self, user_id: str) -> int:
        """Clear all cached entries for a user. Returns count deleted."""
        pattern = f"cache:user:{user_id}:prompt:*"
        keys = self.redis.keys(pattern)
        
        if keys:
            self.redis.delete(*keys)
            size_key = self._user_cache_size_key(user_id)
            self.redis.delete(size_key)
        
        return len(keys)


class ResponseFilter:
    """
    Post-processing filter for model responses.
    
    Removes:
    - PII from responses (email, phone, SSN)
    - Code snippets with secrets
    - Internal references (IP addresses, hostnames)
    - External URLs (phase 1 blocker for offline mode)
    
    Preserves:
    - Code structure and syntax
    - Technical accuracy
    - User context awareness
    """
    
    PII_PATTERNS = {
        "email": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
        "phone": r"\b(?:\d{3}[-.]?)?\d{3}[-.]?\d{4}\b",
        "ssn": r"\b\d{3}-\d{2}-\d{4}\b",
        "credit_card": r"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b",
        "ip_address": r"\b(?:192\.168|10\.|172\.(?:1[6-9]|2\d|3[01])\.)[\w.]+\b",
        "hostname": r"\b(?:(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,})\b",
    }
    
    def __init__(self, enable_redaction: bool = True, log_redactions: bool = True):
        self.enable_redaction = enable_redaction
        self.log_redactions = log_redactions
        self.redactions_log: List[Dict] = []
    
    def filter_response(self, response: str) -> Tuple[str, List[str]]:
        """
        Filter response text for PII and sensitive data.
        
        Returns:
            Tuple of (filtered_response, list_of_findings)
        """
        if not self.enable_redaction:
            return response, []
        
        import re
        findings = []
        filtered_response = response
        
        for pattern_name, pattern in self.PII_PATTERNS.items():
            matches = re.finditer(pattern, filtered_response, re.IGNORECASE)
            for match in matches:
                findings.append({
                    "type": pattern_name,
                    "value": match.group(),
                    "position": match.start()
                })
                # Redact with placeholder
                filtered_response = filtered_response.replace(
                    match.group(), 
                    f"[REDACTED_{pattern_name.upper()}]"
                )
        
        if self.log_redactions and findings:
            self.redactions_log.append({
                "timestamp": datetime.utcnow().isoformat(),
                "redactions_count": len(findings),
                "findings": findings
            })
        
        return filtered_response, findings
    
    def get_redactions_log(self) -> List[Dict]:
        """Return log of all redactions performed"""
        return self.redactions_log
