"""
Phase 26B Integration Tests

Comprehensive testing for GraphQL API and business metrics modules.
Tests cover GraphQL operations, SDK generation, KPI tracking, and correlation analysis.
"""

import pytest
from datetime import datetime, timedelta
from apps.integration.graphql_api import (
    GraphQLSchema,
    GraphQLField,
    GraphQLType,
    GraphQLRequest,
    GraphQLResponse,
    GraphQLResolver,
    SDKGenerator,
    SDKLanguage,
    SDKConfig,
    GraphQLAPI,
)
from apps.integration.business_metrics import (
    KPIEngine,
    KPI,
    KPITarget,
    KPIType,
    BusinessMetric,
    BusinessDashboard,
    MetricCorrelationEngine,
    KPICorrelation,
    MetricAlignment,
)


class TestGraphQLSchema:
    """Test suite for GraphQL schema."""

    def test_schema_creation(self):
        """Test creating GraphQL schema."""
        schema = GraphQLSchema()
        assert len(schema.types) > 0
        assert len(schema.query_fields) > 0
        assert len(schema.mutation_fields) > 0

    def test_schema_types(self):
        """Test GraphQL types are defined."""
        schema = GraphQLSchema()
        assert "Metric" in schema.types
        assert "Alert" in schema.types
        assert "Trace" in schema.types

    def test_schema_input_types(self):
        """Test GraphQL input types."""
        schema = GraphQLSchema()
        assert "MetricInput" in schema.input_types
        assert "AlertInput" in schema.input_types

    def test_query_fields(self):
        """Test query field definitions."""
        schema = GraphQLSchema()
        assert "metrics" in schema.query_fields
        assert "alerts" in schema.query_fields
        assert "traces" in schema.query_fields

    def test_mutation_fields(self):
        """Test mutation field definitions."""
        schema = GraphQLSchema()
        assert "createMetric" in schema.mutation_fields
        assert "createAlert" in schema.mutation_fields
        assert "acknowledgeAlert" in schema.mutation_fields

    def test_schema_to_string(self):
        """Test schema to SDL string conversion."""
        schema = GraphQLSchema()
        schema_str = schema.to_schema_string()
        assert "type Query" in schema_str
        assert "type Mutation" in schema_str
        assert "type Metric" in schema_str


class TestGraphQLResolver:
    """Test suite for GraphQL resolver."""

    def test_register_query(self):
        """Test registering query resolver."""
        resolver = GraphQLResolver()

        def test_query(**args):
            return "test_result"

        resolver.register_query("testQuery", test_query)
        assert "testQuery" in resolver.query_resolvers

    def test_resolve_query(self):
        """Test resolving query."""
        resolver = GraphQLResolver()

        def test_query(**args):
            return "test_result"

        resolver.register_query("testQuery", test_query)
        success, result = resolver.resolve_query("testQuery", {})

        assert success == True
        assert result == "test_result"

    def test_resolve_mutation(self):
        """Test resolving mutation."""
        resolver = GraphQLResolver()

        def test_mutation(**args):
            return True

        resolver.register_mutation("testMutation", test_mutation)
        success, result = resolver.resolve_mutation("testMutation", {})

        assert success == True
        assert result == True

    def test_resolve_nonexistent_query(self):
        """Test resolving nonexistent query."""
        resolver = GraphQLResolver()
        success, result = resolver.resolve_query("nonexistent", {})

        assert success == False
        assert "not found" in result.lower()


class TestGraphQLAPI:
    """Test suite for GraphQL API."""

    def test_api_creation(self):
        """Test creating GraphQL API."""
        api = GraphQLAPI()
        assert api.request_count == 0
        assert api.error_count == 0

    def test_schema_string(self):
        """Test getting schema string."""
        api = GraphQLAPI()
        schema_str = api.get_schema_string()
        assert "type Query" in schema_str
        assert "type Mutation" in schema_str

    def test_execute_query(self):
        """Test executing GraphQL query."""
        api = GraphQLAPI()
        request = GraphQLRequest(query="query { metrics }")
        response = api.execute(request)

        assert isinstance(response, GraphQLResponse)
        assert api.request_count >= 1

    def test_api_statistics(self):
        """Test API statistics."""
        api = GraphQLAPI()
        request = GraphQLRequest(query="query { metrics }")
        api.execute(request)

        stats = api.get_statistics()
        assert stats["total_requests"] >= 1
        assert "error_rate" in stats

    def test_request_validation(self):
        """Test query validation."""
        api = GraphQLAPI()
        invalid_request = GraphQLRequest(query="invalid query")
        response = api.execute(invalid_request)

        # Should either validate or error gracefully
        assert isinstance(response, GraphQLResponse)


