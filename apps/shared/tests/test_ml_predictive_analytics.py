"""
Tests for advanced ML integration and predictive analytics system.
"""

import importlib.util
import sys
import types
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

apps_pkg = types.ModuleType("apps")
apps_pkg.__path__ = [str(ROOT.parent)]
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
shared_pkg.__path__ = [str(ROOT)]
sys.modules["apps.shared"] = shared_pkg


def _load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / file_name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


ML_PREDICTIVE = _load_module("apps.shared.ml_predictive_analytics", "ml_predictive_analytics.py")

ModelType = ML_PREDICTIVE.ModelType
TimeSeriesPoint = ML_PREDICTIVE.TimeSeriesPoint
Forecast = ML_PREDICTIVE.Forecast
SeasonalDecomposition = ML_PREDICTIVE.SeasonalDecomposition
AnomalyPrediction = ML_PREDICTIVE.AnomalyPrediction
ExponentialSmoothingModel = ML_PREDICTIVE.ExponentialSmoothingModel
LinearRegressionModel = ML_PREDICTIVE.LinearRegressionModel
SeasonalDecompositionModel = ML_PREDICTIVE.SeasonalDecompositionModel
AnomalyPredictionModel = ML_PREDICTIVE.AnomalyPredictionModel
MLCorrelationAnalyzer = ML_PREDICTIVE.MLCorrelationAnalyzer
ForecastingEngine = ML_PREDICTIVE.ForecastingEngine


class TestTimeSeriesPoint:
    """Test time series point creation."""
    
    def test_create_point(self):
        """Test creating time series point."""
        now = datetime.utcnow()
        point = TimeSeriesPoint(timestamp=now, value=42.5)
        
        assert point.value == 42.5


class TestForecast:
    """Test forecast results."""
    
    def test_create_forecast(self):
        """Test creating forecast."""
        forecast = Forecast(
            metric_name="cpu_usage",
            model_type=ModelType.LINEAR_REGRESSION
        )
        
        assert forecast.metric_name == "cpu_usage"
        assert forecast.model_type == ModelType.LINEAR_REGRESSION
    
    def test_forecast_to_dict(self):
        """Test converting forecast to dict."""
        now = datetime.utcnow()
        forecast = Forecast(
            metric_name="memory",
            model_type=ModelType.EXPONENTIAL_SMOOTHING,
            forecast_points=[TimeSeriesPoint(now, 100.0)]
        )
        
        d = forecast.to_dict()
        assert d["metric_name"] == "memory"
        assert d["model_type"] == "exponential_smoothing"


class TestExponentialSmoothingModel:
    """Test exponential smoothing model."""
    
    def test_fit_model(self):
        """Test fitting exponential smoothing."""
        model = ExponentialSmoothingModel()
        data = [10.0, 12.0, 11.0, 13.0, 15.0, 14.0]
        
        result = model.fit(data)
        
        assert result is True
        assert len(model.training_data) == 6
    
    def test_forecast(self):
        """Test forecasting with exponential smoothing."""
        model = ExponentialSmoothingModel()
        data = [10.0, 12.0, 11.0, 13.0, 15.0, 14.0, 16.0, 15.0]
        
        model.fit(data)
        forecast = model.forecast(steps=5)
        
        assert forecast.model_type == ModelType.EXPONENTIAL_SMOOTHING
        assert len(forecast.forecast_points) == 5
        assert len(forecast.confidence_intervals) == 5
    
    def test_forecast_increasing_confidence(self):
        """Test confidence intervals increase over time."""
        model = ExponentialSmoothingModel()
        data = list(range(1, 11))
        
        model.fit(data)
        forecast = model.forecast(steps=5)
        
        # Confidence intervals should increase
        intervals = forecast.confidence_intervals
        widths = [intervals[i][1] - intervals[i][0] for i in range(len(intervals))]
        
        assert widths[-1] > widths[0]


class TestLinearRegressionModel:
    """Test linear regression model."""
    
    def test_fit_model(self):
        """Test fitting linear regression."""
        model = LinearRegressionModel()
        data = [10.0, 20.0, 30.0, 40.0, 50.0]
        
        result = model.fit(data)
        
        assert result is True
    
    def test_slope_calculation(self):
        """Test slope calculation."""
        model = LinearRegressionModel()
        data = [10.0, 20.0, 30.0, 40.0, 50.0]
        
        model.fit(data)
        
        # Should have positive slope
        assert model.slope > 0
    
    def test_forecast(self):
        """Test linear regression forecast."""
        model = LinearRegressionModel()
        data = [10.0, 20.0, 30.0, 40.0, 50.0]
        
        model.fit(data)
        forecast = model.forecast(steps=3)
        
        assert len(forecast.forecast_points) == 3
        assert forecast.model_type == ModelType.LINEAR_REGRESSION


