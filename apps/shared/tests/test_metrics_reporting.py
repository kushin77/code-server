"""Tests for metrics collection, aggregation and reporting."""

import pytest
from datetime import datetime, timedelta
from apps.shared.metrics_reporting import (
    MetricType,
    AggregationPeriod,
    Metric,
    TimeSeries,
    MetricsCollector,
    MetricsAggregator,
    ReportSection,
    Report,
    ReportGenerator,
    AlertingRule,
    AlertingEngine,
)


class TestMetric:
    """Test metric."""

    def test_metric_creation(self):
        """Test creating metric."""
        now = datetime.now()
        metric = Metric(
            name="latency",
            value=45.5,
            timestamp=now,
            unit="ms",
            metric_type=MetricType.GAUGE,
        )

        assert metric.name == "latency"
        assert metric.value == 45.5

    def test_metric_to_dict(self):
        """Test converting metric to dict."""
        now = datetime.now()
        metric = Metric(
            name="request_count",
            value=100.0,
            timestamp=now,
            labels={"service": "api"},
            metric_type=MetricType.COUNTER,
        )

        metric_dict = metric.to_dict()

        assert metric_dict["name"] == "request_count"
        assert metric_dict["labels"]["service"] == "api"


class TestTimeSeries:
    """Test time series."""

    def test_series_creation(self):
        """Test creating time series."""
        series = TimeSeries(metric_name="latency")

        assert len(series.values) == 0

    def test_add_value(self):
        """Test adding values."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        series.add_value(now, 100.0)
        series.add_value(now + timedelta(minutes=1), 150.0)

        assert len(series.values) == 2

    def test_get_latest(self):
        """Test getting latest value."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        series.add_value(now, 100.0)
        series.add_value(now + timedelta(minutes=1), 200.0)

        assert series.get_latest() == 200.0

    def test_get_average(self):
        """Test getting average."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        for i in range(5):
            series.add_value(now + timedelta(minutes=i), 100.0 + i * 10)

        avg = series.get_average()

        assert avg == 120.0

    def test_get_min_max(self):
        """Test getting min/max."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        values = [50.0, 100.0, 150.0, 75.0, 200.0]

        for i, val in enumerate(values):
            series.add_value(now + timedelta(minutes=i), val)

        assert series.get_min() == 50.0
        assert series.get_max() == 200.0

    def test_series_to_dict(self):
        """Test converting series to dict."""
        series = TimeSeries(metric_name="requests", labels={"service": "api"})

        now = datetime.now()
        series.add_value(now, 100.0)
        series.add_value(now + timedelta(minutes=1), 200.0)

        series_dict = series.to_dict()

        assert series_dict["metricName"] == "requests"
        assert len(series_dict["values"]) == 2


class TestMetricsCollector:
    """Test metrics collector."""

    def test_collector_creation(self):
        """Test creating collector."""
        collector = MetricsCollector()

        assert len(collector.metrics) == 0
        assert len(collector.series) == 0

    def test_collect_from_trace(self):
        """Test collecting from trace."""
        collector = MetricsCollector()

        trace = {
            "service_name": "api",
            "operation_name": "request",
            "duration_ms": 100.0,
            "status": "OK",
        }

        collector.collect_from_trace(trace)

        assert len(collector.metrics) >= 2  # latency + request count
        assert len(collector.series) >= 2

    def test_collect_error_metrics(self):
        """Test collecting error metrics."""
        collector = MetricsCollector()

        trace = {
            "service_name": "api",
            "operation_name": "query",
            "duration_ms": 500.0,
            "status": "ERROR",
        }

        collector.collect_from_trace(trace)

        # Should have latency, request count, and error count
        assert len(collector.metrics) >= 3

    def test_get_series(self):
        """Test getting time series."""
        collector = MetricsCollector()

        trace = {
            "service_name": "db",
            "operation_name": "select",
            "duration_ms": 50.0,
            "status": "OK",
        }

        collector.collect_from_trace(trace)

        series = collector.get_series("db.select.latency")

        assert series is not None
        assert len(series.values) > 0


