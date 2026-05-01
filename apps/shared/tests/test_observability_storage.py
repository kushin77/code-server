"""
Tests for observability storage system.
"""

import pytest
from datetime import datetime, timedelta
from apps.shared.observability_storage import (
    StorageBackend, QueryTimeRange, RetentionPolicy, MetricPoint, TracePoint,
    StorageQuery, InfluxDBAdapter, TimescaleDBAdapter, MemoryStorageAdapter,
    StorageFactory, DataCompactor
)


class TestRetentionPolicy:
    """Test retention policy configuration."""
    
    def test_create_retention_policy(self):
        """Test creating retention policy."""
        policy = RetentionPolicy(
            name="7days",
            duration=timedelta(days=7),
            replication_factor=3
        )
        
        assert policy.name == "7days"
        assert policy.duration == timedelta(days=7)
        assert policy.replication_factor == 3
    
    def test_retention_policy_to_dict(self):
        """Test converting retention policy to dict."""
        policy = RetentionPolicy(
            name="30days",
            duration=timedelta(days=30)
        )
        
        d = policy.to_dict()
        assert d["name"] == "30days"
        assert "duration" in d


class TestMetricPoint:
    """Test metric data points."""
    
    def test_create_metric_point(self):
        """Test creating metric point."""
        now = datetime.utcnow()
        point = MetricPoint(
            timestamp=now,
            value=42.5,
            metric_name="requests_per_sec",
            labels={"service": "api"},
            tags={"environment": "prod"}
        )
        
        assert point.value == 42.5
        assert point.metric_name == "requests_per_sec"
        assert point.labels["service"] == "api"
    
    def test_metric_point_to_dict(self):
        """Test converting metric point to dict."""
        point = MetricPoint(
            timestamp=datetime.utcnow(),
            value=100,
            metric_name="cpu_usage"
        )
        
        d = point.to_dict()
        assert d["value"] == 100
        assert d["metric_name"] == "cpu_usage"
        assert "timestamp" in d


class TestTracePoint:
    """Test trace data points."""
    
    def test_create_trace_point(self):
        """Test creating trace point."""
        now = datetime.utcnow()
        point = TracePoint(
            trace_id="abc123",
            span_id="def456",
            span_name="process_request",
            timestamp=now,
            duration_ms=150.5,
            service_name="api-service"
        )
        
        assert point.trace_id == "abc123"
        assert point.duration_ms == 150.5
        assert point.status == "ok"
    
    def test_trace_point_with_error(self):
        """Test trace point with error status."""
        point = TracePoint(
            trace_id="xyz789",
            span_id="uvw456",
            span_name="database_query",
            timestamp=datetime.utcnow(),
            duration_ms=500,
            service_name="db-service",
            status="error",
            tags={"error": "timeout"}
        )
        
        assert point.status == "error"
        assert point.tags["error"] == "timeout"


class TestStorageQuery:
    """Test storage query builder."""
    
    def test_query_with_metric_name(self):
        """Test query with metric name."""
        query = StorageQuery(
            metric_name="cpu_usage",
            time_range="1h",
            limit=100
        )
        
        assert query.metric_name == "cpu_usage"
        assert query.limit == 100
    
    def test_query_with_labels(self):
        """Test query with label filters."""
        query = StorageQuery(
            metric_name="requests",
            labels={"service": "api", "method": "GET"},
            limit=50
        )
        
        assert query.labels["service"] == "api"
        assert query.labels["method"] == "GET"
    
    def test_query_with_aggregation(self):
        """Test query with aggregation."""
        query = StorageQuery(
            metric_name="latency",
            aggregation="avg",
            step="1m"
        )
        
        assert query.aggregation == "avg"
        assert query.step == "1m"


