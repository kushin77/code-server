"""
Root Cause Analysis Engine (Phase 27C)

Identifies root causes of incidents through:
- Correlation analysis
- Dependency graph tracking
- Error propagation analysis
- Blast radius estimation
- Probable root cause ranking

Part of Observability Platform v1.0.0
"""

import math
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple


class ImpactLevel(Enum):
    """Impact levels for root cause analysis."""
    
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass
class ServiceDependency:
    """Service-to-service dependency."""
    
    source_service: str
    target_service: str
    dependency_type: str = "http"  # http, grpc, database, queue
    failure_propagation: float = 0.8  # 0-1, probability of failure propagation
    latency_impact: float = 0.0  # ms of additional latency when slow


@dataclass
class CorrelationResult:
    """Correlation between two metrics."""
    
    metric_a: str
    metric_b: str
    correlation_coefficient: float  # -1 to 1
    significance: float  # 0-1, statistical significance
    lag: int  # Time lag in seconds where correlation is strongest
    relationship: str  # "positive", "negative", "none"


@dataclass
class ErrorPropagation:
    """Error propagation through dependency chain."""
    
    root_service: str
    affected_services: List[str]
    propagation_path: List[str]
    error_rate_increase: Dict[str, float]  # Service -> error rate increase
    latency_increase: Dict[str, float]  # Service -> latency increase
    blast_radius: float  # 0-1, fraction of system affected


@dataclass
class RootCauseCandidate:
    """Potential root cause."""
    
    candidate_name: str
    confidence: float  # 0-1
    impact_level: ImpactLevel
    evidence: List[str]
    correlated_metrics: List[str]
    affected_services: List[str]
    estimated_blast_radius: float
    probability_ranking: float  # 0-1, final ranking score


@dataclass
class RootCauseReport:
    """Root cause analysis report."""
    
    incident_id: str
    timestamp: datetime
    primary_issue: str
    suspected_root_cause: str
    confidence: float
    secondary_candidates: List[RootCauseCandidate] = field(default_factory=list)
    correlation_analysis: List[CorrelationResult] = field(default_factory=list)
    error_propagation: Optional[ErrorPropagation] = None
    blast_radius: float = 0.0
    affected_services: List[str] = field(default_factory=list)
    recommendations: List[str] = field(default_factory=list)


class DependencyGraph:
    """Service dependency graph."""
    
    def __init__(self):
        """Initialize dependency graph."""
        self.dependencies: List[ServiceDependency] = []
        self.services: Set[str] = set()
    
    def add_dependency(
        self,
        source: str,
        target: str,
        dependency_type: str = "http",
        failure_propagation: float = 0.8
    ) -> None:
        """Add dependency between services."""
        dep = ServiceDependency(
            source_service=source,
            target_service=target,
            dependency_type=dependency_type,
            failure_propagation=failure_propagation
        )
        self.dependencies.append(dep)
        self.services.add(source)
        self.services.add(target)
    
    def get_downstream_services(self, service: str) -> Set[str]:
        """Get all services downstream from service."""
        visited = set()
        to_visit = [service]
        
        while to_visit:
            current = to_visit.pop(0)
            if current in visited:
                continue
            visited.add(current)
            
            # Find dependencies
            for dep in self.dependencies:
                if dep.source_service == current and dep.target_service not in visited:
                    to_visit.append(dep.target_service)
        
        visited.discard(service)
        return visited
    
    def get_upstream_services(self, service: str) -> Set[str]:
        """Get all services upstream from service."""
        visited = set()
        to_visit = [service]
        
        while to_visit:
            current = to_visit.pop(0)
            if current in visited:
                continue
            visited.add(current)
            
            # Find reverse dependencies
            for dep in self.dependencies:
                if dep.target_service == current and dep.source_service not in visited:
                    to_visit.append(dep.source_service)
        
        visited.discard(service)
        return visited
    
    def get_dependency_path(self, source: str, target: str) -> Optional[List[str]]:
        """Find path from source to target service."""
        queue = [(source, [source])]
        visited = set()
        
        while queue:
            current, path = queue.pop(0)
            
            if current == target:
                return path
            
            if current in visited:
                continue
            visited.add(current)
            
            for dep in self.dependencies:
                if dep.source_service == current:
                    next_service = dep.target_service
                    if next_service not in visited:
                        queue.append((next_service, path + [next_service]))
        
        return None


