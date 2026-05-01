"""
Tests for dashboard builder and visualization system.
"""

import pytest
import json
from datetime import datetime
from apps.shared.dashboard_builder import (
    DashboardLayout, WidgetType, ThemeMode, DataSource, MetricQuery,
    WidgetThreshold, WidgetOptions, DashboardWidget, DashboardVariable,
    DashboardAnnotation, Dashboard, DashboardBuilder, DashboardManager,
    DashboardTemplate, VisualizationExporter
)


class TestDataSource:
    """Test data source configuration."""
    
    def test_create_datasource(self):
        """Test creating data source."""
        ds = DataSource(
            id="prom1",
            name="Prometheus",
            type="prometheus",
            url="http://localhost:9090"
        )
        
        assert ds.id == "prom1"
        assert ds.type == "prometheus"
    
    def test_datasource_to_dict(self):
        """Test converting to dict."""
        ds = DataSource(
            id="influx1",
            name="InfluxDB",
            type="influxdb",
            url="http://localhost:8086"
        )
        
        d = ds.to_dict()
        assert d["id"] == "influx1"
        assert d["type"] == "influxdb"


class TestMetricQuery:
    """Test metric queries."""
    
    def test_create_query(self):
        """Test creating metric query."""
        query = MetricQuery(
            id="q1",
            datasource_id="prom1",
            query="rate(http_requests_total[1m])"
        )
        
        assert query.query == "rate(http_requests_total[1m])"
        assert query.interval == "30s"
    
    def test_query_to_dict(self):
        """Test converting query to dict."""
        query = MetricQuery(
            id="q2",
            datasource_id="prom1",
            query="cpu_usage"
        )
        
        d = query.to_dict()
        assert d["id"] == "q2"
        assert d["query"] == "cpu_usage"


class TestWidgetThreshold:
    """Test widget thresholds."""
    
    def test_create_threshold(self):
        """Test creating threshold."""
        threshold = WidgetThreshold(
            value=80,
            color="red",
            label="critical"
        )
        
        assert threshold.value == 80
        assert threshold.operator == "gt"
    
    def test_threshold_with_operator(self):
        """Test threshold with custom operator."""
        threshold = WidgetThreshold(
            value=10,
            color="yellow",
            label="warning",
            operator="lt"
        )
        
        assert threshold.operator == "lt"


class TestWidgetOptions:
    """Test widget display options."""
    
    def test_create_options(self):
        """Test creating widget options."""
        options = WidgetOptions(
            title="CPU Usage",
            unit="%",
            decimals=2
        )
        
        assert options.title == "CPU Usage"
        assert options.unit == "%"
    
    def test_options_with_thresholds(self):
        """Test options with thresholds."""
        thresholds = [
            WidgetThreshold(50, "yellow", "warning"),
            WidgetThreshold(80, "red", "critical")
        ]
        
        options = WidgetOptions(
            title="Latency",
            thresholds=thresholds,
            unit="ms"
        )
        
        assert len(options.thresholds) == 2


class TestDashboardWidget:
    """Test dashboard widgets."""
    
    def test_create_widget(self):
        """Test creating widget."""
        query = MetricQuery("q1", "prom1", "metric_name")
        widget = DashboardWidget(
            type=WidgetType.TIMESERIES,
            title="Request Rate",
            queries=[query]
        )
        
        assert widget.type == WidgetType.TIMESERIES
        assert len(widget.queries) == 1
    
    def test_widget_to_dict(self):
        """Test converting widget to dict."""
        query = MetricQuery("q1", "prom1", "cpu_usage")
        widget = DashboardWidget(
            type=WidgetType.GAUGE,
            title="CPU",
            queries=[query],
            x=0,
            y=0,
            width=2,
            height=2
        )
        
        d = widget.to_dict()
        assert d["type"] == "gauge"
        assert d["width"] == 2
        assert len(d["queries"]) == 1
    
    def test_widget_sizing(self):
        """Test widget sizing."""
        widget = DashboardWidget(
            title="Test",
            width=6,
            height=4
        )
        
        assert widget.width == 6
        assert widget.height == 4


class TestDashboardVariable:
    """Test dashboard template variables."""
    
    def test_create_variable(self):
        """Test creating variable."""
        var = DashboardVariable(
            name="service",
            type="query",
            value="api",
            label="Service"
        )
        
        assert var.name == "service"
        assert var.value == "api"
    
    def test_variable_with_options(self):
        """Test variable with options."""
        var = DashboardVariable(
            name="environment",
            type="query",
            value="prod",
            options=["dev", "staging", "prod"],
            multi=False
        )
        
        assert len(var.options) == 3


class TestDashboardAnnotation:
    """Test dashboard annotations."""
    
    def test_create_annotation(self):
        """Test creating annotation."""
        annotation = DashboardAnnotation(
            name="deployments",
            datasource_id="prom1",
            query="deployment_events",
            tags=["deployment", "release"]
        )
        
        assert annotation.name == "deployments"
        assert len(annotation.tags) == 2


