"""
Phase 25B: Predictive Analytics Framework

Predictive analytics for forecasting and trend analysis:
- Time series forecasting
- Resource usage prediction
- Failure prediction
- Capacity planning

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


class PredictionType(Enum):
    """Types of predictions."""
    RESOURCE_USAGE = "resource_usage"
    FAILURE_PROBABILITY = "failure_probability"
    ANOMALY_LIKELIHOOD = "anomaly_likelihood"
    CAPACITY_NEED = "capacity_need"


class ConfidenceLevel(Enum):
    """Confidence levels for predictions."""
    LOW = 0.6
    MEDIUM = 0.75
    HIGH = 0.85
    VERY_HIGH = 0.95


@dataclass
class Prediction:
    """A single prediction."""
    prediction_id: str
    prediction_type: PredictionType
    predicted_value: float
    confidence: float  # 0-1
    prediction_time: datetime
    valid_until: datetime
    details: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def is_confident(self) -> bool:
        """Check if prediction is confident."""
        return self.confidence > 0.75
    
    @property
    def time_remaining_seconds(self) -> int:
        """Get time until prediction expires."""
        return int((self.valid_until - datetime.utcnow()).total_seconds())


class SimpleMovingAveragePredictor:
    """Simple moving average based predictor."""
    
    def __init__(self, window_size: int = 10):
        """Initialize predictor."""
        self.window_size = window_size
        self.history: Dict[str, List[float]] = {}
    
    def add_sample(self, metric_name: str, value: float) -> None:
        """Add sample to history."""
        if metric_name not in self.history:
            self.history[metric_name] = []
        
        self.history[metric_name].append(value)
        
        # Keep only recent samples
        if len(self.history[metric_name]) > self.window_size:
            self.history[metric_name] = self.history[metric_name][-self.window_size:]
    
    def predict(self, metric_name: str, periods_ahead: int = 1) -> Optional[Tuple[float, float]]:
        """Predict future value."""
        if metric_name not in self.history or len(self.history[metric_name]) < 3:
            return None
        
        values = self.history[metric_name]
        avg = statistics.mean(values)
        
        # Confidence based on variance
        if len(values) > 1:
            variance = statistics.variance(values)
            std_dev = math.sqrt(variance)
            cv = std_dev / avg if avg > 0 else 0  # Coefficient of variation
            confidence = max(0.5, 1.0 - cv)
        else:
            confidence = 0.5
        
        return avg, confidence


class ExponentialSmoothingPredictor:
    """Exponential smoothing predictor."""
    
    def __init__(self, alpha: float = 0.3, beta: float = 0.1):
        """Initialize predictor."""
        self.alpha = alpha  # Level smoothing
        self.beta = beta    # Trend smoothing
        self.level: Dict[str, float] = {}
        self.trend: Dict[str, float] = {}
        self.history: Dict[str, List[float]] = {}
    
    def add_sample(self, metric_name: str, value: float) -> None:
        """Add sample."""
        if metric_name not in self.history:
            self.history[metric_name] = []
            self.level[metric_name] = value
            self.trend[metric_name] = 0.0
        
        self.history[metric_name].append(value)
        
        # Update level and trend
        prev_level = self.level[metric_name]
        self.level[metric_name] = self.alpha * value + (1 - self.alpha) * (prev_level + self.trend[metric_name])
        self.trend[metric_name] = self.beta * (self.level[metric_name] - prev_level) + (1 - self.beta) * self.trend[metric_name]
    
    def predict(self, metric_name: str, periods_ahead: int = 1) -> Optional[Tuple[float, float]]:
        """Predict future value."""
        if metric_name not in self.level:
            return None
        
        predicted_value = self.level[metric_name] + periods_ahead * self.trend[metric_name]
        
        # Confidence decreases with forecast horizon
        confidence = max(0.5, 1.0 - (periods_ahead * 0.1))
        
        return predicted_value, confidence


class LinearRegressionPredictor:
    """Linear regression based predictor."""
    
    def __init__(self, window_size: int = 20):
        """Initialize predictor."""
        self.window_size = window_size
        self.history: Dict[str, List[Tuple[int, float]]] = {}
        self.sample_count: Dict[str, int] = {}
    
    def add_sample(self, metric_name: str, value: float) -> None:
        """Add sample."""
        if metric_name not in self.history:
            self.history[metric_name] = []
            self.sample_count[metric_name] = 0
        
        self.sample_count[metric_name] += 1
        self.history[metric_name].append((self.sample_count[metric_name], value))
        
        # Keep recent samples
        if len(self.history[metric_name]) > self.window_size:
            self.history[metric_name] = self.history[metric_name][-self.window_size:]
    
    def predict(self, metric_name: str, periods_ahead: int = 1) -> Optional[Tuple[float, float]]:
        """Predict using linear regression."""
        if metric_name not in self.history or len(self.history[metric_name]) < 3:
            return None
        
        samples = self.history[metric_name]
        x_values = [s[0] for s in samples]
        y_values = [s[1] for s in samples]
        
        # Calculate linear regression
        n = len(samples)
        x_mean = statistics.mean(x_values)
        y_mean = statistics.mean(y_values)
        
        numerator = sum((x_values[i] - x_mean) * (y_values[i] - y_mean) for i in range(n))
        denominator = sum((x_values[i] - x_mean) ** 2 for i in range(n))
        
        if denominator == 0:
            return None
        
        slope = numerator / denominator
        intercept = y_mean - slope * x_mean
        
        # Predict
        next_x = x_values[-1] + periods_ahead
        predicted_value = slope * next_x + intercept
        
        # Calculate R-squared for confidence
        residuals = [y_values[i] - (slope * x_values[i] + intercept) for i in range(n)]
        ss_res = sum(r ** 2 for r in residuals)
        ss_tot = sum((y_values[i] - y_mean) ** 2 for i in range(n))
        
        r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0
        confidence = max(0.5, r_squared)
        
        return predicted_value, confidence


class PredictiveModel:
    """Combined predictive model."""
    
    def __init__(self):
        """Initialize model."""
        self.sma_predictor = SimpleMovingAveragePredictor()
        self.exp_predictor = ExponentialSmoothingPredictor()
        self.lr_predictor = LinearRegressionPredictor()
    
    def add_sample(self, metric_name: str, value: float) -> None:
        """Add sample to all predictors."""
        self.sma_predictor.add_sample(metric_name, value)
        self.exp_predictor.add_sample(metric_name, value)
        self.lr_predictor.add_sample(metric_name, value)
    
    def predict(self, metric_name: str, periods_ahead: int = 1) -> Optional[Prediction]:
        """Generate ensemble prediction."""
        predictions = []
        confidences = []
        
        # Get predictions from each model
        sma_pred = self.sma_predictor.predict(metric_name, periods_ahead)
        if sma_pred:
            predictions.append(sma_pred[0])
            confidences.append(sma_pred[1])
        
        exp_pred = self.exp_predictor.predict(metric_name, periods_ahead)
        if exp_pred:
            predictions.append(exp_pred[0])
            confidences.append(exp_pred[1])
        
        lr_pred = self.lr_predictor.predict(metric_name, periods_ahead)
        if lr_pred:
            predictions.append(lr_pred[0])
            confidences.append(lr_pred[1])
        
        if not predictions:
            return None
        
        # Ensemble: weighted average
        avg_prediction = statistics.mean(predictions)
        avg_confidence = statistics.mean(confidences)
        
        return Prediction(
            prediction_id=f"{metric_name}_{periods_ahead}",
            prediction_type=PredictionType.RESOURCE_USAGE,
            predicted_value=avg_prediction,
            confidence=avg_confidence,
            prediction_time=datetime.utcnow(),
            valid_until=datetime.utcnow() + timedelta(minutes=periods_ahead * 5),
            details={
                "sma": sma_pred[0] if sma_pred else None,
                "exp": exp_pred[0] if exp_pred else None,
                "lr": lr_pred[0] if lr_pred else None,
            }
        )


class FailureProbabilityPredictor:
    """Predicts probability of failure."""
    
    def __init__(self, failure_threshold: float = 3.0):
        """Initialize predictor."""
        self.failure_threshold = failure_threshold
        self.metric_history: Dict[str, List[float]] = {}
        self.failures: List[datetime] = []
    
    def add_sample(self, metric_name: str, value: float) -> None:
        """Add metric sample."""
        if metric_name not in self.metric_history:
            self.metric_history[metric_name] = []
        
        self.metric_history[metric_name].append(value)
        
        # Keep recent history
        if len(self.metric_history[metric_name]) > 100:
            self.metric_history[metric_name] = self.metric_history[metric_name][-100:]
    
    def record_failure(self) -> None:
        """Record failure event."""
        self.failures.append(datetime.utcnow())
    
    def predict_failure_probability(self, metric_name: str) -> Optional[Tuple[float, str]]:
        """Predict probability of imminent failure."""
        if metric_name not in self.metric_history or len(self.metric_history[metric_name]) < 5:
            return None
        
        recent_values = self.metric_history[metric_name][-10:]
        avg = statistics.mean(recent_values)
        stdev = statistics.stdev(recent_values) if len(recent_values) > 1 else 0
        
        # Simple heuristic: deviation from mean indicates risk
        current = recent_values[-1]
        deviation = abs(current - avg) / stdev if stdev > 0 else 0
        
        failure_probability = min(1.0, deviation / self.failure_threshold)
        
        if failure_probability > 0.8:
            risk_level = "critical"
        elif failure_probability > 0.5:
            risk_level = "high"
        elif failure_probability > 0.3:
            risk_level = "medium"
        else:
            risk_level = "low"
        
        return failure_probability, risk_level


class PredictiveAnalyticsEngine:
    """High-level predictive analytics engine."""
    
    def __init__(self):
        """Initialize engine."""
        self.predictive_model = PredictiveModel()
        self.failure_predictor = FailureProbabilityPredictor()
        self.predictions_history: List[Prediction] = []
    
    def add_metric_sample(self, metric_name: str, value: float) -> None:
        """Add metric sample."""
        self.predictive_model.add_sample(metric_name, value)
        self.failure_predictor.add_sample(metric_name, value)
    
    def predict_resource_usage(
        self,
        metric_name: str,
        periods_ahead: int = 1
    ) -> Optional[Prediction]:
        """Predict future resource usage."""
        prediction = self.predictive_model.predict(metric_name, periods_ahead)
        if prediction:
            self.predictions_history.append(prediction)
        return prediction
    
    def predict_failure_risk(self, metric_name: str) -> Optional[Dict[str, Any]]:
        """Predict failure risk."""
        result = self.failure_predictor.predict_failure_probability(metric_name)
        if result:
            prob, risk_level = result
            return {
                "metric_name": metric_name,
                "failure_probability": prob,
                "risk_level": risk_level,
                "timestamp": datetime.utcnow().isoformat(),
            }
        return None
    
    def get_predictions_summary(self) -> Dict[str, Any]:
        """Get predictions summary."""
        recent_predictions = self.predictions_history[-100:] if self.predictions_history else []
        
        confident_predictions = [p for p in recent_predictions if p.is_confident]
        
        return {
            "total_predictions": len(recent_predictions),
            "confident_predictions": len(confident_predictions),
            "avg_confidence": statistics.mean(p.confidence for p in recent_predictions) if recent_predictions else 0,
            "latest_predictions": [
                {
                    "metric": p.prediction_id,
                    "value": p.predicted_value,
                    "confidence": p.confidence,
                }
                for p in recent_predictions[-10:]
            ]
        }


__all__ = [
    "PredictionType",
    "ConfidenceLevel",
    "Prediction",
    "SimpleMovingAveragePredictor",
    "ExponentialSmoothingPredictor",
    "LinearRegressionPredictor",
    "PredictiveModel",
    "FailureProbabilityPredictor",
    "PredictiveAnalyticsEngine",
]