class TestMemoryStorageAdapter:
    """Test in-memory storage adapter."""
    
    def setup_method(self):
        """Setup for each test."""
        self.adapter = MemoryStorageAdapter()
    
    def test_connect_and_health(self):
        """Test connection and health check."""
        assert self.adapter.connect({}) is True
        assert self.adapter.health_check() is True
    
    def test_write_metric(self):
        """Test writing single metric."""
        point = MetricPoint(
            timestamp=datetime.utcnow(),
            value=42,
            metric_name="test_metric"
        )
        
        assert self.adapter.write_metric(point) is True
        assert len(self.adapter.metrics) == 1
    
    def test_write_metrics_batch(self):
        """Test writing batch of metrics."""
        points = [
            MetricPoint(datetime.utcnow(), i, f"metric_{i}")
            for i in range(10)
        ]
        
        assert self.adapter.write_metrics_batch(points) is True
        assert len(self.adapter.metrics) == 10
    
    def test_query_metrics(self):
        """Test querying metrics."""
        # Write test data
        for i in range(5):
            point = MetricPoint(
                timestamp=datetime.utcnow(),
                value=i * 10,
                metric_name="test_metric"
            )
            self.adapter.write_metric(point)
        
        # Query
        query = StorageQuery(metric_name="test_metric", limit=10)
        results = self.adapter.query_metrics(query)
        
        assert len(results) == 5
        assert all(r.metric_name == "test_metric" for r in results)
    
    def test_query_metrics_with_limit(self):
        """Test query with limit."""
        for i in range(20):
            self.adapter.write_metric(
                MetricPoint(datetime.utcnow(), i, "test_metric")
            )
        
        query = StorageQuery(metric_name="test_metric", limit=5, offset=0)
        results = self.adapter.query_metrics(query)
        
        assert len(results) == 5
    
    def test_query_metrics_with_offset(self):
        """Test query with offset."""
        for i in range(10):
            self.adapter.write_metric(
                MetricPoint(datetime.utcnow(), i, "test_metric")
            )
        
        query = StorageQuery(metric_name="test_metric", limit=5, offset=5)
        results = self.adapter.query_metrics(query)
        
        assert len(results) == 5
    
    def test_write_trace(self):
        """Test writing trace."""
        point = TracePoint(
            trace_id="abc123",
            span_id="def456",
            span_name="test_span",
            timestamp=datetime.utcnow(),
            duration_ms=100,
            service_name="test_service"
        )
        
        assert self.adapter.write_trace(point) is True
        assert len(self.adapter.traces) == 1
    
    def test_query_traces(self):
        """Test querying traces."""
        for i in range(5):
            trace = TracePoint(
                trace_id=f"trace_{i}",
                span_id=f"span_{i}",
                span_name="operation",
                timestamp=datetime.utcnow(),
                duration_ms=100 + i * 10,
                service_name="service"
            )
            self.adapter.write_trace(trace)
        
        query = StorageQuery(limit=10)
        results = self.adapter.query_traces(query)
        
        assert len(results) == 5
    
    def test_delete_old_data(self):
        """Test deleting old data."""
        now = datetime.utcnow()
        
        # Write recent data
        recent = MetricPoint(now, 1, "recent")
        self.adapter.write_metric(recent)
        
        # Write old data
        old = MetricPoint(now - timedelta(days=10), 2, "old")
        self.adapter.write_metric(old)
        
        # Delete data before 7 days ago
        cutoff = now - timedelta(days=7)
        deleted = self.adapter.delete_old_data(cutoff)
        
        assert deleted == 1
        assert len(self.adapter.metrics) == 1


class TestStorageFactory:
    """Test storage adapter factory."""
    
    def test_get_memory_adapter(self):
        """Test getting memory adapter."""
        adapter = StorageFactory.get_adapter(StorageBackend.MEMORY)
        
        assert isinstance(adapter, MemoryStorageAdapter)
        assert adapter.health_check() is True
    
    def test_adapter_caching(self):
        """Test that adapters are cached."""
        adapter1 = StorageFactory.get_adapter(StorageBackend.MEMORY)
        adapter2 = StorageFactory.get_adapter(StorageBackend.MEMORY)
        
        assert adapter1 is adapter2
    
    def test_reset_adapters(self):
        """Test resetting all adapters."""
        adapter1 = StorageFactory.get_adapter(StorageBackend.MEMORY)
        StorageFactory.reset()
        adapter2 = StorageFactory.get_adapter(StorageBackend.MEMORY)
        
        assert adapter1 is not adapter2


