"""
Phase 28 Integration Tests

Comprehensive testing for data export, API standardization, 
persistence, caching, and dashboard functionality.
"""

import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from apps.ml_ai.data_export import (
    DataExporter, ExportConfig, ExportFormat, CompressionFormat,
    ExportMetadata
)
from apps.ml_ai.api_standardization import (
    APIRequest, APIResponse, StatusCode, RequestContext,
    AnomalyDetectionAPI, PredictiveScalingAPI, RootCauseAnalysisAPI,
    IntelligentAlertingAPI, APIRegistry
)
from apps.ml_ai.persistence_layer import (
    PostgreSQLPersistenceManager, ConnectionConfig, AnomalyRecord,
    ForecastRecord, IncidentRecord, AlertRecord
)
from apps.ml_ai.cache_layer import (
    MemoryCache, CacheConfig, CacheKey, CachedAnomalyDetector,
    CacheManager
)
from apps.ml_ai.dashboard_queries import (
    DashboardQueryBuilder, TimeRange, AggregationType,
    AnomalyDashboardQueries, ScalingDashboardQueries,
    RCADashboardQueries, AlertingDashboardQueries
)


class TestDataExport:
    """Test data export functionality."""
    
    def test_json_export(self):
        """Test JSON export."""
        exporter = DataExporter()
        data = [
            {"id": "1", "metric": "cpu", "value": 75.5},
            {"id": "2", "metric": "memory", "value": 82.3}
        ]
        
        result = exporter.export_data(data, "test_module")
        
        assert result is not None
        assert b"cpu" in result
        assert b"memory" in result
    
    def test_json_export_to_file(self):
        """Test JSON export to file."""
        exporter = DataExporter()
        data = [{"id": "1", "value": 100}]
        
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "export.json"
            result = exporter.export_to_file(data, "test_module", file_path)
            
            assert result.exists()
            assert result.read_bytes() is not None
    
    def test_csv_export(self):
        """Test CSV export."""
        config = ExportConfig(format=ExportFormat.CSV)
        exporter = DataExporter(config)
        data = [
            {"id": "1", "metric": "cpu", "value": 75.5},
            {"id": "2", "metric": "memory", "value": 82.3}
        ]
        
        result = exporter.export_data(data, "test_module")
        
        assert result is not None
        assert b"id,metric,value" in result or b"cpu" in result
    
    def test_jsonl_export(self):
        """Test JSON Lines export."""
        config = ExportConfig(format=ExportFormat.JSON_LINES)
        exporter = DataExporter(config)
        data = [
            {"id": "1", "value": 100},
            {"id": "2", "value": 200}
        ]
        
        result = exporter.export_data(data, "test_module")
        
        assert result is not None
        lines = result.decode('utf-8').split('\n')
        assert len(lines) >= 2


class TestAPIStandardization:
    """Test API standardization."""
    
    def test_api_response(self):
        """Test API response creation."""
        response = APIResponse(
            status=StatusCode.SUCCESS,
            data={"result": "ok"},
            message="Success"
        )
        
        assert response.is_success()
        assert not response.is_error()
        assert response.status == StatusCode.SUCCESS
    
    def test_api_request(self):
        """Test API request."""
        request = APIRequest(
            query={"action": "detect", "value": 100}
        )
        
        assert request.validate()
        assert request.query["action"] == "detect"
    
    def test_api_response_to_dict(self):
        """Test response serialization."""
        response = APIResponse(
            status=StatusCode.SUCCESS,
            data={"value": 42},
            message="Test"
        )
        
        response_dict = response.to_dict()
        
        assert response_dict["status"] == "success"
        assert response_dict["data"]["value"] == 42
    
    def test_api_error_response(self):
        """Test error response."""
        response = APIResponse(
            status=StatusCode.BAD_REQUEST,
            error="Invalid input",
            error_code="INVALID_INPUT"
        )
        
        assert response.is_error()
        assert not response.is_success()
    
    def test_api_registry(self):
        """Test API registry."""
        registry = APIRegistry()
        
        # Mock API
        class MockAPI:
            def handle_request(self, request):
                return APIResponse(status=StatusCode.SUCCESS)
        
        mock_api = MockAPI()
        registry.register("mock", mock_api)
        
        assert "mock" in registry.list_apis()
        assert registry.get_api("mock") is mock_api


