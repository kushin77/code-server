"""
Tests for advanced visualization and real-time UI system.
"""

import pytest
from datetime import datetime, timedelta
from apps.shared.advanced_visualization import (
    VisualizationType, InteractionMode, DataPoint, VisualizationData,
    VisualizationConfig, InteractionEvent, TimeSeriesVisualization,
    GaugeVisualization, HeatmapVisualization, StatVisualization,
    TableVisualization, HistogramVisualization, RealTimeDataStream,
    DashboardLayout, ReactiveDashboard
)


class TestDataPoint:
    """Test data point creation."""
    
    def test_create_data_point(self):
        """Test creating data point."""
        now = datetime.utcnow()
        point = DataPoint(
            timestamp=now,
            value=42.5,
            label="metric1"
        )
        
        assert point.value == 42.5
        assert point.label == "metric1"


class TestVisualizationData:
    """Test visualization data source."""
    
    def test_create_visualization_data(self):
        """Test creating visualization data."""
        data = VisualizationData(name="cpu_usage")
        
        assert data.name == "cpu_usage"
        assert len(data.points) == 0
    
    def test_add_point(self):
        """Test adding data point."""
        data = VisualizationData()
        point = DataPoint(datetime.utcnow(), 50.0)
        
        data.add_point(point)
        
        assert len(data.points) == 1
        assert data.points[0].value == 50.0
    
    def test_add_multiple_points(self):
        """Test adding multiple points."""
        data = VisualizationData()
        points = [
            DataPoint(datetime.utcnow() - timedelta(seconds=i), float(50 + i))
            for i in range(5)
        ]
        
        data.add_points(points)
        
        assert len(data.points) == 5
    
    def test_get_latest(self):
        """Test getting latest points."""
        data = VisualizationData()
        
        for i in range(20):
            data.add_point(DataPoint(datetime.utcnow(), float(i)))
        
        latest = data.get_latest(5)
        assert len(latest) == 5
    
    def test_get_time_range(self):
        """Test getting points in time range."""
        data = VisualizationData()
        now = datetime.utcnow()
        
        for i in range(10):
            data.add_point(
                DataPoint(now + timedelta(seconds=i), float(i))
            )
        
        start = now + timedelta(seconds=2)
        end = now + timedelta(seconds=7)
        
        points = data.get_time_range(start, end)
        assert len(points) > 0


class TestVisualizationConfig:
    """Test visualization configuration."""
    
    def test_create_config(self):
        """Test creating visualization config."""
        config = VisualizationConfig(
            type=VisualizationType.TIMESERIES,
            title="Latency"
        )
        
        assert config.title == "Latency"
        assert config.type == VisualizationType.TIMESERIES
    
    def test_config_to_dict(self):
        """Test converting config to dict."""
        config = VisualizationConfig(
            type=VisualizationType.GAUGE,
            title="Temperature"
        )
        
        d = config.to_dict()
        assert d["type"] == "gauge"
        assert d["title"] == "Temperature"


class TestInteractionEvent:
    """Test interaction events."""
    
    def test_create_event(self):
        """Test creating interaction event."""
        event = InteractionEvent(
            visualization_id="vis_123",
            event_type="click",
            data={"x": 100, "y": 200}
        )
        
        assert event.event_type == "click"
        assert event.data["x"] == 100
    
    def test_event_to_dict(self):
        """Test converting event to dict."""
        event = InteractionEvent(
            visualization_id="vis_456",
            event_type="drill_down",
            data={"metric": "cpu"}
        )
        
        d = event.to_dict()
        assert d["visualization_id"] == "vis_456"
        assert d["event_type"] == "drill_down"


class TestTimeSeriesVisualization:
    """Test time series visualization."""
    
    def test_render_empty(self):
        """Test rendering without data."""
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        vis = TimeSeriesVisualization(config)
        
        rendered = vis.render()
        assert rendered["type"] == "timeseries"
        assert len(rendered["data"]) == 0
    
    def test_render_with_data(self):
        """Test rendering with data."""
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        vis = TimeSeriesVisualization(config)
        
        data = VisualizationData()
        for i in range(5):
            data.add_point(DataPoint(datetime.utcnow(), float(i)))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert len(rendered["data"]) == 5


class TestGaugeVisualization:
    """Test gauge visualization."""
    
    def test_render_gauge(self):
        """Test rendering gauge."""
        config = VisualizationConfig(
            type=VisualizationType.GAUGE,
            options={"min": 0, "max": 100}
        )
        vis = GaugeVisualization(config)
        
        data = VisualizationData()
        data.add_point(DataPoint(datetime.utcnow(), 75.0))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert rendered["type"] == "gauge"
        assert rendered["value"] == 75.0