class TestDataCompactor:
    """Test data compaction and downsampling."""
    
    def test_downsample_metrics_empty(self):
        """Test downsampling empty list."""
        result = DataCompactor.downsample_metrics([])
        assert result == []
    
    def test_downsample_metrics_single(self):
        """Test downsampling single point."""
        points = [
            MetricPoint(datetime.utcnow(), 100, "metric1")
        ]
        
        result = DataCompactor.downsample_metrics(points, interval_minutes=5)
        
        assert len(result) == 1
        assert result[0].value == 100
    
    def test_downsample_metrics_multiple(self):
        """Test downsampling multiple points in same bucket."""
        base_time = datetime.utcnow()
        points = [
            MetricPoint(base_time, 100, "metric1"),
            MetricPoint(base_time + timedelta(seconds=30), 120, "metric1"),
            MetricPoint(base_time + timedelta(seconds=60), 140, "metric1"),
        ]
        
        result = DataCompactor.downsample_metrics(points, interval_minutes=5)
        
        # All three points fall in same 5-minute bucket
        assert len(result) == 1
        # Average should be (100 + 120 + 140) / 3 = 120
        assert abs(result[0].value - 120) < 1
    
    def test_downsample_metrics_different_buckets(self):
        """Test downsampling points in different buckets."""
        base_time = datetime.utcnow()
        points = [
            MetricPoint(base_time, 100, "metric1"),
            MetricPoint(base_time + timedelta(minutes=6), 200, "metric1"),
        ]
        
        result = DataCompactor.downsample_metrics(points, interval_minutes=5)
        
        # Points should fall in different 5-minute buckets
        assert len(result) == 2
    
    def test_downsample_preserves_metadata(self):
        """Test that downsampling preserves metric metadata."""
        point = MetricPoint(
            timestamp=datetime.utcnow(),
            value=100,
            metric_name="cpu_usage",
            labels={"host": "server1"},
            tags={"environment": "prod"}
        )
        
        result = DataCompactor.downsample_metrics([point])
        
        assert result[0].metric_name == "cpu_usage"
        assert result[0].labels == {"host": "server1"}
        assert result[0].tags == {"environment": "prod"}


class TestTimescaleDBAdapter:
    """Test TimescaleDB adapter (integration tests)."""
    
    def test_parse_duration(self):
        """Test duration string parsing."""
        from apps.shared.observability_storage import TimescaleDBAdapter
        
        assert TimescaleDBAdapter._parse_duration("5m") == timedelta(minutes=5)
        assert TimescaleDBAdapter._parse_duration("1h") == timedelta(hours=1)
        assert TimescaleDBAdapter._parse_duration("24h") == timedelta(hours=24)
        assert TimescaleDBAdapter._parse_duration("7d") == timedelta(days=7)
        assert TimescaleDBAdapter._parse_duration("30s") == timedelta(seconds=30)
    
    def test_parse_duration_invalid(self):
        """Test parsing invalid duration."""
        from apps.shared.observability_storage import TimescaleDBAdapter
        
        # Should return default 1h
        result = TimescaleDBAdapter._parse_duration("invalid")
        assert result == timedelta(hours=1)


class TestStorageIntegration:
    """Integration tests for storage system."""
    
    def setup_method(self):
        """Setup for each test."""
        self.adapter = MemoryStorageAdapter()
        self.adapter.connect({})
    
    def test_write_and_query_cycle(self):
        """Test complete write and query cycle."""
        # Write metrics
        for i in range(10):
            point = MetricPoint(
                timestamp=datetime.utcnow(),
                value=i * 10,
                metric_name="response_time",
                labels={"service": "api"}
            )
            self.adapter.write_metric(point)
        
        # Query metrics
        query = StorageQuery(metric_name="response_time", limit=100)
        results = self.adapter.query_metrics(query)
        
        assert len(results) == 10
        assert results[0].metric_name == "response_time"
    
    def test_trace_storage_workflow(self):
        """Test trace storage workflow."""
        # Write related traces
        trace1 = TracePoint(
            trace_id="trace1",
            span_id="span1",
            span_name="request",
            timestamp=datetime.utcnow(),
            duration_ms=100,
            service_name="api"
        )
        
        trace2 = TracePoint(
            trace_id="trace1",
            span_id="span2",
            span_name="database",
            timestamp=datetime.utcnow(),
            duration_ms=50,
            service_name="db",
            parent_span_id="span1"
        )
        
        self.adapter.write_trace(trace1)
        self.adapter.write_trace(trace2)
        
        # Query and verify
        query = StorageQuery(limit=100)
        results = self.adapter.query_traces(query)
        
        assert len(results) == 2
        # Find parent-child relationship
        parent = next(t for t in results if t.parent_span_id is None)
        child = next(t for t in results if t.parent_span_id is not None)
        
        assert child.parent_span_id == parent.span_id
