"""Trace analysis and insights for distributed tracing data.

Provides:
- Anomaly detection in trace metrics
- Latency profiling with percentile analysis
- Critical path identification
- Trace correlation and dependency mapping
- Performance insights from trace data
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, List, Optional, Tuple
from enum import Enum


class AnomalyType(str, Enum):
    """Types of detected anomalies."""

    LATENCY_SPIKE = "latency_spike"
    ERROR_SPIKE = "error_spike"
    THROUGHPUT_DROP = "throughput_drop"
    HIGH_VARIANCE = "high_variance"
    OUTLIER = "outlier"


@dataclass
class LatencyStats:
    """Latency statistics for trace operation."""

    operation_name: str
    count: int = 0
    min_ms: float = float("inf")
    max_ms: float = 0.0
    mean_ms: float = 0.0
    median_ms: float = 0.0
    p95_ms: float = 0.0
    p99_ms: float = 0.0
    stddev_ms: float = 0.0
    total_ms: float = 0.0

    def add_sample(self, latency_ms: float) -> None:
        """Add a latency sample.

        Args:
            latency_ms: Latency in milliseconds
        """
        self.count += 1
        self.min_ms = min(self.min_ms, latency_ms)
        self.max_ms = max(self.max_ms, latency_ms)
        self.total_ms += latency_ms

    def finalize(self, samples: List[float]) -> None:
        """Finalize statistics with collected samples.

        Args:
            samples: List of latency samples
        """
        if not samples:
            return

        self.count = len(samples)
        self.mean_ms = statistics.mean(samples)

        if len(samples) > 1:
            self.median_ms = statistics.median(samples)
            self.stddev_ms = statistics.stdev(samples)
            self.p95_ms = self._percentile(samples, 0.95)
            self.p99_ms = self._percentile(samples, 0.99)
        else:
            self.median_ms = samples[0]

    @staticmethod
    def _percentile(data: List[float], percentile: float) -> float:
        """Calculate percentile value.

        Args:
            data: Sorted list of values
            percentile: Percentile (0-1)

        Returns:
            Percentile value
        """
        sorted_data = sorted(data)
        index = int(len(sorted_data) * percentile)
        return sorted_data[min(index, len(sorted_data) - 1)]

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "operation": self.operation_name,
            "count": self.count,
            "min_ms": round(self.min_ms, 2),
            "max_ms": round(self.max_ms, 2),
            "mean_ms": round(self.mean_ms, 2),
            "median_ms": round(self.median_ms, 2),
            "p95_ms": round(self.p95_ms, 2),
            "p99_ms": round(self.p99_ms, 2),
            "stddev_ms": round(self.stddev_ms, 2),
        }


@dataclass
class Anomaly:
    """Detected anomaly in trace data."""

    anomaly_type: AnomalyType
    operation_name: str
    severity: str  # low, medium, high, critical
    detected_at: datetime
    metric_name: str
    baseline_value: float
    observed_value: float
    variance_percent: float
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "type": self.anomaly_type.value,
            "operation": self.operation_name,
            "severity": self.severity,
            "detected_at": self.detected_at.isoformat(),
            "metric": self.metric_name,
            "baseline": round(self.baseline_value, 2),
            "observed": round(self.observed_value, 2),
            "variance_percent": round(self.variance_percent, 2),
            "details": self.details,
        }


@dataclass
class CriticalPath:
    """Critical path in trace (slowest path through distributed system)."""

    path_id: str
    span_ids: List[str]
    operations: List[str]
    total_latency_ms: float
    span_count: int
    depth: int  # Max nesting level

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "path_id": self.path_id,
            "operations": self.operations,
            "total_latency_ms": round(self.total_latency_ms, 2),
            "span_count": self.span_count,
            "depth": self.depth,
        }


@dataclass
class TraceCorrelation:
    """Correlation between traces based on properties."""

    correlation_id: str
    user_id: Optional[str]
    tenant_id: Optional[str]
    trace_count: int = 0
    avg_latency_ms: float = 0.0
    error_count: int = 0
    success_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "correlation_id": self.correlation_id,
            "user_id": self.user_id,
            "tenant_id": self.tenant_id,
            "trace_count": self.trace_count,
            "avg_latency_ms": round(self.avg_latency_ms, 2),
            "error_count": self.error_count,
            "success_count": self.success_count,
        }


class AnomalyDetector:
    """Detects anomalies in trace metrics."""

    def __init__(
        self,
        baseline_window_minutes: int = 5,
        threshold_stddev: float = 2.0,
    ):
        """Initialize anomaly detector.

        Args:
            baseline_window_minutes: Minutes for baseline calculation
            threshold_stddev: Standard deviation threshold for anomaly
        """
        self.baseline_window_minutes = baseline_window_minutes
        self.threshold_stddev = threshold_stddev
        self.history: Dict[str, List[Tuple[datetime, float]]] = {}

    def record_metric(
        self,
        operation_name: str,
        value: float,
        timestamp: Optional[datetime] = None,
    ) -> None:
        """Record a metric value.

        Args:
            operation_name: Operation name
            value: Metric value
            timestamp: Timestamp (defaults to now)
        """
        timestamp = timestamp or datetime.now()

        if operation_name not in self.history:
            self.history[operation_name] = []

        self.history[operation_name].append((timestamp, value))

        # Keep only recent history
        cutoff = datetime.now() - timedelta(minutes=self.baseline_window_minutes * 2)
        self.history[operation_name] = [
            (ts, v)
            for ts, v in self.history[operation_name]
            if ts > cutoff
        ]

    def detect_anomalies(
        self,
        operation_name: str,
        current_value: float,
    ) -> List[Anomaly]:
        """Detect anomalies for an operation.

        Args:
            operation_name: Operation name
            current_value: Current value to check

        Returns:
            List of detected anomalies
        """
        anomalies = []

        if operation_name not in self.history:
            return anomalies

        # Get recent history
        now = datetime.now()
        baseline_cutoff = now - timedelta(minutes=self.baseline_window_minutes)

        recent_values = [
            v for ts, v in self.history[operation_name]
            if ts > baseline_cutoff
        ]

        if len(recent_values) < 3:
            return anomalies  # Need minimum samples

        # Calculate baseline stats
        try:
            mean_val = statistics.mean(recent_values)
            stddev_val = statistics.stdev(recent_values) if len(recent_values) > 1 else 0
        except (ValueError, statistics.StatisticsError):
            return anomalies

        # Detect outliers (beyond threshold_stddev standard deviations)
        if stddev_val > 0:
            z_score = abs((current_value - mean_val) / stddev_val)

            if z_score > self.threshold_stddev:
                variance_percent = ((current_value - mean_val) / mean_val * 100) if mean_val > 0 else 0
                severity = self._calculate_severity(z_score, variance_percent)

                anomalies.append(
                    Anomaly(
                        anomaly_type=AnomalyType.OUTLIER,
                        operation_name=operation_name,
                        severity=severity,
                        detected_at=now,
                        metric_name="latency",
                        baseline_value=mean_val,
                        observed_value=current_value,
                        variance_percent=variance_percent,
                        details={
                            "z_score": round(z_score, 2),
                            "stddev": round(stddev_val, 2),
                        },
                    )
                )

        return anomalies

    @staticmethod
    def _calculate_severity(z_score: float, variance_percent: float) -> str:
        """Calculate anomaly severity.

        Args:
            z_score: Z-score of anomaly
            variance_percent: Variance percentage

        Returns:
            Severity level
        """
        if z_score > 5 or abs(variance_percent) > 100:
            return "critical"
        elif z_score > 3.5 or abs(variance_percent) > 50:
            return "high"
        elif z_score > 2.5 or abs(variance_percent) > 25:
            return "medium"
        else:
            return "low"


class LatencyProfiler:
    """Profiles latency of trace operations."""

    def __init__(self):
        """Initialize profiler."""
        self.stats: Dict[str, LatencyStats] = {}
        self.samples: Dict[str, List[float]] = {}

    def record_latency(self, operation_name: str, latency_ms: float) -> None:
        """Record operation latency.

        Args:
            operation_name: Operation name
            latency_ms: Latency in milliseconds
        """
        if operation_name not in self.stats:
            self.stats[operation_name] = LatencyStats(operation_name=operation_name)
            self.samples[operation_name] = []

        self.stats[operation_name].add_sample(latency_ms)
        self.samples[operation_name].append(latency_ms)

    def finalize(self) -> None:
        """Finalize all statistics."""
        for operation_name, stats in self.stats.items():
            stats.finalize(self.samples[operation_name])

    def get_stats(self, operation_name: str) -> Optional[LatencyStats]:
        """Get latency stats for operation.

        Args:
            operation_name: Operation name

        Returns:
            LatencyStats or None
        """
        return self.stats.get(operation_name)

    def get_all_stats(self) -> Dict[str, LatencyStats]:
        """Get all latency stats.

        Returns:
            Dictionary of all stats
        """
        return self.stats

    def get_slowest_operations(self, top_n: int = 10) -> List[LatencyStats]:
        """Get slowest operations.

        Args:
            top_n: Number of top operations

        Returns:
            List of slowest operations
        """
        return sorted(
            self.stats.values(),
            key=lambda s: s.mean_ms,
            reverse=True,
        )[:top_n]

    def get_most_variable_operations(self, top_n: int = 10) -> List[LatencyStats]:
        """Get most variable operations.

        Args:
            top_n: Number of top operations

        Returns:
            List of most variable operations
        """
        return sorted(
            self.stats.values(),
            key=lambda s: s.stddev_ms,
            reverse=True,
        )[:top_n]


class CriticalPathFinder:
    """Identifies critical path in distributed traces."""

    @staticmethod
    def find_critical_path(
        spans: List[Dict[str, Any]],
    ) -> Optional[CriticalPath]:
        """Find critical path through spans.

        Args:
            spans: List of span dictionaries with latency info

        Returns:
            CriticalPath or None if no spans
        """
        if not spans:
            return None

        # Sort spans by start time and latency
        sorted_spans = sorted(
            spans,
            key=lambda s: (s.get("start_time", 0), s.get("latency_ms", 0)),
            reverse=True,
        )

        # Build path from longest latency spans
        path_spans = sorted_spans[:min(len(sorted_spans), 10)]

        total_latency = sum(s.get("latency_ms", 0) for s in path_spans)
        operations = [s.get("operation", "unknown") for s in path_spans]
        span_ids = [s.get("span_id", "") for s in path_spans]

        import uuid
        path_id = f"critical_{uuid.uuid4().hex[:12]}"

        return CriticalPath(
            path_id=path_id,
            span_ids=span_ids,
            operations=operations,
            total_latency_ms=total_latency,
            span_count=len(path_spans),
            depth=len(set(s.get("depth", 0) for s in path_spans)),
        )

    @staticmethod
    def find_bottlenecks(
        spans: List[Dict[str, Any]],
        percentile: float = 0.95,
    ) -> List[Dict[str, Any]]:
        """Find bottleneck operations (above percentile).

        Args:
            spans: List of spans
            percentile: Percentile threshold (0-1)

        Returns:
            List of bottleneck spans
        """
        latencies = sorted([s.get("latency_ms", 0) for s in spans])

        if not latencies:
            return []

        threshold = latencies[int(len(latencies) * percentile)]

        return [s for s in spans if s.get("latency_ms", 0) >= threshold]


class TraceCorrelationEngine:
    """Correlates traces by user, tenant, correlation ID."""

    def __init__(self):
        """Initialize correlation engine."""
        self.correlations: Dict[str, TraceCorrelation] = {}

    def add_trace(
        self,
        correlation_id: str,
        user_id: Optional[str],
        tenant_id: Optional[str],
        latency_ms: float,
        success: bool,
    ) -> None:
        """Add trace to correlation.

        Args:
            correlation_id: Correlation ID
            user_id: User ID
            tenant_id: Tenant ID
            latency_ms: Trace latency
            success: Whether trace succeeded
        """
        if correlation_id not in self.correlations:
            self.correlations[correlation_id] = TraceCorrelation(
                correlation_id=correlation_id,
                user_id=user_id,
                tenant_id=tenant_id,
            )

        corr = self.correlations[correlation_id]
        corr.trace_count += 1
        corr.avg_latency_ms = (
            (corr.avg_latency_ms * (corr.trace_count - 1) + latency_ms)
            / corr.trace_count
        )

        if success:
            corr.success_count += 1
        else:
            corr.error_count += 1

    def get_correlation(self, correlation_id: str) -> Optional[TraceCorrelation]:
        """Get correlation data.

        Args:
            correlation_id: Correlation ID

        Returns:
            TraceCorrelation or None
        """
        return self.correlations.get(correlation_id)

    def get_all_correlations(self) -> Dict[str, TraceCorrelation]:
        """Get all correlations."""
        return self.correlations

    def get_by_user(self, user_id: str) -> List[TraceCorrelation]:
        """Get correlations by user.

        Args:
            user_id: User ID

        Returns:
            List of correlations
        """
        return [
            corr for corr in self.correlations.values()
            if corr.user_id == user_id
        ]

    def get_by_tenant(self, tenant_id: str) -> List[TraceCorrelation]:
        """Get correlations by tenant.

        Args:
            tenant_id: Tenant ID

        Returns:
            List of correlations
        """
        return [
            corr for corr in self.correlations.values()
            if corr.tenant_id == tenant_id
        ]


__all__ = [
    "AnomalyType",
    "LatencyStats",
    "Anomaly",
    "CriticalPath",
    "TraceCorrelation",
    "AnomalyDetector",
    "LatencyProfiler",
    "CriticalPathFinder",
    "TraceCorrelationEngine",
]