class TestSeasonalDecompositionModel:
    """Test seasonal decomposition model."""
    
    def test_fit_model(self):
        """Test fitting seasonal model."""
        model = SeasonalDecompositionModel(period=4)
        data = [10, 20, 15, 25] * 3  # 3 cycles
        
        result = model.fit(data)
        
        assert result is True
    
    def test_decompose(self):
        """Test decomposition."""
        model = SeasonalDecompositionModel(period=4)
        data = [10, 20, 15, 25] * 3
        
        model.fit(data)
        decomp = model.decompose()
        
        assert len(decomp.trend) == 12
        assert len(decomp.seasonal) == 12
        assert len(decomp.residual) == 12
        assert decomp.period == 4
    
    def test_forecast_seasonal(self):
        """Test forecasting with seasonality."""
        model = SeasonalDecompositionModel(period=4)
        data = [10, 20, 15, 25] * 3
        
        model.fit(data)
        forecast = model.forecast(steps=4)
        
        assert len(forecast.forecast_points) == 4


class TestAnomalyPredictionModel:
    """Test anomaly prediction model."""
    
    def test_fit_model(self):
        """Test fitting anomaly model."""
        model = AnomalyPredictionModel()
        data = [100.0] * 10  # Constant values
        
        result = model.fit(data)
        
        assert result is True
        assert model.mean == 100.0
    
    def test_normal_value_prediction(self):
        """Test predicting normal value."""
        model = AnomalyPredictionModel()
        data = [100.0 + i * 0.1 for i in range(20)]
        
        model.fit(data)
        prediction = model.predict_anomaly(100.0)
        
        assert prediction.predicted_anomaly is False
    
    def test_anomalous_value_prediction(self):
        """Test predicting anomalous value."""
        model = AnomalyPredictionModel()
        data = [100.0 + i for i in range(20)]
        
        model.fit(data)
        prediction = model.predict_anomaly(200.0)
        
        assert prediction.predicted_anomaly is True
        assert prediction.anomaly_probability < 0.01
    
    def test_confidence_interval(self):
        """Test confidence interval calculation."""
        model = AnomalyPredictionModel()
        data = [100.0 + i for i in range(20)]
        
        model.fit(data)
        prediction = model.predict_anomaly(50.0)
        
        lower, upper = prediction.expected_value_range
        assert lower < 100.0 < upper


class TestMLCorrelationAnalyzer:
    """Test ML correlation analyzer."""
    
    def test_perfect_positive_correlation(self):
        """Test perfect positive correlation."""
        analyzer = MLCorrelationAnalyzer()
        
        values1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        values2 = [2.0, 4.0, 6.0, 8.0, 10.0]
        
        correlation = analyzer.learn_correlation("metric1", "metric2", values1, values2)
        
        assert abs(correlation - 1.0) < 0.01
    
    def test_negative_correlation(self):
        """Test negative correlation."""
        analyzer = MLCorrelationAnalyzer()
        
        values1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        values2 = [5.0, 4.0, 3.0, 2.0, 1.0]
        
        correlation = analyzer.learn_correlation("metric1", "metric2", values1, values2)
        
        assert abs(correlation + 1.0) < 0.01
    
    def test_no_correlation(self):
        """Test no correlation."""
        analyzer = MLCorrelationAnalyzer()
        
        values1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        values2 = [5.0, 1.0, 3.0, 2.0, 4.0]
        
        correlation = analyzer.learn_correlation("metric1", "metric2", values1, values2)
        
        assert abs(correlation) < 0.5
    
    def test_discover_causality(self):
        """Test causality discovery."""
        analyzer = MLCorrelationAnalyzer()
        
        # metric1 leads metric2 by 1 step
        values1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        values2 = [0.0, 2.0, 4.0, 6.0, 8.0]
        
        causality = analyzer.discover_causality("metric1", "metric2", values1, values2, lag=1)
        
        assert causality > 0.5
        assert "metric2" in analyzer.causality_graph.get("metric1", [])
    
    def test_get_correlated_metrics(self):
        """Test retrieving correlated metrics."""
        analyzer = MLCorrelationAnalyzer()
        
        # Create correlations
        analyzer.learn_correlation("cpu", "memory", [1, 2, 3], [2, 4, 6])
        analyzer.learn_correlation("cpu", "disk", [1, 2, 3], [3, 2, 1])
        
        correlated = analyzer.get_correlated_metrics("cpu", threshold=0.5)
        
        assert "memory" in correlated