class TestDashboard:
    """Test dashboard configuration."""
    
    def test_create_dashboard(self):
        """Test creating dashboard."""
        dashboard = Dashboard(
            title="System Metrics",
            description="CPU, Memory, Disk"
        )
        
        assert dashboard.title == "System Metrics"
        assert dashboard.layout == DashboardLayout.GRID
    
    def test_dashboard_to_dict(self):
        """Test converting dashboard to dict."""
        dashboard = Dashboard(
            title="API Metrics",
            tags=["api", "monitoring"]
        )
        
        d = dashboard.to_dict()
        assert d["title"] == "API Metrics"
        assert "api" in d["tags"]
    
    def test_dashboard_to_json(self):
        """Test converting dashboard to JSON."""
        dashboard = Dashboard(
            title="Test Dashboard",
            tags=["test"]
        )
        
        json_str = dashboard.to_json()
        assert isinstance(json_str, str)
        
        # Verify it's valid JSON
        data = json.loads(json_str)
        assert data["title"] == "Test Dashboard"
    
    def test_dashboard_from_dict(self):
        """Test loading dashboard from dict."""
        original = Dashboard(
            title="Original Dashboard",
            tags=["test"]
        )
        
        data = original.to_dict()
        restored = Dashboard.from_dict(data)
        
        assert restored.title == original.title
        assert restored.tags == original.tags


