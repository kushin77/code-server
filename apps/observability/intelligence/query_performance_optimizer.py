"""
Phase 25B: Query Performance Optimization

Advanced query optimization for the observability platform:
- Query indexing and caching strategies
- Query execution planning
- Index recommendations
- Query performance profiling

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Tuple, Set
from datetime import datetime, timedelta
from enum import Enum
import hashlib
import statistics

logger = logging.getLogger(__name__)


class IndexType(Enum):
    """Types of indexes."""
    PRIMARY = "primary"
    SECONDARY = "secondary"
    COMPOSITE = "composite"
    FULL_TEXT = "full_text"
    GEO = "geo"
    BITMAP = "bitmap"


class QueryType(Enum):
    """Types of queries."""
    TRACE = "trace"
    METRICS = "metrics"
    LOGS = "logs"
    COMPOSITE = "composite"


@dataclass
class QueryStatistic:
    """Statistics for a query."""
    query_hash: str
    query_type: QueryType
    execution_count: int = 0
    total_duration_ms: int = 0
    min_duration_ms: int = 0
    max_duration_ms: int = 0
    avg_duration_ms: float = 0.0
    rows_returned: int = 0
    cache_hits: int = 0
    cache_misses: int = 0
    
    @property
    def avg_rows_per_query(self) -> float:
        """Get average rows per query."""
        if self.execution_count == 0:
            return 0.0
        return self.rows_returned / self.execution_count
    
    @property
    def cache_hit_rate(self) -> float:
        """Get cache hit rate."""
        total = self.cache_hits + self.cache_misses
        if total == 0:
            return 0.0
        return (self.cache_hits / total) * 100.0
    
    def update_stats(self, duration_ms: int, rows: int, was_cached: bool) -> None:
        """Update statistics with new query result."""
        self.execution_count += 1
        self.total_duration_ms += duration_ms
        self.min_duration_ms = min(self.min_duration_ms, duration_ms) if self.min_duration_ms > 0 else duration_ms
        self.max_duration_ms = max(self.max_duration_ms, duration_ms)
        self.avg_duration_ms = self.total_duration_ms / self.execution_count
        self.rows_returned += rows
        
        if was_cached:
            self.cache_hits += 1
        else:
            self.cache_misses += 1


@dataclass
class IndexDefinition:
    """Definition of a database index."""
    index_id: str
    name: str
    index_type: IndexType
    columns: List[str] = field(default_factory=list)
    composite_columns: List[Tuple[str, ...]] = field(default_factory=list)
    estimated_size_mb: float = 0.0
    selectivity: float = 1.0  # How selective the index is (0-1)
    cardinality: int = 0  # Number of distinct values
    created_at: Optional[datetime] = None
    last_analyzed: Optional[datetime] = None
    
    def validate(self) -> bool:
        """Validate index definition."""
        if not self.name:
            return False
        if self.index_type == IndexType.COMPOSITE and not self.composite_columns:
            return False
        if self.index_type != IndexType.COMPOSITE and not self.columns:
            return False
        return True


@dataclass
class QueryExecutionPlan:
    """Execution plan for a query."""
    query_id: str
    query_type: QueryType
    estimated_cost: float
    estimated_rows: int
    indexes_used: List[str] = field(default_factory=list)
    steps: List[str] = field(default_factory=list)
    optimizations_applied: List[str] = field(default_factory=list)
    
    @property
    def is_optimized(self) -> bool:
        """Check if query is well-optimized."""
        return self.estimated_cost < 100.0 and len(self.indexes_used) > 0


@dataclass
class CachedQuery:
    """A cached query result."""
    query_hash: str
    result: Any
    created_at: datetime
    accessed_at: datetime
    access_count: int = 1
    size_bytes: int = 0
    
    @property
    def age_seconds(self) -> int:
        """Get cache entry age in seconds."""
        return int((datetime.utcnow() - self.created_at).total_seconds())
    
    @property
    def time_to_live_seconds(self) -> int:
        """Get time until entry expires (configurable)."""
        # Default TTL: 5 minutes
        return 300 - self.age_seconds


class QueryCache:
    """In-memory query cache with LRU eviction."""
    
    def __init__(self, max_entries: int = 1000, max_size_mb: int = 100):
        """Initialize query cache."""
        self.max_entries = max_entries
        self.max_size_bytes = max_size_mb * 1024 * 1024
        self.cache: Dict[str, CachedQuery] = {}
        self.total_size_bytes = 0
    
    def get(self, query_hash: str) -> Optional[Any]:
        """Get cached query result."""
        if query_hash not in self.cache:
            return None
        
        cached = self.cache[query_hash]
        cached.accessed_at = datetime.utcnow()
        cached.access_count += 1
        return cached.result
    
    def put(self, query_hash: str, result: Any, size_bytes: int) -> None:
        """Cache query result."""
        # Check size limit
        if self.total_size_bytes + size_bytes > self.max_size_bytes:
            self._evict_lru()
        
        # Check entry count limit
        if len(self.cache) >= self.max_entries:
            self._evict_lru()
        
        cached = CachedQuery(
            query_hash=query_hash,
            result=result,
            created_at=datetime.utcnow(),
            accessed_at=datetime.utcnow(),
            size_bytes=size_bytes,
        )
        self.cache[query_hash] = cached
        self.total_size_bytes += size_bytes
    
    def _evict_lru(self) -> None:
        """Evict least recently used entry."""
        if not self.cache:
            return
        
        # Find LRU entry
        lru_hash = min(
            self.cache.keys(),
            key=lambda k: self.cache[k].accessed_at
        )
        
        evicted = self.cache.pop(lru_hash)
        self.total_size_bytes -= evicted.size_bytes
    
    def invalidate(self, query_hash: str) -> None:
        """Invalidate cache entry."""
        if query_hash in self.cache:
            evicted = self.cache.pop(query_hash)
            self.total_size_bytes -= evicted.size_bytes
    
    def clear(self) -> None:
        """Clear all cache entries."""
        self.cache.clear()
        self.total_size_bytes = 0
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        return {
            "entries": len(self.cache),
            "total_size_mb": self.total_size_bytes / (1024 * 1024),
            "max_entries": self.max_entries,
            "max_size_mb": self.max_size_bytes / (1024 * 1024),
            "utilization": (len(self.cache) / self.max_entries) * 100 if self.max_entries > 0 else 0,
        }


class IndexRecommendationEngine:
    """Recommends indexes based on query patterns."""
    
    def __init__(self):
        """Initialize engine."""
        self.query_statistics: Dict[str, QueryStatistic] = {}
        self.existing_indexes: Dict[str, IndexDefinition] = {}
    
    def record_query(
        self,
        query_type: QueryType,
        query_text: str,
        duration_ms: int,
        rows_returned: int,
        was_cached: bool,
    ) -> None:
        """Record query execution."""
        query_hash = self._hash_query(query_text)
        
        if query_hash not in self.query_statistics:
            self.query_statistics[query_hash] = QueryStatistic(
                query_hash=query_hash,
                query_type=query_type,
            )
        
        stat = self.query_statistics[query_hash]
        stat.update_stats(duration_ms, rows_returned, was_cached)
    
    def get_slow_queries(self, threshold_ms: int = 1000) -> List[QueryStatistic]:
        """Get queries slower than threshold."""
        return [
            stat for stat in self.query_statistics.values()
            if stat.avg_duration_ms > threshold_ms
        ]
    
    def get_hot_queries(self, threshold_count: int = 100) -> List[QueryStatistic]:
        """Get most frequently executed queries."""
        return sorted(
            self.query_statistics.values(),
            key=lambda s: s.execution_count,
            reverse=True
        )[:threshold_count]
    
    def recommend_indexes(self) -> List[Dict[str, Any]]:
        """Generate index recommendations."""
        recommendations = []
        
        # Recommend indexes for slow queries
        slow_queries = self.get_slow_queries()
        for query in slow_queries:
            if query.cache_hit_rate < 50:  # Not well cached
                recommendations.append({
                    "type": "slow_query_index",
                    "query_hash": query.query_hash,
                    "avg_duration_ms": query.avg_duration_ms,
                    "execution_count": query.execution_count,
                    "priority": "high",
                })
        
        # Recommend indexes for hot queries
        hot_queries = self.get_hot_queries()
        for query in hot_queries[:20]:  # Top 20
            recommendations.append({
                "type": "hot_query_index",
                "query_hash": query.query_hash,
                "execution_count": query.execution_count,
                "priority": "medium",
            })
        
        return recommendations
    
    def _hash_query(self, query_text: str) -> str:
        """Hash query text."""
        return hashlib.md5(query_text.encode()).hexdigest()


class QueryOptimizer:
    """Optimizes query execution."""
    
    def __init__(self, cache: QueryCache, index_engine: IndexRecommendationEngine):
        """Initialize optimizer."""
        self.cache = cache
        self.index_engine = index_engine
        self.available_indexes: Dict[str, IndexDefinition] = {}
    
    def register_index(self, index: IndexDefinition) -> bool:
        """Register available index."""
        if not index.validate():
            return False
        self.available_indexes[index.index_id] = index
        logger.info(f"Registered index: {index.name}")
        return True
    
    def optimize_query(
        self,
        query_id: str,
        query_type: QueryType,
        query_text: str,
    ) -> QueryExecutionPlan:
        """Optimize query execution."""
        plan = QueryExecutionPlan(
            query_id=query_id,
            query_type=query_type,
            estimated_cost=100.0,
            estimated_rows=1000,
        )
        
        # Check cache
        query_hash = self.index_engine._hash_query(query_text)
        if self.cache.get(query_hash):
            plan.optimizations_applied.append("cache_hit")
            plan.estimated_cost = 1.0
        
        # Select appropriate indexes
        for index in self.available_indexes.values():
            if self._is_applicable_index(index, query_text):
                plan.indexes_used.append(index.name)
                plan.estimated_cost *= (1.0 - index.selectivity)
        
        # Apply optimizations
        if plan.estimated_cost > 50.0:
            plan.optimizations_applied.append("parallel_execution")
        if len(plan.indexes_used) == 0:
            plan.optimizations_applied.append("full_scan_warning")
        
        return plan
    
    def _is_applicable_index(self, index: IndexDefinition, query_text: str) -> bool:
        """Check if index applies to query."""
        for column in index.columns:
            if column in query_text:
                return True
        return False


class QueryAnalyzer:
    """Analyzes query execution patterns."""
    
    def __init__(self):
        """Initialize analyzer."""
        self.query_patterns: Dict[str, List[QueryStatistic]] = {}
    
    def analyze_pattern(self, statistics: List[QueryStatistic]) -> Dict[str, Any]:
        """Analyze query statistics pattern."""
        if not statistics:
            return {}
        
        durations = [s.avg_duration_ms for s in statistics]
        frequencies = [s.execution_count for s in statistics]
        
        return {
            "query_count": len(statistics),
            "avg_duration_ms": statistics.mean(durations) if durations else 0,
            "median_duration_ms": statistics.median(durations) if durations else 0,
            "max_duration_ms": max(durations) if durations else 0,
            "total_executions": sum(frequencies),
            "cache_hit_rate": sum(s.cache_hits for s in statistics) / (sum(s.cache_hits + s.cache_misses for s in statistics) or 1),
        }
    
    def identify_bottlenecks(self, statistics: List[QueryStatistic]) -> List[Dict[str, Any]]:
        """Identify query bottlenecks."""
        bottlenecks = []
        
        for stat in statistics:
            if stat.avg_duration_ms > 5000:  # > 5 seconds
                bottlenecks.append({
                    "type": "slow_query",
                    "query_hash": stat.query_hash,
                    "avg_duration_ms": stat.avg_duration_ms,
                    "severity": "critical",
                })
            elif stat.execution_count > 10000 and stat.cache_hit_rate < 30:
                bottlenecks.append({
                    "type": "hot_uncached_query",
                    "query_hash": stat.query_hash,
                    "execution_count": stat.execution_count,
                    "cache_hit_rate": stat.cache_hit_rate,
                    "severity": "high",
                })
        
        return bottlenecks


class QueryPerformanceOptimizer:
    """High-level query performance optimization."""
    
    def __init__(self):
        """Initialize optimizer."""
        self.cache = QueryCache()
        self.index_engine = IndexRecommendationEngine()
        self.query_optimizer = QueryOptimizer(self.cache, self.index_engine)
        self.analyzer = QueryAnalyzer()
    
    def register_index(self, index: IndexDefinition) -> bool:
        """Register index."""
        return self.query_optimizer.register_index(index)
    
    def record_query_execution(
        self,
        query_type: QueryType,
        query_text: str,
        duration_ms: int,
        rows_returned: int,
        was_cached: bool = False,
    ) -> None:
        """Record query execution."""
        self.index_engine.record_query(
            query_type, query_text, duration_ms, rows_returned, was_cached
        )
    
    def optimize_query(
        self,
        query_id: str,
        query_type: QueryType,
        query_text: str,
    ) -> QueryExecutionPlan:
        """Optimize query."""
        return self.query_optimizer.optimize_query(query_id, query_type, query_text)
    
    def get_recommendations(self) -> List[Dict[str, Any]]:
        """Get index recommendations."""
        return self.index_engine.recommend_indexes()
    
    def get_performance_report(self) -> Dict[str, Any]:
        """Get performance report."""
        all_stats = list(self.index_engine.query_statistics.values())
        
        return {
            "cache_stats": self.cache.get_stats(),
            "index_recommendations": self.get_recommendations(),
            "bottlenecks": self.analyzer.identify_bottlenecks(all_stats),
            "hot_queries": [
                {
                    "query_hash": s.query_hash,
                    "execution_count": s.execution_count,
                    "avg_duration_ms": s.avg_duration_ms,
                }
                for s in self.index_engine.get_hot_queries()[:10]
            ],
            "slow_queries": [
                {
                    "query_hash": s.query_hash,
                    "avg_duration_ms": s.avg_duration_ms,
                    "execution_count": s.execution_count,
                }
                for s in self.index_engine.get_slow_queries()[:10]
            ],
        }


__all__ = [
    "IndexType",
    "QueryType",
    "QueryStatistic",
    "IndexDefinition",
    "QueryExecutionPlan",
    "CachedQuery",
    "QueryCache",
    "IndexRecommendationEngine",
    "QueryOptimizer",
    "QueryAnalyzer",
    "QueryPerformanceOptimizer",
]