class TestMetricsAggregator:
    """Test metrics aggregator."""

    def test_aggregate_by_minute(self):
        """Test aggregating by minute."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now().replace(second=0, microsecond=0)
        for i in range(6):
            series.add_value(now + timedelta(seconds=i * 10), 100.0 + i)

        aggregated = MetricsAggregator.aggregate_by_period(series, AggregationPeriod.MINUTE)

        assert len(aggregated) > 0

    def test_percentile_calculation(self):
        """Test percentile calculation."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        for i in range(10):
            series.add_value(now + timedelta(minutes=i), 100.0 + i * 10)

        percentiles = MetricsAggregator.percentile_by_period(
            series,
            AggregationPeriod.HOUR,
            0.95,
        )

        assert len(percentiles) > 0

    def test_invalid_percentile(self):
        """Test invalid percentile."""
        series = TimeSeries(metric_name="latency")

        now = datetime.now()
        series.add_value(now, 100.0)

        with pytest.raises(ValueError):
            MetricsAggregator.percentile_by_period(
                series,
                AggregationPeriod.HOUR,
                1.5,  # Invalid
            )


class TestReportSection:
    """Test report section."""

    def test_section_creation(self):
        """Test creating section."""
        section = ReportSection(
            title="Performance",
            content="Performance metrics",
        )

        assert section.title == "Performance"

    def test_section_to_dict(self):
        """Test converting section to dict."""
        section = ReportSection(
            title="Reliability",
            content="Error rates",
            metrics={"error_rate": 0.01},
        )

        section_dict = section.to_dict()

        assert section_dict["title"] == "Reliability"
        assert section_dict["metrics"]["error_rate"] == 0.01


class TestReport:
    """Test report."""

    def test_report_creation(self):
        """Test creating report."""
        now = datetime.now()

        report = Report(
            title="Daily Report",
            generated_at=now,
            period_start=now - timedelta(days=1),
            period_end=now,
        )

        assert report.title == "Daily Report"
        assert len(report.sections) == 0

    def test_add_section(self):
        """Test adding sections."""
        now = datetime.now()
        report = Report(
            title="Report",
            generated_at=now,
            period_start=now - timedelta(hours=1),
            period_end=now,
        )

        section1 = ReportSection("Performance", "Performance data")
        section2 = ReportSection("Reliability", "Reliability data")

        report.add_section(section1).add_section(section2)

        assert len(report.sections) == 2

    def test_report_to_dict(self):
        """Test converting report to dict."""
        now = datetime.now()

        report = Report(
            title="Report",
            generated_at=now,
            period_start=now - timedelta(hours=1),
            period_end=now,
        )

        report_dict = report.to_dict()

        assert report_dict["title"] == "Report"
        assert "generatedAt" in report_dict


class TestReportGenerator:
    """Test report generator."""

    def test_generate_service_report(self):
        """Test generating service report."""
        now = datetime.now()

        # Create metrics
        latency_series = TimeSeries(metric_name="api.request.latency")
        latency_series.add_value(now, 50.0)
        latency_series.add_value(now + timedelta(minutes=1), 75.0)

        metrics = {"api.request.latency": latency_series}

        report = ReportGenerator.generate_service_report(
            "api-service",
            metrics,
            now - timedelta(hours=1),
            now,
        )

        assert report.title == "Service Report: api-service"
        assert len(report.sections) >= 2

    def test_report_contains_metrics(self):
        """Test report contains metrics."""
        now = datetime.now()

        latency_series = TimeSeries(metric_name="service.op.latency")
        latency_series.add_value(now, 100.0)

        metrics = {"service.op.latency": latency_series}

        report = ReportGenerator.generate_service_report(
            "service",
            metrics,
            now - timedelta(hours=1),
            now,
        )

        assert len(report.sections) > 0
        # At least one section should have metrics
        assert any(len(s.metrics) > 0 for s in report.sections)


class TestAlertingRule:
    """Test alerting rule."""

    def test_rule_creation(self):
        """Test creating rule."""
        rule = AlertingRule(
            rule_id="rule_1",
            name="High Latency",
            condition="gt",
            threshold=500.0,
            metric_name="latency",
            severity="critical",
        )

        assert rule.rule_id == "rule_1"
        assert rule.enabled

    def test_rule_to_dict(self):
        """Test converting rule to dict."""
        rule = AlertingRule(
            rule_id="r1",
            name="Error Rate High",
            condition="gte",
            threshold=0.05,
            metric_name="error_rate",
            severity="warning",
        )

        rule_dict = rule.to_dict()

        assert rule_dict["ruleId"] == "r1"
        assert rule_dict["severity"] == "warning"


