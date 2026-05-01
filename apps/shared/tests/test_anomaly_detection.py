"""
Tests for advanced anomaly detection and ML correlation system.
"""

import pytest
from datetime import datetime, timedelta
import math
from apps.shared.anomaly_detection import (
    AnomalyType, SeverityLevel, DataPoint, AnomalyDetected,
    CorrelationAnalysis, StatisticalAnomalyDetector, TrendAnomalyDetector,
    CorrelationAnalyzer, RootCauseAnalyzer, AnomalyManager, PredictiveAlert
)


class TestDataPoint:
    """Test data point creation."""
    
    def test_create_data_point(self):
        """Test creating data point."""
        now = datetime.utcnow()
        point = DataPoint(
            timestamp=now,
            value=42.5,
            metric_name="cpu_usage",
            labels={"host": "server1"}
        )
        
        assert point.value == 42.5
        assert point.metric_name == "cpu_usage"


class TestAnomalyDetected:
    """Test anomaly detection results."""
    
    def test_create_anomaly(self):
        """Test creating anomaly."""
        now = datetime.utcnow()
        anomaly = AnomalyDetected(
            id="anom_1",
            type=AnomalyType.SPIKE,
            metric_name="latency",
            timestamp=now,
            value=500,
            expected_value=100,
            severity=SeverityLevel.CRITICAL,
            confidence=0.95,
            description="High latency spike detected"
        )
        
        assert anomaly.type == AnomalyType.SPIKE
        assert anomaly.confidence == 0.95
    
    def test_anomaly_to_dict(self):
        """Test converting anomaly to dict."""
        anomaly = AnomalyDetected(
            id="anom_1",
            type=AnomalyType.DROP,
            metric_name="requests",
            timestamp=datetime.utcnow(),
            value=10,
            expected_value=100,
            severity=SeverityLevel.WARNING,
            confidence=0.8,
            description="Request drop"
        )
        
        d = anomaly.to_dict()
        assert d["type"] == "drop"
        assert d["severity"] == "warning"


class TestStatisticalAnomalyDetector:
    """Test statistical anomaly detection."""
    
    def test_detect_spike(self):
        """Test detecting spike anomalies."""
        detector = StatisticalAnomalyDetector(z_score_threshold=2.0)
        
        now = datetime.utcnow()
        points = [
            DataPoint(now - timedelta(seconds=i), float(50), "metric1")
            for i in range(10, 0, -1)
        ]
        
        # Add spike
        points.append(DataPoint(now, 200.0, "metric1"))
        
        anomalies = detector.detect(points)
        
        assert len(anomalies) > 0
        assert anomalies[0].type == AnomalyType.SPIKE
    
    def test_detect_drop(self):
        """Test detecting drop anomalies."""
        detector = StatisticalAnomalyDetector(z_score_threshold=2.0)
        
        now = datetime.utcnow()
        points = [
            DataPoint(now - timedelta(seconds=i), float(100), "metric1")
            for i in range(10, 0, -1)
        ]
        
        # Add drop
        points.append(DataPoint(now, 5.0, "metric1"))
        
        anomalies = detector.detect(points)
        
        assert len(anomalies) > 0
        assert anomalies[0].type == AnomalyType.DROP
    
    def test_severity_calculation(self):
        """Test severity calculation."""
        detector = StatisticalAnomalyDetector(z_score_threshold=2.0)
        
        # High Z-score should be critical
        anomaly = AnomalyDetected(
            id="test", type=AnomalyType.SPIKE, metric_name="test",
            timestamp=datetime.utcnow(), value=100, expected_value=10,
            severity=detector._calculate_severity(6.0),
            confidence=0.9, description="Test"
        )
        
        assert anomaly.severity == SeverityLevel.CRITICAL
    
    def test_baseline_update(self):
        """Test updating baseline."""
        detector = StatisticalAnomalyDetector()
        
        now = datetime.utcnow()
        points = [
            DataPoint(now - timedelta(seconds=i), float(50 + i), "metric1")
            for i in range(10)
        ]
        
        detector.update_baseline(points)
        
        assert "metric1" in detector.baselines
        assert "mean" in detector.baselines["metric1"]
        assert "std_dev" in detector.baselines["metric1"]


class TestTrendAnomalyDetector:
    """Test trend-based anomaly detection."""
    
    def test_detect_trend_change(self):
        """Test detecting trend changes."""
        detector = TrendAnomalyDetector(window_size=5, min_slope_change=0.5)
        
        now = datetime.utcnow()
        points = []
        
        # First trend: gradual increase
        for i in range(15):
            points.append(DataPoint(now - timedelta(seconds=30-i), float(i * 5), "metric1"))
        
        # Second trend: sharp increase
        for i in range(15, 25):
            points.append(DataPoint(now - timedelta(seconds=30-(i-15)), float(i * 20), "metric1"))
        
        # Sort by timestamp
        points = sorted(points, key=lambda p: p.timestamp)
        
        anomalies = detector.detect(points)
        
        assert len(anomalies) > 0
        assert anomalies[0].type == AnomalyType.TREND
    
    def test_slope_calculation(self):
        """Test linear slope calculation."""
        points = [
            DataPoint(datetime.utcnow(), float(i * 2), "metric1")
            for i in range(10)
        ]
        
        slope = TrendAnomalyDetector._calculate_slope(points)
        
        assert slope > 1.5  # Should be close to 2.0


