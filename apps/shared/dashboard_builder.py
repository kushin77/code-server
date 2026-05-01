"""
Advanced Dashboarding and Visualization

Provides dashboard components, widgets, and visualization tools for observability data:
- Dashboard configuration and management
- Widget types for different metrics
- Real-time data updates
- Custom dashboard builders
- Export and sharing capabilities
"""

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Any, Callable, Union
from enum import Enum
from datetime import datetime
import json
from uuid import uuid4


class DashboardLayout(Enum):
    """Dashboard layout types."""
    GRID = "grid"
    FLEX = "flex"
    RESPONSIVE = "responsive"


class WidgetType(Enum):
    """Types of dashboard widgets."""
    TIMESERIES = "timeseries"
    GAUGE = "gauge"
    STAT = "stat"
    HEATMAP = "heatmap"
    TABLE = "table"
    PIECHART = "piechart"
    BARCHART = "barchart"
    LINECHART = "linechart"
    HISTOGRAM = "histogram"
    TOPOLOGY = "topology"
    TRACE_TIMELINE = "trace_timeline"


class ThemeMode(Enum):
    """Dashboard theme modes."""
    LIGHT = "light"
    DARK = "dark"
    AUTO = "auto"


@dataclass
class DataSource:
    """Dashboard data source configuration."""
    id: str
    name: str
    type: str  # prometheus, influxdb, jaeger, elasticsearch, etc.
    url: str
    config: Dict[str, Any] = field(default_factory=dict)
    authentication: Dict[str, str] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)


@dataclass
class MetricQuery:
    """Query for metrics display."""
    id: str
    datasource_id: str
    query: str
    legend: Optional[str] = None
    interval: str = "30s"
    max_data_points: int = 1000
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)


@dataclass
class WidgetThreshold:
    """Threshold for widget alerting."""
    value: Union[int, float]
    color: str
    label: str
    operator: str = "gt"  # gt, gte, lt, lte, eq


@dataclass
class WidgetOptions:
    """Widget display options."""
    title: str = ""
    description: str = ""
    show_legend: bool = True
    show_grid: bool = True
    show_tooltip: bool = True
    min_value: Optional[Union[int, float]] = None
    max_value: Optional[Union[int, float]] = None
    unit: str = ""
    decimals: int = 2
    thresholds: List[WidgetThreshold] = field(default_factory=list)
    no_value: str = "No data"
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "title": self.title,
            "description": self.description,
            "show_legend": self.show_legend,
            "show_grid": self.show_grid,
            "show_tooltip": self.show_tooltip,
            "min_value": self.min_value,
            "max_value": self.max_value,
            "unit": self.unit,
            "decimals": self.decimals,
            "thresholds": [asdict(t) for t in self.thresholds],
            "no_value": self.no_value,
        }


@dataclass
class DashboardWidget:
    """Dashboard widget configuration."""
    id: str = field(default_factory=lambda: str(uuid4())[:8])
    type: WidgetType = WidgetType.TIMESERIES
    title: str = ""
    queries: List[MetricQuery] = field(default_factory=list)
    options: WidgetOptions = field(default_factory=WidgetOptions)
    x: int = 0
    y: int = 0
    width: int = 4
    height: int = 3
    refresh_interval: str = "30s"
    transparent: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "type": self.type.value,
            "title": self.title,
            "queries": [q.to_dict() for q in self.queries],
            "options": self.options.to_dict(),
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
            "refresh_interval": self.refresh_interval,
            "transparent": self.transparent,
        }


@dataclass
class DashboardVariable:
    """Template variable for dashboards."""
    name: str
    type: str  # query, constant, interval, datasource, etc.
    value: Any
    label: str = ""
    description: str = ""
    options: List[str] = field(default_factory=list)
    multi: bool = False
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)


@dataclass
class DashboardAnnotation:
    """Dashboard annotation/event marker."""
    name: str
    datasource_id: str
    query: str
    text_format: Optional[str] = None
    tags: List[str] = field(default_factory=list)
    enabled: bool = True
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return asdict(self)