class TestSDKGenerator:
    """Test suite for SDK code generation."""

    def test_sdk_generator_creation(self):
        """Test creating SDK generator."""
        schema = GraphQLSchema()
        generator = SDKGenerator(schema)
        assert generator.schema is not None

    def test_generate_python_sdk(self):
        """Test generating Python SDK."""
        schema = GraphQLSchema()
        generator = SDKGenerator(schema)
        config = SDKConfig(
            language=SDKLanguage.PYTHON,
            package_name="observability_sdk",
            version="1.0.0",
            authors=["Test Team"],
        )

        sdk_code = generator.generate_python_sdk(config)
        assert "GraphQLClient" in sdk_code
        assert "class Metric" in sdk_code
        assert "version" in sdk_code

    def test_generate_javascript_sdk(self):
        """Test generating JavaScript SDK."""
        schema = GraphQLSchema()
        generator = SDKGenerator(schema)
        config = SDKConfig(
            language=SDKLanguage.JAVASCRIPT,
            package_name="observability-sdk",
            version="1.0.0",
            authors=["Test Team"],
        )

        sdk_code = generator.generate_javascript_sdk(config)
        assert "GraphQLClient" in sdk_code
        assert "async query" in sdk_code

    def test_generate_go_sdk(self):
        """Test generating Go SDK."""
        schema = GraphQLSchema()
        generator = SDKGenerator(schema)
        config = SDKConfig(
            language=SDKLanguage.GO,
            package_name="observability",
            version="1.0.0",
            authors=["Test Team"],
        )

        sdk_code = generator.generate_go_sdk(config)
        assert "GraphQLClient" in sdk_code
        assert "package" in sdk_code

    def test_generate_sdk_dispatch(self):
        """Test SDK generation dispatch."""
        schema = GraphQLSchema()
        generator = SDKGenerator(schema)
        config = SDKConfig(
            language=SDKLanguage.PYTHON,
            package_name="test",
            version="1.0.0",
        )

        sdk_code = generator.generate_sdk(SDKLanguage.PYTHON, config)
        assert len(sdk_code) > 0
        assert "GraphQLClient" in sdk_code


