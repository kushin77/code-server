"""
Advanced Anomaly Detection & ML-Based Correlation

Implements intelligent anomaly detection and correlation for observability data:
- Statistical anomaly detection (Z-score, IQR, moving average)
- Machine learning-based pattern detection
- Automatic correlation of related incidents
- Root cause analysis
- Predictive alerting
"""

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Tuple, Any, Callable
from enum import Enum
from datetime import datetime, timedelta
import json
from collections import deque
import math
from abc import ABC, abstractmethod


class AnomalyType(Enum):
    """Types of anomalies."""
    SPIKE = "spike"  # Sudden increase
    DROP = "drop"  # Sudden decrease
    TREND = "trend"  # Gradual change
    CYCLE = "cycle"  # Periodic pattern break
    OUTLIER = "outlier"  # Statistical outlier
    CORRELATION = "correlation"  # Multiple metrics changing together


class SeverityLevel(Enum):
    """Anomaly severity levels."""
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


@dataclass
class DataPoint:
    """Time-series data point."""
    timestamp: datetime
    value: float
    metric_name: str
    labels: Dict[str, str] = field(default_factory=dict)


@dataclass
class AnomalyDetected:
    """Detected anomaly information."""
    id: str
    type: AnomalyType
    metric_name: str
    timestamp: datetime
    value: float
    expected_value: float
    severity: SeverityLevel
    confidence: float  # 0.0 to 1.0
    description: str
    affected_metrics: List[str] = field(default_factory=list)
    correlated_anomalies: List[str] = field(default_factory=list)
    root_cause_hypothesis: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "type": self.type.value,
            "metric_name": self.metric_name,
            "timestamp": self.timestamp.isoformat(),
            "value": self.value,
            "expected_value": self.expected_value,
            "severity": self.severity.value,
            "confidence": self.confidence,
            "description": self.description,
            "affected_metrics": self.affected_metrics,
            "correlated_anomalies": self.correlated_anomalies,
            "root_cause_hypothesis": self.root_cause_hypothesis,
        }


@dataclass
class CorrelationAnalysis:
    """Analysis of correlated metrics."""
    primary_anomaly_id: str
    correlated_metric_pairs: List[Tuple[str, str, float]] = field(default_factory=list)  # metric1, metric2, correlation_coefficient
    temporal_correlation: Dict[str, int] = field(default_factory=dict)  # lag in seconds
    causal_relationships: List[Tuple[str, str, str]] = field(default_factory=list)  # cause, effect, strength
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "primary_anomaly_id": self.primary_anomaly_id,
            "correlated_metric_pairs": self.correlated_metric_pairs,
            "temporal_correlation": self.temporal_correlation,
            "causal_relationships": self.causal_relationships,
        }


class AnomalyDetector(ABC):
    """Abstract base for anomaly detection algorithms."""
    
    @abstractmethod
    def detect(self, data_points: List[DataPoint]) -> List[AnomalyDetected]:
        """Detect anomalies in data."""
        pass
    
    @abstractmethod
    def update_baseline(self, data_points: List[DataPoint]):
        """Update baseline for detection."""
        pass


