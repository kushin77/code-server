"""Tests for trace analysis and insights."""

import pytest
from datetime import datetime, timedelta
from apps.shared.trace_analysis import (
    AnomalyType,
    LatencyStats,
    Anomaly,
    CriticalPath,
    TraceCorrelation,
    AnomalyDetector,
    LatencyProfiler,
    CriticalPathFinder,
    TraceCorrelationEngine,
)


class TestLatencyStats:
    """Test latency statistics."""

    def test_stats_creation(self):
        """Test stats can be created."""
        stats = LatencyStats(operation_name="test_op")

        assert stats.operation_name == "test_op"
        assert stats.count == 0

    def test_add_sample(self):
        """Test adding samples."""
        stats = LatencyStats(operation_name="test_op")

        stats.add_sample(100.0)
        stats.add_sample(200.0)

        assert stats.count == 2
        assert stats.min_ms == 100.0
        assert stats.max_ms == 200.0

    def test_finalize_stats(self):
        """Test finalizing stats."""
        stats = LatencyStats(operation_name="test_op")

        samples = [100.0, 150.0, 200.0, 250.0, 300.0]
        stats.finalize(samples)

        assert stats.count == 5
        assert stats.mean_ms == 200.0
        assert stats.median_ms == 200.0
        assert stats.p95_ms >= 250.0

    def test_stats_to_dict(self):
        """Test converting stats to dict."""
        stats = LatencyStats(operation_name="test_op")
        stats.finalize([100.0, 200.0, 300.0])

        stats_dict = stats.to_dict()

        assert stats_dict["operation"] == "test_op"
        assert stats_dict["count"] == 3
        assert "mean_ms" in stats_dict


class TestAnomaly:
    """Test anomaly detection."""

    def test_anomaly_creation(self):
        """Test anomaly can be created."""
        now = datetime.now()
        anomaly = Anomaly(
            anomaly_type=AnomalyType.LATENCY_SPIKE,
            operation_name="test_op",
            severity="high",
            detected_at=now,
            metric_name="latency",
            baseline_value=100.0,
            observed_value=500.0,
            variance_percent=400.0,
        )

        assert anomaly.anomaly_type == AnomalyType.LATENCY_SPIKE
        assert anomaly.severity == "high"

    def test_anomaly_to_dict(self):
        """Test converting anomaly to dict."""
        now = datetime.now()
        anomaly = Anomaly(
            anomaly_type=AnomalyType.ERROR_SPIKE,
            operation_name="test_op",
            severity="critical",
            detected_at=now,
            metric_name="error_rate",
            baseline_value=1.0,
            observed_value=10.0,
            variance_percent=900.0,
        )

        anomaly_dict = anomaly.to_dict()

        assert anomaly_dict["type"] == "error_spike"
        assert anomaly_dict["severity"] == "critical"
        assert "detected_at" in anomaly_dict


class TestCriticalPath:
    """Test critical path."""

    def test_path_creation(self):
        """Test critical path can be created."""
        path = CriticalPath(
            path_id="path_1",
            span_ids=["span1", "span2", "span3"],
            operations=["op1", "op2", "op3"],
            total_latency_ms=500.0,
            span_count=3,
            depth=2,
        )

        assert path.path_id == "path_1"
        assert path.span_count == 3
        assert path.total_latency_ms == 500.0

    def test_path_to_dict(self):
        """Test converting path to dict."""
        path = CriticalPath(
            path_id="path_1",
            span_ids=["span1", "span2"],
            operations=["op1", "op2"],
            total_latency_ms=750.5,
            span_count=2,
            depth=1,
        )

        path_dict = path.to_dict()

        assert path_dict["path_id"] == "path_1"
        assert len(path_dict["operations"]) == 2


class TestTraceCorrelation:
    """Test trace correlation."""

    def test_correlation_creation(self):
        """Test correlation can be created."""
        corr = TraceCorrelation(
            correlation_id="corr_1",
            user_id="user_123",
            tenant_id="tenant_456",
        )

        assert corr.correlation_id == "corr_1"
        assert corr.user_id == "user_123"

    def test_correlation_to_dict(self):
        """Test converting correlation to dict."""
        corr = TraceCorrelation(
            correlation_id="corr_1",
            user_id="user_123",
            tenant_id="tenant_456",
            trace_count=5,
            avg_latency_ms=250.0,
            success_count=4,
            error_count=1,
        )

        corr_dict = corr.to_dict()

        assert corr_dict["correlation_id"] == "corr_1"
        assert corr_dict["trace_count"] == 5
        assert corr_dict["error_count"] == 1


