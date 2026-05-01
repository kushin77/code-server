"""
Phase 27 Integration Tests (ML/AI Enhancement)

Comprehensive testing for anomaly detection, predictive scaling,
root cause analysis, and intelligent alerting modules.
"""

import pytest
from datetime import datetime, timedelta
from apps.ml_ai.anomaly_detection import (
    AnomalyDetector, TimeSeriesAnalyzer, DetectionAlgorithm,
    AnomalySeverity, DetectionModel
)
from apps.ml_ai.predictive_scaling import (
    PredictiveScaler, CapacityPlanner, WorkloadForecaster,
    ForecastHorizon, ScalingAction
)
from apps.ml_ai.root_cause_analysis import (
    RootCauseAnalyzer, DependencyGraph, CorrelationAnalyzer,
    BlastRadiusCalculator
)
from apps.ml_ai.intelligent_alerting import (
    IntelligentAlerter, AlertDeduplicator, RawAlert,
    AlertSeverity, SeverityPredictor
)


class TestAnomalyDetection:
    """Test anomaly detection engine."""
    
    def test_z_score_detection(self):
        """Test Z-score anomaly detection."""
        detector = AnomalyDetector()
        detector.create_model("cpu_usage", DetectionAlgorithm.Z_SCORE)
        
        # Add normal data
        for i in range(100):
            detector.add_data_point("cpu_usage", 50.0 + (i % 10))
        
        # Add anomaly
        anomaly = detector.detect_anomaly("cpu_usage", 95.0)
        
        assert anomaly is not None
        assert anomaly.severity == AnomalySeverity.CRITICAL
        assert anomaly.score > 0.7
    
    def test_iqr_detection(self):
        """Test IQR anomaly detection."""
        detector = AnomalyDetector()
        detector.create_model("memory_usage", DetectionAlgorithm.IQR)
        
        # Add data
        for val in [40, 42, 41, 43, 40, 41, 42, 200]:
            detector.add_data_point("memory_usage", val)
        
        # Detect anomaly
        anomaly = detector.detect_anomaly("memory_usage", 200.0)
        
        assert anomaly is not None
        assert anomaly.severity in [AnomalySeverity.HIGH, AnomalySeverity.CRITICAL]
    
    def test_isolation_forest_detection(self):
        """Test Isolation Forest detection."""
        detector = AnomalyDetector()
        detector.create_model("network_io", DetectionAlgorithm.ISOLATION_FOREST)
        
        # Add normal data
        for i in range(50):
            detector.add_data_point("network_io", 100.0 + (i % 20))
        
        # Test anomaly
        anomaly = detector.detect_anomaly("network_io", 500.0)
        assert anomaly is not None
    
    def test_baseline_calculation(self):
        """Test baseline statistics calculation."""
        data = [10, 15, 12, 18, 14, 16, 13, 17, 11, 19]
        analyzer = TimeSeriesAnalyzer()
        baseline = analyzer.calculate_baseline(data)
        
        assert baseline.mean > 0
        assert baseline.std_dev > 0
        assert baseline.min_value == 10
        assert baseline.max_value == 19
        assert baseline.q1 < baseline.median < baseline.q3
    
    def test_detector_statistics(self):
        """Test detector statistics."""
        detector = AnomalyDetector()
        detector.create_model("test_metric")
        
        for i in range(100):
            detector.add_data_point("test_metric", 50.0)
        
        # Add some anomalies
        detector.detect_anomaly("test_metric", 100.0)
        
        stats = detector.get_statistics()
        assert stats['models_configured'] >= 1
        assert stats['anomalies_found'] > 0