class TestAlertingEngine:
    """Test alerting engine."""

    def test_engine_creation(self):
        """Test creating engine."""
        engine = AlertingEngine()

        assert len(engine.rules) == 0

    def test_add_rule(self):
        """Test adding rules."""
        engine = AlertingEngine()

        rule = AlertingRule(
            rule_id="r1",
            name="test",
            condition="gt",
            threshold=100,
            metric_name="latency",
        )

        engine.add_rule(rule)

        assert len(engine.rules) == 1

    def test_evaluate_gt_condition(self):
        """Test evaluating greater-than condition."""
        engine = AlertingEngine()

        rule = AlertingRule(
            rule_id="r1",
            name="High Latency",
            condition="gt",
            threshold=100.0,
            metric_name="latency",
            severity="critical",
        )

        engine.add_rule(rule)

        now = datetime.now()
        alerts = engine.evaluate("latency", 150.0, now)

        assert len(alerts) == 1
        assert alerts[0]["name"] == "High Latency"

    def test_evaluate_gte_condition(self):
        """Test evaluating greater-or-equal condition."""
        engine = AlertingEngine()

        rule = AlertingRule(
            rule_id="r1",
            name="test",
            condition="gte",
            threshold=100.0,
            metric_name="metric",
        )

        engine.add_rule(rule)

        now = datetime.now()

        # Exact threshold
        alerts1 = engine.evaluate("metric", 100.0, now)
        assert len(alerts1) == 1

        # Above threshold
        alerts2 = engine.evaluate("metric", 150.0, now)
        assert len(alerts2) == 0  # Already active

    def test_evaluate_lt_condition(self):
        """Test evaluating less-than condition."""
        engine = AlertingEngine()

        rule = AlertingRule(
            rule_id="r1",
            name="Low Availability",
            condition="lt",
            threshold=99.0,
            metric_name="availability_percent",
        )

        engine.add_rule(rule)

        now = datetime.now()
        alerts = engine.evaluate("availability_percent", 95.0, now)

        assert len(alerts) == 1

    def test_no_alert_when_disabled(self):
        """Test no alert when rule disabled."""
        engine = AlertingEngine()

        rule = AlertingRule(
            rule_id="r1",
            name="test",
            condition="gt",
            threshold=100.0,
            metric_name="latency",
            enabled=False,
        )

        engine.add_rule(rule)

        now = datetime.now()
        alerts = engine.evaluate("latency", 200.0, now)

        assert len(alerts) == 0


class TestMetricsIntegration:
    """Integration tests for metrics."""

    def test_collect_and_report(self):
        """Test collecting metrics and generating report."""
        collector = MetricsCollector()

        # Collect metrics from multiple traces
        for i in range(5):
            trace = {
                "service_name": "api",
                "operation_name": "request",
                "duration_ms": 100.0 + i * 20,
                "status": "OK" if i < 4 else "ERROR",
            }
            collector.collect_from_trace(trace)

        # Get series
        series = collector.get_all_series()

        # Generate report
        now = datetime.now()
        report = ReportGenerator.generate_service_report(
            "api",
            series,
            now - timedelta(hours=1),
            now,
        )

        assert report is not None
        assert len(report.sections) > 0

    def test_alerting_workflow(self):
        """Test full alerting workflow."""
        engine = AlertingEngine()

        # Add rules
        latency_rule = AlertingRule(
            rule_id="high_latency",
            name="High Latency",
            condition="gt",
            threshold=500.0,
            metric_name="api.request.latency",
        )

        error_rule = AlertingRule(
            rule_id="high_errors",
            name="High Errors",
            condition="gte",
            threshold=0.05,
            metric_name="api.request.error_rate",
        )

        engine.add_rule(latency_rule).add_rule(error_rule)

        now = datetime.now()

        # Normal latency - no alert
        alerts1 = engine.evaluate("api.request.latency", 200.0, now)
        assert len(alerts1) == 0

        # High latency - alert!
        alerts2 = engine.evaluate("api.request.latency", 600.0, now)
        assert len(alerts2) == 1

        # Error rate alert
        alerts3 = engine.evaluate("api.request.error_rate", 0.1, now)
        assert len(alerts3) == 1