@dataclass
class Dashboard:
    """Complete dashboard configuration."""
    id: str = field(default_factory=lambda: str(uuid4()))
    title: str = ""
    description: str = ""
    tags: List[str] = field(default_factory=list)
    widgets: List[DashboardWidget] = field(default_factory=list)
    datasources: List[DataSource] = field(default_factory=list)
    variables: List[DashboardVariable] = field(default_factory=list)
    annotations: List[DashboardAnnotation] = field(default_factory=list)
    layout: DashboardLayout = DashboardLayout.GRID
    theme: ThemeMode = ThemeMode.AUTO
    refresh_interval: str = "30s"
    time_range_from: str = "now-6h"
    time_range_to: str = "now"
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    created_by: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "tags": self.tags,
            "widgets": [w.to_dict() for w in self.widgets],
            "datasources": [d.to_dict() for d in self.datasources],
            "variables": [v.to_dict() for v in self.variables],
            "annotations": [a.to_dict() for a in self.annotations],
            "layout": self.layout.value,
            "theme": self.theme.value,
            "refresh_interval": self.refresh_interval,
            "time_range_from": self.time_range_from,
            "time_range_to": self.time_range_to,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "created_by": self.created_by,
        }
    
    def to_json(self) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict())
    
    @staticmethod
    def from_dict(data: Dict[str, Any]) -> 'Dashboard':
        """Create from dictionary."""
        dashboard = Dashboard(
            id=data.get("id", str(uuid4())),
            title=data.get("title", ""),
            description=data.get("description", ""),
            tags=data.get("tags", []),
            created_by=data.get("created_by", "")
        )
        
        # Restore widgets
        for w_data in data.get("widgets", []):
            queries = [MetricQuery(**q) for q in w_data.get("queries", [])]
            options = WidgetOptions(**w_data.get("options", {}))
            widget = DashboardWidget(
                id=w_data.get("id"),
                type=WidgetType(w_data.get("type", "timeseries")),
                title=w_data.get("title"),
                queries=queries,
                options=options,
                x=w_data.get("x", 0),
                y=w_data.get("y", 0),
                width=w_data.get("width", 4),
                height=w_data.get("height", 3),
            )
            dashboard.widgets.append(widget)
        
        # Restore datasources
        for ds_data in data.get("datasources", []):
            datasource = DataSource(**ds_data)
            dashboard.datasources.append(datasource)
        
        return dashboard


