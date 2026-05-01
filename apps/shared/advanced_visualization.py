"""
Advanced visualization and real-time UI system.

Provides sophisticated visualization components for observability dashboards:
- Real-time data streaming
- Interactive reactive updates
- Multiple chart types
- Custom visualizations
- WebSocket support
- Event-driven updates
"""

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Any, Callable, Set
from enum import Enum
from datetime import datetime, timedelta
from uuid import uuid4
import json
from abc import ABC, abstractmethod
from collections import deque
import asyncio


class VisualizationType(Enum):
    """Visualization component types."""
    TIMESERIES = "timeseries"
    GAUGE = "gauge"
    STAT = "stat"
    TABLE = "table"
    HEATMAP = "heatmap"
    SCATTER = "scatter"
    HISTOGRAM = "histogram"
    CANDLESTICK = "candlestick"
    SANKEY = "sankey"
    TREEMAP = "treemap"
    WORLD_MAP = "world_map"
    FLAME_GRAPH = "flame_graph"


class InteractionMode(Enum):
    """Interaction modes for visualizations."""
    NONE = "none"
    CLICK = "click"
    HOVER = "hover"
    BRUSH = "brush"
    ZOOM = "zoom"
    DRILL_DOWN = "drill_down"


@dataclass
class DataPoint:
    """Data point for visualization."""
    timestamp: datetime
    value: float
    label: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class VisualizationData:
    """Data source for visualization."""
    id: str = field(default_factory=lambda: str(uuid4()))
    name: str = ""
    points: List[DataPoint] = field(default_factory=list)
    interval: int = 60  # seconds
    last_updated: datetime = field(default_factory=datetime.utcnow)
    
    def add_point(self, point: DataPoint):
        """Add data point."""
        self.points.append(point)
        self.last_updated = datetime.utcnow()
    
    def add_points(self, points: List[DataPoint]):
        """Add multiple data points."""
        self.points.extend(points)
        self.last_updated = datetime.utcnow()
    
    def get_latest(self, limit: int = 100) -> List[DataPoint]:
        """Get latest data points."""
        return self.points[-limit:]
    
    def get_time_range(self, start: datetime, end: datetime) -> List[DataPoint]:
        """Get points in time range."""
        return [p for p in self.points if start <= p.timestamp <= end]
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "name": self.name,
            "points": [
                {
                    "timestamp": p.timestamp.isoformat(),
                    "value": p.value,
                    "label": p.label,
                    "metadata": p.metadata
                } for p in self.points
            ],
            "interval": self.interval,
            "last_updated": self.last_updated.isoformat(),
        }


@dataclass
class VisualizationConfig:
    """Configuration for visualization."""
    id: str = field(default_factory=lambda: str(uuid4()))
    type: VisualizationType = VisualizationType.TIMESERIES
    title: str = ""
    description: str = ""
    x_axis_label: str = ""
    y_axis_label: str = ""
    colors: List[str] = field(default_factory=lambda: ["#1f77b4", "#ff7f0e"])
    interaction: InteractionMode = InteractionMode.NONE
    refresh_interval: int = 5000  # milliseconds
    height: int = 300
    width: int = 100  # percentage
    options: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "type": self.type.value,
            "title": self.title,
            "description": self.description,
            "x_axis_label": self.x_axis_label,
            "y_axis_label": self.y_axis_label,
            "colors": self.colors,
            "interaction": self.interaction.value,
            "refresh_interval": self.refresh_interval,
            "height": self.height,
            "width": self.width,
            "options": self.options,
        }


@dataclass
class InteractionEvent:
    """User interaction event."""
    id: str = field(default_factory=lambda: str(uuid4()))
    timestamp: datetime = field(default_factory=datetime.utcnow)
    visualization_id: str = ""
    event_type: str = ""  # click, hover, drill_down, etc.
    data: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat(),
            "visualization_id": self.visualization_id,
            "event_type": self.event_type,
            "data": self.data,
        }


class VisualizationComponent(ABC):
    """Abstract base for visualization components."""
    
    def __init__(self, config: VisualizationConfig):
        self.config = config
        self.data_source: Optional[VisualizationData] = None
        self.event_handlers: Dict[str, List[Callable]] = {}
    
    @abstractmethod
    def render(self) -> Dict[str, Any]:
        """Render visualization."""
        pass
    
    def set_data(self, data: VisualizationData):
        """Set data source."""
        self.data_source = data
        self.emit_event("data_changed", {"data_id": data.id})
    
    def on_event(self, event_type: str, handler: Callable):
        """Register event handler."""
        if event_type not in self.event_handlers:
            self.event_handlers[event_type] = []
        self.event_handlers[event_type].append(handler)
    
    def emit_event(self, event_type: str, data: Dict[str, Any]):
        """Emit event to handlers."""
        if event_type in self.event_handlers:
            for handler in self.event_handlers[event_type]:
                handler(event_type, data)


