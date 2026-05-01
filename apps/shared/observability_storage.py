"""
Observability Data Storage & Persistence

Implements storage backends for metrics and trace data:
- Time-series database adapters (InfluxDB, Prometheus, TimescaleDB)
- Trace storage backends (Elasticsearch, Jaeger, custom)
- Data retention policies
- Query builders for different backends
- Automatic data compaction and cleanup
"""

from dataclasses import dataclass, asdict, field
from typing import Dict, List, Optional, Any, Union, Callable, Tuple, Generator
from enum import Enum
from datetime import datetime, timedelta
from abc import ABC, abstractmethod
import json
from threading import Lock
import hashlib


class StorageBackend(Enum):
    """Supported storage backends."""
    INFLUXDB = "influxdb"
    PROMETHEUS = "prometheus"
    TIMESCALEDB = "timescaledb"
    ELASTICSEARCH = "elasticsearch"
    JAEGER = "jaeger"
    MEMORY = "memory"  # For testing


class QueryTimeRange(Enum):
    """Predefined time ranges."""
    LAST_5M = "5m"
    LAST_15M = "15m"
    LAST_1H = "1h"
    LAST_6H = "6h"
    LAST_24H = "24h"
    LAST_7D = "7d"
    LAST_30D = "30d"


@dataclass
class RetentionPolicy:
    """Data retention configuration."""
    name: str
    duration: timedelta
    replication_factor: int = 1
    shard_duration: Optional[timedelta] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "duration": str(self.duration),
            "replication_factor": self.replication_factor,
            "shard_duration": str(self.shard_duration) if self.shard_duration else None,
        }


@dataclass
class MetricPoint:
    """Individual metric data point."""
    timestamp: datetime
    value: Union[int, float]
    metric_name: str
    labels: Dict[str, str] = field(default_factory=dict)
    tags: Dict[str, str] = field(default_factory=dict)  # InfluxDB tags
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "value": self.value,
            "metric_name": self.metric_name,
            "labels": self.labels,
            "tags": self.tags,
        }


@dataclass
class TracePoint:
    """Trace span data point."""
    trace_id: str
    span_id: str
    span_name: str
    timestamp: datetime
    duration_ms: float
    service_name: str
    status: str = "ok"  # ok, error
    tags: Dict[str, str] = field(default_factory=dict)
    logs: List[Dict[str, Any]] = field(default_factory=list)
    parent_span_id: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "trace_id": self.trace_id,
            "span_id": self.span_id,
            "span_name": self.span_name,
            "timestamp": self.timestamp.isoformat(),
            "duration_ms": self.duration_ms,
            "service_name": self.service_name,
            "status": self.status,
            "tags": self.tags,
            "logs": self.logs,
            "parent_span_id": self.parent_span_id,
        }


@dataclass
class StorageQuery:
    """Unified storage query builder."""
    metric_name: Optional[str] = None
    time_range: Union[str, Tuple[datetime, datetime]] = "1h"
    labels: Dict[str, str] = field(default_factory=dict)
    aggregation: Optional[str] = None  # avg, sum, max, min
    step: Optional[str] = None  # Prometheus step
    limit: int = 1000
    offset: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)


class StorageBackendAdapter(ABC):
    """Abstract base for storage backends."""
    
    @abstractmethod
    def connect(self, config: Dict[str, Any]) -> bool:
        """Connect to backend."""
        pass
    
    @abstractmethod
    def disconnect(self):
        """Disconnect from backend."""
        pass
    
    @abstractmethod
    def health_check(self) -> bool:
        """Check backend health."""
        pass
    
    @abstractmethod
    def write_metric(self, point: MetricPoint) -> bool:
        """Write metric point."""
        pass
    
    @abstractmethod
    def write_metrics_batch(self, points: List[MetricPoint]) -> bool:
        """Write batch of metrics."""
        pass
    
    @abstractmethod
    def query_metrics(self, query: StorageQuery) -> List[MetricPoint]:
        """Query metrics from storage."""
        pass
    
    @abstractmethod
    def write_trace(self, point: TracePoint) -> bool:
        """Write trace point."""
        pass
    
    @abstractmethod
    def query_traces(self, query: StorageQuery) -> List[TracePoint]:
        """Query traces from storage."""
        pass
    
    @abstractmethod
    def delete_old_data(self, before: datetime) -> int:
        """Delete data older than timestamp."""
        pass