class TestDashboardBuilder:
    """Test fluent dashboard builder."""
    
    def test_builder_basic(self):
        """Test basic builder."""
        dashboard = DashboardBuilder() \
            .set_title("Test Dashboard") \
            .set_description("Test description") \
            .build()
        
        assert dashboard.title == "Test Dashboard"
        assert dashboard.description == "Test description"
    
    def test_builder_add_datasource(self):
        """Test adding data source."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_datasource("Prometheus", "prometheus", "http://localhost:9090") \
            .build()
        
        assert len(dashboard.datasources) == 1
        assert dashboard.datasources[0].name == "Prometheus"
    
    def test_builder_add_tag(self):
        """Test adding tags."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_tag("production") \
            .add_tag("monitoring") \
            .build()
        
        assert len(dashboard.tags) == 2
        assert "production" in dashboard.tags
    
    def test_builder_add_variable(self):
        """Test adding variables."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_variable("env", "query", "prod", options=["dev", "prod"]) \
            .build()
        
        assert len(dashboard.variables) == 1
        assert dashboard.variables[0].name == "env"
    
    def test_builder_add_timeseries_widget(self):
        """Test adding timeseries widget."""
        dashboard = DashboardBuilder() \
            .add_datasource("Prometheus", "prometheus", "http://localhost:9090") \
            .set_title("Dashboard") \
            .add_timeseries_widget("CPU Usage", "cpu_usage", "prometheus_id") \
            .build()
        
        assert len(dashboard.widgets) == 1
        assert dashboard.widgets[0].type == WidgetType.TIMESERIES
    
    def test_builder_add_gauge_widget(self):
        """Test adding gauge widget."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_gauge_widget("Memory", "memory_usage", "prometheus_id", 0, 100) \
            .build()
        
        assert len(dashboard.widgets) == 1
        assert dashboard.widgets[0].type == WidgetType.GAUGE
    
    def test_builder_add_stat_widget(self):
        """Test adding stat widget."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_stat_widget("Error Count", "errors", "prometheus_id", unit="count") \
            .build()
        
        assert len(dashboard.widgets) == 1
        assert dashboard.widgets[0].type == WidgetType.STAT
    
    def test_builder_add_table_widget(self):
        """Test adding table widget."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .add_table_widget("Top Services", "services", "prometheus_id") \
            .build()
        
        assert len(dashboard.widgets) == 1
        assert dashboard.widgets[0].type == WidgetType.TABLE
    
    def test_builder_set_time_range(self):
        """Test setting time range."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .set_time_range("now-24h", "now") \
            .build()
        
        assert dashboard.time_range_from == "now-24h"
        assert dashboard.time_range_to == "now"
    
    def test_builder_set_refresh_interval(self):
        """Test setting refresh interval."""
        dashboard = DashboardBuilder() \
            .set_title("Dashboard") \
            .set_refresh_interval("1m") \
            .build()
        
        assert dashboard.refresh_interval == "1m"


class TestDashboardManager:
    """Test dashboard management."""
    
    def setup_method(self):
        """Setup for each test."""
        self.manager = DashboardManager()
    
    def test_create_dashboard(self):
        """Test creating dashboard."""
        dashboard = Dashboard(title="Test")
        dashboard_id = self.manager.create(dashboard)
        
        assert dashboard_id is not None
        assert self.manager.get(dashboard_id) is not None
    
    def test_get_dashboard(self):
        """Test getting dashboard."""
        dashboard = Dashboard(title="Test Dashboard")
        dashboard_id = self.manager.create(dashboard)
        
        retrieved = self.manager.get(dashboard_id)
        
        assert retrieved is not None
        assert retrieved.title == "Test Dashboard"
    
    def test_list_dashboards(self):
        """Test listing dashboards."""
        for i in range(3):
            d = Dashboard(title=f"Dashboard {i}")
            self.manager.create(d)
        
        dashboards = self.manager.list()
        assert len(dashboards) == 3
    
    def test_list_by_tags(self):
        """Test filtering dashboards by tags."""
        d1 = Dashboard(title="API", tags=["api", "production"])
        d2 = Dashboard(title="Database", tags=["database", "production"])
        d3 = Dashboard(title="Dev", tags=["development"])
        
        self.manager.create(d1)
        self.manager.create(d2)
        self.manager.create(d3)
        
        prod_dashboards = self.manager.list(tags=["production"])
        
        assert len(prod_dashboards) == 2
    
    def test_update_dashboard(self):
        """Test updating dashboard."""
        dashboard = Dashboard(title="Original")
        dashboard_id = self.manager.create(dashboard)
        
        dashboard.title = "Updated"
        assert self.manager.update(dashboard) is True
        
        retrieved = self.manager.get(dashboard_id)
        assert retrieved.title == "Updated"
    
    def test_delete_dashboard(self):
        """Test deleting dashboard."""
        dashboard = Dashboard(title="To Delete")
        dashboard_id = self.manager.create(dashboard)
        
        assert self.manager.delete(dashboard_id) is True
        assert self.manager.get(dashboard_id) is None
    
    def test_export_dashboard(self):
        """Test exporting dashboard."""
        dashboard = Dashboard(title="Export Test")
        dashboard_id = self.manager.create(dashboard)
        
        json_str = self.manager.export(dashboard_id)
        
        assert json_str is not None
        data = json.loads(json_str)
        assert data["title"] == "Export Test"
    
    def test_import_dashboard(self):
        """Test importing dashboard."""
        original = Dashboard(title="Import Test")
        original_id = self.manager.create(original)
        
        json_str = self.manager.export(original_id)
        
        # Clear manager and reimport
        self.manager = DashboardManager()
        new_id = self.manager.import_json(json_str)
        
        assert new_id is not None
        imported = self.manager.get(new_id)
        assert imported.title == "Import Test"


class TestDashboardTemplate:
    """Test pre-built templates."""
    
    def test_system_metrics_template(self):
        """Test system metrics template."""
        dashboard = DashboardTemplate.system_metrics_template("prometheus_id")
        
        assert dashboard.title == "System Metrics"
        assert len(dashboard.widgets) > 0
        assert "system" in dashboard.tags
    
    def test_application_metrics_template(self):
        """Test application metrics template."""
        dashboard = DashboardTemplate.application_metrics_template("prometheus_id")
        
        assert dashboard.title == "Application Metrics"
        assert len(dashboard.widgets) > 0
        assert "application" in dashboard.tags
    
    def test_trace_metrics_template(self):
        """Test trace metrics template."""
        dashboard = DashboardTemplate.trace_metrics_template("prometheus_id")
        
        assert dashboard.title == "Distributed Tracing"
        assert len(dashboard.widgets) > 0
        assert "tracing" in dashboard.tags


class TestVisualizationExporter:
    """Test visualization export."""
    
    def test_export_json(self):
        """Test JSON export."""
        dashboard = Dashboard(title="Test")
        json_str = VisualizationExporter.export_json(dashboard)
        
        assert isinstance(json_str, str)
        data = json.loads(json_str)
        assert data["title"] == "Test"
    
    def test_export_grafana_json(self):
        """Test Grafana JSON export."""
        dashboard = DashboardBuilder() \
            .set_title("Grafana Test") \
            .add_timeseries_widget("CPU", "cpu_usage", "prom1") \
            .build()
        
        json_str = VisualizationExporter.export_grafana_json(dashboard)
        
        assert isinstance(json_str, str)
        data = json.loads(json_str)
        assert "dashboard" in data
        assert data["dashboard"]["title"] == "Grafana Test"


class TestDashboardIntegration:
    """Integration tests for dashboard workflow."""
    
    def test_build_and_manage_dashboard(self):
        """Test complete dashboard workflow."""
        # Build
        dashboard = DashboardBuilder() \
            .set_title("Production Metrics") \
            .add_datasource("Prometheus", "prometheus", "http://localhost:9090") \
            .add_tag("production") \
            .add_variable("env", "query", "prod") \
            .add_timeseries_widget("Request Rate", "rate(requests[1m])", "prometheus_id") \
            .add_gauge_widget("Error Rate", "errors_percent", "prometheus_id") \
            .set_refresh_interval("30s") \
            .build()
        
        # Manage
        manager = DashboardManager()
        dashboard_id = manager.create(dashboard)
        
        # Retrieve and verify
        retrieved = manager.get(dashboard_id)
        assert retrieved.title == "Production Metrics"
        assert len(retrieved.widgets) == 2
        assert len(retrieved.variables) == 1
        
        # Export
        json_str = manager.export(dashboard_id)
        assert json_str is not None
        
        # Import
        manager2 = DashboardManager()
        new_id = manager2.import_json(json_str)
        assert manager2.get(new_id).title == "Production Metrics"