class TestForecastingEngine:
    """Test unified forecasting engine."""
    
    def test_register_model(self):
        """Test registering model."""
        engine = ForecastingEngine()
        model = ExponentialSmoothingModel()
        
        engine.register_model("cpu", model)
        
        assert "cpu" in engine.models
    
    def test_auto_create_model(self):
        """Test auto-creating model on training."""
        engine = ForecastingEngine()
        data = [10.0, 12.0, 11.0, 13.0]
        
        result = engine.train_model("memory", data)
        
        assert result is True
        assert "memory" in engine.models
    
    def test_generate_forecast(self):
        """Test generating forecast."""
        engine = ForecastingEngine()
        data = [10.0, 12.0, 11.0, 13.0, 15.0, 14.0]
        
        engine.train_model("latency", data)
        forecast = engine.generate_forecast("latency", steps=5)
        
        assert forecast is not None
        assert len(forecast.forecast_points) == 5
        assert "latency" in engine.forecasts
    
    def test_predict_anomalies(self):
        """Test predicting anomalies."""
        engine = ForecastingEngine()
        data = [100.0] * 20
        
        engine.train_model("error_rate", data)
        predictions = engine.predict_anomalies("error_rate", [100.0, 101.0, 500.0])
        
        assert len(predictions) == 3
        assert predictions[0].predicted_anomaly is False
        assert predictions[2].predicted_anomaly is True


class TestIntegration:
    """Integration tests for ML system."""
    
    def test_complete_ml_workflow(self):
        """Test complete ML workflow."""
        # Create engine
        engine = ForecastingEngine()
        
        # Historical data
        historical_data = [100 + i * 2 + (i % 10) for i in range(100)]
        
        # Train model
        engine.train_model("response_time", historical_data)
        
        # Generate forecast
        forecast = engine.generate_forecast("response_time", steps=24)
        
        assert forecast is not None
        assert len(forecast.forecast_points) == 24
        assert all(p.value > 0 for p in forecast.forecast_points)
    
    def test_multi_metric_analysis(self):
        """Test multi-metric correlation analysis."""
        engine = ForecastingEngine()
        
        # CPU and memory are correlated
        cpu_data = [50 + i for i in range(50)]
        memory_data = [60 + i for i in range(50)]
        
        engine.train_model("cpu", cpu_data)
        engine.train_model("memory", memory_data)
        
        # Learn correlation
        correlation = engine.correlation_analyzer.learn_correlation(
            "cpu", "memory", cpu_data, memory_data
        )
        
        assert correlation > 0.9
    
    def test_seasonal_forecasting(self):
        """Test seasonal forecasting."""
        engine = ForecastingEngine()
        
        # Create seasonal data
        seasonal_model = SeasonalDecompositionModel(period=7)
        seasonal_pattern = [10, 20, 15, 25, 30, 20, 15] * 8  # 8 weeks
        
        seasonal_model.fit(seasonal_pattern)
        forecast = seasonal_model.forecast(steps=7)
        
        assert len(forecast.forecast_points) == 7
    
    def test_anomaly_prediction_workflow(self):
        """Test anomaly prediction workflow."""
        engine = ForecastingEngine()
        
        # Normal operation
        normal_values = [100.0 + (i % 5) for i in range(100)]
        
        engine.train_model("requests", normal_values)
        
        # Predict anomalies in new values
        test_values = [101.0, 102.0, 100.0, 500.0, 99.0]
        predictions = engine.predict_anomalies("requests", test_values)
        
        assert len(predictions) == 5
        
        # Should detect spike
        anomalies = [p for p in predictions if p.predicted_anomaly]
        assert len(anomalies) > 0


class TestModelComparison:
    """Test comparing different models."""
    
    def test_exponential_vs_linear(self):
        """Test exponential smoothing vs linear regression."""
        # Trending data
        data = [100 + i * 5 for i in range(50)]
        
        exp_model = ExponentialSmoothingModel()
        lin_model = LinearRegressionModel()
        
        exp_model.fit(data)
        lin_model.fit(data)
        
        exp_forecast = exp_model.forecast(steps=10)
        lin_forecast = lin_model.forecast(steps=10)
        
        assert len(exp_forecast.forecast_points) == 10
        assert len(lin_forecast.forecast_points) == 10