class TestPersistence:
    """Test persistence layer."""
    
    def test_connection_manager(self):
        """Test connection management."""
        config = ConnectionConfig(host="localhost")
        manager = PostgreSQLPersistenceManager(config)
        
        assert manager.connect()
        assert manager.status.value == "connected"
        assert manager.disconnect()
    
    def test_anomaly_persistence(self):
        """Test anomaly record persistence."""
        manager = PostgreSQLPersistenceManager()
        manager.connect()
        
        record = AnomalyRecord(
            metric_name="cpu",
            detected_value=95.0,
            baseline_mean=50.0,
            z_score=4.5,
            severity="CRITICAL"
        )
        
        assert manager.save_anomaly(record)
    
    def test_forecast_persistence(self):
        """Test forecast record persistence."""
        manager = PostgreSQLPersistenceManager()
        manager.connect()
        
        record = ForecastRecord(
            metric_name="cpu",
            horizon="1h",
            predicted_value=75.0,
            trend="increasing"
        )
        
        assert manager.save_forecast(record)
    
    def test_incident_persistence(self):
        """Test incident record persistence."""
        manager = PostgreSQLPersistenceManager()
        manager.connect()
        
        record = IncidentRecord(
            incident_id="inc-001",
            suspected_root_cause="Database connection pool exhausted",
            confidence=0.95
        )
        
        assert manager.save_incident(record)
    
    def test_persistence_statistics(self):
        """Test persistence statistics."""
        manager = PostgreSQLPersistenceManager()
        manager.connect()
        
        stats = manager.get_statistics()
        
        assert "status" in stats
        assert stats["status"] == "connected"
        assert "query_count" in stats


class TestCaching:
    """Test caching functionality."""
    
    def test_memory_cache_set_get(self):
        """Test cache set/get."""
        cache = MemoryCache()
        
        cache.set("key1", "value1")
        assert cache.get("key1") == "value1"
    
    def test_cache_expiration(self):
        """Test cache expiration."""
        cache = MemoryCache()
        
        cache.set("key1", "value1", ttl_seconds=1)
        assert cache.get("key1") == "value1"
        
        # Simulate expiration
        entry = cache.cache["key1"]
        entry.created_at = datetime.utcnow() - timedelta(seconds=2)
        
        assert cache.get("key1") is None
    
    def test_cache_eviction(self):
        """Test LRU eviction."""
        config = CacheConfig(max_entries=2)
        cache = MemoryCache(config)
        
        cache.set("key1", "value1")
        cache.set("key2", "value2")
        cache.set("key3", "value3")
        
        # key1 should be evicted
        assert cache.get("key1") is None
        assert cache.get("key2") == "value2"
        assert cache.get("key3") == "value3"
    
    def test_cache_statistics(self):
        """Test cache statistics."""
        cache = MemoryCache()
        
        cache.set("key1", "value1")
        cache.get("key1")
        cache.get("key1")
        cache.get("missing")
        
        stats = cache.get_statistics()
        
        assert stats["hits"] == 2
        assert stats["misses"] == 1
        assert stats["hit_rate"] > 0.5
    
    def test_cache_manager(self):
        """Test multi-level cache manager."""
        manager = CacheManager()
        
        manager.set_cascading("key1", "value1")
        assert manager.get_cascading("key1") == "value1"
        
        manager.invalidate("key1")
        assert manager.get_cascading("key1") is None


class TestDashboardQueries:
    """Test dashboard query generation."""
    
    def test_anomaly_dashboard_queries(self):
        """Test anomaly dashboard queries."""
        query = AnomalyDashboardQueries.anomaly_rate(TimeRange.LAST_24_HOURS)
        
        assert "anomalies_detected_total" in query
        assert "rate" in query.lower()
    
    def test_scaling_dashboard_queries(self):
        """Test scaling dashboard queries."""
        query = ScalingDashboardQueries.scaling_recommendations()
        
        assert "scaling_recommendations_total" in query
    
    def test_rca_dashboard_queries(self):
        """Test RCA dashboard queries."""
        query = RCADashboardQueries.incidents_analyzed()
        
        assert "incidents_analyzed_total" in query
    
    def test_alerting_dashboard_queries(self):
        """Test alerting dashboard queries."""
        query = AlertingDashboardQueries.alerts_processed()
        
        assert "alerts_processed_total" in query
    
    def test_query_builder_prometheus(self):
        """Test Prometheus query building."""
        query = (DashboardQueryBuilder()
                 .metric("cpu_usage")
                 .time_range(TimeRange.LAST_1_HOUR)
                 .filter("instance", "server1")
                 .aggregation(AggregationType.AVG)
                 .build_prometheus_query())
        
        assert "cpu_usage" in query
        assert "server1" in query