class TimeSeriesVisualization(VisualizationComponent):
    """Time series chart."""
    
    def render(self) -> Dict[str, Any]:
        """Render time series."""
        if not self.data_source:
            return {"type": "timeseries", "data": []}
        
        points = self.data_source.get_latest()
        
        return {
            "type": "timeseries",
            "config": self.config.to_dict(),
            "data": [
                {
                    "x": p.timestamp.isoformat(),
                    "y": p.value,
                    "label": p.label
                } for p in points
            ],
        }


class GaugeVisualization(VisualizationComponent):
    """Gauge visualization."""
    
    def render(self) -> Dict[str, Any]:
        """Render gauge."""
        if not self.data_source or not self.data_source.points:
            current_value = 0
        else:
            current_value = self.data_source.points[-1].value
        
        return {
            "type": "gauge",
            "config": self.config.to_dict(),
            "value": current_value,
            "min": self.config.options.get("min", 0),
            "max": self.config.options.get("max", 100),
            "thresholds": self.config.options.get("thresholds", []),
        }


class HeatmapVisualization(VisualizationComponent):
    """Heatmap visualization."""
    
    def render(self) -> Dict[str, Any]:
        """Render heatmap."""
        if not self.data_source:
            return {"type": "heatmap", "data": []}
        
        # Group data by labels
        grouped: Dict[str, List[DataPoint]] = {}
        for point in self.data_source.get_latest(100):
            label = point.label or "default"
            if label not in grouped:
                grouped[label] = []
            grouped[label].append(point)
        
        return {
            "type": "heatmap",
            "config": self.config.to_dict(),
            "data": grouped,
        }


class StatVisualization(VisualizationComponent):
    """Single stat visualization."""
    
    def render(self) -> Dict[str, Any]:
        """Render stat."""
        if not self.data_source or not self.data_source.points:
            current = 0
            previous = 0
        else:
            current = self.data_source.points[-1].value
            previous = self.data_source.points[-2].value if len(self.data_source.points) > 1 else current
        
        change = ((current - previous) / previous * 100) if previous != 0 else 0
        
        return {
            "type": "stat",
            "config": self.config.to_dict(),
            "value": current,
            "previous": previous,
            "change_percent": change,
            "unit": self.config.options.get("unit", ""),
        }


class TableVisualization(VisualizationComponent):
    """Table visualization."""
    
    def render(self) -> Dict[str, Any]:
        """Render table."""
        if not self.data_source:
            return {"type": "table", "columns": [], "rows": []}
        
        # Convert to table rows
        rows = []
        for point in self.data_source.get_latest(100):
            rows.append({
                "timestamp": point.timestamp.isoformat(),
                "value": point.value,
                "label": point.label,
                **point.metadata
            })
        
        columns = list(rows[0].keys()) if rows else []
        
        return {
            "type": "table",
            "config": self.config.to_dict(),
            "columns": columns,
            "rows": rows,
        }


class HistogramVisualization(VisualizationComponent):
    """Histogram visualization."""
    
    def render(self) -> Dict[str, Any]:
        """Render histogram."""
        if not self.data_source:
            return {"type": "histogram", "bins": []}
        
        values = [p.value for p in self.data_source.points]
        if not values:
            return {"type": "histogram", "bins": []}
        
        # Create bins
        bins = self.config.options.get("bins", 10)
        min_val = min(values)
        max_val = max(values)
        bin_width = (max_val - min_val) / bins if max_val > min_val else 1
        
        hist_data = [0] * bins
        for v in values:
            bin_idx = int((v - min_val) / bin_width) if bin_width > 0 else 0
            bin_idx = min(bin_idx, bins - 1)
            hist_data[bin_idx] += 1
        
        return {
            "type": "histogram",
            "config": self.config.to_dict(),
            "bins": hist_data,
            "min": min_val,
            "max": max_val,
        }