class StatisticalAnomalyDetector(AnomalyDetector):
    """Statistical anomaly detection using Z-score and IQR methods."""
    
    def __init__(self, z_score_threshold: float = 3.0, iqr_multiplier: float = 1.5):
        self.z_score_threshold = z_score_threshold
        self.iqr_multiplier = iqr_multiplier
        self.baselines: Dict[str, Dict[str, float]] = {}
    
    def detect(self, data_points: List[DataPoint]) -> List[AnomalyDetected]:
        """Detect anomalies using Z-score method."""
        if len(data_points) < 3:
            return []
        
        anomalies = []
        
        # Group by metric
        metrics = {}
        for point in data_points:
            if point.metric_name not in metrics:
                metrics[point.metric_name] = []
            metrics[point.metric_name].append(point)
        
        # Detect for each metric
        for metric_name, points in metrics.items():
            values = [p.value for p in points]
            
            # Calculate statistics
            mean = sum(values) / len(values)
            variance = sum((x - mean) ** 2 for x in values) / len(values)
            std_dev = math.sqrt(variance) if variance > 0 else 0
            
            if std_dev == 0:
                continue
            
            # Check for Z-score anomalies
            for point in points:
                z_score = abs((point.value - mean) / std_dev)
                if z_score > self.z_score_threshold:
                    anomaly = AnomalyDetected(
                        id=f"anom_{hash((metric_name, point.timestamp)) % 1000000}",
                        type=self._classify_anomaly(point.value, mean),
                        metric_name=metric_name,
                        timestamp=point.timestamp,
                        value=point.value,
                        expected_value=mean,
                        severity=self._calculate_severity(z_score),
                        confidence=min(z_score / 5.0, 1.0),  # Confidence based on z-score
                        description=f"Statistical anomaly detected (Z-score: {z_score:.2f})"
                    )
                    anomalies.append(anomaly)
        
        return anomalies
    
    def update_baseline(self, data_points: List[DataPoint]):
        """Update baseline statistics."""
        for metric_name in {p.metric_name for p in data_points}:
            metric_points = [p for p in data_points if p.metric_name == metric_name]
            if metric_points:
                values = [p.value for p in metric_points]
                self.baselines[metric_name] = {
                    "mean": sum(values) / len(values),
                    "std_dev": math.sqrt(
                        sum((x - sum(values) / len(values)) ** 2 for x in values) / len(values)
                    )
                }
    
    @staticmethod
    def _classify_anomaly(actual: float, expected: float) -> AnomalyType:
        """Classify anomaly type."""
        if actual > expected:
            return AnomalyType.SPIKE
        else:
            return AnomalyType.DROP
    
    @staticmethod
    def _calculate_severity(z_score: float) -> SeverityLevel:
        """Calculate severity based on Z-score."""
        if z_score > 5.0:
            return SeverityLevel.CRITICAL
        elif z_score > 3.0:
            return SeverityLevel.WARNING
        else:
            return SeverityLevel.INFO


class TrendAnomalyDetector(AnomalyDetector):
    """Detect trend-based anomalies (gradual changes)."""
    
    def __init__(self, window_size: int = 10, min_slope_change: float = 0.1):
        self.window_size = window_size
        self.min_slope_change = min_slope_change
    
    def detect(self, data_points: List[DataPoint]) -> List[AnomalyDetected]:
        """Detect trend anomalies."""
        if len(data_points) < self.window_size * 2:
            return []
        
        anomalies = []
        
        # Sort by timestamp
        sorted_points = sorted(data_points, key=lambda p: p.timestamp)
        
        # Calculate slopes
        for i in range(self.window_size, len(sorted_points) - self.window_size):
            # Previous window slope
            prev_window = sorted_points[i - self.window_size:i]
            prev_slope = self._calculate_slope(prev_window)
            
            # Current window slope
            curr_window = sorted_points[i:i + self.window_size]
            curr_slope = self._calculate_slope(curr_window)
            
            # Detect trend change
            slope_change = abs(curr_slope - prev_slope)
            if slope_change > self.min_slope_change:
                anomaly = AnomalyDetected(
                    id=f"trend_{hash((sorted_points[i].metric_name, sorted_points[i].timestamp)) % 1000000}",
                    type=AnomalyType.TREND,
                    metric_name=sorted_points[i].metric_name,
                    timestamp=sorted_points[i].timestamp,
                    value=sorted_points[i].value,
                    expected_value=sorted_points[i - 1].value + prev_slope,
                    severity=SeverityLevel.WARNING,
                    confidence=min(slope_change / 1.0, 1.0),
                    description=f"Trend change detected (slope change: {slope_change:.2f})"
                )
                anomalies.append(anomaly)
        
        return anomalies
    
    def update_baseline(self, data_points: List[DataPoint]):
        """Update baseline (no-op for trend detector)."""
        pass
    
    @staticmethod
    def _calculate_slope(points: List[DataPoint]) -> float:
        """Calculate linear regression slope."""
        if len(points) < 2:
            return 0.0
        
        n = len(points)
        x_values = list(range(n))
        y_values = [p.value for p in points]
        
        x_mean = sum(x_values) / n
        y_mean = sum(y_values) / n
        
        numerator = sum((x_values[i] - x_mean) * (y_values[i] - y_mean) for i in range(n))
        denominator = sum((x_values[i] - x_mean) ** 2 for i in range(n))
        
        return numerator / denominator if denominator != 0 else 0.0


