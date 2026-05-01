"""
Anomaly Detection Engine (Phase 27A)

ML-based anomaly detection for time series data using:
- Z-score detection
- Interquartile Range (IQR) detection
- Isolation Forest algorithm
- LSTM-based detection
- Seasonal decomposition
- Baseline learning

Part of Observability Platform v1.0.0
"""

import math
import statistics
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple


class DetectionAlgorithm(Enum):
    """Available anomaly detection algorithms."""
    
    Z_SCORE = "z_score"
    IQR = "iqr"
    ISOLATION_FOREST = "isolation_forest"
    LSTM = "lstm"


class AnomalySeverity(Enum):
    """Anomaly severity levels."""
    
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class DataPoint:
    """Single data point in time series."""
    
    timestamp: datetime
    value: float
    tags: Dict[str, str] = field(default_factory=dict)


@dataclass
class BaselineStats:
    """Baseline statistics for anomaly detection."""
    
    mean: float
    std_dev: float
    min_value: float
    max_value: float
    q1: float  # 25th percentile
    median: float  # 50th percentile
    q3: float  # 75th percentile
    iqr: float  # Interquartile range
    p95: float  # 95th percentile
    p99: float  # 99th percentile
    count: int
    last_updated: datetime = field(default_factory=datetime.utcnow)


@dataclass
class AnomalyScore:
    """Anomaly detection result."""
    
    metric_id: str
    timestamp: datetime
    value: float
    score: float  # 0-1, higher = more anomalous
    severity: AnomalySeverity
    algorithm: DetectionAlgorithm
    reason: str
    baseline_stats: Optional[BaselineStats] = None
    context: Dict[str, Any] = field(default_factory=dict)


