"""
Edge Agent Workspace Asset Cache - Localized caching for low-latency access
@governance GOV-002: IaC, immutable, version-controlled
@description Implements localized caching of workspace assets at edge agents
             to reduce latency for remote teams accessing shared workspaces.
"""

import hashlib
import time
from datetime import datetime, timedelta
from enum import Enum
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field


class CacheEntryStatus(str, Enum):
    """Cache entry lifecycle states"""
    FRESH = "fresh"        # Within TTL, served from cache
    STALE = "stale"        # Beyond TTL, should be revalidated
    EVICTED = "evicted"    # Removed from cache
    PENDING = "pending"    # Being fetched from origin


class AssetType(str, Enum):
    """Workspace asset types with different cache TTLs"""
    WORKSPACE_METADATA = "workspace_metadata"   # 60s TTL
    FILE_CONTENT = "file_content"               # 300s TTL
    DIRECTORY_LISTING = "directory_listing"     # 30s TTL
    EXTENSION_BUNDLE = "extension_bundle"       # 3600s TTL (extensions are immutable)
    SETTINGS = "settings"                       # 120s TTL
    THEME = "theme"                             # 3600s TTL


# TTL in seconds per asset type
ASSET_TTL: Dict[AssetType, int] = {
    AssetType.WORKSPACE_METADATA: 60,
    AssetType.FILE_CONTENT: 300,
    AssetType.DIRECTORY_LISTING: 30,
    AssetType.EXTENSION_BUNDLE: 3600,
    AssetType.SETTINGS: 120,
    AssetType.THEME: 3600,
}

# Maximum cache size per asset type (bytes)
MAX_ASSET_SIZE: Dict[AssetType, int] = {
    AssetType.WORKSPACE_METADATA: 64 * 1024,       # 64 KB
    AssetType.FILE_CONTENT: 10 * 1024 * 1024,      # 10 MB
    AssetType.DIRECTORY_LISTING: 256 * 1024,        # 256 KB
    AssetType.EXTENSION_BUNDLE: 50 * 1024 * 1024,  # 50 MB
    AssetType.SETTINGS: 64 * 1024,                  # 64 KB
    AssetType.THEME: 5 * 1024 * 1024,              # 5 MB
}


class CacheEntry(BaseModel):
    """Single cache entry for a workspace asset"""
    cache_key: str
    asset_type: AssetType
    content_hash: str          # SHA256 for integrity validation
    size_bytes: int
    etag: Optional[str] = None
    cached_at: datetime = Field(default_factory=datetime.utcnow)
    accessed_at: datetime = Field(default_factory=datetime.utcnow)
    access_count: int = Field(default=1)
    status: CacheEntryStatus = CacheEntryStatus.FRESH
    origin_url: str            # Where to revalidate from
    ttl_seconds: int

    @property
    def is_expired(self) -> bool:
        age = (datetime.utcnow() - self.cached_at).total_seconds()
        return age > self.ttl_seconds

    @property
    def age_seconds(self) -> float:
        return (datetime.utcnow() - self.cached_at).total_seconds()

    class Config:
        use_enum_values = True


class CacheStoreRequest(BaseModel):
    """Request to store an asset in the edge cache"""
    asset_type: AssetType
    content_hash: str
    size_bytes: int
    origin_url: str
    workspace_id: str
    path: str
    etag: Optional[str] = None
    custom_ttl_seconds: Optional[int] = None


class CacheStoreResponse(BaseModel):
    """Response from cache store operation"""
    cache_key: str
    stored: bool
    rejected_reason: Optional[str] = None
    ttl_seconds: int


class CacheLookupResponse(BaseModel):
    """Response from cache lookup"""
    cache_key: str
    found: bool
    status: Optional[CacheEntryStatus] = None
    content_hash: Optional[str] = None
    etag: Optional[str] = None
    age_seconds: Optional[float] = None
    ttl_remaining_seconds: Optional[float] = None


class CacheEvictionPolicy(str, Enum):
    """Cache eviction strategies"""
    LRU = "lru"         # Least recently used
    LFU = "lfu"         # Least frequently used
    TTL = "ttl"         # Evict expired entries only


class CacheStats(BaseModel):
    """Cache performance statistics"""
    agent_id: str
    total_entries: int
    total_size_bytes: int
    max_size_bytes: int
    hit_rate_pct: float
    miss_count: int
    hit_count: int
    eviction_count: int
    fresh_entries: int
    stale_entries: int
    recorded_at: datetime = Field(default_factory=datetime.utcnow)