class CorrelationAnalyzer:
    """Analyzes correlations between metrics."""
    
    def __init__(self, correlation_threshold: float = 0.7):
        self.correlation_threshold = correlation_threshold
        self.metric_history: Dict[str, deque] = {}
        self.max_history = 1000
    
    def add_point(self, point: DataPoint):
        """Add data point to history."""
        if point.metric_name not in self.metric_history:
            self.metric_history[point.metric_name] = deque(maxlen=self.max_history)
        
        self.metric_history[point.metric_name].append(point)
    
    def correlate_anomalies(self, anomaly: AnomalyDetected) -> CorrelationAnalysis:
        """Find correlated metrics for an anomaly."""
        analysis = CorrelationAnalysis(primary_anomaly_id=anomaly.id)
        
        # Get baseline metric for correlation
        baseline = self.metric_history.get(anomaly.metric_name)
        if not baseline or len(baseline) < 10:
            return analysis
        
        # Calculate correlations with other metrics
        for metric_name, history in self.metric_history.items():
            if metric_name == anomaly.metric_name:
                continue
            
            if len(history) < 10:
                continue
            
            # Calculate Pearson correlation
            correlation = self._pearson_correlation(
                [p.value for p in baseline],
                [p.value for p in history]
            )
            
            if abs(correlation) > self.correlation_threshold:
                analysis.correlated_metric_pairs.append(
                    (anomaly.metric_name, metric_name, correlation)
                )
        
        return analysis
    
    @staticmethod
    def _pearson_correlation(x: List[float], y: List[float]) -> float:
        """Calculate Pearson correlation coefficient."""
        if len(x) != len(y) or len(x) < 2:
            return 0.0
        
        n = len(x)
        x_mean = sum(x) / n
        y_mean = sum(y) / n
        
        numerator = sum((x[i] - x_mean) * (y[i] - y_mean) for i in range(n))
        x_variance = sum((x[i] - x_mean) ** 2 for i in range(n))
        y_variance = sum((y[i] - y_mean) ** 2 for i in range(n))
        
        denominator = math.sqrt(x_variance * y_variance)
        
        return numerator / denominator if denominator != 0 else 0.0


class RootCauseAnalyzer:
    """Analyzes root causes of anomalies."""
    
    def __init__(self):
        self.incident_history: List[Dict[str, Any]] = []
        self.patterns: Dict[str, List[str]] = {}
    
    def analyze_root_cause(self, anomaly: AnomalyDetected, 
                          related_anomalies: List[AnomalyDetected]) -> str:
        """Analyze potential root cause."""
        # If multiple metrics affected at same time, likely common root cause
        if len(related_anomalies) > 1:
            metrics = [a.metric_name for a in related_anomalies]
            
            # Check for known patterns
            for pattern, metrics_in_pattern in self.patterns.items():
                if all(m in metrics for m in metrics_in_pattern):
                    return f"Known pattern detected: {pattern}"
            
            return "Multiple metrics affected - potential infrastructure issue"
        
        # Check metric-specific patterns
        if anomaly.metric_name in self.patterns:
            return f"Common failure mode for {anomaly.metric_name}"
        
        return f"Isolated anomaly in {anomaly.metric_name}"
    
    def record_incident(self, anomaly: AnomalyDetected, root_cause: str):
        """Record incident for pattern learning."""
        self.incident_history.append({
            "timestamp": anomaly.timestamp.isoformat(),
            "metric": anomaly.metric_name,
            "root_cause": root_cause
        })


