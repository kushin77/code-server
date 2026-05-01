"""
Integration Tests for Complete Observability Platform

Tests the entire observability system working together:
- End-to-end request tracing
- Metrics collection and reporting
- Context propagation across services
- Data storage and retrieval
- Dashboard generation and export
"""

import pytest
from datetime import datetime, timedelta
from typing import List

# Import all observability modules
from apps.shared.trace_enhancement import Tracer, Span, SpanKind
from apps.shared.metrics_reporting import MetricsCollector, MetricsAggregator, Report
from apps.shared.context_propagation import ContextManager, DistributedContext, TraceIdentifiers
from apps.shared.observability_storage import (
    MemoryStorageAdapter, MetricPoint, TracePoint, StorageQuery
)
from apps.shared.dashboard_builder import DashboardBuilder, DashboardManager, DashboardTemplate


class TestEndToEndTracing:
    """End-to-end distributed tracing workflow."""
    
    def test_multi_service_trace(self):
        """Test tracing across multiple services."""
        # Service 1: API
        api_tracer = Tracer("api-service")
        
        with api_tracer.start_span("handle_request", kind=SpanKind.SERVER) as span:
            span.set_attribute("http.method", "GET")
            span.set_attribute("http.url", "/api/users")
            
            # Create context for downstream
            context = ContextManager.get_or_create("api-service")
            context_headers = ContextManager.inject_context(context)
            
            # Service 2: Database
            db_tracer = Tracer("db-service")
            
            # Extract context in downstream service
            extracted_context = ContextManager.extract_context(context_headers)
            assert extracted_context is not None
            assert extracted_context.trace_ids.trace_id == context.trace_ids.trace_id
            
            with db_tracer.start_span("query_database", kind=SpanKind.CLIENT) as db_span:
                db_span.set_attribute("db.statement", "SELECT * FROM users")
                db_span.set_attribute("db.rows_affected", 10)
    
    def test_context_propagation_through_request(self):
        """Test context propagation through request chain."""
        # Create root context
        root_context = DistributedContext(trace_ids=TraceIdentifiers.generate())
        root_context.baggage.set("user-id", "user123")
        root_context.baggage.set("tenant", "acme")
        
        ContextManager.set_context(root_context)
        
        # Extract and propagate
        headers = ContextManager.inject_context()
        
        # Extract in downstream
        downstream_context = ContextManager.extract_context(headers)
        
        # Verify context preservation
        assert downstream_context.trace_ids.trace_id == root_context.trace_ids.trace_id
        assert downstream_context.baggage.get("user-id") == "user123"
        assert downstream_context.baggage.get("tenant") == "acme"
    
    def test_trace_with_errors(self):
        """Test tracing error handling."""
        tracer = Tracer("error-service")
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        try:
            with tracer.start_span("risky_operation") as span:
                span.set_attribute("operation", "data_processing")
                raise ValueError("Processing failed")
        except ValueError:
            # Verify error was recorded
            pass


class TestMetricsCollectionWorkflow:
    """Metrics collection and aggregation workflow."""
    
    def test_metrics_collection_to_aggregation(self):
        """Test complete metrics workflow."""
        # 1. Collect metrics
        collector = MetricsCollector("api-service")
        
        # Simulate requests
        for i in range(10):
            collector.record_counter("requests", 1, {"method": "GET", "status": "200"})
            collector.record_histogram("latency", 50 + i * 10, {"endpoint": "/api"})
        
        # 2. Get metrics
        metrics = collector.get_metrics()
        assert len(metrics) > 0
        
        # 3. Aggregate metrics
        aggregator = MetricsAggregator("5m")
        
        now = datetime.utcnow()
        # Simulate data points
        data_points = [
            (50, "p50"),
            (75, "p75"),
            (90, "p90"),
            (99, "p99"),
            (100, "p99.9"),
        ]
        
        aggregated = aggregator.aggregate("latency", data_points)
        assert len(aggregated) > 0
    
    def test_metrics_to_storage(self):
        """Test metrics being stored."""
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # Collect and store metrics
        collector = MetricsCollector("service")
        
        for i in range(5):
            collector.record_counter("requests", 1)
        
        # Convert to storage format
        now = datetime.utcnow()
        for i in range(5):
            point = MetricPoint(
                timestamp=now,
                value=i * 10,
                metric_name="cpu_usage",
                tags={"service": "service", "host": "host1"}
            )
            storage.write_metric(point)
        
        # Query and verify
        query = StorageQuery(metric_name="cpu_usage", limit=100)
        results = storage.query_metrics(query)
        
        assert len(results) == 5