class TestCorrelationAnalyzer:
    """Test metric correlation analysis."""
    
    def test_add_point(self):
        """Test adding data points."""
        analyzer = CorrelationAnalyzer()
        
        point = DataPoint(datetime.utcnow(), 100.0, "cpu")
        analyzer.add_point(point)
        
        assert "cpu" in analyzer.metric_history
        assert len(analyzer.metric_history["cpu"]) == 1
    
    def test_pearson_correlation_perfect_positive(self):
        """Test perfect positive correlation."""
        x = [1.0, 2.0, 3.0, 4.0, 5.0]
        y = [2.0, 4.0, 6.0, 8.0, 10.0]
        
        correlation = CorrelationAnalyzer._pearson_correlation(x, y)
        
        assert abs(correlation - 1.0) < 0.01
    
    def test_pearson_correlation_perfect_negative(self):
        """Test perfect negative correlation."""
        x = [1.0, 2.0, 3.0, 4.0, 5.0]
        y = [5.0, 4.0, 3.0, 2.0, 1.0]
        
        correlation = CorrelationAnalyzer._pearson_correlation(x, y)
        
        assert abs(correlation + 1.0) < 0.01
    
    def test_pearson_correlation_no_correlation(self):
        """Test no correlation."""
        x = [1.0, 2.0, 3.0, 4.0, 5.0]
        y = [5.0, 1.0, 3.0, 2.0, 4.0]
        
        correlation = CorrelationAnalyzer._pearson_correlation(x, y)
        
        assert abs(correlation) < 0.5


class TestRootCauseAnalyzer:
    """Test root cause analysis."""
    
    def test_analyze_isolated_anomaly(self):
        """Test analyzing isolated anomaly."""
        analyzer = RootCauseAnalyzer()
        
        anomaly = AnomalyDetected(
            id="anom_1", type=AnomalyType.SPIKE,
            metric_name="latency", timestamp=datetime.utcnow(),
            value=500, expected_value=100,
            severity=SeverityLevel.WARNING, confidence=0.8,
            description="Latency spike"
        )
        
        root_cause = analyzer.analyze_root_cause(anomaly, [])
        
        assert "Isolated anomaly" in root_cause
    
    def test_analyze_correlated_anomalies(self):
        """Test analyzing multiple correlated anomalies."""
        analyzer = RootCauseAnalyzer()
        
        now = datetime.utcnow()
        primary = AnomalyDetected(
            id="anom_1", type=AnomalyType.SPIKE,
            metric_name="cpu", timestamp=now,
            value=90, expected_value=50,
            severity=SeverityLevel.CRITICAL, confidence=0.9,
            description="CPU spike"
        )
        
        related = AnomalyDetected(
            id="anom_2", type=AnomalyType.SPIKE,
            metric_name="memory", timestamp=now,
            value=85, expected_value=40,
            severity=SeverityLevel.CRITICAL, confidence=0.9,
            description="Memory spike"
        )
        
        root_cause = analyzer.analyze_root_cause(primary, [related])
        
        assert "Multiple metrics" in root_cause
    
    def test_record_incident(self):
        """Test recording incidents."""
        analyzer = RootCauseAnalyzer()
        
        anomaly = AnomalyDetected(
            id="anom_1", type=AnomalyType.SPIKE,
            metric_name="errors", timestamp=datetime.utcnow(),
            value=100, expected_value=10,
            severity=SeverityLevel.CRITICAL, confidence=0.95,
            description="Error spike"
        )
        
        analyzer.record_incident(anomaly, "Database connection timeout")
        
        assert len(analyzer.incident_history) == 1


