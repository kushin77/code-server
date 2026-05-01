"""Tests for trace insights service."""

import importlib.util
import sys
import types
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

apps_pkg = types.ModuleType("apps")
apps_pkg.__path__ = [str(ROOT.parent)]
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
shared_pkg.__path__ = [str(ROOT)]
sys.modules["apps.shared"] = shared_pkg


def _load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / file_name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


TRACE_ANALYSIS = _load_module("apps.shared.trace_analysis", "trace_analysis.py")
shared_pkg.trace_analysis = TRACE_ANALYSIS
TRACE_INSIGHTS = _load_module("apps.shared.trace_insights", "trace_insights.py")

LatencyStats = TRACE_ANALYSIS.LatencyStats
HealthScore = TRACE_INSIGHTS.HealthScore
SLOMetrics = TRACE_INSIGHTS.SLOMetrics
PerformanceRecommendation = TRACE_INSIGHTS.PerformanceRecommendation
ServiceDependency = TRACE_INSIGHTS.ServiceDependency
ServiceHealthScore = TRACE_INSIGHTS.ServiceHealthScore
TraceInsightsEngine = TRACE_INSIGHTS.TraceInsightsEngine
DependencyAnalyzer = TRACE_INSIGHTS.DependencyAnalyzer


class TestSLOMetrics:
    """Test SLO metrics."""

    def test_slo_creation(self):
        """Test SLO metrics can be created."""
        slo = SLOMetrics(
            service_name="api-service",
            latency_p99_ms=150.0,
            latency_p95_ms=100.0,
            error_rate_percent=0.05,
            availability_percent=99.95,
            error_budget_remaining_percent=95.0,
        )

        assert slo.service_name == "api-service"
        assert slo.latency_p99_ms == 150.0

    def test_slo_to_dict(self):
        """Test converting SLO to dict."""
        slo = SLOMetrics(
            service_name="api-service",
            latency_p99_ms=150.0,
            latency_p95_ms=100.0,
            error_rate_percent=0.05,
            availability_percent=99.95,
            error_budget_remaining_percent=95.0,
        )

        slo_dict = slo.to_dict()

        assert slo_dict["service"] == "api-service"
        assert slo_dict["latency_p99_ms"] == 150.0


class TestPerformanceRecommendation:
    """Test performance recommendations."""

    def test_recommendation_creation(self):
        """Test recommendation can be created."""
        rec = PerformanceRecommendation(
            priority="high",
            category="latency",
            operation_name="db_query",
            current_metric=500.0,
            recommended_target=100.0,
            metric_name="p99_latency_ms",
            rationale="Exceeds SLO",
            estimated_improvement_percent=80.0,
        )

        assert rec.priority == "high"
        assert rec.operation_name == "db_query"

    def test_recommendation_to_dict(self):
        """Test converting recommendation to dict."""
        rec = PerformanceRecommendation(
            priority="medium",
            category="throughput",
            operation_name="cache_lookup",
            current_metric=500.0,
            recommended_target=100.0,
            metric_name="p99_latency_ms",
            rationale="Cache miss rate high",
            estimated_improvement_percent=50.0,
        )

        rec_dict = rec.to_dict()

        assert rec_dict["priority"] == "medium"
        assert rec_dict["category"] == "throughput"


class TestServiceDependency:
    """Test service dependency."""

    def test_dependency_creation(self):
        """Test dependency can be created."""
        dep = ServiceDependency(
            source_service="api-service",
            target_service="db-service",
            call_count=1000,
            avg_latency_ms=50.0,
            error_rate_percent=0.1,
            criticality="high",
        )

        assert dep.source_service == "api-service"
        assert dep.target_service == "db-service"

    def test_dependency_to_dict(self):
        """Test converting dependency to dict."""
        dep = ServiceDependency(
            source_service="api-service",
            target_service="cache-service",
            call_count=5000,
            avg_latency_ms=10.0,
            error_rate_percent=0.01,
            criticality="medium",
        )

        dep_dict = dep.to_dict()

        assert dep_dict["source"] == "api-service"
        assert dep_dict["calls"] == 5000


class TestServiceHealthScore:
    """Test service health score."""

    def test_health_score_creation(self):
        """Test health score can be created."""
        score = ServiceHealthScore(
            service_name="api-service",
            overall_score=95.5,
            health_status=HealthScore.EXCELLENT,
            latency_score=95.0,
            reliability_score=96.0,
            throughput_score=94.0,
            timestamp=datetime.now(),
        )

        assert score.service_name == "api-service"
        assert score.health_status == HealthScore.EXCELLENT

    def test_health_score_to_dict(self):
        """Test converting health score to dict."""
        score = ServiceHealthScore(
            service_name="api-service",
            overall_score=87.5,
            health_status=HealthScore.GOOD,
            latency_score=85.0,
            reliability_score=90.0,
            throughput_score=85.0,
            timestamp=datetime.now(),
        )

        score_dict = score.to_dict()

        assert score_dict["service"] == "api-service"
        assert score_dict["status"] == "good"


