"""
Phase 25B: Advanced Anomaly Detection

Enhanced anomaly detection with machine learning:
- Statistical anomaly detection
- ML-based pattern recognition
- Multi-variate anomaly detection
- Contextual anomaly scoring

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime, timedelta
from enum import Enum
import statistics
import math

logger = logging.getLogger(__name__)


class AnomalyType(Enum):
    """Types of anomalies."""
    SPIKE = "spike"                      # Sudden increase
    DIP = "dip"                          # Sudden decrease
    TREND = "trend"                      # Sustained change
    SEASONAL = "seasonal"                # Against seasonal pattern
    CONTEXTUAL = "contextual"            # Unusual in context
    COLLECTIVE = "collective"            # Group behavior change


class AnomalySeverity(Enum):
    """Severity levels for anomalies."""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass
class DataPoint:
    """Single data point in time series."""
    timestamp: datetime
    value: float
    context: Dict[str, Any] = field(default_factory=dict)


@dataclass
class AnomalyScore:
    """Score for a potential anomaly."""
    timestamp: datetime
    anomaly_type: AnomalyType
    score: float  # 0-100, >70 is anomalous
    severity: AnomalySeverity
    confidence: float  # 0-1
    details: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def is_anomalous(self) -> bool:
        """Check if score indicates anomaly."""
        return self.score > 70


class StatisticalAnomalyDetector:
    """Statistical-based anomaly detection."""
    
    def __init__(self, lookback_periods: int = 20, std_dev_threshold: float = 3.0):
        """Initialize detector."""
        self.lookback_periods = lookback_periods
        self.std_dev_threshold = std_dev_threshold
        self.history: Dict[str, List[DataPoint]] = {}
    
    def add_point(self, metric_name: str, point: DataPoint) -> Optional[AnomalyScore]:
        """Add data point and check for anomalies."""
        if metric_name not in self.history:
            self.history[metric_name] = []
        
        self.history[metric_name].append(point)
        
        # Keep only recent history
        if len(self.history[metric_name]) > self.lookback_periods:
            self.history[metric_name] = self.history[metric_name][-self.lookback_periods:]
        
        if len(self.history[metric_name]) < 3:
            return None  # Need minimum data
        
        return self._detect_statistical_anomaly(metric_name, point)
    
    def _detect_statistical_anomaly(self, metric_name: str, point: DataPoint) -> Optional[AnomalyScore]:
        """Detect anomaly using statistical methods."""
        history = self.history[metric_name]
        values = [p.value for p in history[:-1]]  # Exclude current point
        
        if len(values) < 2:
            return None
        
        mean = statistics.mean(values)
        stdev = statistics.stdev(values)
        
        if stdev == 0:
            return None  # No variance
        
        z_score = abs((point.value - mean) / stdev)
        
        if z_score > self.std_dev_threshold:
            # Determine anomaly type
            if point.value > mean:
                anomaly_type = AnomalyType.SPIKE
            else:
                anomaly_type = AnomalyType.DIP
            
            # Calculate severity
            score = min(100.0, (z_score / self.std_dev_threshold) * 100)
            if score > 90:
                severity = AnomalySeverity.CRITICAL
            elif score > 80:
                severity = AnomalySeverity.ERROR
            else:
                severity = AnomalySeverity.WARNING
            
            return AnomalyScore(
                timestamp=point.timestamp,
                anomaly_type=anomaly_type,
                score=score,
                severity=severity,
                confidence=min(1.0, z_score / (self.std_dev_threshold * 2)),
                details={
                    "z_score": z_score,
                    "mean": mean,
                    "stdev": stdev,
                    "value": point.value,
                }
            )
        
        return None


class TrendAnomalyDetector:
    """Detects trend-based anomalies."""
    
    def __init__(self, window_size: int = 10, trend_threshold: float = 0.1):
        """Initialize detector."""
        self.window_size = window_size
        self.trend_threshold = trend_threshold
        self.history: Dict[str, List[DataPoint]] = {}
    
    def add_point(self, metric_name: str, point: DataPoint) -> Optional[AnomalyScore]:
        """Add point and detect trend anomalies."""
        if metric_name not in self.history:
            self.history[metric_name] = []
        
        self.history[metric_name].append(point)
        
        # Keep recent history
        if len(self.history[metric_name]) > self.window_size:
            self.history[metric_name] = self.history[metric_name][-self.window_size:]
        
        if len(self.history[metric_name]) < 4:
            return None
        
        return self._detect_trend_anomaly(metric_name)
    
    def _detect_trend_anomaly(self, metric_name: str) -> Optional[AnomalyScore]:
        """Detect sustained trend changes."""
        history = self.history[metric_name]
        
        if len(history) < 4:
            return None
        
        # Compare first half to second half
        mid = len(history) // 2
        first_half = [p.value for p in history[:mid]]
        second_half = [p.value for p in history[mid:]]
        
        first_avg = statistics.mean(first_half)
        second_avg = statistics.mean(second_half)
        
        # Calculate percentage change
        if first_avg == 0:
            return None
        
        pct_change = abs(second_avg - first_avg) / first_avg
        
        if pct_change > self.trend_threshold:
            score = min(100.0, (pct_change / self.trend_threshold) * 100)
            
            if score > 85:
                severity = AnomalySeverity.ERROR
            else:
                severity = AnomalySeverity.WARNING
            
            return AnomalyScore(
                timestamp=history[-1].timestamp,
                anomaly_type=AnomalyType.TREND,
                score=score,
                severity=severity,
                confidence=min(1.0, pct_change / (self.trend_threshold * 2)),
                details={
                    "first_avg": first_avg,
                    "second_avg": second_avg,
                    "pct_change": pct_change,
                }
            )
        
        return None


class MultivariteAnomalyDetector:
    """Detects anomalies across multiple metrics."""
    
    def __init__(self, correlation_threshold: float = 0.7):
        """Initialize detector."""
        self.correlation_threshold = correlation_threshold
        self.metrics: Dict[str, List[DataPoint]] = {}
        self.correlations: Dict[Tuple[str, str], float] = {}
    
    def add_point(self, metric_name: str, point: DataPoint) -> Optional[AnomalyScore]:
        """Add point to multivariate detector."""
        if metric_name not in self.metrics:
            self.metrics[metric_name] = []
        
        self.metrics[metric_name].append(point)
        
        # Keep recent history
        if len(self.metrics[metric_name]) > 100:
            self.metrics[metric_name] = self.metrics[metric_name][-100:]
        
        return self._detect_multivariate_anomaly(metric_name)
    
    def _detect_multivariate_anomaly(self, metric_name: str) -> Optional[AnomalyScore]:
        """Detect correlation-based anomalies."""
        if len(self.metrics) < 2:
            return None
        
        # Find correlated metrics
        metric_values = [p.value for p in self.metrics[metric_name][-20:]]
        if len(metric_values) < 5:
            return None
        
        anomalies = []
        
        for other_metric, other_points in self.metrics.items():
            if other_metric == metric_name or len(other_points) < 5:
                continue
            
            other_values = [p.value for p in other_points[-20:]]
            
            # Calculate correlation
            corr = self._calculate_correlation(metric_values, other_values)
            
            # Check if correlation broken
            key = tuple(sorted([metric_name, other_metric]))
            expected_corr = self.correlations.get(key, corr)
            
            if abs(corr - expected_corr) > 0.3 and expected_corr > self.correlation_threshold:
                anomalies.append({
                    "other_metric": other_metric,
                    "correlation": corr,
                    "expected": expected_corr,
                })
        
        if anomalies:
            return AnomalyScore(
                timestamp=datetime.utcnow(),
                anomaly_type=AnomalyType.COLLECTIVE,
                score=80.0,
                severity=AnomalySeverity.WARNING,
                confidence=0.8,
                details={"broken_correlations": anomalies}
            )
        
        return None
    
    def _calculate_correlation(self, values1: List[float], values2: List[float]) -> float:
        """Calculate Pearson correlation."""
        if len(values1) != len(values2) or len(values1) < 2:
            return 0.0
        
        mean1 = statistics.mean(values1)
        mean2 = statistics.mean(values2)
        
        numerator = sum((values1[i] - mean1) * (values2[i] - mean2) for i in range(len(values1)))
        denominator = math.sqrt(
            sum((values1[i] - mean1) ** 2 for i in range(len(values1))) *
            sum((values2[i] - mean2) ** 2 for i in range(len(values2)))
        )
        
        if denominator == 0:
            return 0.0
        
        return numerator / denominator


class ContextualAnomalyDetector:
    """Detects context-aware anomalies."""
    
    def __init__(self):
        """Initialize detector."""
        self.context_patterns: Dict[str, Dict[str, List[float]]] = {}
    
    def add_point_with_context(
        self,
        metric_name: str,
        point: DataPoint,
        context_key: str,
    ) -> Optional[AnomalyScore]:
        """Add point with context."""
        if metric_name not in self.context_patterns:
            self.context_patterns[metric_name] = {}
        
        if context_key not in self.context_patterns[metric_name]:
            self.context_patterns[metric_name][context_key] = []
        
        self.context_patterns[metric_name][context_key].append(point.value)
        
        # Keep recent values
        if len(self.context_patterns[metric_name][context_key]) > 50:
            self.context_patterns[metric_name][context_key] = \
                self.context_patterns[metric_name][context_key][-50:]
        
        return self._detect_contextual_anomaly(metric_name, point, context_key)
    
    def _detect_contextual_anomaly(
        self,
        metric_name: str,
        point: DataPoint,
        context_key: str,
    ) -> Optional[AnomalyScore]:
        """Detect anomaly in context."""
        values = self.context_patterns[metric_name][context_key]
        
        if len(values) < 3:
            return None
        
        historical = values[:-1]
        current = values[-1]
        
        mean = statistics.mean(historical)
        if len(historical) > 1:
            stdev = statistics.stdev(historical)
        else:
            stdev = 0
        
        if stdev == 0 or current == mean:
            return None
        
        deviation = abs(current - mean) / stdev if stdev > 0 else 0
        
        if deviation > 2.5:  # Context-specific threshold
            return AnomalyScore(
                timestamp=point.timestamp,
                anomaly_type=AnomalyType.CONTEXTUAL,
                score=min(100.0, (deviation / 2.5) * 100),
                severity=AnomalySeverity.WARNING if deviation < 3.5 else AnomalySeverity.ERROR,
                confidence=min(1.0, deviation / 5.0),
                details={
                    "context": context_key,
                    "expected_mean": mean,
                    "actual": current,
                    "deviation": deviation,
                }
            )
        
        return None


class AnomalyDetectionEngine:
    """Orchestrates multiple anomaly detectors."""
    
    def __init__(self):
        """Initialize engine."""
        self.statistical_detector = StatisticalAnomalyDetector()
        self.trend_detector = TrendAnomalyDetector()
        self.multivariate_detector = MultivariteAnomalyDetector()
        self.contextual_detector = ContextualAnomalyDetector()
        self.anomaly_history: List[AnomalyScore] = []
    
    def detect_anomalies(
        self,
        metric_name: str,
        point: DataPoint,
        context_key: Optional[str] = None,
    ) -> List[AnomalyScore]:
        """Run all anomaly detectors."""
        detected_anomalies = []
        
        # Statistical detection
        stat_anomaly = self.statistical_detector.add_point(metric_name, point)
        if stat_anomaly:
            detected_anomalies.append(stat_anomaly)
        
        # Trend detection
        trend_anomaly = self.trend_detector.add_point(metric_name, point)
        if trend_anomaly:
            detected_anomalies.append(trend_anomaly)
        
        # Multivariate detection
        multi_anomaly = self.multivariate_detector.add_point(metric_name, point)
        if multi_anomaly:
            detected_anomalies.append(multi_anomaly)
        
        # Contextual detection
        if context_key:
            ctx_anomaly = self.contextual_detector.add_point_with_context(
                metric_name, point, context_key
            )
            if ctx_anomaly:
                detected_anomalies.append(ctx_anomaly)
        
        # Record all anomalies
        self.anomaly_history.extend(detected_anomalies)
        
        return detected_anomalies
    
    def get_recent_anomalies(self, limit: int = 100) -> List[AnomalyScore]:
        """Get recent anomalies."""
        return self.anomaly_history[-limit:]
    
    def get_critical_anomalies(self) -> List[AnomalyScore]:
        """Get all critical anomalies."""
        return [
            a for a in self.anomaly_history
            if a.severity == AnomalySeverity.CRITICAL
        ]


__all__ = [
    "AnomalyType",
    "AnomalySeverity",
    "DataPoint",
    "AnomalyScore",
    "StatisticalAnomalyDetector",
    "TrendAnomalyDetector",
    "MultivariteAnomalyDetector",
    "ContextualAnomalyDetector",
    "AnomalyDetectionEngine",
]
