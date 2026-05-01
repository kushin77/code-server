"""
Phase 25B: Integration Tests

Integration tests for intelligence and analytics modules:
- Query optimization tests
- Anomaly detection tests
- Alert and notification tests
- Predictive analytics tests

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import pytest
from datetime import datetime, timedelta
from apps.observability.intelligence.query_performance_optimizer import (
    QueryType, QueryCache, IndexDefinition, IndexType, IndexRecommendationEngine,
    QueryOptimizer, QueryPerformanceOptimizer,
)
from apps.observability.intelligence.advanced_anomaly_detection import (
    AnomalyType, AnomalySeverity, DataPoint, StatisticalAnomalyDetector,
    TrendAnomalyDetector, AnomalyDetectionEngine,
)
from apps.observability.intelligence.alerting_notifications import (
    NotificationChannel, AlertSeverity, AlertState, AlertRule,
    Alert, AlertRuleEngine, AlertNotificationManager,
)
from apps.observability.intelligence.predictive_analytics import (
    PredictionType, SimpleMovingAveragePredictor, PredictiveModel,
    FailureProbabilityPredictor, PredictiveAnalyticsEngine,
)


class TestQueryPerformance:
    """Tests for query performance optimization."""
    
    def test_query_cache(self):
        """Test query cache."""
        cache = QueryCache(max_entries=10, max_size_mb=1)
        
        # Add entry
        cache.put("query1", {"result": [1, 2, 3]}, 100)
        
        # Retrieve entry
        result = cache.get("query1")
        assert result is not None
        assert result["result"] == [1, 2, 3]
    
    def test_query_cache_miss(self):
        """Test cache miss."""
        cache = QueryCache()
        result = cache.get("nonexistent")
        assert result is None
    
    def test_index_definition(self):
        """Test index definition."""
        index = IndexDefinition(
            index_id="idx1",
            name="service_name_idx",
            index_type=IndexType.SECONDARY,
            columns=["service_name"],
        )
        assert index.validate()
    
    def test_index_recommendation_engine(self):
        """Test index recommendation engine."""
        engine = IndexRecommendationEngine()
        
        # Record queries
        engine.record_query(
            QueryType.TRACE,
            "SELECT * FROM traces WHERE service = 'web'",
            1500,  # Slow query
            100,
            False
        )
        
        # Get recommendations
        recommendations = engine.recommend_indexes()
        assert isinstance(recommendations, list)
    
    def test_query_optimizer(self):
        """Test query optimizer."""
        cache = QueryCache()
        index_engine = IndexRecommendationEngine()
        optimizer = QueryOptimizer(cache, index_engine)
        
        # Register index
        index = IndexDefinition(
            index_id="idx1",
            name="trace_service_idx",
            index_type=IndexType.SECONDARY,
            columns=["service_name"],
        )
        assert optimizer.register_index(index)
        
        # Optimize query
        plan = optimizer.optimize_query(
            "q1",
            QueryType.TRACE,
            "SELECT * FROM traces WHERE service_name = 'web'"
        )
        assert plan is not None


class TestAnomalyDetection:
    """Tests for anomaly detection."""
    
    def test_statistical_anomaly_detector(self):
        """Test statistical anomaly detection."""
        detector = StatisticalAnomalyDetector()
        
        # Add normal points
        for i in range(10):
            point = DataPoint(
                timestamp=datetime.utcnow(),
                value=100.0 + i,
            )
            detector.add_point("cpu", point)
        
        # Add anomaly
        anomalous_point = DataPoint(
            timestamp=datetime.utcnow(),
            value=500.0,  # Spike
        )
        anomaly = detector.add_point("cpu", anomalous_point)
        assert anomaly is not None
        assert anomaly.anomaly_type == AnomalyType.SPIKE
    
    def test_trend_anomaly_detector(self):
        """Test trend anomaly detection."""
        detector = TrendAnomalyDetector()
        
        # Add points with trend
        for i in range(5):
            point = DataPoint(timestamp=datetime.utcnow(), value=100.0 + i)
            detector.add_point("metric", point)
        
        # Add points with different trend
        for i in range(5):
            point = DataPoint(timestamp=datetime.utcnow(), value=200.0 + i)
            detector.add_point("metric", point)
        
        anomaly = detector.add_point("metric", DataPoint(timestamp=datetime.utcnow(), value=210.0))
        # Trend detector should detect sustained change
    
    def test_anomaly_detection_engine(self):
        """Test full anomaly detection engine."""
        engine = AnomalyDetectionEngine()
        
        # Add samples
        for i in range(10):
            point = DataPoint(
                timestamp=datetime.utcnow(),
                value=100.0 + i + (0.1 * i),
            )
            anomalies = engine.detect_anomalies("cpu", point)
            assert isinstance(anomalies, list)


class TestAlertingNotifications:
    """Tests for alerting and notifications."""
    
    def test_alert_creation(self):
        """Test alert creation."""
        alert = Alert(
            alert_id="a1",
            rule_id="r1",
            severity=AlertSeverity.CRITICAL,
            state=AlertState.FIRING,
            title="High CPU",
            description="CPU usage is high",
            fired_at=datetime.utcnow(),
        )
        assert alert.is_active
    
    def test_alert_rule_engine(self):
        """Test alert rule engine."""
        engine = AlertRuleEngine()
        
        def cpu_rule(context):
            return context.get("cpu", 0) > 80
        
        rule = AlertRule(
            rule_id="cpu_high",
            name="High CPU Alert",
            description="Alert when CPU > 80%",
            condition=cpu_rule,
            severity=AlertSeverity.CRITICAL,
        )
        
        engine.register_rule(rule)
        
        # Evaluate with normal context
        alerts = engine.evaluate_rules({"cpu": 50})
        assert len(alerts) == 0
        
        # Evaluate with high CPU
        alerts = engine.evaluate_rules({"cpu": 85})
        assert len(alerts) == 1
        assert alerts[0].severity == AlertSeverity.CRITICAL
    
    def test_alert_notification_manager(self):
        """Test alert notification manager."""
        manager = AlertNotificationManager()
        
        def cpu_condition(context):
            return context.get("cpu", 0) > 80
        
        rule = AlertRule(
            rule_id="cpu_high",
            name="High CPU Alert",
            description="CPU high",
            condition=cpu_condition,
            severity=AlertSeverity.CRITICAL,
            channels=[NotificationChannel.EMAIL],
        )
        
        manager.register_rule(rule)
        
        # Handler for email notifications
        def email_handler(alert):
            pass
        
        manager.register_notification_handler(
            NotificationChannel.EMAIL,
            email_handler
        )
        
        # Trigger alert
        alerts = manager.evaluate_and_notify({"cpu": 90})
        assert len(alerts) == 1
        
        # Get statistics
        stats = manager.get_alert_statistics()
        assert stats["active_alerts"] >= 1


class TestPredictiveAnalytics:
    """Tests for predictive analytics."""
    
    def test_simple_moving_average_predictor(self):
        """Test SMA predictor."""
        predictor = SimpleMovingAveragePredictor(window_size=5)
        
        # Add samples
        for i in range(10):
            predictor.add_sample("metric", 100.0 + i)
        
        # Predict
        prediction = predictor.predict("metric", periods_ahead=1)
        assert prediction is not None
        assert len(prediction) == 2  # value, confidence
        assert prediction[1] > 0.5  # Should have reasonable confidence
    
    def test_predictive_model_ensemble(self):
        """Test ensemble predictive model."""
        model = PredictiveModel()
        
        # Add samples
        for i in range(20):
            model.add_sample("cpu", 50.0 + i * 0.5)
        
        # Generate prediction
        prediction = model.predict("cpu", periods_ahead=1)
        assert prediction is not None
        assert prediction.confidence > 0.5
        assert prediction.predicted_value > 0
    
    def test_failure_probability_predictor(self):
        """Test failure probability prediction."""
        predictor = FailureProbabilityPredictor()
        
        # Add normal samples
        for i in range(20):
            predictor.add_sample("error_rate", 0.01 + (i * 0.001))
        
        # Predict failure probability
        result = predictor.predict_failure_probability("error_rate")
        if result:
            prob, risk_level = result
            assert 0 <= prob <= 1
            assert risk_level in ["low", "medium", "high", "critical"]
    
    def test_predictive_analytics_engine(self):
        """Test full predictive analytics engine."""
        engine = PredictiveAnalyticsEngine()
        
        # Add metric samples
        for i in range(15):
            engine.add_metric_sample("requests", 1000 + i * 10)
        
        # Get resource usage prediction
        prediction = engine.predict_resource_usage("requests", periods_ahead=1)
        assert prediction is not None
        assert prediction.predicted_value > 0
        
        # Get summary
        summary = engine.get_predictions_summary()
        assert "total_predictions" in summary
        assert "confident_predictions" in summary


# Run tests
if __name__ == "__main__":
    pytest.main([__file__, "-v"])