class TestTraceInsightsEngine:
    """Test trace insights engine."""

    def test_engine_creation(self):
        """Test engine can be created."""
        engine = TraceInsightsEngine()

        assert engine.latency_p99_slo == 200.0
        assert engine.error_rate_slo == 0.1

    def test_custom_slo(self):
        """Test creating engine with custom SLO."""
        engine = TraceInsightsEngine(
            latency_p99_slo_ms=100.0,
            error_rate_slo_percent=0.05,
        )

        assert engine.latency_p99_slo == 100.0
        assert engine.error_rate_slo == 0.05

    def test_calculate_slo_metrics(self):
        """Test calculating SLO metrics."""
        engine = TraceInsightsEngine()

        stats = LatencyStats(operation_name="test_op")
        stats.finalize([100.0, 150.0, 200.0, 250.0, 300.0])

        metrics = engine.calculate_slo_metrics(
            service_name="test_service",
            stats=stats,
            error_count=0,
            total_count=100,
        )

        assert metrics.service_name == "test_service"
        assert metrics.error_rate_percent == 0.0
        assert metrics.availability_percent == 100.0

    def test_calculate_slo_with_errors(self):
        """Test calculating SLO with errors."""
        engine = TraceInsightsEngine(error_rate_slo_percent=1.0)

        stats = LatencyStats(operation_name="test_op")
        stats.finalize([100.0, 150.0, 200.0])

        metrics = engine.calculate_slo_metrics(
            service_name="test_service",
            stats=stats,
            error_count=2,
            total_count=100,
        )

        assert metrics.error_rate_percent == 2.0
        assert metrics.availability_percent == 98.0
        assert metrics.error_budget_remaining_percent < 100.0

    def test_generate_recommendations(self):
        """Test generating recommendations."""
        engine = TraceInsightsEngine(latency_p99_slo_ms=100.0)

        # Create slow operation stats
        stats = {
            "slow_op": LatencyStats(operation_name="slow_op"),
            "fast_op": LatencyStats(operation_name="fast_op"),
        }

        stats["slow_op"].finalize([400.0, 450.0, 500.0, 550.0, 600.0])
        stats["fast_op"].finalize([50.0, 60.0, 70.0, 80.0, 90.0])

        recommendations = engine.generate_recommendations(stats, [])

        # Should have recommendation for slow_op
        assert len(recommendations) > 0
        assert any(r.operation_name == "slow_op" for r in recommendations)

    def test_generate_recommendations_priority(self):
        """Test recommendations are prioritized."""
        engine = TraceInsightsEngine(latency_p99_slo_ms=100.0)

        stats = {
            "slightly_slow": LatencyStats(operation_name="slightly_slow"),
            "very_slow": LatencyStats(operation_name="very_slow"),
        }

        stats["slightly_slow"].finalize([150.0, 160.0, 170.0])
        stats["very_slow"].finalize([300.0, 350.0, 400.0])

        recommendations = engine.generate_recommendations(stats, [])

        if len(recommendations) > 1:
            # Very slow should be higher priority
            very_slow_idx = next(
                (i for i, r in enumerate(recommendations) if r.operation_name == "very_slow"),
                -1,
            )
            slightly_slow_idx = next(
                (i for i, r in enumerate(recommendations) if r.operation_name == "slightly_slow"),
                -1,
            )

            if very_slow_idx >= 0 and slightly_slow_idx >= 0:
                assert very_slow_idx < slightly_slow_idx

    def test_calculate_health_score(self):
        """Test calculating health score."""
        engine = TraceInsightsEngine()

        stats = LatencyStats(operation_name="test_op")
        stats.finalize([100.0, 150.0, 200.0])

        score = engine.calculate_health_score(
            service_name="test_service",
            stats=stats,
            error_count=0,
            total_count=100,
        )

        assert score.service_name == "test_service"
        assert score.overall_score >= 0
        assert score.overall_score <= 100
        assert score.latency_score >= 0
        assert score.reliability_score >= 0

    def test_health_status_excellent(self):
        """Test excellent health status."""
        engine = TraceInsightsEngine()

        stats = LatencyStats(operation_name="test_op")
        stats.finalize([50.0, 60.0, 70.0, 80.0, 90.0])

        score = engine.calculate_health_score(
            service_name="test_service",
            stats=stats,
            error_count=0,
            total_count=1000,
        )

        assert score.health_status == HealthScore.EXCELLENT

    def test_health_status_poor(self):
        """Test poor health status."""
        engine = TraceInsightsEngine(latency_p99_slo_ms=100.0)

        stats = LatencyStats(operation_name="test_op")
        stats.finalize([500.0, 600.0, 700.0, 800.0, 900.0])

        score = engine.calculate_health_score(
            service_name="test_service",
            stats=stats,
            error_count=50,
            total_count=100,
        )

        assert score.health_status == HealthScore.POOR