class DashboardBuilder:
    """Fluent builder for creating dashboards."""
    
    def __init__(self):
        self.dashboard = Dashboard()
    
    def set_title(self, title: str) -> 'DashboardBuilder':
        """Set dashboard title."""
        self.dashboard.title = title
        return self
    
    def set_description(self, description: str) -> 'DashboardBuilder':
        """Set dashboard description."""
        self.dashboard.description = description
        return self
    
    def add_tag(self, tag: str) -> 'DashboardBuilder':
        """Add tag."""
        self.dashboard.tags.append(tag)
        return self
    
    def add_datasource(self, name: str, ds_type: str, url: str,
                      config: Optional[Dict] = None) -> 'DashboardBuilder':
        """Add data source."""
        datasource = DataSource(
            id=str(uuid4())[:8],
            name=name,
            type=ds_type,
            url=url,
            config=config or {}
        )
        self.dashboard.datasources.append(datasource)
        return self
    
    def add_variable(self, name: str, var_type: str, value: Any,
                    label: str = "", options: Optional[List[str]] = None) -> 'DashboardBuilder':
        """Add template variable."""
        variable = DashboardVariable(
            name=name,
            type=var_type,
            value=value,
            label=label,
            options=options or []
        )
        self.dashboard.variables.append(variable)
        return self
    
    def add_widget(self, widget: DashboardWidget) -> 'DashboardBuilder':
        """Add widget to dashboard."""
        self.dashboard.widgets.append(widget)
        return self
    
    def add_timeseries_widget(self, title: str, query: str,
                            datasource_id: str, x: int = 0, y: int = 0) -> 'DashboardBuilder':
        """Add timeseries widget."""
        metric_query = MetricQuery(
            id=str(uuid4())[:8],
            datasource_id=datasource_id,
            query=query
        )
        
        widget = DashboardWidget(
            type=WidgetType.TIMESERIES,
            title=title,
            queries=[metric_query],
            x=x,
            y=y,
            options=WidgetOptions(title=title)
        )
        
        self.dashboard.widgets.append(widget)
        return self
    
    def add_gauge_widget(self, title: str, query: str,
                        datasource_id: str, min_value: float = 0,
                        max_value: float = 100, x: int = 0, y: int = 0) -> 'DashboardBuilder':
        """Add gauge widget."""
        metric_query = MetricQuery(
            id=str(uuid4())[:8],
            datasource_id=datasource_id,
            query=query
        )
        
        options = WidgetOptions(
            title=title,
            min_value=min_value,
            max_value=max_value
        )
        
        widget = DashboardWidget(
            type=WidgetType.GAUGE,
            title=title,
            queries=[metric_query],
            options=options,
            x=x,
            y=y,
            width=2,
            height=2
        )
        
        self.dashboard.widgets.append(widget)
        return self
    
    def add_stat_widget(self, title: str, query: str,
                       datasource_id: str, unit: str = "", x: int = 0, y: int = 0) -> 'DashboardBuilder':
        """Add stat widget."""
        metric_query = MetricQuery(
            id=str(uuid4())[:8],
            datasource_id=datasource_id,
            query=query
        )
        
        options = WidgetOptions(
            title=title,
            unit=unit
        )
        
        widget = DashboardWidget(
            type=WidgetType.STAT,
            title=title,
            queries=[metric_query],
            options=options,
            x=x,
            y=y,
            width=2,
            height=2
        )
        
        self.dashboard.widgets.append(widget)
        return self
    
    def add_table_widget(self, title: str, query: str,
                         datasource_id: str, x: int = 0, y: int = 0) -> 'DashboardBuilder':
        """Add table widget."""
        metric_query = MetricQuery(
            id=str(uuid4())[:8],
            datasource_id=datasource_id,
            query=query
        )
        
        widget = DashboardWidget(
            type=WidgetType.TABLE,
            title=title,
            queries=[metric_query],
            x=x,
            y=y,
            width=6,
            height=4,
            options=WidgetOptions(title=title)
        )
        
        self.dashboard.widgets.append(widget)
        return self
    
    def set_refresh_interval(self, interval: str) -> 'DashboardBuilder':
        """Set refresh interval."""
        self.dashboard.refresh_interval = interval
        return self
    
    def set_time_range(self, from_time: str, to_time: str) -> 'DashboardBuilder':
        """Set time range."""
        self.dashboard.time_range_from = from_time
        self.dashboard.time_range_to = to_time
        return self
    
    def set_layout(self, layout: DashboardLayout) -> 'DashboardBuilder':
        """Set layout."""
        self.dashboard.layout = layout
        return self
    
    def set_theme(self, theme: ThemeMode) -> 'DashboardBuilder':
        """Set theme."""
        self.dashboard.theme = theme
        return self
    
    def build(self) -> Dashboard:
        """Build dashboard."""
        self.dashboard.updated_at = datetime.utcnow()
        return self.dashboard


class DashboardManager:
    """Manages dashboard lifecycle."""
    
    def __init__(self):
        self.dashboards: Dict[str, Dashboard] = {}
    
    def create(self, dashboard: Dashboard) -> str:
        """Create new dashboard."""
        dashboard.id = str(uuid4())
        dashboard.created_at = datetime.utcnow()
        dashboard.updated_at = datetime.utcnow()
        self.dashboards[dashboard.id] = dashboard
        return dashboard.id
    
    def get(self, dashboard_id: str) -> Optional[Dashboard]:
        """Get dashboard by ID."""
        return self.dashboards.get(dashboard_id)
    
    def list(self, tags: Optional[List[str]] = None) -> List[Dashboard]:
        """List dashboards."""
        dashboards = list(self.dashboards.values())
        
        if tags:
            dashboards = [
                d for d in dashboards
                if any(tag in d.tags for tag in tags)
            ]
        
        return dashboards
    
    def update(self, dashboard: Dashboard) -> bool:
        """Update dashboard."""
        if dashboard.id not in self.dashboards:
            return False
        
        dashboard.updated_at = datetime.utcnow()
        self.dashboards[dashboard.id] = dashboard
        return True
    
    def delete(self, dashboard_id: str) -> bool:
        """Delete dashboard."""
        if dashboard_id in self.dashboards:
            del self.dashboards[dashboard_id]
            return True
        return False
    
    def export(self, dashboard_id: str) -> Optional[str]:
        """Export dashboard as JSON."""
        dashboard = self.get(dashboard_id)
        if not dashboard:
            return None
        return dashboard.to_json()
    
    def import_json(self, json_str: str) -> Optional[str]:
        """Import dashboard from JSON."""
        try:
            data = json.loads(json_str)
            dashboard = Dashboard.from_dict(data)
            return self.create(dashboard)
        except Exception:
            return None