class TestPhase28Integration:
    """End-to-end integration tests."""
    
    def test_complete_export_pipeline(self):
        """Test complete export pipeline."""
        exporter = DataExporter()
        
        # Simulate data
        anomalies = [
            {"id": "1", "metric": "cpu", "value": 95.0, "severity": "CRITICAL"},
            {"id": "2", "metric": "memory", "value": 88.0, "severity": "HIGH"}
        ]
        
        # Export to multiple formats
        json_data = exporter.export_anomalies(anomalies)
        assert json_data is not None
        
        # Export to file
        with tempfile.TemporaryDirectory() as tmpdir:
            csv_config = ExportConfig(format=ExportFormat.CSV)
            file_path = exporter.export_anomalies(anomalies, f"{tmpdir}/anomalies.csv", csv_config)
            assert Path(file_path).exists()
    
    def test_api_request_response_cycle(self):
        """Test API request/response cycle."""
        # Create mock detector
        class MockDetector:
            def detect_anomaly(self, metric_name, value):
                return {"metric": metric_name, "anomaly": True, "severity": "HIGH"}
            
            def get_statistics(self):
                return {"anomalies_found": 5, "models_configured": 3}
        
        detector = MockDetector()
        api = AnomalyDetectionAPI(detector)
        
        # Make request
        request = APIRequest(query={
            "action": "detect",
            "metric_name": "cpu_usage",
            "value": 95.0
        })
        
        response = api.handle_request(request)
        
        assert response.is_success()
        assert response.data is not None
    
    def test_caching_with_persistence(self):
        """Test caching integrated with persistence."""
        cache = MemoryCache()
        persistence = PostgreSQLPersistenceManager()
        persistence.connect()
        
        # Store in both
        anomaly_record = AnomalyRecord(
            metric_name="cpu",
            detected_value=95.0,
            severity="CRITICAL"
        )
        
        # Save to persistence
        assert persistence.save_anomaly(anomaly_record)
        
        # Cache the record
        cache_key = CacheKey.anomaly_detection("cpu")
        cache.set(cache_key, anomaly_record, ttl_seconds=300)
        
        # Retrieve from cache
        cached_record = cache.get(cache_key)
        assert cached_record is not None
    
    def test_query_generation_for_dashboards(self):
        """Test query generation for monitoring dashboards."""
        queries = {
            "anomaly_rate": AnomalyDashboardQueries.anomaly_rate(),
            "scaling_recommendations": ScalingDashboardQueries.scaling_recommendations(),
            "incidents": RCADashboardQueries.incidents_analyzed(),
            "alerts": AlertingDashboardQueries.alerts_processed()
        }
        
        for name, query in queries.items():
            assert query is not None
            assert len(query) > 0


if __name__ == '__main__':
    # Simple test runner
    test_classes = [
        TestDataExport,
        TestAPIStandardization,
        TestPersistence,
        TestCaching,
        TestDashboardQueries,
        TestPhase28Integration
    ]
    
    total_tests = 0
    passed_tests = 0
    
    for test_class in test_classes:
        test_instance = test_class()
        methods = [m for m in dir(test_instance) if m.startswith('test_')]
        
        for method_name in methods:
            total_tests += 1
            try:
                method = getattr(test_instance, method_name)
                method()
                passed_tests += 1
                print(f"✓ {test_class.__name__}.{method_name}")
            except Exception as e:
                print(f"✗ {test_class.__name__}.{method_name}: {e}")
    
    print(f"\n{passed_tests}/{total_tests} tests passed")
