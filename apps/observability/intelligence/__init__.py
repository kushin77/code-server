"""
Phase 25B: Intelligence & Analytics Package

Comprehensive intelligence and analytics capabilities:
- Query performance optimization
- Advanced anomaly detection
- Alerting and notifications
- Predictive analytics

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

# Query Performance Optimization
from apps.observability.intelligence.query_performance_optimizer import (
    QueryType,
    QueryCache,
    IndexType,
    IndexDefinition,
    IndexRecommendationEngine,
    QueryOptimizer,
    QueryAnalyzer,
    QueryPerformanceOptimizer,
    QueryStatistic,
    QueryExecutionPlan,
    CachedQuery,
)

# Advanced Anomaly Detection
from apps.observability.intelligence.advanced_anomaly_detection import (
    AnomalyType,
    AnomalySeverity,
    DataPoint,
    AnomalyScore,
    StatisticalAnomalyDetector,
    TrendAnomalyDetector,
    MultivariteAnomalyDetector,
    ContextualAnomalyDetector,
    AnomalyDetectionEngine,
)

# Alerting & Notifications
from apps.observability.intelligence.alerting_notifications import (
    NotificationChannel,
    AlertSeverity,
    AlertState,
    AlertRule,
    Alert,
    AlertGroup,
    NotificationHandler,
    AlertRuleEngine,
    AlertGrouper,
    EscalationPolicy,
    AlertNotificationManager,
)

# Predictive Analytics
from apps.observability.intelligence.predictive_analytics import (
    PredictionType,
    ConfidenceLevel,
    Prediction,
    SimpleMovingAveragePredictor,
    ExponentialSmoothingPredictor,
    LinearRegressionPredictor,
    PredictiveModel,
    FailureProbabilityPredictor,
    PredictiveAnalyticsEngine,
)

__version__ = "1.0.0"

__all__ = [
    # Query Performance Optimization
    "QueryType",
    "QueryCache",
    "IndexType",
    "IndexDefinition",
    "IndexRecommendationEngine",
    "QueryOptimizer",
    "QueryAnalyzer",
    "QueryPerformanceOptimizer",
    "QueryStatistic",
    "QueryExecutionPlan",
    "CachedQuery",
    
    # Advanced Anomaly Detection
    "AnomalyType",
    "AnomalySeverity",
    "DataPoint",
    "AnomalyScore",
    "StatisticalAnomalyDetector",
    "TrendAnomalyDetector",
    "MultivariteAnomalyDetector",
    "ContextualAnomalyDetector",
    "AnomalyDetectionEngine",
    
    # Alerting & Notifications
    "NotificationChannel",
    "AlertSeverity",
    "AlertState",
    "AlertRule",
    "Alert",
    "AlertGroup",
    "NotificationHandler",
    "AlertRuleEngine",
    "AlertGrouper",
    "EscalationPolicy",
    "AlertNotificationManager",
    
    # Predictive Analytics
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