class InfluxDBAdapter(StorageBackendAdapter):
    """InfluxDB storage adapter."""
    
    def __init__(self):
        self.client = None
        self.bucket = None
        self.org = None
    
    def connect(self, config: Dict[str, Any]) -> bool:
        """Connect to InfluxDB."""
        try:
            from influxdb_client import InfluxDBClient
            
            self.client = InfluxDBClient(
                url=config.get("url", "http://localhost:8086"),
                token=config.get("token", ""),
                org=config.get("org", ""),
                timeout=30000  # 30s timeout
            )
            self.bucket = config.get("bucket", "observability")
            self.org = config.get("org", "")
            
            return self.health_check()
        except Exception as e:
            print(f"Failed to connect to InfluxDB: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from InfluxDB."""
        if self.client:
            self.client.close()
    
    def health_check(self) -> bool:
        """Check InfluxDB health."""
        try:
            if self.client:
                self.client.ping()
                return True
        except Exception:
            pass
        return False
    
    def write_metric(self, point: MetricPoint) -> bool:
        """Write metric point."""
        return self.write_metrics_batch([point])
    
    def write_metrics_batch(self, points: List[MetricPoint]) -> bool:
        """Write batch of metrics to InfluxDB."""
        if not self.client:
            return False
        
        try:
            write_api = self.client.write_api()
            
            for point in points:
                # InfluxDB line protocol
                tags = ",".join(f"{k}={v}" for k, v in point.tags.items())
                line = f"{point.metric_name},{tags} value={point.value} {int(point.timestamp.timestamp() * 1e9)}"
                
                write_api.write(self.bucket, self.org, line)
            
            return True
        except Exception as e:
            print(f"Failed to write metrics: {e}")
            return False
    
    def query_metrics(self, query: StorageQuery) -> List[MetricPoint]:
        """Query metrics from InfluxDB."""
        if not self.client or not query.metric_name:
            return []
        
        try:
            query_api = self.client.query_api()
            
            # Build Flux query
            flux = f'from(bucket:"{self.bucket}") |> range(start: -{query.time_range})'
            if query.metric_name:
                flux += f' |> filter(fn: (r) => r._measurement == "{query.metric_name}")'
            
            result = query_api.query(flux)
            
            points = []
            for table in result:
                for record in table.records:
                    points.append(MetricPoint(
                        timestamp=record.get_time(),
                        value=record.get_value(),
                        metric_name=record.values.get("_measurement", ""),
                        tags=dict(record.tags)
                    ))
            
            return points[:query.limit]
        except Exception as e:
            print(f"Failed to query metrics: {e}")
            return []
    
    def write_trace(self, point: TracePoint) -> bool:
        """Write trace to InfluxDB."""
        # Store traces as measurements with duration
        metric_point = MetricPoint(
            timestamp=point.timestamp,
            value=point.duration_ms,
            metric_name=f"trace_{point.service_name}",
            tags={
                "trace_id": point.trace_id,
                "span_id": point.span_id,
                "span_name": point.span_name,
                "service": point.service_name,
                "status": point.status,
            }
        )
        return self.write_metric(metric_point)
    
    def query_traces(self, query: StorageQuery) -> List[TracePoint]:
        """Query traces from InfluxDB."""
        # Simplified trace query
        metric_points = self.query_metrics(query)
        
        traces = []
        for mp in metric_points:
            traces.append(TracePoint(
                trace_id=mp.tags.get("trace_id", ""),
                span_id=mp.tags.get("span_id", ""),
                span_name=mp.tags.get("span_name", ""),
                timestamp=mp.timestamp,
                duration_ms=mp.value,
                service_name=mp.tags.get("service", ""),
                status=mp.tags.get("status", "ok"),
                tags=mp.tags,
            ))
        
        return traces
    
    def delete_old_data(self, before: datetime) -> int:
        """Delete data before timestamp (not natively supported in InfluxDB Cloud)."""
        # InfluxDB handles retention via RetentionPolicy
        return 0


class TimescaleDBAdapter(StorageBackendAdapter):
    """TimescaleDB storage adapter."""
    
    def __init__(self):
        self.connection = None
        self._lock = Lock()
    
    def connect(self, config: Dict[str, Any]) -> bool:
        """Connect to TimescaleDB."""
        try:
            import psycopg2
            
            self.connection = psycopg2.connect(
                host=config.get("host", "localhost"),
                port=config.get("port", 5432),
                database=config.get("database", "observability"),
                user=config.get("user", "postgres"),
                password=config.get("password", ""),
                connect_timeout=10
            )
            
            # Create hypertables if needed
            self._create_tables()
            
            return self.health_check()
        except Exception as e:
            print(f"Failed to connect to TimescaleDB: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from TimescaleDB."""
        if self.connection:
            self.connection.close()
    
    def health_check(self) -> bool:
        """Check TimescaleDB health."""
        try:
            with self.connection.cursor() as cur:
                cur.execute("SELECT 1")
                return True
        except Exception:
            return False
    
    def _create_tables(self):
        """Create metrics and traces hypertables."""
        try:
            with self.connection.cursor() as cur:
                # Metrics table
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS metrics (
                        time TIMESTAMPTZ NOT NULL,
                        metric_name TEXT NOT NULL,
                        value FLOAT8,
                        labels JSONB,
                        tags JSONB
                    );
                    SELECT create_hypertable('metrics', 'time', if_not_exists => TRUE);
                """)
                
                # Traces table
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS traces (
                        time TIMESTAMPTZ NOT NULL,
                        trace_id TEXT NOT NULL,
                        span_id TEXT NOT NULL,
                        span_name TEXT,
                        duration_ms FLOAT8,
                        service_name TEXT,
                        status TEXT,
                        tags JSONB,
                        logs JSONB,
                        parent_span_id TEXT
                    );
                    SELECT create_hypertable('traces', 'time', if_not_exists => TRUE);
                """)
                
                # Create indexes
                cur.execute("""
                    CREATE INDEX IF NOT EXISTS idx_traces_trace_id ON traces (trace_id);
                    CREATE INDEX IF NOT EXISTS idx_metrics_name ON metrics (metric_name, time DESC);
                """)
                
                self.connection.commit()
        except Exception as e:
            print(f"Failed to create tables: {e}")
    
    def write_metric(self, point: MetricPoint) -> bool:
        """Write metric point."""
        return self.write_metrics_batch([point])
    
    def write_metrics_batch(self, points: List[MetricPoint]) -> bool:
        """Write batch of metrics."""
        if not self.connection:
            return False
        
        try:
            with self.connection.cursor() as cur:
                for point in points:
                    cur.execute("""
                        INSERT INTO metrics (time, metric_name, value, labels, tags)
                        VALUES (%s, %s, %s, %s, %s)
                    """, (
                        point.timestamp,
                        point.metric_name,
                        point.value,
                        json.dumps(point.labels),
                        json.dumps(point.tags),
                    ))
                
                self.connection.commit()
            return True
        except Exception as e:
            print(f"Failed to write metrics: {e}")
            self.connection.rollback()
            return False
    
    def query_metrics(self, query: StorageQuery) -> List[MetricPoint]:
        """Query metrics from storage."""
        if not self.connection or not query.metric_name:
            return []
        
        try:
            # Parse time range
            if isinstance(query.time_range, str):
                # Convert "1h" format to timedelta
                td = self._parse_duration(query.time_range)
                start_time = datetime.utcnow() - td
            else:
                start_time = query.time_range[0]
            
            with self.connection.cursor() as cur:
                sql = """
                    SELECT time, metric_name, value, labels, tags
                    FROM metrics
                    WHERE metric_name = %s AND time >= %s
                    ORDER BY time DESC
                    LIMIT %s OFFSET %s
                """
                cur.execute(sql, (query.metric_name, start_time, query.limit, query.offset))
                
                points = []
                for row in cur.fetchall():
                    points.append(MetricPoint(
                        timestamp=row[0],
                        metric_name=row[1],
                        value=row[2],
                        labels=json.loads(row[3]) if row[3] else {},
                        tags=json.loads(row[4]) if row[4] else {},
                    ))
                
                return points
        except Exception as e:
            print(f"Failed to query metrics: {e}")
            return []
    
    def write_trace(self, point: TracePoint) -> bool:
        """Write trace point."""
        if not self.connection:
            return False
        
        try:
            with self.connection.cursor() as cur:
                cur.execute("""
                    INSERT INTO traces (
                        time, trace_id, span_id, span_name, duration_ms,
                        service_name, status, tags, logs, parent_span_id
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    point.timestamp,
                    point.trace_id,
                    point.span_id,
                    point.span_name,
                    point.duration_ms,
                    point.service_name,
                    point.status,
                    json.dumps(point.tags),
                    json.dumps(point.logs),
                    point.parent_span_id,
                ))
                
                self.connection.commit()
            return True
        except Exception as e:
            print(f"Failed to write trace: {e}")
            self.connection.rollback()
            return False
    
    def query_traces(self, query: StorageQuery) -> List[TracePoint]:
        """Query traces from storage."""
        if not self.connection:
            return []
        
        try:
            if isinstance(query.time_range, str):
                td = self._parse_duration(query.time_range)
                start_time = datetime.utcnow() - td
            else:
                start_time = query.time_range[0]
            
            with self.connection.cursor() as cur:
                sql = """
                    SELECT time, trace_id, span_id, span_name, duration_ms,
                           service_name, status, tags, logs, parent_span_id
                    FROM traces
                    WHERE time >= %s
                    ORDER BY time DESC
                    LIMIT %s OFFSET %s
                """
                cur.execute(sql, (start_time, query.limit, query.offset))
                
                traces = []
                for row in cur.fetchall():
                    traces.append(TracePoint(
                        timestamp=row[0],
                        trace_id=row[1],
                        span_id=row[2],
                        span_name=row[3],
                        duration_ms=row[4],
                        service_name=row[5],
                        status=row[6],
                        tags=json.loads(row[7]) if row[7] else {},
                        logs=json.loads(row[8]) if row[8] else [],
                        parent_span_id=row[9],
                    ))
                
                return traces
        except Exception as e:
            print(f"Failed to query traces: {e}")
            return []
    
    def delete_old_data(self, before: datetime) -> int:
        """Delete data before timestamp."""
        if not self.connection:
            return 0
        
        try:
            with self.connection.cursor() as cur:
                # Delete old metrics
                cur.execute("DELETE FROM metrics WHERE time < %s", (before,))
                metrics_deleted = cur.rowcount
                
                # Delete old traces
                cur.execute("DELETE FROM traces WHERE time < %s", (before,))
                traces_deleted = cur.rowcount
                
                self.connection.commit()
            
            return metrics_deleted + traces_deleted
        except Exception as e:
            print(f"Failed to delete old data: {e}")
            return 0
    
    @staticmethod
    def _parse_duration(duration_str: str) -> timedelta:
        """Parse duration string like '1h', '5m', etc."""
        import re
        match = re.match(r"(\d+)([smhd])", duration_str)
        if not match:
            return timedelta(hours=1)
        
        value, unit = int(match.group(1)), match.group(2)
        if unit == "s":
            return timedelta(seconds=value)
        elif unit == "m":
            return timedelta(minutes=value)
        elif unit == "h":
            return timedelta(hours=value)
        elif unit == "d":
            return timedelta(days=value)
        
        return timedelta(hours=1)


class MemoryStorageAdapter(StorageBackendAdapter):
    """In-memory storage adapter for testing."""
    
    def __init__(self):
        self.metrics: List[MetricPoint] = []
        self.traces: List[TracePoint] = []
        self._lock = Lock()
    
    def connect(self, config: Dict[str, Any]) -> bool:
        """Connect (no-op for memory)."""
        return True
    
    def disconnect(self):
        """Disconnect (no-op for memory)."""
        pass
    
    def health_check(self) -> bool:
        """Health check (always OK for memory)."""
        return True
    
    def write_metric(self, point: MetricPoint) -> bool:
        """Write metric point."""
        with self._lock:
            self.metrics.append(point)
        return True
    
    def write_metrics_batch(self, points: List[MetricPoint]) -> bool:
        """Write batch of metrics."""
        with self._lock:
            self.metrics.extend(points)
        return True
    
    def query_metrics(self, query: StorageQuery) -> List[MetricPoint]:
        """Query metrics from memory."""
        with self._lock:
            results = [
                m for m in self.metrics
                if not query.metric_name or m.metric_name == query.metric_name
            ]
            return results[query.offset:query.offset + query.limit]
    
    def write_trace(self, point: TracePoint) -> bool:
        """Write trace point."""
        with self._lock:
            self.traces.append(point)
        return True
    
    def query_traces(self, query: StorageQuery) -> List[TracePoint]:
        """Query traces from memory."""
        with self._lock:
            return self.traces[query.offset:query.offset + query.limit]
    
    def delete_old_data(self, before: datetime) -> int:
        """Delete old data."""
        with self._lock:
            old_metrics = [m for m in self.metrics if m.timestamp < before]
            old_traces = [t for t in self.traces if t.timestamp < before]
            
            self.metrics = [m for m in self.metrics if m.timestamp >= before]
            self.traces = [t for t in self.traces if t.timestamp >= before]
            
            return len(old_metrics) + len(old_traces)


class StorageFactory:
    """Factory for creating storage adapters."""
    
    _adapters: Dict[StorageBackend, StorageBackendAdapter] = {}
    
    @classmethod
    def get_adapter(cls, backend: StorageBackend) -> StorageBackendAdapter:
        """Get or create storage adapter."""
        if backend not in cls._adapters:
            if backend == StorageBackend.INFLUXDB:
                cls._adapters[backend] = InfluxDBAdapter()
            elif backend == StorageBackend.TIMESCALEDB:
                cls._adapters[backend] = TimescaleDBAdapter()
            elif backend == StorageBackend.MEMORY:
                cls._adapters[backend] = MemoryStorageAdapter()
            else:
                raise ValueError(f"Unsupported backend: {backend}")
        
        return cls._adapters[backend]
    
    @classmethod
    def reset(cls):
        """Reset all adapters."""
        for adapter in cls._adapters.values():
            try:
                adapter.disconnect()
            except Exception:
                pass
        cls._adapters.clear()


class DataCompactor:
    """Compacts and downsamples observability data."""
    
    @staticmethod
    def downsample_metrics(points: List[MetricPoint], 
                          interval_minutes: int = 5) -> List[MetricPoint]:
        """Downsample metrics to reduce storage."""
        if not points:
            return []
        
        # Group by time bucket
        buckets: Dict[int, List[MetricPoint]] = {}
        for point in points:
            bucket_key = int(point.timestamp.timestamp() // (interval_minutes * 60))
            if bucket_key not in buckets:
                buckets[bucket_key] = []
            buckets[bucket_key].append(point)
        
        # Aggregate each bucket
        downsampled = []
        for bucket_time, bucket_points in sorted(buckets.items()):
            if not bucket_points:
                continue
            
            avg_value = sum(p.value for p in bucket_points) / len(bucket_points)
            downsampled.append(MetricPoint(
                timestamp=bucket_points[0].timestamp,
                value=avg_value,
                metric_name=bucket_points[0].metric_name,
                labels=bucket_points[0].labels,
                tags=bucket_points[0].tags,
            ))
        
        return downsampled


__all__ = [
    'StorageBackend',
    'QueryTimeRange',
    'RetentionPolicy',
    'MetricPoint',
    'TracePoint',
    'StorageQuery',
    'StorageBackendAdapter',
    'InfluxDBAdapter',
    'TimescaleDBAdapter',
    'MemoryStorageAdapter',
    'StorageFactory',
    'DataCompactor',
]