class TestDependencyAnalyzer:
    """Test dependency analyzer."""

    def test_analyzer_creation(self):
        """Test analyzer can be created."""
        analyzer = DependencyAnalyzer()

        assert len(analyzer.dependencies) == 0

    def test_record_call(self):
        """Test recording a call."""
        analyzer = DependencyAnalyzer()

        analyzer.record_call("api", "db", 50.0, True)

        dep = analyzer.get_dependency("api", "db")

        assert dep is not None
        assert dep.call_count == 1
        assert dep.avg_latency_ms == 50.0

    def test_record_multiple_calls(self):
        """Test recording multiple calls."""
        analyzer = DependencyAnalyzer()

        analyzer.record_call("api", "db", 50.0, True)
        analyzer.record_call("api", "db", 100.0, True)
        analyzer.record_call("api", "db", 150.0, True)

        dep = analyzer.get_dependency("api", "db")

        assert dep.call_count == 3
        assert dep.avg_latency_ms == 100.0

    def test_record_failed_calls(self):
        """Test recording failed calls."""
        analyzer = DependencyAnalyzer()

        analyzer.record_call("api", "cache", 10.0, True)
        analyzer.record_call("api", "cache", 20.0, False)

        dep = analyzer.get_dependency("api", "cache")

        assert dep.call_count == 2
        assert dep.error_rate_percent > 0

    def test_criticality_high_error_rate(self):
        """Test criticality with high error rate."""
        analyzer = DependencyAnalyzer()

        # Record mostly failures
        for _ in range(10):
            analyzer.record_call("api", "service", 100.0, False)

        dep = analyzer.get_dependency("api", "service")

        assert dep.criticality == "critical"

    def test_criticality_high_latency(self):
        """Test criticality with high latency."""
        analyzer = DependencyAnalyzer()

        # Record high latency calls
        for _ in range(10):
            analyzer.record_call("api", "slow_service", 600.0, True)

        dep = analyzer.get_dependency("api", "slow_service")

        assert dep.criticality in ("critical", "high")

    def test_get_critical_dependencies(self):
        """Test getting critical dependencies."""
        analyzer = DependencyAnalyzer()

        # Record various dependencies
        analyzer.record_call("api", "db", 50.0, True)
        analyzer.record_call("api", "slow_service", 600.0, True)
        for _ in range(5):
            analyzer.record_call("api", "failing_service", 100.0, False)

        critical = analyzer.get_critical_dependencies()

        assert len(critical) > 0
        # Failing service should be in critical list
        assert any(d.target_service == "failing_service" for d in critical)

    def test_get_dependencies_for_service(self):
        """Test getting dependencies for a service."""
        analyzer = DependencyAnalyzer()

        analyzer.record_call("api", "db", 50.0, True)
        analyzer.record_call("api", "cache", 10.0, True)
        analyzer.record_call("worker", "db", 60.0, True)

        api_deps = analyzer.get_dependencies_for_service("api")

        assert len(api_deps) == 2
        assert all(d.source_service == "api" for d in api_deps)

    def test_get_dependents(self):
        """Test getting dependents (incoming calls)."""
        analyzer = DependencyAnalyzer()

        analyzer.record_call("api", "db", 50.0, True)
        analyzer.record_call("worker", "db", 60.0, True)
        analyzer.record_call("cache", "db", 30.0, True)

        db_dependents = analyzer.get_dependents("db")

        assert len(db_dependents) == 3
        assert all(d.target_service == "db" for d in db_dependents)


class TestInsightsIntegration:
    """Integration tests for insights."""

    def test_end_to_end_insights(self):
        """Test end-to-end insights generation."""
        engine = TraceInsightsEngine()
        analyzer = DependencyAnalyzer()

        # Create stats
        stats = LatencyStats(operation_name="api_call")
        stats.finalize([100.0, 120.0, 150.0, 180.0, 200.0])

        # Calculate SLO
        slo = engine.calculate_slo_metrics(
            "api-service",
            stats,
            error_count=1,
            total_count=1000,
        )

        # Calculate health
        health = engine.calculate_health_score(
            "api-service",
            stats,
            error_count=1,
            total_count=1000,
        )

        # Record dependencies
        analyzer.record_call("api", "db", 50.0, True)
        analyzer.record_call("api", "cache", 10.0, True)

        # Verify
        assert slo.latency_p99_ms > 0
        assert health.overall_score > 0
        assert len(analyzer.dependencies) == 2