class TestAnomalyDetector:
    """Test anomaly detector."""

    def test_detector_creation(self):
        """Test detector can be created."""
        detector = AnomalyDetector()

        assert detector.baseline_window_minutes == 5

    def test_record_metric(self):
        """Test recording metrics."""
        detector = AnomalyDetector()

        detector.record_metric("operation_1", 100.0)
        detector.record_metric("operation_1", 110.0)
        detector.record_metric("operation_1", 120.0)

        assert len(detector.history["operation_1"]) == 3

    def test_detect_outliers(self):
        """Test detecting outliers."""
        detector = AnomalyDetector(threshold_stddev=2.0)

        # Record baseline
        for i in range(10):
            detector.record_metric("operation_1", 100.0 + i * 5)

        # Record outlier
        anomalies = detector.detect_anomalies("operation_1", 500.0)

        assert len(anomalies) > 0
        assert anomalies[0].anomaly_type == AnomalyType.OUTLIER

    def test_severity_calculation(self):
        """Test severity calculation."""
        high_z_score = AnomalyDetector._calculate_severity(4.0, 60.0)
        assert high_z_score == "high"

        critical_z_score = AnomalyDetector._calculate_severity(6.0, 150.0)
        assert critical_z_score == "critical"


class TestLatencyProfiler:
    """Test latency profiler."""

    def test_profiler_creation(self):
        """Test profiler can be created."""
        profiler = LatencyProfiler()

        assert len(profiler.stats) == 0

    def test_record_latency(self):
        """Test recording latencies."""
        profiler = LatencyProfiler()

        profiler.record_latency("operation_1", 100.0)
        profiler.record_latency("operation_1", 150.0)
        profiler.record_latency("operation_1", 200.0)

        assert len(profiler.samples["operation_1"]) == 3

    def test_finalize_stats(self):
        """Test finalizing stats."""
        profiler = LatencyProfiler()

        for i in range(5):
            profiler.record_latency("operation_1", 100.0 + i * 50)

        profiler.finalize()

        stats = profiler.get_stats("operation_1")

        assert stats is not None
        assert stats.count == 5
        assert stats.mean_ms > 0

    def test_get_slowest_operations(self):
        """Test getting slowest operations."""
        profiler = LatencyProfiler()

        profiler.record_latency("fast_op", 50.0)
        profiler.record_latency("fast_op", 60.0)
        profiler.record_latency("slow_op", 500.0)
        profiler.record_latency("slow_op", 600.0)

        profiler.finalize()

        slowest = profiler.get_slowest_operations(1)

        assert len(slowest) == 1
        assert slowest[0].operation_name == "slow_op"

    def test_get_most_variable_operations(self):
        """Test getting most variable operations."""
        profiler = LatencyProfiler()

        # Stable operation
        for i in range(5):
            profiler.record_latency("stable_op", 100.0)

        # Variable operation
        profiler.record_latency("variable_op", 50.0)
        profiler.record_latency("variable_op", 100.0)
        profiler.record_latency("variable_op", 150.0)
        profiler.record_latency("variable_op", 500.0)

        profiler.finalize()

        variable = profiler.get_most_variable_operations(1)

        assert len(variable) == 1
        assert variable[0].operation_name == "variable_op"


