"""
Predictive Scaling & Forecasting Engine (Phase 27B)

ML-based resource forecasting and auto-scaling recommendations using:
- Linear regression forecasting
- Seasonal pattern analysis
- Workload trend detection
- Capacity planning
- Multi-horizon predictions

Part of Observability Platform v1.0.0
"""

import math
import statistics
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple


class ForecastHorizon(Enum):
    """Forecast time horizons."""
    
    ONE_HOUR = "1h"
    FOUR_HOURS = "4h"
    ONE_DAY = "24h"
    ONE_WEEK = "7d"


class ScalingAction(Enum):
    """Scaling recommendation actions."""
    
    SCALE_UP = "scale_up"
    SCALE_DOWN = "scale_down"
    MAINTAIN = "maintain"


@dataclass
class MetricPoint:
    """Single resource metric data point."""
    
    timestamp: datetime
    value: float  # Percentage or count
    resource_type: str = "cpu"
    instance_id: str = ""


@dataclass
class Forecast:
    """Forecast prediction result."""
    
    metric_name: str
    horizon: ForecastHorizon
    forecast_time: datetime
    predicted_value: float
    confidence_80: Tuple[float, float]  # (lower, upper)
    confidence_95: Tuple[float, float]
    confidence_99: Tuple[float, float]
    trend: str  # "increasing", "decreasing", "stable"
    seasonality_detected: bool


@dataclass
class ScalingRecommendation:
    """Resource scaling recommendation."""
    
    resource_type: str
    action: ScalingAction
    current_utilization: float
    predicted_utilization: float
    scale_factor: float  # 1.0 = no change, 2.0 = double, 0.5 = halve
    confidence: float  # 0-1
    reasoning: str
    cost_impact: float  # Estimated cost change percentage
    created_at: datetime = field(default_factory=datetime.utcnow)


@dataclass
class CapacityPlan:
    """Capacity planning report."""
    
    planning_horizon: ForecastHorizon
    resource_type: str
    current_capacity: float
    forecasted_demand: float
    recommended_capacity: float
    saturation_risk: float  # 0-1, higher = more risk
    recommended_actions: List[ScalingRecommendation] = field(default_factory=list)
    cost_projection: float = 0.0
    created_at: datetime = field(default_factory=datetime.utcnow)


