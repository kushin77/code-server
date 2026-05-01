"""
Phase 28 Dashboard Queries Module

Pre-built queries and transformations for monitoring dashboards:
- Grafana/Prometheus compatible queries
- Time-series aggregations
- Alert summaries
- SLA/SLI metrics
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple


class TimeRange(Enum):
    """Time range options."""
    LAST_5_MIN = "5m"
    LAST_15_MIN = "15m"
    LAST_1_HOUR = "1h"
    LAST_6_HOURS = "6h"
    LAST_24_HOURS = "24h"
    LAST_7_DAYS = "7d"
    LAST_30_DAYS = "30d"


class AggregationType(Enum):
    """Aggregation types."""
    SUM = "sum"
    AVG = "avg"
    MAX = "max"
    MIN = "min"
    RATE = "rate"
    PERCENTILE = "percentile"


@dataclass
class QueryResult:
    """Query result."""
    metric_name: str
    value: float
    timestamp: datetime
    labels: Dict[str, str] = None
    
    def __post_init__(self):
        """Initialize labels."""
        if self.labels is None:
            self.labels = {}


@dataclass
class TimeSeriesData:
    """Time series data for charting."""
    metric_name: str
    data_points: List[Tuple[datetime, float]]
    aggregation: AggregationType
    time_range: TimeRange


class DashboardQueryBuilder:
    """Builder for dashboard queries."""
    
    def __init__(self):
        """Initialize query builder."""
        self.metric_name: Optional[str] = None
        self.time_range: TimeRange = TimeRange.LAST_1_HOUR
        self.aggregation: AggregationType = AggregationType.AVG
        self.filters: Dict[str, Any] = {}
    
    def metric(self, name: str) -> 'DashboardQueryBuilder':
        """Set metric name."""
        self.metric_name = name
        return self
    
    def time_range(self, time_range: TimeRange) -> 'DashboardQueryBuilder':
        """Set time range."""
        self.time_range = time_range
        return self
    
    def aggregation(self, agg: AggregationType) -> 'DashboardQueryBuilder':
        """Set aggregation type."""
        self.aggregation = agg
        return self
    
    def filter(self, label: str, value: Any) -> 'DashboardQueryBuilder':
        """Add filter."""
        self.filters[label] = value
        return self
    
    def build_prometheus_query(self) -> str:
        """Build Prometheus query."""
        if not self.metric_name:
            raise ValueError("Metric name is required")
        
        query = self.metric_name
        
        # Add filters
        if self.filters:
            filter_str = ", ".join(f'{k}="{v}"' for k, v in self.filters.items())
            query = f"{query}{{{filter_str}}}"
        
        # Add aggregation and range
        if self.aggregation == AggregationType.RATE:
            query = f"rate({query}[{self.time_range.value}])"
        elif self.aggregation == AggregationType.SUM:
            query = f"sum({query})"
        elif self.aggregation == AggregationType.AVG:
            query = f"avg({query})"
        elif self.aggregation == AggregationType.MAX:
            query = f"max({query})"
        elif self.aggregation == AggregationType.MIN:
            query = f"min({query})"
        
        return query
    
    def build_sql_query(self) -> str:
        """Build SQL query for timeseries DB."""
        if not self.metric_name:
            raise ValueError("Metric name is required")
        
        time_func = self._get_time_range_sql()
        
        query = f"SELECT timestamp, value FROM metrics WHERE metric_name = '{self.metric_name}' "
        query += f"AND timestamp > {time_func}"
        
        # Add filters
        for label, value in self.filters.items():
            if isinstance(value, str):
                query += f" AND labels ->> '{label}' = '{value}'"
            else:
                query += f" AND labels ->> '{label}' = {value}"
        
        # Add aggregation
        if self.aggregation == AggregationType.AVG:
            query = f"SELECT AVG(value) as value FROM ({query})"
        elif self.aggregation == AggregationType.MAX:
            query = f"SELECT MAX(value) as value FROM ({query})"
        elif self.aggregation == AggregationType.MIN:
            query = f"SELECT MIN(value) as value FROM ({query})"
        elif self.aggregation == AggregationType.SUM:
            query = f"SELECT SUM(value) as value FROM ({query})"
        
        return query
    
    def _get_time_range_sql(self) -> str:
        """Get time range in SQL format."""
        time_deltas = {
            TimeRange.LAST_5_MIN: "now() - interval '5 minutes'",
            TimeRange.LAST_15_MIN: "now() - interval '15 minutes'",
            TimeRange.LAST_1_HOUR: "now() - interval '1 hour'",
            TimeRange.LAST_6_HOURS: "now() - interval '6 hours'",
            TimeRange.LAST_24_HOURS: "now() - interval '24 hours'",
            TimeRange.LAST_7_DAYS: "now() - interval '7 days'",
            TimeRange.LAST_30_DAYS: "now() - interval '30 days'",
        }
        return time_deltas.get(self.time_range, "now() - interval '1 hour'")


class AnomalyDashboardQueries:
    """Pre-built anomaly detection dashboard queries."""
    
    @staticmethod
    def anomaly_rate(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get anomaly detection rate."""
        return (DashboardQueryBuilder()
                .metric("anomalies_detected_total")
                .time_range(time_range)
                .aggregation(AggregationType.RATE)
                .build_prometheus_query())
    
    @staticmethod
    def anomalies_by_severity(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get anomalies by severity."""
        return (DashboardQueryBuilder()
                .metric("anomalies_severity_total")
                .time_range(time_range)
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def detection_latency(time_range: TimeRange = TimeRange.LAST_1_HOUR) -> str:
        """Get detection latency."""
        return (DashboardQueryBuilder()
                .metric("anomaly_detection_latency_ms")
                .time_range(time_range)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def models_active() -> str:
        """Get count of active models."""
        return (DashboardQueryBuilder()
                .metric("anomaly_models_active")
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())


class ScalingDashboardQueries:
    """Pre-built scaling dashboard queries."""
    
    @staticmethod
    def scaling_recommendations(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get scaling recommendations."""
        return (DashboardQueryBuilder()
                .metric("scaling_recommendations_total")
                .time_range(time_range)
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def scale_up_events(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get scale-up events."""
        return (DashboardQueryBuilder()
                .metric("scaling_scale_up_total")
                .time_range(time_range)
                .filter("action", "scale_up")
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def scale_down_events(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get scale-down events."""
        return (DashboardQueryBuilder()
                .metric("scaling_scale_down_total")
                .time_range(time_range)
                .filter("action", "scale_down")
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def forecast_accuracy(time_range: TimeRange = TimeRange.LAST_7_DAYS) -> str:
        """Get forecast accuracy."""
        return (DashboardQueryBuilder()
                .metric("forecast_accuracy_percent")
                .time_range(time_range)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def saturation_risk(time_range: TimeRange = TimeRange.LAST_1_HOUR) -> str:
        """Get saturation risk."""
        return (DashboardQueryBuilder()
                .metric("saturation_risk")
                .time_range(time_range)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())


class RCADashboardQueries:
    """Pre-built RCA dashboard queries."""
    
    @staticmethod
    def incidents_analyzed(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get incidents analyzed."""
        return (DashboardQueryBuilder()
                .metric("incidents_analyzed_total")
                .time_range(time_range)
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def root_cause_accuracy(time_range: TimeRange = TimeRange.LAST_7_DAYS) -> str:
        """Get root cause identification accuracy."""
        return (DashboardQueryBuilder()
                .metric("root_cause_accuracy_percent")
                .time_range(time_range)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def blast_radius_distribution() -> str:
        """Get blast radius distribution."""
        return (DashboardQueryBuilder()
                .metric("blast_radius")
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def services_tracked() -> str:
        """Get number of services tracked."""
        return (DashboardQueryBuilder()
                .metric("services_tracked")
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())


class AlertingDashboardQueries:
    """Pre-built alerting dashboard queries."""
    
    @staticmethod
    def alerts_processed(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get alerts processed."""
        return (DashboardQueryBuilder()
                .metric("alerts_processed_total")
                .time_range(time_range)
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def deduplication_ratio(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get alert deduplication ratio."""
        return (DashboardQueryBuilder()
                .metric("alert_deduplication_ratio")
                .time_range(time_range)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def alerts_by_severity(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get alerts by severity."""
        return (DashboardQueryBuilder()
                .metric("alerts_severity_total")
                .time_range(time_range)
                .aggregation(AggregationType.SUM)
                .build_prometheus_query())
    
    @staticmethod
    def alert_suppression_rate(time_range: TimeRange = TimeRange.LAST_24_HOURS) -> str:
        """Get alert suppression rate."""
        return (DashboardQueryBuilder()
                .metric("alerts_suppressed_total")
                .time_range(time_range)
                .aggregation(AggregationType.RATE)
                .build_prometheus_query())
    
    @staticmethod
    def mtta_time() -> str:
        """Get mean time to alert (MTTA)."""
        return (DashboardQueryBuilder()
                .metric("alert_mtta_seconds")
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())


class SLADashboardQueries:
    """SLA/SLI dashboard queries."""
    
    @staticmethod
    def availability(service: str, time_range: TimeRange = TimeRange.LAST_30_DAYS) -> str:
        """Get service availability SLI."""
        return (DashboardQueryBuilder()
                .metric(f"{service}_availability_percent")
                .time_range(time_range)
                .filter("service", service)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def latency_p99(service: str, time_range: TimeRange = TimeRange.LAST_1_HOUR) -> str:
        """Get P99 latency SLI."""
        return (DashboardQueryBuilder()
                .metric(f"{service}_latency_p99_ms")
                .time_range(time_range)
                .filter("service", service)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())
    
    @staticmethod
    def error_rate(service: str, time_range: TimeRange = TimeRange.LAST_1_HOUR) -> str:
        """Get error rate SLI."""
        return (DashboardQueryBuilder()
                .metric(f"{service}_error_rate_percent")
                .time_range(time_range)
                .filter("service", service)
                .aggregation(AggregationType.AVG)
                .build_prometheus_query())


class DashboardDataTransformers:
    """Data transformers for dashboard presentation."""
    
    @staticmethod
    def timeseries_to_chart_data(data: TimeSeriesData) -> Dict[str, Any]:
        """Transform timeseries to chart format."""
        return {
            "metric": data.metric_name,
            "aggregation": data.aggregation.value,
            "time_range": data.time_range.value,
            "data": [
                {
                    "timestamp": ts.isoformat(),
                    "value": value
                }
                for ts, value in data.data_points
            ]
        }
    
    @staticmethod
    def query_results_to_table(results: List[QueryResult]) -> List[Dict[str, Any]]:
        """Transform query results to table format."""
        return [
            {
                "metric": r.metric_name,
                "value": r.value,
                "timestamp": r.timestamp.isoformat(),
                **r.labels
            }
            for r in results
        ]
    
    @staticmethod
    def summary_statistics(values: List[float]) -> Dict[str, float]:
        """Calculate summary statistics."""
        if not values:
            return {}
        
        sorted_values = sorted(values)
        n = len(sorted_values)
        
        return {
            "count": n,
            "min": min(values),
            "max": max(values),
            "mean": sum(values) / n,
            "median": sorted_values[n // 2],
            "p95": sorted_values[int(n * 0.95)],
            "p99": sorted_values[int(n * 0.99)]
        }