class TestHeatmapVisualization:
    """Test heatmap visualization."""
    
    def test_render_heatmap(self):
        """Test rendering heatmap."""
        config = VisualizationConfig(type=VisualizationType.HEATMAP)
        vis = HeatmapVisualization(config)
        
        data = VisualizationData()
        data.add_point(DataPoint(datetime.utcnow(), 50.0, label="region1"))
        data.add_point(DataPoint(datetime.utcnow(), 60.0, label="region2"))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert rendered["type"] == "heatmap"
        assert len(rendered["data"]) > 0


class TestStatVisualization:
    """Test stat visualization."""
    
    def test_render_stat_with_change(self):
        """Test rendering stat with change."""
        config = VisualizationConfig(type=VisualizationType.STAT)
        vis = StatVisualization(config)
        
        data = VisualizationData()
        data.add_point(DataPoint(datetime.utcnow() - timedelta(seconds=10), 100.0))
        data.add_point(DataPoint(datetime.utcnow(), 110.0))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert rendered["value"] == 110.0
        assert rendered["change_percent"] > 0


class TestTableVisualization:
    """Test table visualization."""
    
    def test_render_table(self):
        """Test rendering table."""
        config = VisualizationConfig(type=VisualizationType.TABLE)
        vis = TableVisualization(config)
        
        data = VisualizationData()
        data.add_point(DataPoint(
            datetime.utcnow(), 50.0,
            metadata={"host": "server1", "region": "us-east"}
        ))
        data.add_point(DataPoint(
            datetime.utcnow(), 60.0,
            metadata={"host": "server2", "region": "us-west"}
        ))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert rendered["type"] == "table"
        assert len(rendered["rows"]) == 2


class TestHistogramVisualization:
    """Test histogram visualization."""
    
    def test_render_histogram(self):
        """Test rendering histogram."""
        config = VisualizationConfig(
            type=VisualizationType.HISTOGRAM,
            options={"bins": 10}
        )
        vis = HistogramVisualization(config)
        
        data = VisualizationData()
        for i in range(100):
            data.add_point(DataPoint(datetime.utcnow(), float(i % 50)))
        
        vis.set_data(data)
        rendered = vis.render()
        
        assert rendered["type"] == "histogram"
        assert len(rendered["bins"]) == 10


class TestRealTimeDataStream:
    """Test real-time data streaming."""
    
    def test_subscribe_and_publish(self):
        """Test subscribing and publishing."""
        stream = RealTimeDataStream()
        received = []
        
        def callback(data):
            received.append(data)
        
        stream.subscribe("stream1", callback)
        point = DataPoint(datetime.utcnow(), 50.0)
        
        stream.publish("stream1", point)
        
        assert len(received) == 1
        assert received[0].value == 50.0
    
    def test_multiple_subscribers(self):
        """Test multiple subscribers."""
        stream = RealTimeDataStream()
        received1 = []
        received2 = []
        
        stream.subscribe("stream1", lambda d: received1.append(d))
        stream.subscribe("stream1", lambda d: received2.append(d))
        
        point = DataPoint(datetime.utcnow(), 75.0)
        stream.publish("stream1", point)
        
        assert len(received1) == 1
        assert len(received2) == 1
    
    def test_unsubscribe(self):
        """Test unsubscribing."""
        stream = RealTimeDataStream()
        received = []
        
        callback = lambda d: received.append(d)
        stream.subscribe("stream1", callback)
        stream.unsubscribe("stream1", callback)
        
        stream.publish("stream1", DataPoint(datetime.utcnow(), 50.0))
        
        assert len(received) == 0
    
    def test_broadcast(self):
        """Test broadcasting."""
        stream = RealTimeDataStream()
        received1 = []
        received2 = []
        
        stream.subscribe("stream1", lambda d: received1.append(d))
        stream.subscribe("stream2", lambda d: received2.append(d))
        
        point = DataPoint(datetime.utcnow(), 100.0)
        stream.broadcast(point)
        
        assert len(received1) == 1
        assert len(received2) == 1


class TestDashboardLayout:
    """Test dashboard layout."""
    
    def test_create_layout(self):
        """Test creating layout."""
        layout = DashboardLayout()
        
        assert layout.auto_refresh is True
        assert len(layout.rows) == 0
    
    def test_add_row(self):
        """Test adding row."""
        layout = DashboardLayout()
        configs = [
            VisualizationConfig(type=VisualizationType.TIMESERIES),
            VisualizationConfig(type=VisualizationType.GAUGE),
        ]
        
        layout.add_row(configs)
        
        assert len(layout.rows) == 1
        assert len(layout.rows[0]) == 2