class WorkloadForecaster:
    """Workload pattern recognition and forecasting."""
    
    def __init__(self):
        """Initialize forecaster."""
        self.workload_history: Dict[str, List[MetricPoint]] = {}
        self.patterns: Dict[str, Dict[str, Any]] = {}
    
    def add_metric_point(
        self,
        metric_name: str,
        value: float,
        timestamp: Optional[datetime] = None,
        resource_type: str = "cpu"
    ) -> None:
        """Add metric data point."""
        if metric_name not in self.workload_history:
            self.workload_history[metric_name] = []
        
        if timestamp is None:
            timestamp = datetime.utcnow()
        
        point = MetricPoint(timestamp=timestamp, value=value, resource_type=resource_type)
        self.workload_history[metric_name].append(point)
        
        # Keep reasonable size
        max_points = 5000
        if len(self.workload_history[metric_name]) > max_points:
            self.workload_history[metric_name] = self.workload_history[metric_name][-max_points:]
    
    def detect_patterns(self, metric_name: str) -> Dict[str, Any]:
        """Detect workload patterns."""
        if metric_name not in self.workload_history:
            return {}
        
        history = self.workload_history[metric_name]
        if len(history) < 24:
            return {}
        
        values = [p.value for p in history]
        
        # Detect peak hours (highest average in hour windows)
        hourly_windows = {}
        for point in history:
            hour = point.timestamp.hour
            if hour not in hourly_windows:
                hourly_windows[hour] = []
            hourly_windows[hour].append(point.value)
        
        peak_hours = sorted(
            hourly_windows.items(),
            key=lambda x: statistics.mean(x[1]),
            reverse=True
        )[:3]
        
        # Detect day-of-week patterns
        dow_windows = {}
        for point in history:
            dow = point.timestamp.weekday()
            if dow not in dow_windows:
                dow_windows[dow] = []
            dow_windows[dow].append(point.value)
        
        # Trend detection
        if len(values) > 10:
            trend_values = values[-10:]
            trend_up = sum(1 for i in range(1, len(trend_values))
                          if trend_values[i] > trend_values[i-1])
            trend = "increasing" if trend_up > 5 else ("decreasing" if trend_up < 3 else "stable")
        else:
            trend = "stable"
        
        pattern = {
            'peak_hours': [h for h, _ in peak_hours],
            'avg_peak_value': statistics.mean([values[h] for h, _ in peak_hours]) if peak_hours else 0,
            'avg_off_peak_value': statistics.mean(values),
            'trend': trend,
            'volatility': statistics.stdev(values) if len(values) > 1 else 0,
            'min_value': min(values),
            'max_value': max(values)
        }
        
        self.patterns[metric_name] = pattern
        return pattern
    
    def forecast(
        self,
        metric_name: str,
        horizon: ForecastHorizon = ForecastHorizon.ONE_HOUR
    ) -> Optional[Forecast]:
        """Forecast metric value."""
        if metric_name not in self.workload_history:
            return None
        
        history = self.workload_history[metric_name]
        if len(history) < 24:
            return None
        
        # Ensure patterns detected
        if metric_name not in self.patterns:
            self.detect_patterns(metric_name)
        
        pattern = self.patterns.get(metric_name, {})
        values = [p.value for p in history]
        
        # Simple linear regression for trend
        n = len(values)
        x_values = list(range(n))
        mean_x = statistics.mean(x_values)
        mean_y = statistics.mean(values)
        
        numerator = sum((x_values[i] - mean_x) * (values[i] - mean_y) for i in range(n))
        denominator = sum((x_values[i] - mean_x) ** 2 for i in range(n))
        
        if denominator == 0:
            slope = 0
        else:
            slope = numerator / denominator
        
        intercept = mean_y - slope * mean_x
        
        # Forecast based on horizon
        horizon_multiplier = {
            ForecastHorizon.ONE_HOUR: 1,
            ForecastHorizon.FOUR_HOURS: 4,
            ForecastHorizon.ONE_DAY: 24,
            ForecastHorizon.ONE_WEEK: 168
        }
        
        multiplier = horizon_multiplier.get(horizon, 1)
        projected_x = n + (multiplier * 4)  # 15-min intervals
        predicted_value = intercept + slope * projected_x
        predicted_value = max(0, min(100, predicted_value))  # Clamp 0-100
        
        # Calculate confidence intervals
        residuals = [(values[i] - (intercept + slope * x_values[i])) ** 2 for i in range(n)]
        std_error = math.sqrt(statistics.mean(residuals)) if residuals else 0
        
        margin_80 = 1.282 * std_error
        margin_95 = 1.96 * std_error
        margin_99 = 2.576 * std_error
        
        trend = pattern.get('trend', 'stable')
        seasonality = len(pattern.get('peak_hours', [])) > 0
        
        return Forecast(
            metric_name=metric_name,
            horizon=horizon,
            forecast_time=datetime.utcnow() + timedelta(hours=horizon_multiplier.get(horizon, 1)),
            predicted_value=predicted_value,
            confidence_80=(max(0, predicted_value - margin_80), min(100, predicted_value + margin_80)),
            confidence_95=(max(0, predicted_value - margin_95), min(100, predicted_value + margin_95)),
            confidence_99=(max(0, predicted_value - margin_99), min(100, predicted_value + margin_99)),
            trend=trend,
            seasonality_detected=seasonality
        )