class CorrelationAnalyzer:
    """Metric correlation analysis."""
    
    def __init__(self):
        """Initialize analyzer."""
        self.metric_history: Dict[str, List[float]] = {}
    
    def add_metric_value(self, metric_name: str, value: float) -> None:
        """Add metric value."""
        if metric_name not in self.metric_history:
            self.metric_history[metric_name] = []
        
        self.metric_history[metric_name].append(value)
        
        # Keep reasonable size
        if len(self.metric_history[metric_name]) > 1000:
            self.metric_history[metric_name] = self.metric_history[metric_name][-1000:]
    
    def calculate_correlation(
        self,
        metric_a: str,
        metric_b: str,
        max_lag: int = 60
    ) -> Optional[CorrelationResult]:
        """Calculate correlation between metrics."""
        if metric_a not in self.metric_history or metric_b not in self.metric_history:
            return None
        
        values_a = self.metric_history[metric_a]
        values_b = self.metric_history[metric_b]
        
        if len(values_a) < 10 or len(values_b) < 10:
            return None
        
        # Ensure same length
        min_len = min(len(values_a), len(values_b))
        values_a = values_a[-min_len:]
        values_b = values_b[-min_len:]
        
        # Calculate Pearson correlation at different lags
        best_correlation = 0.0
        best_lag = 0
        best_relationship = "none"
        
        for lag in range(-max_lag, max_lag + 1):
            if lag < 0:
                a = values_a[-lag:]
                b = values_b[:len(values_a) + lag]
            elif lag > 0:
                a = values_a[:-lag]
                b = values_b[lag:]
            else:
                a = values_a
                b = values_b
            
            if len(a) < 10:
                continue
            
            corr = self._pearson_correlation(a, b)
            
            if abs(corr) > abs(best_correlation):
                best_correlation = corr
                best_lag = lag
                best_relationship = "positive" if corr > 0 else "negative"
        
        # Calculate significance
        n = len(values_a)
        if n > 2:
            t_stat = best_correlation * math.sqrt(n - 2) / math.sqrt(1 - best_correlation**2 + 0.001)
            significance = min(abs(t_stat) / 10, 1.0)  # Simplified significance
        else:
            significance = 0.0
        
        if abs(best_correlation) < 0.3:
            best_relationship = "none"
        
        return CorrelationResult(
            metric_a=metric_a,
            metric_b=metric_b,
            correlation_coefficient=best_correlation,
            significance=significance,
            lag=best_lag,
            relationship=best_relationship
        )
    
    @staticmethod
    def _pearson_correlation(x: List[float], y: List[float]) -> float:
        """Calculate Pearson correlation coefficient."""
        if len(x) < 2 or len(y) < 2:
            return 0.0
        
        mean_x = sum(x) / len(x)
        mean_y = sum(y) / len(y)
        
        numerator = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(len(x)))
        
        sum_sq_x = sum((x[i] - mean_x) ** 2 for i in range(len(x)))
        sum_sq_y = sum((y[i] - mean_y) ** 2 for i in range(len(y)))
        
        denominator = math.sqrt(sum_sq_x * sum_sq_y)
        
        if denominator == 0:
            return 0.0
        
        return numerator / denominator


class BlastRadiusCalculator:
    """Calculate blast radius of failures."""
    
    def __init__(self, dependency_graph: DependencyGraph):
        """Initialize calculator."""
        self.graph = dependency_graph
    
    def calculate_blast_radius(
        self,
        failed_service: str,
        affected_error_rate: Dict[str, float]
    ) -> ErrorPropagation:
        """Calculate blast radius from failed service."""
        downstream = self.graph.get_downstream_services(failed_service)
        
        error_increases = {failed_service: affected_error_rate.get(failed_service, 100.0)}
        latency_increases = {}
        
        # Propagate through dependencies
        for service in downstream:
            # Find dependency
            for dep in self.graph.dependencies:
                if dep.source_service == failed_service and dep.target_service == service:
                    error_increase = affected_error_rate.get(failed_service, 0) * dep.failure_propagation
                    error_increases[service] = error_increase
                    latency_increases[service] = dep.latency_impact
        
        # Calculate blast radius
        total_services = len(self.graph.services)
        affected_count = len(set([failed_service] + list(downstream)))
        blast_radius = affected_count / max(total_services, 1)
        
        return ErrorPropagation(
            root_service=failed_service,
            affected_services=list(downstream),
            propagation_path=[failed_service] + list(downstream)[:5],
            error_rate_increase=error_increases,
            latency_increase=latency_increases,
            blast_radius=blast_radius
        )