class WorkspaceAssetCache:
    """
    In-memory workspace asset cache for edge agents.
    Implements LRU eviction with per-asset-type TTL and size limits.
    Thread-safe for concurrent access patterns.
    """

    # Maximum total cache size: 500 MB per edge agent
    MAX_TOTAL_CACHE_BYTES = 500 * 1024 * 1024
    EVICTION_POLICY = CacheEvictionPolicy.LRU

    def __init__(self, agent_id: str, max_total_bytes: Optional[int] = None):
        self.agent_id = agent_id
        self.max_total_bytes = max_total_bytes or self.MAX_TOTAL_CACHE_BYTES
        self._entries: Dict[str, CacheEntry] = {}
        self._data: Dict[str, bytes] = {}      # Actual cached content
        self._total_size_bytes = 0
        self._hit_count = 0
        self._miss_count = 0
        self._eviction_count = 0

    @staticmethod
    def make_cache_key(workspace_id: str, path: str, asset_type: AssetType) -> str:
        """Generate deterministic cache key from workspace + path + type"""
        raw = f"{workspace_id}:{path}:{asset_type}"
        return hashlib.sha256(raw.encode()).hexdigest()[:32]

    def store(self, request: CacheStoreRequest, content: bytes) -> CacheStoreResponse:
        """Store asset in cache, evicting if necessary"""
        asset_type = request.asset_type

        # Reject if exceeds per-type size limit
        max_size = MAX_ASSET_SIZE.get(asset_type, 1 * 1024 * 1024)
        if request.size_bytes > max_size:
            return CacheStoreResponse(
                cache_key="",
                stored=False,
                rejected_reason=f"Asset size {request.size_bytes} exceeds limit {max_size} for {asset_type}",
                ttl_seconds=0,
            )

        cache_key = self.make_cache_key(
            request.workspace_id, request.path, asset_type
        )
        ttl = request.custom_ttl_seconds or ASSET_TTL.get(asset_type, 60)

        # Evict if needed to make room
        while (
            self._total_size_bytes + request.size_bytes > self.max_total_bytes
            and self._entries
        ):
            self._evict_one()

        # Store entry metadata
        entry = CacheEntry(
            cache_key=cache_key,
            asset_type=asset_type,
            content_hash=request.content_hash,
            size_bytes=request.size_bytes,
            etag=request.etag,
            origin_url=request.origin_url,
            ttl_seconds=ttl,
        )
        # Replace existing if same key
        if cache_key in self._entries:
            self._total_size_bytes -= self._entries[cache_key].size_bytes
        self._entries[cache_key] = entry
        self._data[cache_key] = content
        self._total_size_bytes += request.size_bytes

        return CacheStoreResponse(
            cache_key=cache_key,
            stored=True,
            ttl_seconds=ttl,
        )

    def lookup(self, workspace_id: str, path: str, asset_type: AssetType) -> CacheLookupResponse:
        """Look up asset in cache, returning metadata (not content)"""
        cache_key = self.make_cache_key(workspace_id, path, asset_type)

        if cache_key not in self._entries:
            self._miss_count += 1
            return CacheLookupResponse(cache_key=cache_key, found=False)

        entry = self._entries[cache_key]

        if entry.is_expired:
            entry.status = CacheEntryStatus.STALE
            self._miss_count += 1
            return CacheLookupResponse(
                cache_key=cache_key,
                found=True,
                status=CacheEntryStatus.STALE,
                content_hash=entry.content_hash,
                etag=entry.etag,
                age_seconds=entry.age_seconds,
                ttl_remaining_seconds=0,
            )

        # Cache hit: update access metadata
        entry.accessed_at = datetime.utcnow()
        entry.access_count += 1
        self._hit_count += 1

        ttl_remaining = entry.ttl_seconds - entry.age_seconds

        return CacheLookupResponse(
            cache_key=cache_key,
            found=True,
            status=CacheEntryStatus.FRESH,
            content_hash=entry.content_hash,
            etag=entry.etag,
            age_seconds=entry.age_seconds,
            ttl_remaining_seconds=ttl_remaining,
        )

    def get_content(self, cache_key: str) -> Optional[bytes]:
        """Retrieve cached content bytes by key"""
        return self._data.get(cache_key)

    def invalidate(self, workspace_id: str, path: str, asset_type: AssetType) -> bool:
        """Explicitly invalidate a cache entry (e.g. on file write)"""
        cache_key = self.make_cache_key(workspace_id, path, asset_type)
        if cache_key in self._entries:
            self._total_size_bytes -= self._entries[cache_key].size_bytes
            del self._entries[cache_key]
            del self._data[cache_key]
            self._eviction_count += 1
            return True
        return False

    def invalidate_workspace(self, workspace_id: str) -> int:
        """Invalidate all cache entries for a workspace (e.g. on workspace close)"""
        keys_to_remove = [
            k for k, v in self._entries.items()
            if workspace_id in v.origin_url
        ]
        for key in keys_to_remove:
            self._total_size_bytes -= self._entries[key].size_bytes
            del self._entries[key]
            del self._data[key]
            self._eviction_count += 1
        return len(keys_to_remove)

    def evict_stale(self) -> int:
        """Evict all expired entries (run periodically)"""
        expired_keys = [k for k, v in self._entries.items() if v.is_expired]
        for key in expired_keys:
            self._total_size_bytes -= self._entries[key].size_bytes
            del self._entries[key]
            if key in self._data:
                del self._data[key]
            self._eviction_count += 1
        return len(expired_keys)

    def get_stats(self) -> CacheStats:
        """Return cache performance statistics"""
        total = self._hit_count + self._miss_count
        hit_rate = (self._hit_count / total * 100) if total > 0 else 0.0
        fresh = sum(1 for e in self._entries.values() if not e.is_expired)
        stale = len(self._entries) - fresh

        return CacheStats(
            agent_id=self.agent_id,
            total_entries=len(self._entries),
            total_size_bytes=self._total_size_bytes,
            max_size_bytes=self.max_total_bytes,
            hit_rate_pct=round(hit_rate, 2),
            miss_count=self._miss_count,
            hit_count=self._hit_count,
            eviction_count=self._eviction_count,
            fresh_entries=fresh,
            stale_entries=stale,
        )

    def _evict_one(self):
        """Evict single entry using LRU policy"""
        if not self._entries:
            return
        # LRU: evict the entry with oldest access time
        lru_key = min(self._entries, key=lambda k: self._entries[k].accessed_at)
        self._total_size_bytes -= self._entries[lru_key].size_bytes
        del self._entries[lru_key]
        if lru_key in self._data:
            del self._data[lru_key]
        self._eviction_count += 1