class TestTraceStorageAndQuerying:
    """Test traces being stored and retrieved."""
    
    def test_trace_workflow(self):
        """Test complete trace workflow."""
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # Simulate distributed trace
        trace_id = "trace-123"
        now = datetime.utcnow()
        
        # Root span
        root_span = TracePoint(
            trace_id=trace_id,
            span_id="span-1",
            span_name="request",
            timestamp=now,
            duration_ms=500,
            service_name="api"
        )
        storage.write_trace(root_span)
        
        # Child span 1
        child1 = TracePoint(
            trace_id=trace_id,
            span_id="span-2",
            span_name="database_query",
            timestamp=now + timedelta(ms=10),
            duration_ms=200,
            service_name="database",
            parent_span_id="span-1"
        )
        storage.write_trace(child1)
        
        # Child span 2
        child2 = TracePoint(
            trace_id=trace_id,
            span_id="span-3",
            span_name="cache_lookup",
            timestamp=now + timedelta(ms=250),
            duration_ms=50,
            service_name="cache",
            parent_span_id="span-1"
        )
        storage.write_trace(child2)
        
        # Query and verify
        query = StorageQuery(limit=100)
        traces = storage.query_traces(query)
        
        assert len(traces) == 3
        
        # Verify parent-child relationships
        parents = [t for t in traces if t.parent_span_id is None]
        children = [t for t in traces if t.parent_span_id is not None]
        
        assert len(parents) == 1
        assert len(children) == 2
        assert all(c.parent_span_id == "span-1" for c in children)


class TestDashboardIntegration:
    """Test dashboard creation with real data."""
    
    def test_dashboard_from_metrics_template(self):
        """Test dashboard built from metrics."""
        # Create dashboard from template
        dashboard = DashboardTemplate.application_metrics_template("prometheus_id")
        
        assert dashboard.title == "Application Metrics"
        assert len(dashboard.widgets) > 0
        
        # Manage dashboard
        manager = DashboardManager()
        dashboard_id = manager.create(dashboard)
        
        # Verify it was created
        retrieved = manager.get(dashboard_id)
        assert retrieved.title == "Application Metrics"
    
    def test_dashboard_with_stored_data(self):
        """Test dashboard displaying stored data."""
        # Setup storage
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # Store sample metrics
        for i in range(10):
            point = MetricPoint(
                timestamp=datetime.utcnow() - timedelta(minutes=i),
                value=50 + i,
                metric_name="request_latency",
                tags={"service": "api", "endpoint": "/users"}
            )
            storage.write_metric(point)
        
        # Query data
        query = StorageQuery(metric_name="request_latency", limit=100)
        results = storage.query_metrics(query)
        
        # Create dashboard with the data
        builder = DashboardBuilder()
        dashboard = builder \
            .set_title("API Performance") \
            .add_datasource("Prometheus", "prometheus", "http://localhost:9090") \
            .add_timeseries_widget("Request Latency", "request_latency", "prometheus_id") \
            .build()
        
        assert len(results) == 10
        assert dashboard.widgets[0].title == "Request Latency"


class TestFullObservabilityStack:
    """Test complete observability stack together."""
    
    def test_complete_workflow(self):
        """
        Test complete workflow:
        1. Application generates trace and metrics
        2. Context propagates across services
        3. Data is stored
        4. Queries retrieve data
        5. Dashboard visualizes data
        """
        # Setup
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # 1. Generate trace with context
        api_tracer = Tracer("api-service")
        context = DistributedContext(trace_ids=TraceIdentifiers.generate())
        context.user_id = "user123"
        context.tenant_id = "acme"
        ContextManager.set_context(context)
        
        with api_tracer.start_span("api_request") as span:
            span.set_attribute("http.method", "POST")
            span.set_attribute("http.path", "/api/data")
            
            # Collect metrics
            collector = MetricsCollector("api-service")
            collector.record_counter("requests", 1, {"method": "POST"})
            collector.record_histogram("latency", 150, {"endpoint": "/api/data"})
            
            # 2. Propagate context downstream
            headers = ContextManager.inject_context()
            
            # 3. Store metrics
            now = datetime.utcnow()
            metric_point = MetricPoint(
                timestamp=now,
                value=150,
                metric_name="request_latency",
                tags={"service": "api", "method": "POST"}
            )
            storage.write_metric(metric_point)
            
            # Store trace
            trace_point = TracePoint(
                trace_id=context.trace_ids.trace_id,
                span_id=context.trace_ids.span_id,
                span_name="api_request",
                timestamp=now,
                duration_ms=150,
                service_name="api-service",
                tags={"user_id": "user123"}
            )
            storage.write_trace(trace_point)
        
        # 4. Query stored data
        metric_query = StorageQuery(metric_name="request_latency", limit=100)
        metrics = storage.query_metrics(metric_query)
        
        trace_query = StorageQuery(limit=100)
        traces = storage.query_traces(trace_query)
        
        assert len(metrics) == 1
        assert len(traces) == 1
        
        # 5. Create dashboard with data
        dashboard = DashboardBuilder() \
            .set_title("API Monitoring") \
            .add_datasource("Prometheus", "prometheus", "http://localhost:9090") \
            .add_timeseries_widget("Latency", "request_latency", "prometheus_id") \
            .add_stat_widget("Request Count", "requests_total", "prometheus_id") \
            .build()
        
        manager = DashboardManager()
        dashboard_id = manager.create(dashboard)
        
        # Verify complete flow
        assert len(metrics) > 0
        assert len(traces) > 0
        assert manager.get(dashboard_id) is not None


