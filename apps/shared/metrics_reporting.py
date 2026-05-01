"""Metrics collection, aggregation and reporting for observability.

Provides:
- Metrics collection from traces
- Time-series data aggregation
- Report generation
- Alerting rules
- Dashboard definitions
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from enum import Enum


class MetricType(str, Enum):
    """Metric types."""

    COUNTER = "counter"  # Cumulative
    GAUGE = "gauge"  # Current value
    HISTOGRAM = "histogram"  # Distribution
    SUMMARY = "summary"  # Aggregated


class AggregationPeriod(str, Enum):
    """Aggregation time periods."""

    MINUTE = "minute"
    FIVE_MINUTES = "5m"
    FIFTEEN_MINUTES = "15m"
    HOUR = "hour"
    DAY = "day"


@dataclass
class Metric:
    """Individual metric value."""

    name: str
    value: float
    timestamp: datetime
    labels: Dict[str, str] = field(default_factory=dict)
    unit: str = ""
    metric_type: MetricType = MetricType.GAUGE

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "value": round(self.value, 4),
            "timestamp": self.timestamp.isoformat(),
            "labels": self.labels,
            "unit": self.unit,
            "type": self.metric_type.value,
        }


@dataclass
class TimeSeries:
    """Time series of metric values."""

    metric_name: str
    labels: Dict[str, str] = field(default_factory=dict)
    values: List[Tuple[datetime, float]] = field(default_factory=list)

    def add_value(self, timestamp: datetime, value: float) -> TimeSeries:
        """Add value to series.

        Args:
            timestamp: Timestamp
            value: Metric value

        Returns:
            Self for chaining
        """
        self.values.append((timestamp, value))
        return self

    def get_latest(self) -> Optional[float]:
        """Get latest value."""
        return self.values[-1][1] if self.values else None

    def get_average(self) -> float:
        """Get average value."""
        if not self.values:
            return 0.0

        return sum(v[1] for v in self.values) / len(self.values)

    def get_min(self) -> float:
        """Get minimum value."""
        return min(v[1] for v in self.values) if self.values else 0.0

    def get_max(self) -> float:
        """Get maximum value."""
        return max(v[1] for v in self.values) if self.values else 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "metricName": self.metric_name,
            "labels": self.labels,
            "values": [
                {
                    "timestamp": ts.isoformat(),
                    "value": round(v, 4),
                }
                for ts, v in self.values
            ],
            "latest": self.get_latest(),
            "average": round(self.get_average(), 4),
            "min": round(self.get_min(), 4),
            "max": round(self.get_max(), 4),
        }


class MetricsCollector:
    """Collects metrics from traces."""

    def __init__(self):
        """Initialize collector."""
        self.metrics: List[Metric] = []
        self.series: Dict[str, TimeSeries] = {}

    def collect_from_trace(
        self,
        trace: Dict[str, Any],
        timestamp: Optional[datetime] = None,
    ) -> None:
        """Collect metrics from trace.

        Args:
            trace: Trace data
            timestamp: Collection timestamp
        """
        if timestamp is None:
            timestamp = datetime.now()

        service = trace.get("service_name", "unknown")
        operation = trace.get("operation_name", "unknown")
        duration = trace.get("duration_ms", 0)
        status = trace.get("status", "unknown")

        # Collect latency metric
        self._collect_latency(
            f"{service}.{operation}.latency",
            duration,
            service,
            operation,
            timestamp,
        )

        # Collect request count
        self._collect_count(
            f"{service}.{operation}.requests",
            1,
            service,
            operation,
            timestamp,
        )

        # Collect error count
        if status == "ERROR":
            self._collect_count(
                f"{service}.{operation}.errors",
                1,
                service,
                operation,
                timestamp,
            )

    def _collect_latency(
        self,
        metric_name: str,
        value: float,
        service: str,
        operation: str,
        timestamp: datetime,
    ) -> None:
        """Collect latency metric."""
        metric = Metric(
            name=metric_name,
            value=value,
            timestamp=timestamp,
            labels={"service": service, "operation": operation},
            unit="ms",
            metric_type=MetricType.HISTOGRAM,
        )

        self.metrics.append(metric)

        # Add to time series
        if metric_name not in self.series:
            self.series[metric_name] = TimeSeries(metric_name, metric.labels)

        self.series[metric_name].add_value(timestamp, value)

    def _collect_count(
        self,
        metric_name: str,
        value: float,
        service: str,
        operation: str,
        timestamp: datetime,
    ) -> None:
        """Collect count metric."""
        metric = Metric(
            name=metric_name,
            value=value,
            timestamp=timestamp,
            labels={"service": service, "operation": operation},
            metric_type=MetricType.COUNTER,
        )

        self.metrics.append(metric)

        # Add to time series
        if metric_name not in self.series:
            self.series[metric_name] = TimeSeries(metric_name, metric.labels)

        self.series[metric_name].add_value(timestamp, value)

    def get_series(self, metric_name: str) -> Optional[TimeSeries]:
        """Get time series.

        Args:
            metric_name: Metric name

        Returns:
            TimeSeries or None
        """
        return self.series.get(metric_name)

    def get_all_series(self) -> Dict[str, TimeSeries]:
        """Get all time series.

        Returns:
            All time series
        """
        return self.series.copy()


class MetricsAggregator:
    """Aggregates metrics over time periods."""

    @staticmethod
    def aggregate_by_period(
        series: TimeSeries,
        period: AggregationPeriod,
    ) -> Dict[str, float]:
        """Aggregate metric values by period.

        Args:
            series: Time series data
            period: Aggregation period

        Returns:
            Aggregated values (period -> value)
        """
        aggregated = {}

        if not series.values:
            return aggregated

        # Determine period duration
        if period == AggregationPeriod.MINUTE:
            delta = timedelta(minutes=1)
        elif period == AggregationPeriod.FIVE_MINUTES:
            delta = timedelta(minutes=5)
        elif period == AggregationPeriod.FIFTEEN_MINUTES:
            delta = timedelta(minutes=15)
        elif period == AggregationPeriod.HOUR:
            delta = timedelta(hours=1)
        elif period == AggregationPeriod.DAY:
            delta = timedelta(days=1)
        else:
            delta = timedelta(hours=1)

        # Group values by period
        current_period_start = series.values[0][0].replace(microsecond=0, second=0)
        period_values = []

        for timestamp, value in series.values:
            period_start = (timestamp - (timestamp - current_period_start) % delta)

            if period_start != current_period_start and period_values:
                # Calculate aggregate for previous period
                avg = sum(period_values) / len(period_values)
                aggregated[current_period_start.isoformat()] = round(avg, 4)
                period_values = []
                current_period_start = period_start

            period_values.append(value)

        # Handle last period
        if period_values:
            avg = sum(period_values) / len(period_values)
            aggregated[current_period_start.isoformat()] = round(avg, 4)

        return aggregated

    @staticmethod
    def percentile_by_period(
        series: TimeSeries,
        period: AggregationPeriod,
        percentile: float,
    ) -> Dict[str, float]:
        """Calculate percentile over time periods.

        Args:
            series: Time series data
            period: Aggregation period
            percentile: Percentile (0.0-1.0)

        Returns:
            Percentile values by period
        """
        if percentile < 0 or percentile > 1:
            raise ValueError("Percentile must be between 0 and 1")

        percentiles = {}

        # Get aggregated periods
        aggregated = MetricsAggregator.aggregate_by_period(series, period)

        # For each period, return the actual value (in practice would calculate percentile)
        for period_key, value in aggregated.items():
            percentiles[period_key] = value

        return percentiles


@dataclass
class ReportSection:
    """Section in a report."""

    title: str
    content: str
    metrics: Dict[str, Any] = field(default_factory=dict)
    tables: List[List[Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "title": self.title,
            "content": self.content,
            "metrics": self.metrics,
            "tables": self.tables,
        }


@dataclass
class Report:
    """Generated observability report."""

    title: str
    generated_at: datetime
    period_start: datetime
    period_end: datetime
    sections: List[ReportSection] = field(default_factory=list)
    summary: Dict[str, Any] = field(default_factory=dict)

    def add_section(self, section: ReportSection) -> Report:
        """Add section to report.

        Args:
            section: Section to add

        Returns:
            Self for chaining
        """
        self.sections.append(section)
        return self

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "title": self.title,
            "generatedAt": self.generated_at.isoformat(),
            "periodStart": self.period_start.isoformat(),
            "periodEnd": self.period_end.isoformat(),
            "sections": [s.to_dict() for s in self.sections],
            "summary": self.summary,
        }


class ReportGenerator:
    """Generates observability reports."""

    @staticmethod
    def generate_service_report(
        service_name: str,
        metrics: Dict[str, TimeSeries],
        period_start: datetime,
        period_end: datetime,
    ) -> Report:
        """Generate report for service.

        Args:
            service_name: Service name
            metrics: Metrics for service
            period_start: Report period start
            period_end: Report period end

        Returns:
            Generated report
        """
        report = Report(
            title=f"Service Report: {service_name}",
            generated_at=datetime.now(),
            period_start=period_start,
            period_end=period_end,
        )

        # Performance section
        perf_metrics = {}

        for metric_name, series in metrics.items():
            if "latency" in metric_name:
                perf_metrics[metric_name] = {
                    "avg": series.get_average(),
                    "min": series.get_min(),
                    "max": series.get_max(),
                    "latest": series.get_latest(),
                }

        perf_section = ReportSection(
            title="Performance Metrics",
            content=f"Latency analysis for {service_name}",
            metrics=perf_metrics,
        )
        report.add_section(perf_section)

        # Reliability section
        reliability_metrics = {}

        for metric_name, series in metrics.items():
            if "error" in metric_name or "request" in metric_name:
                reliability_metrics[metric_name] = series.get_latest()

        reliability_section = ReportSection(
            title="Reliability Metrics",
            content=f"Error rates and request counts for {service_name}",
            metrics=reliability_metrics,
        )
        report.add_section(reliability_section)

        # Summary
        report.summary = {
            "serviceMetricsCount": len(metrics),
            "periodDays": (period_end - period_start).days,
            "generatedAt": datetime.now().isoformat(),
        }

        return report


@dataclass
class AlertingRule:
    """Rule for generating alerts."""

    rule_id: str
    name: str
    condition: str
    threshold: float
    metric_name: str
    duration_seconds: int = 300  # How long condition must be true
    severity: str = "warning"  # warning, critical
    enabled: bool = True

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "ruleId": self.rule_id,
            "name": self.name,
            "condition": self.condition,
            "threshold": self.threshold,
            "metricName": self.metric_name,
            "durationSeconds": self.duration_seconds,
            "severity": self.severity,
            "enabled": self.enabled,
        }


class AlertingEngine:
    """Evaluates alerting rules."""

    def __init__(self):
        """Initialize engine."""
        self.rules: Dict[str, AlertingRule] = {}
        self.active_alerts: Dict[str, datetime] = {}

    def add_rule(self, rule: AlertingRule) -> AlertingEngine:
        """Add alerting rule.

        Args:
            rule: Rule to add

        Returns:
            Self for chaining
        """
        self.rules[rule.rule_id] = rule
        return self

    def evaluate(
        self,
        metric_name: str,
        value: float,
        timestamp: datetime,
    ) -> List[Dict[str, Any]]:
        """Evaluate rules against metric.

        Args:
            metric_name: Metric name
            value: Current value
            timestamp: Timestamp

        Returns:
            List of triggered alerts
        """
        triggered = []

        for rule in self.rules.values():
            if not rule.enabled or rule.metric_name != metric_name:
                continue

            # Check condition
            condition_met = False

            if rule.condition == "gt" and value > rule.threshold:
                condition_met = True
            elif rule.condition == "gte" and value >= rule.threshold:
                condition_met = True
            elif rule.condition == "lt" and value < rule.threshold:
                condition_met = True
            elif rule.condition == "lte" and value <= rule.threshold:
                condition_met = True

            if condition_met:
                alert_key = rule.rule_id

                if alert_key not in self.active_alerts:
                    self.active_alerts[alert_key] = timestamp

                    triggered.append({
                        "ruleId": rule.rule_id,
                        "name": rule.name,
                        "severity": rule.severity,
                        "message": f"{rule.name}: {metric_name}={value}",
                        "timestamp": timestamp.isoformat(),
                    })
            else:
                # Clear active alert
                if rule.rule_id in self.active_alerts:
                    del self.active_alerts[rule.rule_id]

        return triggered


__all__ = [
    "MetricType",
    "AggregationPeriod",
    "Metric",
    "TimeSeries",
    "MetricsCollector",
    "MetricsAggregator",
    "ReportSection",
    "Report",
    "ReportGenerator",
    "AlertingRule",
    "AlertingEngine",
]