class TestBusinessMetrics:
    """Test suite for business metrics."""

    def test_kpi_engine_creation(self):
        """Test creating KPI engine."""
        engine = KPIEngine()
        assert len(engine.kpis) > 0  # Should have default KPIs

    def test_create_kpi(self):
        """Test creating custom KPI."""
        engine = KPIEngine()
        kpi = KPI(
            kpi_id="custom-kpi",
            name="Custom KPI",
            description="Test KPI",
            kpi_type=KPIType.EFFICIENCY,
            target=KPITarget(target_value=100, warning_threshold=80, critical_threshold=50),
            calculation_method="average",
        )

        success, msg = engine.create_kpi(kpi)
        assert success == True
        assert "custom-kpi" in engine.kpis

    def test_record_business_metric(self):
        """Test recording business metric."""
        engine = KPIEngine()
        metric = BusinessMetric(
            metric_id="revenue",
            name="Total Revenue",
            description="Total revenue today",
            unit="USD",
            current_value=50000,
            timestamp=datetime.utcnow(),
            source="billing_system",
        )

        result = engine.record_business_metric(metric)
        assert result == True
        assert "revenue" in engine.business_metrics

    def test_calculate_kpi(self):
        """Test calculating KPI value."""
        engine = KPIEngine()
        success, msg = engine.calculate_kpi("uptime", 99.95)

        assert success == True
        kpi = engine.kpis["uptime"]
        assert len(kpi.history) > 0
        assert kpi.get_current_value() == 99.95

    def test_kpi_trend_tracking(self):
        """Test tracking KPI trends."""
        engine = KPIEngine()
        engine.calculate_kpi("uptime", 99.0)
        engine.calculate_kpi("uptime", 99.5)
        engine.calculate_kpi("uptime", 99.9)

        kpi = engine.kpis["uptime"]
        trend = kpi.get_trend()
        assert trend == "up"

    def test_kpi_variance_calculation(self):
        """Test variance from target calculation."""
        engine = KPIEngine()
        engine.calculate_kpi("uptime", 99.95)

        kpi = engine.kpis["uptime"]
        variance = kpi.get_variance_from_target()
        # Current is 99.95, target is 99.9, so ~0.05% above target
        assert variance > 0

    def test_kpi_health_status(self):
        """Test KPI health status determination."""
        engine = KPIEngine()
        kpi = KPI(
            kpi_id="test-health",
            name="Test",
            description="Test",
            kpi_type=KPIType.RELIABILITY,
            target=KPITarget(target_value=100, warning_threshold=80, critical_threshold=50),
            calculation_method="average",
        )
        engine.create_kpi(kpi)

        engine.calculate_kpi("test-health", 90)
        assert engine.kpis["test-health"].get_health_status() == "healthy"

        engine.calculate_kpi("test-health", 60)
        assert engine.kpis["test-health"].get_health_status() == "warning"

        engine.calculate_kpi("test-health", 40)
        assert engine.kpis["test-health"].get_health_status() == "critical"

    def test_kpi_forecasting(self):
        """Test KPI value forecasting."""
        engine = KPIEngine()
        for i in range(10):
            engine.calculate_kpi("uptime", 99.0 + i * 0.1)

        forecast = engine.forecast_kpi("uptime", days_ahead=7)
        assert forecast is not None
        assert forecast > 99.0

    def test_correlate_metrics(self):
        """Test metric correlation discovery."""
        engine = KPIEngine()
        success, coefficient = engine.correlate_metrics("uptime", "incident_count", "active_users")

        assert success == True
        assert -1.0 <= coefficient <= 1.0

    def test_create_dashboard(self):
        """Test creating business dashboard."""
        engine = KPIEngine()
        dashboard = BusinessDashboard(
            dashboard_id="main",
            name="Main Dashboard",
            description="Main business dashboard",
            kpi_ids=["uptime", "mttr"],
        )

        success, msg = engine.create_dashboard(dashboard)
        assert success == True
        assert "main" in engine.dashboards

    def test_get_dashboard(self):
        """Test retrieving dashboard."""
        engine = KPIEngine()
        dashboard = BusinessDashboard(
            dashboard_id="test",
            name="Test Dashboard",
            description="Test",
            kpi_ids=["uptime"],
        )
        engine.create_dashboard(dashboard)

        retrieved = engine.get_dashboard("test")
        assert retrieved is not None
        assert retrieved["name"] == "Test Dashboard"
        assert len(retrieved["kpis"]) > 0

    def test_engine_statistics(self):
        """Test engine statistics."""
        engine = KPIEngine()
        engine.calculate_kpi("uptime", 99.95)

        stats = engine.get_statistics()
        assert stats["total_kpis"] > 0
        assert "healthy_kpis" in stats
        assert "critical_kpis" in stats

    def test_kpi_alert_on_critical(self):
        """Test alert generation on critical KPI."""
        engine = KPIEngine()
        kpi = KPI(
            kpi_id="alert-test",
            name="Alert Test",
            description="Test",
            kpi_type=KPIType.RELIABILITY,
            target=KPITarget(target_value=100, warning_threshold=80, critical_threshold=50),
            calculation_method="average",
        )
        engine.create_kpi(kpi)

        engine.calculate_kpi("alert-test", 40)  # Below critical threshold
        assert len(engine.alerts) > 0

    def test_business_metric_to_dict(self):
        """Test converting business metric to dict."""
        metric = BusinessMetric(
            metric_id="test",
            name="Test Metric",
            description="Test",
            unit="count",
            current_value=42,
            timestamp=datetime.utcnow(),
            source="test_system",
        )

        data = metric.to_dict()
        assert data["metric_id"] == "test"
        assert data["current_value"] == 42