class RootCauseAnalyzer:
    """Central root cause analysis engine."""
    
    def __init__(self):
        """Initialize analyzer."""
        self.dependency_graph = DependencyGraph()
        self.correlation_analyzer = CorrelationAnalyzer()
        self.blast_calculator = BlastRadiusCalculator(self.dependency_graph)
        self.analysis_reports: List[RootCauseReport] = []
        self._stats = {
            'analyses_performed': 0,
            'root_causes_identified': 0
        }
    
    def add_dependency(
        self,
        source: str,
        target: str,
        dependency_type: str = "http"
    ) -> None:
        """Add service dependency."""
        self.dependency_graph.add_dependency(source, target, dependency_type)
    
    def add_metric_datapoint(self, metric_name: str, value: float) -> None:
        """Add metric data point."""
        self.correlation_analyzer.add_metric_value(metric_name, value)
    
    def analyze_incident(
        self,
        incident_id: str,
        primary_issue: str,
        affected_services: List[str],
        error_rates: Dict[str, float],
        affected_metrics: List[str]
    ) -> RootCauseReport:
        """Analyze incident for root cause."""
        self._stats['analyses_performed'] += 1
        
        candidates: List[RootCauseCandidate] = []
        correlations: List[CorrelationResult] = []
        
        # Analyze correlations between affected metrics
        for i, metric_a in enumerate(affected_metrics):
            for metric_b in affected_metrics[i+1:]:
                corr = self.correlation_analyzer.calculate_correlation(metric_a, metric_b)
                if corr and corr.significance > 0.5:
                    correlations.append(corr)
        
        # Identify potential root causes
        primary_service = affected_services[0] if affected_services else primary_issue
        
        # Analyze as potential root cause
        blast = self.blast_calculator.calculate_blast_radius(
            primary_service,
            error_rates
        )
        
        confidence = min(blast.blast_radius + 0.2, 1.0)
        impact = (
            ImpactLevel.CRITICAL if blast.blast_radius > 0.7
            else ImpactLevel.HIGH if blast.blast_radius > 0.5
            else ImpactLevel.MEDIUM if blast.blast_radius > 0.3
            else ImpactLevel.LOW
        )
        
        primary_candidate = RootCauseCandidate(
            candidate_name=primary_service,
            confidence=confidence,
            impact_level=impact,
            evidence=["Primary affected service", f"Blast radius: {blast.blast_radius:.2%}"],
            correlated_metrics=[c.metric_a for c in correlations],
            affected_services=affected_services,
            estimated_blast_radius=blast.blast_radius,
            probability_ranking=confidence
        )
        candidates.append(primary_candidate)
        
        # Add upstream services as secondary candidates
        upstream = self.dependency_graph.get_upstream_services(primary_service)
        for upstream_service in list(upstream)[:3]:
            candidate = RootCauseCandidate(
                candidate_name=upstream_service,
                confidence=confidence * 0.6,
                impact_level=ImpactLevel.MEDIUM,
                evidence=["Upstream service", "Potential propagation source"],
                correlated_metrics=[],
                affected_services=[upstream_service],
                estimated_blast_radius=0.5,
                probability_ranking=confidence * 0.6
            )
            candidates.append(candidate)
        
        # Generate report
        recommendations = [
            f"Investigate {primary_candidate.candidate_name} logs and metrics",
            "Check service dependencies for cascading failures",
            f"Review recent changes to {primary_service}",
            "Verify database connectivity and query performance"
        ]
        
        report = RootCauseReport(
            incident_id=incident_id,
            timestamp=datetime.utcnow(),
            primary_issue=primary_issue,
            suspected_root_cause=primary_candidate.candidate_name,
            confidence=primary_candidate.confidence,
            secondary_candidates=candidates[1:],
            correlation_analysis=correlations,
            error_propagation=blast,
            blast_radius=blast.blast_radius,
            affected_services=affected_services,
            recommendations=recommendations
        )
        
        self.analysis_reports.append(report)
        self._stats['root_causes_identified'] += 1
        
        return report
    
    def get_analysis_history(
        self,
        limit: int = 50
    ) -> List[RootCauseReport]:
        """Get analysis history."""
        reports = sorted(
            self.analysis_reports,
            key=lambda r: r.timestamp,
            reverse=True
        )
        return reports[:limit]
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get analyzer statistics."""
        return {
            'analyses_performed': self._stats['analyses_performed'],
            'root_causes_identified': self._stats['root_causes_identified'],
            'total_reports': len(self.analysis_reports),
            'services_tracked': len(self.dependency_graph.services),
            'dependencies_mapped': len(self.dependency_graph.dependencies),
            'metrics_monitored': len(self.correlation_analyzer.metric_history)
        }