class DashboardTemplate:
    """Pre-built dashboard template."""
    
    @staticmethod
    def system_metrics_template(datasource_id: str) -> Dashboard:
        """Create system metrics dashboard template."""
        builder = DashboardBuilder()
        builder.set_title("System Metrics") \
            .set_description("CPU, Memory, Disk and Network metrics") \
            .add_tag("system") \
            .add_tag("infrastructure") \
            .add_timeseries_widget("CPU Usage", "rate(cpu_usage[5m])", datasource_id, x=0, y=0) \
            .add_timeseries_widget("Memory Usage", "memory_usage_bytes", datasource_id, x=4, y=0) \
            .add_gauge_widget("Disk Usage %", "disk_usage_percent", datasource_id, x=8, y=0) \
            .add_timeseries_widget("Network Traffic", "rate(network_bytes[1m])", datasource_id, x=0, y=3)
        
        return builder.build()
    
    @staticmethod
    def application_metrics_template(datasource_id: str) -> Dashboard:
        """Create application metrics dashboard template."""
        builder = DashboardBuilder()
        builder.set_title("Application Metrics") \
            .set_description("Request rate, latency, errors, and throughput") \
            .add_tag("application") \
            .add_tag("performance") \
            .add_timeseries_widget("Request Rate", "rate(http_requests_total[1m])", datasource_id, x=0, y=0) \
            .add_timeseries_widget("Response Latency", "histogram_quantile(0.95, rate(http_request_duration[1m]))", datasource_id, x=4, y=0) \
            .add_stat_widget("Error Rate %", "rate(http_errors_total[5m]) * 100", datasource_id, unit="%", x=8, y=0) \
            .add_table_widget("Top Endpoints", "topk(10, http_requests_total)", datasource_id, x=0, y=3)
        
        return builder.build()
    
    @staticmethod
    def trace_metrics_template(datasource_id: str) -> Dashboard:
        """Create distributed tracing dashboard template."""
        builder = DashboardBuilder()
        builder.set_title("Distributed Tracing") \
            .set_description("Trace latency, error rates, and service dependencies") \
            .add_tag("tracing") \
            .add_tag("observability") \
            .add_timeseries_widget("Trace Latency P99", "trace_duration_p99", datasource_id, x=0, y=0) \
            .add_timeseries_widget("Error Rate", "rate(trace_errors[1m])", datasource_id, x=4, y=0) \
            .add_gauge_widget("Active Traces", "active_traces", datasource_id, x=8, y=0) \
            .add_table_widget("Service Dependencies", "services", datasource_id, x=0, y=3)
        
        return builder.build()


class VisualizationExporter:
    """Exports dashboard data in various formats."""
    
    @staticmethod
    def export_json(dashboard: Dashboard) -> str:
        """Export dashboard as JSON."""
        return dashboard.to_json()
    
    @staticmethod
    def export_yaml(dashboard: Dashboard) -> str:
        """Export dashboard as YAML."""
        try:
            import yaml
            return yaml.dump(dashboard.to_dict())
        except ImportError:
            # Fallback to JSON if YAML not available
            return dashboard.to_json()
    
    @staticmethod
    def export_grafana_json(dashboard: Dashboard) -> str:
        """Export in Grafana-compatible format."""
        data = dashboard.to_dict()
        
        # Convert to Grafana format
        grafana_dashboard = {
            "dashboard": {
                "id": None,
                "uid": data["id"],
                "title": data["title"],
                "tags": data["tags"],
                "timezone": "browser",
                "panels": []
            }
        }
        
        # Add panels from widgets
        for i, widget in enumerate(data.get("widgets", [])):
            panel = {
                "id": i + 1,
                "title": widget["title"],
                "type": widget["type"],
                "gridPos": {
                    "x": widget["x"],
                    "y": widget["y"],
                    "w": widget["width"],
                    "h": widget["height"]
                },
                "targets": []
            }
            grafana_dashboard["dashboard"]["panels"].append(panel)
        
        return json.dumps(grafana_dashboard, indent=2)


__all__ = [
    'DashboardLayout',
    'WidgetType',
    'ThemeMode',
    'DataSource',
    'MetricQuery',
    'WidgetThreshold',
    'WidgetOptions',
    'DashboardWidget',
    'DashboardVariable',
    'DashboardAnnotation',
    'Dashboard',
    'DashboardBuilder',
    'DashboardManager',
    'DashboardTemplate',
    'VisualizationExporter',
]