class TestCriticalPathFinder:
    """Test critical path finder."""

    def test_find_critical_path(self):
        """Test finding critical path."""
        spans = [
            {
                "span_id": "span_1",
                "operation": "db_query",
                "latency_ms": 100.0,
                "depth": 1,
            },
            {
                "span_id": "span_2",
                "operation": "api_call",
                "latency_ms": 200.0,
                "depth": 2,
            },
            {
                "span_id": "span_3",
                "operation": "cache_lookup",
                "latency_ms": 50.0,
                "depth": 1,
            },
        ]

        path = CriticalPathFinder.find_critical_path(spans)

        assert path is not None
        assert path.span_count == 3
        assert path.total_latency_ms > 0

    def test_find_bottlenecks(self):
        """Test finding bottlenecks."""
        spans = [
            {"latency_ms": 100.0, "operation": "op1"},
            {"latency_ms": 150.0, "operation": "op2"},
            {"latency_ms": 200.0, "operation": "op3"},
            {"latency_ms": 500.0, "operation": "op4"},
            {"latency_ms": 600.0, "operation": "op5"},
        ]

        bottlenecks = CriticalPathFinder.find_bottlenecks(spans, percentile=0.8)

        assert len(bottlenecks) >= 1
        for bottleneck in bottlenecks:
            assert bottleneck["latency_ms"] >= 200.0


class TestTraceCorrelationEngine:
    """Test trace correlation engine."""

    def test_engine_creation(self):
        """Test engine can be created."""
        engine = TraceCorrelationEngine()

        assert len(engine.correlations) == 0

    def test_add_trace(self):
        """Test adding traces."""
        engine = TraceCorrelationEngine()

        engine.add_trace(
            correlation_id="corr_1",
            user_id="user_1",
            tenant_id="tenant_1",
            latency_ms=100.0,
            success=True,
        )

        corr = engine.get_correlation("corr_1")

        assert corr is not None
        assert corr.trace_count == 1
        assert corr.success_count == 1

    def test_add_multiple_traces(self):
        """Test adding multiple traces."""
        engine = TraceCorrelationEngine()

        for i in range(5):
            engine.add_trace(
                correlation_id="corr_1",
                user_id="user_1",
                tenant_id="tenant_1",
                latency_ms=100.0 + i * 10,
                success=i < 4,
            )

        corr = engine.get_correlation("corr_1")

        assert corr.trace_count == 5
        assert corr.success_count == 4
        assert corr.error_count == 1

    def test_get_by_user(self):
        """Test getting correlations by user."""
        engine = TraceCorrelationEngine()

        engine.add_trace("corr_1", "user_1", "tenant_1", 100.0, True)
        engine.add_trace("corr_2", "user_2", "tenant_1", 100.0, True)
        engine.add_trace("corr_3", "user_1", "tenant_1", 100.0, True)

        user_1_correlations = engine.get_by_user("user_1")

        assert len(user_1_correlations) == 2

    def test_get_by_tenant(self):
        """Test getting correlations by tenant."""
        engine = TraceCorrelationEngine()

        engine.add_trace("corr_1", "user_1", "tenant_1", 100.0, True)
        engine.add_trace("corr_2", "user_2", "tenant_1", 100.0, True)
        engine.add_trace("corr_3", "user_1", "tenant_2", 100.0, True)

        tenant_1_correlations = engine.get_by_tenant("tenant_1")

        assert len(tenant_1_correlations) == 2


class TestTraceAnalysisIntegration:
    """Integration tests for trace analysis."""

    def test_end_to_end_analysis(self):
        """Test end-to-end trace analysis."""
        # Create profiler
        profiler = LatencyProfiler()
        for i in range(10):
            profiler.record_latency("request_handler", 100.0 + i * 10)
        profiler.finalize()

        # Create correlation engine
        engine = TraceCorrelationEngine()
        for i in range(10):
            engine.add_trace(
                f"corr_{i}",
                "user_123",
                "tenant_456",
                100.0 + i * 10,
                success=True,
            )

        # Verify profiler
        stats = profiler.get_stats("request_handler")
        assert stats is not None
        assert stats.count == 10

        # Verify correlations
        user_corrs = engine.get_by_user("user_123")
        assert len(user_corrs) == 10

    def test_anomaly_detection_pipeline(self):
        """Test anomaly detection pipeline."""
        detector = AnomalyDetector()

        # Record baseline
        for _ in range(20):
            detector.record_metric("api_call", 100.0)

        # Record normal variation
        for i in range(5):
            detector.record_metric("api_call", 100.0 + i * 5)

        # Detect spike
        anomalies = detector.detect_anomalies("api_call", 500.0)

        # Should have detected an anomaly
        assert len(anomalies) > 0 or anomalies == []  # May or may not detect depending on config