class PredictiveScaler:
    """Predictive auto-scaling engine."""
    
    def __init__(self):
        """Initialize scaler."""
        self.forecaster = WorkloadForecaster()
        self.scaling_history: List[ScalingRecommendation] = []
        self.thresholds = {
            'scale_up': 75.0,      # Scale up when > 75%
            'scale_down': 30.0,    # Scale down when < 30%
            'critical': 90.0       # Critical level
        }
        self._stats = {
            'recommendations_made': 0,
            'scale_ups': 0,
            'scale_downs': 0,
            'maintains': 0
        }
    
    def add_metric(
        self,
        metric_name: str,
        value: float,
        resource_type: str = "cpu"
    ) -> None:
        """Add metric data."""
        self.forecaster.add_metric_point(metric_name, value, resource_type=resource_type)
    
    def get_scaling_recommendation(
        self,
        metric_name: str,
        current_value: float
    ) -> Optional[ScalingRecommendation]:
        """Get scaling recommendation."""
        # Get forecast
        forecast = self.forecaster.forecast(metric_name, ForecastHorizon.FOUR_HOURS)
        if not forecast:
            return None
        
        self._stats['recommendations_made'] += 1
        
        # Determine action
        confidence = 0.8  # Base confidence
        
        if forecast.predicted_value > self.thresholds['critical']:
            action = ScalingAction.SCALE_UP
            scale_factor = 1.5  # 50% increase
            confidence = 0.95
            reasoning = "Critical utilization predicted"
            self._stats['scale_ups'] += 1
        elif forecast.predicted_value > self.thresholds['scale_up']:
            action = ScalingAction.SCALE_UP
            scale_factor = 1.25  # 25% increase
            reasoning = "High utilization predicted"
            self._stats['scale_ups'] += 1
        elif forecast.predicted_value < self.thresholds['scale_down']:
            action = ScalingAction.SCALE_DOWN
            scale_factor = 0.75  # 25% decrease
            reasoning = "Low utilization predicted"
            self._stats['scale_downs'] += 1
        else:
            action = ScalingAction.MAINTAIN
            scale_factor = 1.0
            reasoning = "Utilization within normal range"
            self._stats['maintains'] += 1
        
        # Estimate cost impact
        if action == ScalingAction.SCALE_UP:
            cost_impact = (scale_factor - 1.0) * 100
        elif action == ScalingAction.SCALE_DOWN:
            cost_impact = (1.0 - scale_factor) * -100
        else:
            cost_impact = 0.0
        
        recommendation = ScalingRecommendation(
            resource_type=forecast.metric_name,
            action=action,
            current_utilization=current_value,
            predicted_utilization=forecast.predicted_value,
            scale_factor=scale_factor,
            confidence=confidence,
            reasoning=reasoning,
            cost_impact=cost_impact
        )
        
        self.scaling_history.append(recommendation)
        return recommendation
    
    def set_thresholds(
        self,
        scale_up: float = 75.0,
        scale_down: float = 30.0,
        critical: float = 90.0
    ) -> None:
        """Set scaling thresholds."""
        self.thresholds = {
            'scale_up': scale_up,
            'scale_down': scale_down,
            'critical': critical
        }
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get scaler statistics."""
        return {
            'recommendations_made': self._stats['recommendations_made'],
            'scale_ups': self._stats['scale_ups'],
            'scale_downs': self._stats['scale_downs'],
            'maintains': self._stats['maintains'],
            'scaling_history_size': len(self.scaling_history),
            'forecasts_available': len(self.forecaster.patterns)
        }


class CapacityPlanner:
    """Capacity planning for resource management."""
    
    def __init__(self):
        """Initialize planner."""
        self.scaler = PredictiveScaler()
        self.capacity_reports: List[CapacityPlan] = []
    
    def add_metric(
        self,
        metric_name: str,
        value: float,
        resource_type: str = "cpu"
    ) -> None:
        """Add metric data."""
        self.scaler.add_metric(metric_name, value, resource_type)
    
    def plan_capacity(
        self,
        metric_name: str,
        current_capacity: float,
        horizon: ForecastHorizon = ForecastHorizon.ONE_WEEK
    ) -> Optional[CapacityPlan]:
        """Generate capacity plan."""
        forecast = self.scaler.forecaster.forecast(metric_name, horizon)
        if not forecast:
            return None
        
        # Get current utilization
        if metric_name not in self.scaler.forecaster.workload_history:
            return None
        
        current_util = self.scaler.forecaster.workload_history[metric_name][-1].value
        
        # Calculate saturation risk
        if forecast.predicted_value > 85:
            saturation_risk = 0.9
        elif forecast.predicted_value > 70:
            saturation_risk = 0.6
        elif forecast.predicted_value > 50:
            saturation_risk = 0.3
        else:
            saturation_risk = 0.1
        
        # Calculate recommended capacity
        if saturation_risk > 0.7:
            recommended_capacity = current_capacity * 1.5
        elif saturation_risk > 0.4:
            recommended_capacity = current_capacity * 1.25
        elif forecast.predicted_value < 30:
            recommended_capacity = current_capacity * 0.8
        else:
            recommended_capacity = current_capacity
        
        # Generate scaling recommendation
        recommendation = self.scaler.get_scaling_recommendation(
            metric_name,
            current_util
        )
        
        # Cost projection (simplified)
        cost_projection = (recommended_capacity - current_capacity) / current_capacity * 100
        
        plan = CapacityPlan(
            planning_horizon=horizon,
            resource_type=metric_name,
            current_capacity=current_capacity,
            forecasted_demand=forecast.predicted_value,
            recommended_capacity=recommended_capacity,
            saturation_risk=saturation_risk,
            recommended_actions=[recommendation] if recommendation else [],
            cost_projection=cost_projection
        )
        
        self.capacity_reports.append(plan)
        return plan
    
    def get_capacity_report(
        self,
        metric_name: Optional[str] = None,
        limit: int = 50
    ) -> List[CapacityPlan]:
        """Get capacity plans."""
        plans = self.capacity_reports
        
        if metric_name:
            plans = [p for p in plans if p.resource_type == metric_name]
        
        # Sort by creation time descending
        plans.sort(key=lambda p: p.created_at, reverse=True)
        
        return plans[:limit]