class RealTimeDataStream:
    """Real-time data streaming for visualizations."""
    
    def __init__(self, buffer_size: int = 1000):
        self.buffer_size = buffer_size
        self.subscribers: Dict[str, List[Callable]] = {}
        self.data_buffer: deque = deque(maxlen=buffer_size)
        self.metrics: Dict[str, Any] = {}
    
    def subscribe(self, stream_id: str, callback: Callable):
        """Subscribe to data stream."""
        if stream_id not in self.subscribers:
            self.subscribers[stream_id] = []
        self.subscribers[stream_id].append(callback)
    
    def unsubscribe(self, stream_id: str, callback: Callable):
        """Unsubscribe from stream."""
        if stream_id in self.subscribers:
            self.subscribers[stream_id].remove(callback)
    
    def publish(self, stream_id: str, data: DataPoint):
        """Publish data point to stream."""
        self.data_buffer.append(data)
        
        if stream_id in self.subscribers:
            for callback in self.subscribers[stream_id]:
                callback(data)
    
    def broadcast(self, data: DataPoint):
        """Broadcast to all subscribers."""
        for stream_id in self.subscribers:
            self.publish(stream_id, data)


class DashboardLayout:
    """Layout configuration for dashboard."""
    
    def __init__(self, id: str = None):
        self.id = id or str(uuid4())
        self.rows: List[List[VisualizationConfig]] = []
        self.refresh_interval: int = 5000
        self.auto_refresh: bool = True
    
    def add_row(self, configs: List[VisualizationConfig]):
        """Add row of visualizations."""
        self.rows.append(configs)
    
    def get_grid(self) -> List[List[VisualizationConfig]]:
        """Get grid layout."""
        return self.rows
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "rows": [
                [config.to_dict() for config in row]
                for row in self.rows
            ],
            "refresh_interval": self.refresh_interval,
            "auto_refresh": self.auto_refresh,
        }


class ReactiveDashboard:
    """Reactive dashboard with real-time updates."""
    
    def __init__(self, id: str = None):
        self.id = id or str(uuid4())
        self.layout = DashboardLayout(self.id)
        self.visualizations: Dict[str, VisualizationComponent] = {}
        self.data_sources: Dict[str, VisualizationData] = {}
        self.subscriptions: Dict[str, List[Callable]] = {}
        self.interaction_history: List[InteractionEvent] = []
    
    def add_visualization(self, config: VisualizationConfig,
                         vis_type: VisualizationType = None) -> VisualizationComponent:
        """Add visualization."""
        vis_type = vis_type or config.type
        
        if vis_type == VisualizationType.TIMESERIES:
            component = TimeSeriesVisualization(config)
        elif vis_type == VisualizationType.GAUGE:
            component = GaugeVisualization(config)
        elif vis_type == VisualizationType.HEATMAP:
            component = HeatmapVisualization(config)
        elif vis_type == VisualizationType.STAT:
            component = StatVisualization(config)
        elif vis_type == VisualizationType.TABLE:
            component = TableVisualization(config)
        elif vis_type == VisualizationType.HISTOGRAM:
            component = HistogramVisualization(config)
        else:
            component = TimeSeriesVisualization(config)
        
        self.visualizations[config.id] = component
        return component
    
    def add_data_source(self, data: VisualizationData) -> VisualizationData:
        """Add data source."""
        self.data_sources[data.id] = data
        return data
    
    def connect(self, vis_id: str, data_id: str):
        """Connect visualization to data source."""
        if vis_id in self.visualizations and data_id in self.data_sources:
            self.visualizations[vis_id].set_data(self.data_sources[data_id])
    
    def render(self) -> Dict[str, Any]:
        """Render dashboard."""
        return {
            "id": self.id,
            "layout": self.layout.to_dict(),
            "visualizations": {
                vis_id: vis.render()
                for vis_id, vis in self.visualizations.items()
            },
        }
    
    def on_interaction(self, event: InteractionEvent):
        """Handle user interaction."""
        self.interaction_history.append(event)
        
        # Notify subscribers
        if event.visualization_id in self.subscriptions:
            for callback in self.subscriptions[event.visualization_id]:
                callback(event)
    
    def get_state(self) -> Dict[str, Any]:
        """Get dashboard state for serialization."""
        return {
            "id": self.id,
            "layout": self.layout.to_dict(),
            "visualizations": [
                v.config.to_dict() for v in self.visualizations.values()
            ],
            "data_sources": [
                d.to_dict() for d in self.data_sources.values()
            ],
            "interaction_history": [
                e.to_dict() for e in self.interaction_history[-100:]
            ],
        }


__all__ = [
    'VisualizationType',
    'InteractionMode',
    'DataPoint',
    'VisualizationData',
    'VisualizationConfig',
    'InteractionEvent',
    'VisualizationComponent',
    'TimeSeriesVisualization',
    'GaugeVisualization',
    'HeatmapVisualization',
    'StatVisualization',
    'TableVisualization',
    'HistogramVisualization',
    'RealTimeDataStream',
    'DashboardLayout',
    'ReactiveDashboard',
]