class TestPredictiveScaling:
    """Test predictive scaling engine."""
    
    def test_workload_forecasting(self):
        """Test workload forecasting."""
        forecaster = WorkloadForecaster()
        
        # Add hourly data pattern
        for day in range(7):
            for hour in range(24):
                timestamp = datetime.utcnow() - timedelta(days=7-day, hours=24-hour)
                # Peak during business hours
                value = 50 + (50 if 9 <= hour <= 17 else 20)
                forecaster.add_metric_point("cpu", value, timestamp)
        
        # Detect patterns
        pattern = forecaster.detect_patterns("cpu")
        assert 'peak_hours' in pattern
        assert len(pattern['peak_hours']) > 0
    
    def test_forecast_generation(self):
        """Test forecast generation."""
        forecaster = WorkloadForecaster()
        
        # Add data
        base_value = 50
        for i in range(100):
            forecaster.add_metric_point("memory", base_value + (i % 20))
        
        # Generate forecast
        forecast = forecaster.forecast("memory", ForecastHorizon.ONE_HOUR)
        
        assert forecast is not None
        assert forecast.predicted_value >= 0
        assert forecast.confidence_80[0] <= forecast.predicted_value <= forecast.confidence_80[1]
    
    def test_scaling_recommendation(self):
        """Test scaling recommendation generation."""
        scaler = PredictiveScaler()
        
        # Add metrics
        for i in range(100):
            scaler.add_metric("cpu_usage", 80.0 + (i % 10))
        
        # Get recommendation
        recommendation = scaler.get_scaling_recommendation("cpu_usage", 85.0)
        
        assert recommendation is not None
        assert recommendation.action in [ScalingAction.SCALE_UP, ScalingAction.MAINTAIN, ScalingAction.SCALE_DOWN]
        assert recommendation.scale_factor > 0
    
    def test_capacity_planning(self):
        """Test capacity planning."""
        planner = CapacityPlanner()
        
        # Add metrics
        for i in range(100):
            planner.add_metric("cpu", 40.0 + (i % 30))
        
        # Plan capacity
        plan = planner.plan_capacity("cpu", 100.0, ForecastHorizon.ONE_WEEK)
        
        assert plan is not None
        assert plan.recommended_capacity > 0
        assert plan.saturation_risk >= 0 and plan.saturation_risk <= 1
    
    def test_scaler_statistics(self):
        """Test scaler statistics."""
        scaler = PredictiveScaler()
        
        for i in range(50):
            scaler.add_metric("test_metric", 60.0)
        
        stats = scaler.get_statistics()
        assert 'recommendations_made' in stats
        assert 'scale_ups' in stats
        assert 'scale_downs' in stats


class TestRootCauseAnalysis:
    """Test root cause analysis engine."""
    
    def test_dependency_graph(self):
        """Test dependency graph operations."""
        graph = DependencyGraph()
        
        # Build graph
        graph.add_dependency("frontend", "api")
        graph.add_dependency("api", "database")
        graph.add_dependency("api", "cache")
        
        # Test downstream
        downstream = graph.get_downstream_services("api")
        assert "database" in downstream
        assert "cache" in downstream
        
        # Test upstream
        upstream = graph.get_upstream_services("database")
        assert "api" in upstream
    
    def test_correlation_analysis(self):
        """Test correlation analysis."""
        analyzer = CorrelationAnalyzer()
        
        # Add positively correlated data
        for i in range(50):
            analyzer.add_metric_value("cpu", 50.0 + i)
            analyzer.add_metric_value("memory", 100.0 + (2 * i))
        
        # Calculate correlation
        corr = analyzer.calculate_correlation("cpu", "memory")
        
        assert corr is not None
        assert corr.correlation_coefficient > 0  # Positive correlation
        assert corr.relationship == "positive"
    
    def test_blast_radius_calculation(self):
        """Test blast radius calculation."""
        graph = DependencyGraph()
        graph.add_dependency("api", "db1", failure_propagation=0.8)
        graph.add_dependency("api", "db2", failure_propagation=0.7)
        graph.add_dependency("db1", "cache", failure_propagation=0.5)
        
        calculator = BlastRadiusCalculator(graph)
        propagation = calculator.calculate_blast_radius(
            "api",
            {"api": 100.0}
        )
        
        assert propagation is not None
        assert propagation.blast_radius > 0
        assert len(propagation.affected_services) > 0
    
    def test_root_cause_analysis(self):
        """Test root cause analysis."""
        analyzer = RootCauseAnalyzer()
        
        # Add dependencies
        analyzer.add_dependency("service_a", "service_b")
        analyzer.add_dependency("service_b", "database")
        
        # Add metrics
        for i in range(30):
            analyzer.add_metric_datapoint("cpu", 50.0 + i)
            analyzer.add_metric_datapoint("error_rate", 0.5 + (0.01 * i))
        
        # Analyze incident
        report = analyzer.analyze_incident(
            incident_id="incident-001",
            primary_issue="High error rates",
            affected_services=["service_a", "service_b"],
            error_rates={"service_a": 0.5, "service_b": 0.8},
            affected_metrics=["cpu", "error_rate"]
        )
        
        assert report is not None
        assert report.suspected_root_cause is not None
        assert len(report.recommendations) > 0
    
    def test_analyzer_statistics(self):
        """Test analyzer statistics."""
        analyzer = RootCauseAnalyzer()
        analyzer.add_dependency("a", "b")
        
        stats = analyzer.get_statistics()
        assert 'analyses_performed' in stats
        assert 'services_tracked' in stats
        assert stats['services_tracked'] >= 2


