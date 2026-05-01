"""Trace insights service for generating actionable recommendations from trace analysis.

Provides:
- SLO/SLI calculation from traces
- Performance recommendations
- Dependency analysis
- Service health scoring
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional
from enum import Enum

from apps.shared.trace_analysis import (
    LatencyStats,
    TraceCorrelation,
    AnomalyDetector,
    LatencyProfiler,
)


class HealthScore(str, Enum):
    """Service health score."""

    EXCELLENT = "excellent"  # 95-100%
    GOOD = "good"  # 85-94%
    FAIR = "fair"  # 75-84%
    POOR = "poor"  # Below 75%


@dataclass
class SLOMetrics:
    """SLO/SLI metrics for service."""

    service_name: str
    latency_p99_ms: float
    latency_p95_ms: float
    error_rate_percent: float
    availability_percent: float
    error_budget_remaining_percent: float

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "service": self.service_name,
            "latency_p99_ms": round(self.latency_p99_ms, 2),
            "latency_p95_ms": round(self.latency_p95_ms, 2),
            "error_rate_percent": round(self.error_rate_percent, 2),
            "availability_percent": round(self.availability_percent, 2),
            "error_budget_remaining_percent": round(self.error_budget_remaining_percent, 2),
        }


@dataclass
class PerformanceRecommendation:
    """Performance optimization recommendation."""

    priority: str  # high, medium, low
    category: str  # latency, throughput, errors, etc.
    operation_name: str
    current_metric: float
    recommended_target: float
    metric_name: str
    rationale: str
    estimated_improvement_percent: float

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "priority": self.priority,
            "category": self.category,
            "operation": self.operation_name,
            "current": round(self.current_metric, 2),
            "target": round(self.recommended_target, 2),
            "metric": self.metric_name,
            "rationale": self.rationale,
            "improvement_percent": round(self.estimated_improvement_percent, 2),
        }


@dataclass
class ServiceDependency:
    """Service dependency information."""

    source_service: str
    target_service: str
    call_count: int = 0
    avg_latency_ms: float = 0.0
    error_rate_percent: float = 0.0
    criticality: str = "low"  # low, medium, high, critical

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "source": self.source_service,
            "target": self.target_service,
            "calls": self.call_count,
            "avg_latency_ms": round(self.avg_latency_ms, 2),
            "error_rate_percent": round(self.error_rate_percent, 2),
            "criticality": self.criticality,
        }


@dataclass
class ServiceHealthScore:
    """Service health score and details."""

    service_name: str
    overall_score: float  # 0-100
    health_status: HealthScore
    latency_score: float
    reliability_score: float
    throughput_score: float
    timestamp: datetime
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "service": self.service_name,
            "overall_score": round(self.overall_score, 1),
            "status": self.health_status.value,
            "latency_score": round(self.latency_score, 1),
            "reliability_score": round(self.reliability_score, 1),
            "throughput_score": round(self.throughput_score, 1),
            "timestamp": self.timestamp.isoformat(),
            "details": self.details,
        }


class TraceInsightsEngine:
    """Generates insights from trace analysis."""

    def __init__(
        self,
        latency_p99_slo_ms: float = 200.0,
        latency_p95_slo_ms: float = 100.0,
        error_rate_slo_percent: float = 0.1,
        availability_slo_percent: float = 99.9,
    ):
        """Initialize insights engine.

        Args:
            latency_p99_slo_ms: P99 latency SLO
            latency_p95_slo_ms: P95 latency SLO
            error_rate_slo_percent: Error rate SLO
            availability_slo_percent: Availability SLO
        """
        self.latency_p99_slo = latency_p99_slo_ms
        self.latency_p95_slo = latency_p95_slo_ms
        self.error_rate_slo = error_rate_slo_percent
        self.availability_slo = availability_slo_percent

    def calculate_slo_metrics(
        self,
        service_name: str,
        stats: LatencyStats,
        error_count: int,
        total_count: int,
    ) -> SLOMetrics:
        """Calculate SLO/SLI metrics.

        Args:
            service_name: Service name
            stats: Latency statistics
            error_count: Number of errors
            total_count: Total number of traces

        Returns:
            SLOMetrics
        """
        error_rate = (error_count / total_count * 100) if total_count > 0 else 0
        availability = 100.0 - error_rate

        # Calculate error budget
        error_budget_used = error_rate / self.error_rate_slo * 100
        error_budget_remaining = 100.0 - error_budget_used

        return SLOMetrics(
            service_name=service_name,
            latency_p99_ms=stats.p99_ms,
            latency_p95_ms=stats.p95_ms,
            error_rate_percent=error_rate,
            availability_percent=availability,
            error_budget_remaining_percent=error_budget_remaining,
        )

    def generate_recommendations(
        self,
        stats: Dict[str, LatencyStats],
        anomalies: List[Any],
    ) -> List[PerformanceRecommendation]:
        """Generate performance recommendations.

        Args:
            stats: Dictionary of latency stats by operation
            anomalies: List of detected anomalies

        Returns:
            List of recommendations
        """
        recommendations = []

        # Check for slow operations
        for op_name, op_stats in stats.items():
            if op_stats.p99_ms > self.latency_p99_slo:
                variance_ratio = (op_stats.stddev_ms / op_stats.mean_ms) if op_stats.mean_ms > 0 else 0

                if variance_ratio > 0.5:
                    category = "latency variance"
                    rationale = "High variance in latency - consider caching or optimization"
                else:
                    category = "latency"
                    rationale = "Operation exceeds latency SLO - consider optimization"

                improvement = ((op_stats.p99_ms - self.latency_p99_slo) / op_stats.p99_ms) * 100

                recommendations.append(
                    PerformanceRecommendation(
                        priority="high" if op_stats.p99_ms > self.latency_p99_slo * 2 else "medium",
                        category=category,
                        operation_name=op_name,
                        current_metric=op_stats.p99_ms,
                        recommended_target=self.latency_p99_slo,
                        metric_name="p99_latency_ms",
                        rationale=rationale,
                        estimated_improvement_percent=improvement,
                    )
                )

        # Sort by priority
        recommendations.sort(
            key=lambda r: {"high": 0, "medium": 1, "low": 2}.get(r.priority, 3)
        )

        return recommendations[:10]  # Top 10 recommendations

    def calculate_health_score(
        self,
        service_name: str,
        stats: LatencyStats,
        error_count: int,
        total_count: int,
    ) -> ServiceHealthScore:
        """Calculate service health score.

        Args:
            service_name: Service name
            stats: Latency statistics
            error_count: Number of errors
            total_count: Total traces

        Returns:
            ServiceHealthScore
        """
        # Calculate component scores (0-100)
        latency_score = self._calculate_latency_score(stats)
        reliability_score = self._calculate_reliability_score(error_count, total_count)
        throughput_score = self._calculate_throughput_score(total_count)

        # Overall score (weighted average)
        overall_score = (
            latency_score * 0.4 +
            reliability_score * 0.4 +
            throughput_score * 0.2
        )

        # Determine health status
        if overall_score >= 95:
            status = HealthScore.EXCELLENT
        elif overall_score >= 85:
            status = HealthScore.GOOD
        elif overall_score >= 75:
            status = HealthScore.FAIR
        else:
            status = HealthScore.POOR

        return ServiceHealthScore(
            service_name=service_name,
            overall_score=overall_score,
            health_status=status,
            latency_score=latency_score,
            reliability_score=reliability_score,
            throughput_score=throughput_score,
            timestamp=datetime.now(),
            details={
                "p99_latency_ms": stats.p99_ms,
                "p95_latency_ms": stats.p95_ms,
                "error_rate_percent": (error_count / total_count * 100) if total_count > 0 else 0,
                "availability_percent": ((total_count - error_count) / total_count * 100) if total_count > 0 else 0,
            },
        )

    def _calculate_latency_score(self, stats: LatencyStats) -> float:
        """Calculate latency component score."""
        # Score based on p99 latency vs SLO
        if stats.p99_ms <= self.latency_p99_slo:
            return 100.0
        elif stats.p99_ms <= self.latency_p99_slo * 1.5:
            return 75.0
        elif stats.p99_ms <= self.latency_p99_slo * 2.0:
            return 50.0
        else:
            return max(0.0, 50.0 - ((stats.p99_ms - self.latency_p99_slo * 2.0) / 100))

    def _calculate_reliability_score(self, error_count: int, total_count: int) -> float:
        """Calculate reliability component score."""
        if total_count == 0:
            return 100.0

        error_rate = error_count / total_count

        if error_rate < self.error_rate_slo / 100:
            return 100.0
        elif error_rate < self.error_rate_slo / 50:
            return 75.0
        elif error_rate < self.error_rate_slo / 10:
            return 50.0
        else:
            return max(0.0, 50.0 - (error_rate * 1000))

    def _calculate_throughput_score(self, total_count: int) -> float:
        """Calculate throughput component score."""
        # Assume minimum acceptable throughput is 10 requests
        if total_count < 10:
            return (total_count / 10) * 100
        else:
            return 100.0


class DependencyAnalyzer:
    """Analyzes service dependencies from traces."""

    def __init__(self):
        """Initialize analyzer."""
        self.dependencies: Dict[str, ServiceDependency] = {}

    def record_call(
        self,
        source: str,
        target: str,
        latency_ms: float,
        success: bool,
    ) -> None:
        """Record a service-to-service call.

        Args:
            source: Source service
            target: Target service
            latency_ms: Call latency
            success: Whether call succeeded
        """
        key = f"{source}->{target}"

        if key not in self.dependencies:
            self.dependencies[key] = ServiceDependency(
                source_service=source,
                target_service=target,
            )

        dep = self.dependencies[key]
        dep.call_count += 1
        dep.avg_latency_ms = (
            (dep.avg_latency_ms * (dep.call_count - 1) + latency_ms)
            / dep.call_count
        )

        if not success:
            dep.error_rate_percent = (
                (dep.error_rate_percent * (dep.call_count - 1) + 100)
                / dep.call_count
            )
        else:
            dep.error_rate_percent = (
                (dep.error_rate_percent * (dep.call_count - 1))
                / dep.call_count
            )

        # Determine criticality based on latency and error rate
        if dep.error_rate_percent > 1.0:
            dep.criticality = "critical"
        elif dep.avg_latency_ms > 500 or dep.error_rate_percent > 0.1:
            dep.criticality = "high"
        elif dep.avg_latency_ms > 100 or dep.error_rate_percent > 0.01:
            dep.criticality = "medium"
        else:
            dep.criticality = "low"

    def get_dependency(self, source: str, target: str) -> Optional[ServiceDependency]:
        """Get specific dependency."""
        key = f"{source}->{target}"
        return self.dependencies.get(key)

    def get_critical_dependencies(self) -> List[ServiceDependency]:
        """Get critical service dependencies."""
        return sorted(
            [d for d in self.dependencies.values() if d.criticality in ("high", "critical")],
            key=lambda d: d.error_rate_percent,
            reverse=True,
        )

    def get_dependencies_for_service(self, service: str) -> List[ServiceDependency]:
        """Get dependencies for a service (outgoing calls)."""
        return [d for d in self.dependencies.values() if d.source_service == service]

    def get_dependents(self, service: str) -> List[ServiceDependency]:
        """Get services that depend on this service (incoming calls)."""
        return [d for d in self.dependencies.values() if d.target_service == service]


__all__ = [
    "HealthScore",
    "SLOMetrics",
    "PerformanceRecommendation",
    "ServiceDependency",
    "ServiceHealthScore",
    "TraceInsightsEngine",
    "DependencyAnalyzer",
]