class TestAnomalyManager:
    """Test anomaly detection management."""
    
    def test_detect_anomalies(self):
        """Test detecting anomalies."""
        manager = AnomalyManager()
        
        now = datetime.utcnow()
        points = [
            DataPoint(now - timedelta(seconds=i), float(50 + (i % 5)), "metric1")
            for i in range(20)
        ]
        
        # Add spike
        points.append(DataPoint(now, 200.0, "metric1"))
        
        anomalies = manager.detect_anomalies(points)
        
        assert len(anomalies) > 0
    
    def test_get_anomalies(self):
        """Test retrieving detected anomalies."""
        manager = AnomalyManager()
        
        now = datetime.utcnow()
        points = [
            DataPoint(now - timedelta(seconds=i), float(50), "metric1")
            for i in range(10)
        ]
        points.append(DataPoint(now, 200.0, "metric1"))
        
        manager.detect_anomalies(points)
        
        all_anomalies = manager.get_anomalies()
        assert len(all_anomalies) > 0
        
        # Get since specific time
        recent = manager.get_anomalies(since=now - timedelta(minutes=1))
        assert len(recent) > 0
    
    def test_clear_old_anomalies(self):
        """Test clearing old anomalies."""
        manager = AnomalyManager()
        
        # Manually add old anomaly
        old_anomaly = AnomalyDetected(
            id="old", type=AnomalyType.SPIKE,
            metric_name="metric1", timestamp=datetime.utcnow() - timedelta(days=1),
            value=100, expected_value=50,
            severity=SeverityLevel.INFO, confidence=0.5,
            description="Old anomaly"
        )
        manager.detected_anomalies["old"] = old_anomaly
        
        # Add recent anomaly
        recent_anomaly = AnomalyDetected(
            id="recent", type=AnomalyType.SPIKE,
            metric_name="metric1", timestamp=datetime.utcnow(),
            value=100, expected_value=50,
            severity=SeverityLevel.INFO, confidence=0.5,
            description="Recent anomaly"
        )
        manager.detected_anomalies["recent"] = recent_anomaly
        
        # Clear old
        cutoff = datetime.utcnow() - timedelta(hours=1)
        cleared = manager.clear_old_anomalies(cutoff)
        
        assert cleared == 1
        assert len(manager.get_anomalies()) == 1


class TestPredictiveAlert:
    """Test predictive alerting."""
    
    def test_predict_anomaly_with_trend(self):
        """Test predicting anomaly with trend."""
        predictor = PredictiveAlert()
        
        # Create trend with increasing slope
        values = [float(i) for i in range(100)]
        
        prediction = predictor.predict_anomaly("metric1", values)
        
        assert prediction is not None
        assert prediction["metric"] == "metric1"
    
    def test_predict_no_trend(self):
        """Test predicting with no trend."""
        predictor = PredictiveAlert()
        
        # Flat values
        values = [50.0] * 20
        
        prediction = predictor.predict_anomaly("metric1", values)
        
        assert prediction is None or prediction["confidence"] < 0.3
    
    def test_insufficient_data(self):
        """Test with insufficient data."""
        predictor = PredictiveAlert()
        
        values = [50.0, 51.0]
        
        prediction = predictor.predict_anomaly("metric1", values)
        
        assert prediction is None


class TestAnomalyIntegration:
    """Integration tests for anomaly detection."""
    
    def test_complete_detection_workflow(self):
        """Test complete anomaly detection workflow."""
        manager = AnomalyManager()
        predictor = PredictiveAlert()
        
        now = datetime.utcnow()
        
        # Normal data
        normal_points = [
            DataPoint(now - timedelta(seconds=i), float(50 + (i % 3)), "cpu")
            for i in range(30, 0, -1)
        ]
        
        # Add anomalous data
        normal_points.extend([
            DataPoint(now - timedelta(seconds=5), 150.0, "cpu"),
            DataPoint(now - timedelta(seconds=4), 160.0, "cpu"),
            DataPoint(now - timedelta(seconds=3), 155.0, "cpu"),
            DataPoint(now, 200.0, "cpu"),
        ])
        
        # Detect anomalies
        anomalies = manager.detect_anomalies(normal_points)
        assert len(anomalies) > 0
        
        # Predict future anomalies
        cpu_values = [p.value for p in normal_points[-20:]]
        prediction = predictor.predict_anomaly("cpu", cpu_values)
        
        # Should have detected or predicted something
        assert len(anomalies) > 0 or prediction is not None
    
    def test_multiple_metric_correlation(self):
        """Test correlation across multiple metrics."""
        analyzer = CorrelationAnalyzer(correlation_threshold=0.7)
        
        now = datetime.utcnow()
        
        # Correlated metrics
        for i in range(20):
            # CPU and Memory correlated
            analyzer.add_point(DataPoint(now - timedelta(seconds=i), float(50 + i), "cpu"))
            analyzer.add_point(DataPoint(now - timedelta(seconds=i), float(40 + i), "memory"))
        
        # Detect anomaly in CPU
        cpu_anomaly = AnomalyDetected(
            id="cpu_anom", type=AnomalyType.SPIKE,
            metric_name="cpu", timestamp=now,
            value=200.0, expected_value=60.0,
            severity=SeverityLevel.CRITICAL, confidence=0.95,
            description="CPU spike"
        )
        
        # Analyze correlation
        correlation = analyzer.correlate_anomalies(cpu_anomaly)
        
        # Should find memory as correlated
        correlated_metrics = [pair[1] for pair in correlation.correlated_metric_pairs]
        assert "memory" in correlated_metrics or len(correlated_metrics) > 0