class TestReactiveDashboard:
    """Test reactive dashboard."""
    
    def test_create_dashboard(self):
        """Test creating dashboard."""
        dashboard = ReactiveDashboard()
        
        assert dashboard.id is not None
        assert len(dashboard.visualizations) == 0
    
    def test_add_visualization(self):
        """Test adding visualization."""
        dashboard = ReactiveDashboard()
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        
        vis = dashboard.add_visualization(config)
        
        assert len(dashboard.visualizations) == 1
    
    def test_add_data_source(self):
        """Test adding data source."""
        dashboard = ReactiveDashboard()
        data = VisualizationData(name="metric1")
        
        dashboard.add_data_source(data)
        
        assert len(dashboard.data_sources) == 1
    
    def test_connect_visualization_to_data(self):
        """Test connecting visualization to data."""
        dashboard = ReactiveDashboard()
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        vis = dashboard.add_visualization(config)
        
        data = VisualizationData()
        data.add_point(DataPoint(datetime.utcnow(), 50.0))
        dashboard.add_data_source(data)
        
        dashboard.connect(config.id, data.id)
        
        rendered = vis.render()
        assert len(rendered["data"]) == 1
    
    def test_render_dashboard(self):
        """Test rendering dashboard."""
        dashboard = ReactiveDashboard()
        config = VisualizationConfig(type=VisualizationType.STAT)
        dashboard.add_visualization(config)
        
        rendered = dashboard.render()
        
        assert rendered["id"] == dashboard.id
        assert len(rendered["visualizations"]) == 1
    
    def test_handle_interaction(self):
        """Test handling user interaction."""
        dashboard = ReactiveDashboard()
        config = VisualizationConfig()
        dashboard.add_visualization(config)
        
        event = InteractionEvent(
            visualization_id=config.id,
            event_type="click"
        )
        
        dashboard.on_interaction(event)
        
        assert len(dashboard.interaction_history) == 1
    
    def test_get_state(self):
        """Test getting dashboard state."""
        dashboard = ReactiveDashboard()
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        dashboard.add_visualization(config)
        
        data = VisualizationData()
        dashboard.add_data_source(data)
        
        state = dashboard.get_state()
        
        assert state["id"] == dashboard.id
        assert len(state["visualizations"]) == 1


class TestIntegration:
    """Integration tests for visualization system."""
    
    def test_complete_dashboard_workflow(self):
        """Test complete dashboard workflow."""
        # Create dashboard
        dashboard = ReactiveDashboard()
        
        # Add visualizations
        timeseries_config = VisualizationConfig(
            type=VisualizationType.TIMESERIES,
            title="Request Latency"
        )
        gauge_config = VisualizationConfig(
            type=VisualizationType.GAUGE,
            title="CPU Usage"
        )
        
        timeseries_vis = dashboard.add_visualization(timeseries_config)
        gauge_vis = dashboard.add_visualization(gauge_config)
        
        # Create data sources
        latency_data = VisualizationData(name="latency")
        cpu_data = VisualizationData(name="cpu")
        
        for i in range(20):
            latency_data.add_point(
                DataPoint(datetime.utcnow() - timedelta(seconds=i), float(100 + i))
            )
            cpu_data.add_point(
                DataPoint(datetime.utcnow() - timedelta(seconds=i), float(50 + (i % 20)))
            )
        
        dashboard.add_data_source(latency_data)
        dashboard.add_data_source(cpu_data)
        
        # Connect visualizations
        dashboard.connect(timeseries_config.id, latency_data.id)
        dashboard.connect(gauge_config.id, cpu_data.id)
        
        # Render dashboard
        rendered = dashboard.render()
        
        assert len(rendered["visualizations"]) == 2
        assert rendered["visualizations"][timeseries_config.id]["data"]
    
    def test_real_time_updates(self):
        """Test real-time data updates."""
        stream = RealTimeDataStream()
        dashboard = ReactiveDashboard()
        
        # Create visualization
        config = VisualizationConfig(type=VisualizationType.TIMESERIES)
        vis = dashboard.add_visualization(config)
        
        # Create data source
        data = VisualizationData()
        dashboard.add_data_source(data)
        dashboard.connect(config.id, data.id)
        
        # Subscribe to updates
        updates = []
        
        def on_update(point):
            updates.append(point)
        
        stream.subscribe("metric1", on_update)
        
        # Publish data
        point = DataPoint(datetime.utcnow(), 75.0)
        stream.publish("metric1", point)
        data.add_point(point)
        
        assert len(updates) == 1
        
        # Render updated
        rendered = vis.render()
        assert len(rendered["data"]) == 1