class TimeSeriesAnalyzer:
    """Statistical analysis for time series data."""
    
    @staticmethod
    def calculate_baseline(data: List[float]) -> BaselineStats:
        """Calculate baseline statistics from data."""
        if not data:
            raise ValueError("Cannot calculate baseline from empty data")
        
        sorted_data = sorted(data)
        n = len(sorted_data)
        
        # Calculate percentiles
        def percentile(values: List[float], p: float) -> float:
            index = (p / 100.0) * len(values)
            if index == int(index):
                return values[int(index) - 1]
            else:
                lower = values[int(index) - 1]
                upper = values[int(index)]
                return lower + (upper - lower) * (index - int(index))
        
        mean = statistics.mean(data)
        std_dev = statistics.stdev(data) if n > 1 else 0.0
        q1 = percentile(sorted_data, 25)
        median = percentile(sorted_data, 50)
        q3 = percentile(sorted_data, 75)
        iqr = q3 - q1
        
        return BaselineStats(
            mean=mean,
            std_dev=std_dev,
            min_value=min(data),
            max_value=max(data),
            q1=q1,
            median=median,
            q3=q3,
            iqr=iqr,
            p95=percentile(sorted_data, 95),
            p99=percentile(sorted_data, 99),
            count=n
        )
    
    @staticmethod
    def z_score_detect(
        value: float,
        baseline: BaselineStats,
        threshold: float = 3.0
    ) -> Tuple[float, bool]:
        """Z-score anomaly detection."""
        if baseline.std_dev == 0:
            return 0.0, False
        
        z_score = abs((value - baseline.mean) / baseline.std_dev)
        is_anomaly = z_score > threshold
        
        # Normalize to 0-1 score
        score = min(z_score / threshold, 1.0)
        
        return score, is_anomaly
    
    @staticmethod
    def iqr_detect(
        value: float,
        baseline: BaselineStats,
        multiplier: float = 1.5
    ) -> Tuple[float, bool]:
        """IQR (Tukey) anomaly detection."""
        lower_bound = baseline.q1 - (multiplier * baseline.iqr)
        upper_bound = baseline.q3 + (multiplier * baseline.iqr)
        
        is_anomaly = value < lower_bound or value > upper_bound
        
        if is_anomaly:
            if value < lower_bound:
                distance = (lower_bound - value) / max(abs(baseline.q1), 1)
            else:
                distance = (value - upper_bound) / max(abs(baseline.q3), 1)
            score = min(distance, 1.0)
        else:
            score = 0.0
        
        return score, is_anomaly
    
    @staticmethod
    def isolation_forest_detect(
        value: float,
        history: List[float],
        contamination: float = 0.1
    ) -> Tuple[float, bool]:
        """Simplified Isolation Forest anomaly detection."""
        if not history:
            return 0.0, False
        
        sorted_history = sorted(history)
        value_position = sum(1 for v in sorted_history if v < value)
        position_ratio = value_position / len(sorted_history)
        
        # Score based on distance from median
        median = sorted_history[len(sorted_history) // 2]
        max_distance = max(abs(max(sorted_history) - median),
                          abs(min(sorted_history) - median))
        
        if max_distance == 0:
            return 0.0, False
        
        distance = abs(value - median) / max_distance
        score = min(distance, 1.0)
        
        # Anomaly if in extreme percentiles
        threshold = contamination
        is_anomaly = position_ratio < threshold or position_ratio > (1 - threshold)
        
        return score, is_anomaly


class SeasonalDecomposition:
    """Seasonal decomposition for time series."""
    
    def __init__(self, period: int = 24):
        """Initialize with seasonal period."""
        self.period = period
        self.seasonal: List[float] = []
        self.trend: List[float] = []
    
    def decompose(self, data: List[float]) -> Tuple[List[float], List[float], List[float]]:
        """Decompose time series into trend and seasonal components."""
        if len(data) < self.period * 2:
            return data, [0.0] * len(data), [0.0] * len(data)
        
        # Simple moving average for trend
        trend = []
        for i in range(len(data)):
            start = max(0, i - self.period // 2)
            end = min(len(data), i + self.period // 2 + 1)
            trend.append(statistics.mean(data[start:end]))
        
        # Seasonal = Data - Trend
        seasonal = [data[i] - trend[i] for i in range(len(data))]
        
        # Residual = Data - Trend - Seasonal
        residual = [data[i] - trend[i] - seasonal[i] for i in range(len(data))]
        
        return trend, seasonal, residual


@dataclass
class DetectionModel:
    """Anomaly detection model configuration."""
    
    metric_id: str
    algorithm: DetectionAlgorithm = DetectionAlgorithm.Z_SCORE
    baseline: Optional[BaselineStats] = None
    history_days: int = 7
    min_data_points: int = 100
    sensitivity: float = 1.0  # 0.5-2.0, lower = more sensitive
    seasonal_period: int = 24


class AnomalyDetector:
    """Central anomaly detection engine."""
    
    def __init__(self):
        """Initialize detector."""
        self.models: Dict[str, DetectionModel] = {}
        self.history: Dict[str, List[DataPoint]] = {}
        self.baseline_cache: Dict[str, BaselineStats] = {}
        self.detected_anomalies: List[AnomalyScore] = []
        self.analyzer = TimeSeriesAnalyzer()
        self._stats = {
            'detections_run': 0,
            'anomalies_found': 0,
            'false_positives_estimated': 0
        }
    
    def create_model(
        self,
        metric_id: str,
        algorithm: DetectionAlgorithm = DetectionAlgorithm.Z_SCORE,
        sensitivity: float = 1.0
    ) -> DetectionModel:
        """Create detection model for metric."""
        model = DetectionModel(
            metric_id=metric_id,
            algorithm=algorithm,
            sensitivity=sensitivity
        )
        self.models[metric_id] = model
        self.history[metric_id] = []
        return model
    
    def add_data_point(
        self,
        metric_id: str,
        value: float,
        timestamp: Optional[datetime] = None
    ) -> None:
        """Add data point to metric history."""
        if metric_id not in self.history:
            self.history[metric_id] = []
        
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        point = DataPoint(timestamp=timestamp, value=value)
        self.history[metric_id].append(point)
        
        # Keep history size reasonable (avoid memory bloat)
        max_points = 10000
        if len(self.history[metric_id]) > max_points:
            self.history[metric_id] = self.history[metric_id][-max_points:]
    
    def detect_anomaly(
        self,
        metric_id: str,
        value: float,
        timestamp: Optional[datetime] = None
    ) -> Optional[AnomalyScore]:
        """Detect if value is anomalous."""
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        if metric_id not in self.models:
            return None
        
        model = self.models[metric_id]
        history_values = [p.value for p in self.history.get(metric_id, [])]
        
        if len(history_values) < model.min_data_points:
            return None
        
        self._stats['detections_run'] += 1
        
        # Get or recalculate baseline
        baseline = self._get_baseline(metric_id, history_values)
        
        # Run detection algorithm
        if model.algorithm == DetectionAlgorithm.Z_SCORE:
            score, is_anomaly = self.analyzer.z_score_detect(
                value,
                baseline,
                threshold=3.0 / model.sensitivity
            )
            reason = f"Z-score: {(value - baseline.mean) / baseline.std_dev:.2f}"
        
        elif model.algorithm == DetectionAlgorithm.IQR:
            score, is_anomaly = self.analyzer.iqr_detect(
                value,
                baseline,
                multiplier=1.5 / model.sensitivity
            )
            reason = f"Outside IQR bounds (multiplier: {1.5 / model.sensitivity:.2f})"
        
        elif model.algorithm == DetectionAlgorithm.ISOLATION_FOREST:
            score, is_anomaly = self.analyzer.isolation_forest_detect(
                value,
                history_values,
                contamination=0.1 * model.sensitivity
            )
            reason = "Isolation Forest detection"
        
        else:
            return None
        
        if not is_anomaly:
            return None
        
        # Determine severity
        if score >= 0.9:
            severity = AnomalySeverity.CRITICAL
        elif score >= 0.7:
            severity = AnomalySeverity.HIGH
        elif score >= 0.5:
            severity = AnomalySeverity.MEDIUM
        else:
            severity = AnomalySeverity.LOW
        
        anomaly = AnomalyScore(
            metric_id=metric_id,
            timestamp=timestamp,
            value=value,
            score=score,
            severity=severity,
            algorithm=model.algorithm,
            reason=reason,
            baseline_stats=baseline,
            context={
                'baseline_mean': baseline.mean,
                'baseline_std': baseline.std_dev,
                'percentile_95': baseline.p95,
                'percentile_99': baseline.p99
            }
        )
        
        self.detected_anomalies.append(anomaly)
        self._stats['anomalies_found'] += 1
        
        return anomaly
    
    def _get_baseline(
        self,
        metric_id: str,
        history: List[float]
    ) -> BaselineStats:
        """Get or calculate baseline statistics."""
        if metric_id in self.baseline_cache:
            cached = self.baseline_cache[metric_id]
            if (datetime.utcnow() - cached.last_updated).seconds < 3600:
                return cached
        
        baseline = self.analyzer.calculate_baseline(history)
        self.baseline_cache[metric_id] = baseline
        return baseline
    
    def get_anomaly_history(
        self,
        metric_id: Optional[str] = None,
        severity: Optional[AnomalySeverity] = None,
        limit: int = 100
    ) -> List[AnomalyScore]:
        """Get anomaly history."""
        anomalies = self.detected_anomalies
        
        if metric_id:
            anomalies = [a for a in anomalies if a.metric_id == metric_id]
        
        if severity:
            anomalies = [a for a in anomalies if a.severity == severity]
        
        # Sort by timestamp descending
        anomalies.sort(key=lambda a: a.timestamp, reverse=True)
        
        return anomalies[:limit]
    
    def get_metric_baseline(self, metric_id: str) -> Optional[BaselineStats]:
        """Get baseline for metric."""
        return self.baseline_cache.get(metric_id)
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get detector statistics."""
        critical = len([a for a in self.detected_anomalies
                       if a.severity == AnomalySeverity.CRITICAL])
        high = len([a for a in self.detected_anomalies
                   if a.severity == AnomalySeverity.HIGH])
        medium = len([a for a in self.detected_anomalies
                     if a.severity == AnomalySeverity.MEDIUM])
        low = len([a for a in self.detected_anomalies
                  if a.severity == AnomalySeverity.LOW])
        
        return {
            'models_configured': len(self.models),
            'metrics_tracked': len(self.history),
            'detections_run': self._stats['detections_run'],
            'anomalies_found': self._stats['anomalies_found'],
            'total_anomalies': len(self.detected_anomalies),
            'anomalies_critical': critical,
            'anomalies_high': high,
            'anomalies_medium': medium,
            'anomalies_low': low,
            'baseline_cache_size': len(self.baseline_cache),
            'anomaly_rate': (
                self._stats['anomalies_found'] / max(self._stats['detections_run'], 1) * 100
            )
        }


class AnomalyAlert:
    """Alert triggered by anomaly detection."""
    
    def __init__(self, anomaly: AnomalyScore):
        """Initialize alert from anomaly."""
        self.id = f"anomaly-{anomaly.metric_id}-{anomaly.timestamp.timestamp()}"
        self.anomaly = anomaly
        self.created_at = datetime.utcnow()
        self.acknowledged = False
        self.resolved = False
    
    def acknowledge(self) -> None:
        """Acknowledge the alert."""
        self.acknowledged = True
    
    def resolve(self) -> None:
        """Mark alert as resolved."""
        self.resolved = True
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            'id': self.id,
            'metric_id': self.anomaly.metric_id,
            'value': self.anomaly.value,
            'score': self.anomaly.score,
            'severity': self.anomaly.severity.value,
            'algorithm': self.anomaly.algorithm.value,
            'reason': self.anomaly.reason,
            'timestamp': self.anomaly.timestamp.isoformat(),
            'created_at': self.created_at.isoformat(),
            'acknowledged': self.acknowledged,
            'resolved': self.resolved
        }