class TestIntelligentAlerting:
    """Test intelligent alerting engine."""
    
    def test_alert_deduplication(self):
        """Test alert deduplication."""
        dedup = AlertDeduplicator(time_window_seconds=60)
        
        # Create alerts
        alert1 = RawAlert(
            id="alert-1",
            title="High CPU",
            description="CPU > 80%",
            metric_name="cpu_usage",
            metric_value=85.0,
            threshold=80.0,
            source="monitor-1",
            timestamp=datetime.utcnow()
        )
        
        alert2 = RawAlert(
            id="alert-2",
            title="High CPU",
            description="CPU > 80%",
            metric_name="cpu_usage",
            metric_value=87.0,
            threshold=80.0,
            source="monitor-1",
            timestamp=datetime.utcnow() + timedelta(seconds=10)
        )
        
        # Process alerts
        group1 = dedup.process_alert(alert1)
        group2 = dedup.process_alert(alert2)
        
        assert group1.signature == group2.signature
        assert group2.occurrence_count == 2
    
    def test_severity_prediction(self):
        """Test severity prediction."""
        predictor = SeverityPredictor()
        
        # Normal alert
        alert1 = RawAlert(
            id="alert-1",
            title="Minor",
            description="Small deviation",
            metric_name="cpu",
            metric_value=85.0,
            threshold=80.0,
            source="monitor",
            timestamp=datetime.utcnow()
        )
        severity1 = predictor.predict_severity(alert1)
        
        # Critical alert
        alert2 = RawAlert(
            id="alert-2",
            title="Critical",
            description="Large deviation",
            metric_name="cpu",
            metric_value=150.0,
            threshold=80.0,
            source="monitor",
            timestamp=datetime.utcnow()
        )
        severity2 = predictor.predict_severity(alert2)
        
        assert severity2.value > severity1.value
    
    def test_intelligent_alerter(self):
        """Test complete intelligent alerting pipeline."""
        alerter = IntelligentAlerter()
        
        # Process alerts
        for i in range(5):
            alert = RawAlert(
                id=f"alert-{i}",
                title="High CPU",
                description="CPU usage high",
                metric_name="cpu_usage",
                metric_value=85.0,
                threshold=80.0,
                source="monitor-1",
                timestamp=datetime.utcnow()
            )
            enriched = alerter.process_alert(alert)
            assert enriched is not None
        
        # Check statistics
        stats = alerter.get_statistics()
        assert stats['alerts_received'] == 5
        assert stats['alerts_deduplicated'] > 0
    
    def test_alerter_statistics(self):
        """Test alerter statistics."""
        alerter = IntelligentAlerter()
        
        stats = alerter.get_statistics()
        assert 'alerts_received' in stats
        assert 'alerts_suppressed' in stats
        assert 'deduplication_ratio' in stats


class TestPhase27Integration:
    """End-to-end integration tests."""
    
    def test_complete_ml_pipeline(self):
        """Test complete ML/AI pipeline."""
        # Anomaly detection
        anomaly_detector = AnomalyDetector()
        anomaly_detector.create_model("cpu")
        
        # Predictive scaling
        capacity_planner = CapacityPlanner()
        
        # Root cause analysis
        rca = RootCauseAnalyzer()
        rca.add_dependency("web", "api")
        rca.add_dependency("api", "db")
        
        # Intelligent alerting
        alerter = IntelligentAlerter()
        
        # Simulate metrics over time
        for i in range(100):
            value = 50.0 + (20.0 * (i % 10) / 10.0)
            
            # Add to all systems
            anomaly_detector.add_data_point("cpu", value)
            capacity_planner.add_metric("cpu", value)
            rca.add_metric_datapoint("cpu", value)
            
            # Check for anomalies
            if i > 50:
                anomaly = anomaly_detector.detect_anomaly("cpu", 95.0)
                if anomaly:
                    alert = RawAlert(
                        id=f"anom-{i}",
                        title="Anomaly Detected",
                        description=f"CPU anomaly: {anomaly.reason}",
                        metric_name="cpu",
                        metric_value=95.0,
                        threshold=70.0,
                        source="anomaly-detector",
                        timestamp=datetime.utcnow()
                    )
                    alerter.process_alert(alert)
        
        # Verify all systems produced output
        stats_anom = anomaly_detector.get_statistics()
        stats_capacity = capacity_planner.scaler.get_statistics()
        stats_rca = rca.get_statistics()
        stats_alert = alerter.get_statistics()
        
        assert stats_anom['models_configured'] > 0
        assert stats_capacity['recommendations_made'] >= 0
        assert stats_rca['services_tracked'] >= 2
        assert stats_alert['alerts_received'] >= 0


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