class TestMetricCorrelationEngine:
    """Test suite for metric correlation engine."""

    def test_correlation_engine_creation(self):
        """Test creating correlation engine."""
        engine = MetricCorrelationEngine()
        assert len(engine.correlations) == 0

    def test_correlation_calculation(self):
        """Test calculating correlation coefficient."""
        engine = MetricCorrelationEngine()
        series1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        series2 = [2.0, 4.0, 6.0, 8.0, 10.0]

        correlation = engine.calculate_correlation(series1, series2)
        assert -1.0 <= correlation <= 1.0
        assert correlation > 0.9  # Perfect correlation

    def test_negative_correlation(self):
        """Test negative correlation."""
        engine = MetricCorrelationEngine()
        series1 = [1.0, 2.0, 3.0, 4.0, 5.0]
        series2 = [5.0, 4.0, 3.0, 2.0, 1.0]

        correlation = engine.calculate_correlation(series1, series2)
        assert correlation < -0.9  # Near perfect negative correlation

    def test_add_correlation(self):
        """Test adding correlation."""
        engine = MetricCorrelationEngine()
        correlation = KPICorrelation(
            correlation_id="test",
            kpi_id="uptime",
            technical_metric="error_rate",
            business_metric="revenue",
            correlation_coefficient=0.85,
            alignment=MetricAlignment.INVERSE,
            impact_percentage=40.0,
        )

        engine.add_correlation(correlation)
        assert len(engine.correlations) == 1

    def test_get_correlations_for_kpi(self):
        """Test retrieving correlations for KPI."""
        engine = MetricCorrelationEngine()

        for i in range(3):
            correlation = KPICorrelation(
                correlation_id=f"test-{i}",
                kpi_id="uptime",
                technical_metric=f"metric{i}",
                business_metric=f"business{i}",
                correlation_coefficient=0.5 + i * 0.1,
                alignment=MetricAlignment.DIRECT,
                impact_percentage=20.0,
            )
            engine.add_correlation(correlation)

        correlations = engine.get_correlations_for_kpi("uptime")
        assert len(correlations) == 3


class TestPhase26BIntegration:
    """Integration tests between GraphQL and business metrics."""

    def test_graphql_kpi_query(self):
        """Test querying KPIs via GraphQL."""
        api = GraphQLAPI()
        engine = KPIEngine()

        engine.calculate_kpi("uptime", 99.95)
        request = GraphQLRequest(query="query { kpi }")
        response = api.execute(request)

        assert isinstance(response, GraphQLResponse)

    def test_end_to_end_graphql_workflow(self):
        """Test complete GraphQL workflow."""
        api = GraphQLAPI()

        # Query schema
        schema_str = api.get_schema_string()
        assert len(schema_str) > 0

        # Execute query
        request = GraphQLRequest(query="query { metrics }")
        response = api.execute(request)
        assert isinstance(response, GraphQLResponse)

        # Get statistics
        stats = api.get_statistics()
        assert stats["total_requests"] >= 1

    def test_end_to_end_kpi_workflow(self):
        """Test complete KPI workflow."""
        engine = KPIEngine()

        # Record metrics
        metric = BusinessMetric(
            metric_id="revenue",
            name="Revenue",
            description="Revenue",
            unit="USD",
            current_value=100000,
            timestamp=datetime.utcnow(),
            source="billing",
        )
        engine.record_business_metric(metric)

        # Calculate KPI
        engine.calculate_kpi("uptime", 99.95)

        # Create dashboard
        dashboard = BusinessDashboard(
            dashboard_id="exec",
            name="Executive Dashboard",
            description="Exec view",
            kpi_ids=["uptime"],
            business_metrics=["revenue"],
        )
        engine.create_dashboard(dashboard)

        # Get dashboard
        retrieved = engine.get_dashboard("exec")
        assert retrieved is not None
        assert len(retrieved["kpis"]) > 0