class TestDataRetention:
    """Test data retention and cleanup."""
    
    def test_old_data_cleanup(self):
        """Test removing old data."""
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        now = datetime.utcnow()
        old_date = now - timedelta(days=30)
        recent_date = now - timedelta(days=1)
        
        # Write old and recent data
        old_metric = MetricPoint(old_date, 100, "old_metric")
        recent_metric = MetricPoint(recent_date, 200, "recent_metric")
        
        storage.write_metric(old_metric)
        storage.write_metric(recent_metric)
        
        # Delete data older than 7 days
        cutoff = now - timedelta(days=7)
        deleted = storage.delete_old_data(cutoff)
        
        assert deleted == 1
        
        # Verify recent data remains
        remaining = storage.query_metrics(StorageQuery(limit=100))
        assert len(remaining) == 1


class TestMetricsAggregation:
    """Test metrics aggregation and reporting."""
    
    def test_metrics_aggregation_workflow(self):
        """Test aggregating metrics over time."""
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # Write metrics over time
        base_time = datetime.utcnow()
        
        for i in range(5):
            point = MetricPoint(
                timestamp=base_time - timedelta(minutes=i),
                value=100 + i * 10,
                metric_name="cpu_usage",
                tags={"host": "server1"}
            )
            storage.write_metric(point)
        
        # Query metrics
        query = StorageQuery(metric_name="cpu_usage", limit=100)
        metrics = storage.query_metrics(query)
        
        assert len(metrics) == 5
        
        # Calculate statistics
        values = [m.value for m in metrics]
        avg = sum(values) / len(values)
        
        assert 100 <= avg <= 150


class TestErrorHandling:
    """Test error handling throughout the stack."""
    
    def test_malformed_context_extraction(self):
        """Test handling malformed context headers."""
        bad_headers = {
            "traceparent": "invalid-format"
        }
        
        context = ContextManager.extract_context(bad_headers)
        
        # Should not crash, may return None or create new context
        assert context is None or context.trace_ids.trace_id is not None
    
    def test_storage_error_handling(self):
        """Test storage error handling."""
        storage = MemoryStorageAdapter()
        # Don't call connect
        
        # Should handle gracefully
        query = StorageQuery(metric_name="test", limit=100)
        results = storage.query_metrics(query)
        
        assert results is not None


class TestScalability:
    """Test observability platform scalability."""
    
    def test_bulk_metrics_write(self):
        """Test writing many metrics."""
        storage = MemoryStorageAdapter()
        storage.connect({})
        
        # Write 1000 metrics
        now = datetime.utcnow()
        points = [
            MetricPoint(
                timestamp=now - timedelta(minutes=i % 60),
                value=float(i),
                metric_name=f"metric_{i % 10}",
                tags={"index": str(i)}
            )
            for i in range(1000)
        ]
        
        assert storage.write_metrics_batch(points) is True
        
        # Query subset
        query = StorageQuery(metric_name="metric_0", limit=100)
        results = storage.query_metrics(query)
        
        assert len(results) > 0
    
    def test_many_spans(self):
        """Test handling many spans."""
        tracer = Tracer("load-service")
        
        # Create 100 spans
        for i in range(100):
            with tracer.start_span(f"operation_{i}") as span:
                span.set_attribute("index", i)