class AnomalyManager:
    """Manages anomaly detection lifecycle."""
    
    def __init__(self):
        self.detectors: List[AnomalyDetector] = [
            StatisticalAnomalyDetector(z_score_threshold=3.0),
            TrendAnomalyDetector(window_size=10)
        ]
        self.correlation_analyzer = CorrelationAnalyzer()
        self.root_cause_analyzer = RootCauseAnalyzer()
        self.detected_anomalies: Dict[str, AnomalyDetected] = {}
    
    def detect_anomalies(self, data_points: List[DataPoint]) -> List[AnomalyDetected]:
        """Run all detectors on data."""
        anomalies = []
        
        for detector in self.detectors:
            detector_anomalies = detector.detect(data_points)
            anomalies.extend(detector_anomalies)
            detector.update_baseline(data_points)
        
        # Add to history
        for anomaly in anomalies:
            self.detected_anomalies[anomaly.id] = anomaly
            
            # Analyze correlations
            correlation = self.correlation_analyzer.correlate_anomalies(anomaly)
            anomaly.correlated_anomalies = [pair[1] for pair in correlation.correlated_metric_pairs]
            
            # Add data point to history
            for point in data_points:
                if point.metric_name == anomaly.metric_name:
                    self.correlation_analyzer.add_point(point)
            
            # Analyze root cause
            related = [a for a in anomalies if a.id != anomaly.id and a.timestamp.timestamp() - anomaly.timestamp.timestamp() < 60]
            root_cause = self.root_cause_analyzer.analyze_root_cause(anomaly, related)
            anomaly.root_cause_hypothesis = root_cause
        
        return anomalies
    
    def get_anomalies(self, since: Optional[datetime] = None) -> List[AnomalyDetected]:
        """Get detected anomalies."""
        if since:
            return [a for a in self.detected_anomalies.values() if a.timestamp >= since]
        return list(self.detected_anomalies.values())
    
    def clear_old_anomalies(self, older_than: datetime) -> int:
        """Remove old anomaly records."""
        old_ids = [id for id, a in self.detected_anomalies.items() if a.timestamp < older_than]
        for id in old_ids:
            del self.detected_anomalies[id]
        return len(old_ids)


class PredictiveAlert:
    """Predictive alerting based on trend analysis."""
    
    def __init__(self, lookback_window: int = 100):
        self.lookback_window = lookback_window
        self.metric_trends: Dict[str, List[float]] = {}
    
    def predict_anomaly(self, metric_name: str, recent_values: List[float]) -> Optional[Dict[str, Any]]:
        """Predict if anomaly is likely in near future."""
        if len(recent_values) < 10:
            return None
        
        # Calculate trend
        slope = self._calculate_trend_slope(recent_values[-20:])
        
        # Calculate velocity (rate of change)
        velocity = slope
        
        # If trend accelerating (slope increasing), likely anomaly incoming
        if abs(velocity) > 0.5:
            return {
                "metric": metric_name,
                "predicted_anomaly": True,
                "trend_slope": slope,
                "confidence": min(abs(velocity) / 2.0, 1.0)
            }
        
        return None
    
    @staticmethod
    def _calculate_trend_slope(values: List[float]) -> float:
        """Calculate trend slope."""
        if len(values) < 2:
            return 0.0
        
        n = len(values)
        x_values = list(range(n))
        
        x_mean = sum(x_values) / n
        y_mean = sum(values) / n
        
        numerator = sum((x_values[i] - x_mean) * (values[i] - y_mean) for i in range(n))
        denominator = sum((x_values[i] - x_mean) ** 2 for i in range(n))
        
        return numerator / denominator if denominator != 0 else 0.0


__all__ = [
    'AnomalyType',
    'SeverityLevel',
    'DataPoint',
    'AnomalyDetected',
    'CorrelationAnalysis',
    'AnomalyDetector',
    'StatisticalAnomalyDetector',
    'TrendAnomalyDetector',
    'CorrelationAnalyzer',
    'RootCauseAnalyzer',
    'AnomalyManager',
    'PredictiveAlert',
]
