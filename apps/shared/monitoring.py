"""
Shared monitoring infrastructure for all applications.

Provides:
- Prometheus metrics collection and exposition
- Health check endpoints
- Performance metrics (latency, throughput)
- Resource usage tracking
- Application-level observability
"""

import functools
import inspect
import time
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Callable, Dict, Optional

from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram, Info, REGISTRY, Summary, generate_latest


class HealthStatus(str, Enum):
    """Health check status enumeration."""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"


@dataclass
class HealthCheckResult:
    """Result of a health check."""
    status: HealthStatus
    message: str
    timestamp: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    checks: Dict[str, Any] = field(default_factory=dict)
    duration_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "status": self.status.value,
            "message": self.message,
            "timestamp": self.timestamp,
            "checks": self.checks,
            "duration_ms": self.duration_ms,
        }


class MonitoringConfig:
    """Configuration for application monitoring."""
    
    def __init__(
        self,
        app_name: str,
        app_version: str,
        environment: str = "development",
        registry: Optional[CollectorRegistry] = None,
        enable_histograms: bool = True,
    ):
        self.app_name = app_name
        self.app_version = app_version
        self.environment = environment
        self.registry = registry or REGISTRY
        self.enable_histograms = enable_histograms
        
        # Common labels for all metrics
        self.labels = {
            "app": app_name,
            "version": app_version,
            "environment": environment,
        }


class ApplicationMetrics:
    """Central metrics collector for applications."""
    
    def __init__(self, config: MonitoringConfig):
        self.config = config
        self.app_name = config.app_name
        
        # Application info metric
        self.app_info = Info(
            f"{self.app_name}_app_info",
            f"{self.app_name} application information",
            registry=config.registry,
        )
        self.app_info.info({
            "version": config.app_version,
            "environment": config.environment,
        })
        
        # Request metrics
        self.requests_total = Counter(
            f"{self.app_name}_requests_total",
            f"Total {self.app_name} requests",
            ["method", "endpoint", "status"],
            registry=config.registry,
        )
        
        self.request_duration = Summary(
            f"{self.app_name}_request_duration_seconds",
            f"{self.app_name} request duration in seconds",
            ["method", "endpoint"],
            registry=config.registry,
        )
        
        if config.enable_histograms:
            self.request_latency = Histogram(
                f"{self.app_name}_request_latency_seconds",
                f"{self.app_name} request latency histogram",
                ["method", "endpoint"],
                buckets=(0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 2.5, 5.0),
                registry=config.registry,
            )
        
        # Error metrics
        self.errors_total = Counter(
            f"{self.app_name}_errors_total",
            f"Total {self.app_name} errors",
            ["error_type"],
            registry=config.registry,
        )
        
        # Business logic metrics (to be extended by subclasses)
        self.operations_total = Counter(
            f"{self.app_name}_operations_total",
            f"Total {self.app_name} operations",
            ["operation", "status"],
            registry=config.registry,
        )
        
        self.operation_duration = Summary(
            f"{self.app_name}_operation_duration_seconds",
            f"{self.app_name} operation duration",
            ["operation"],
            registry=config.registry,
        )
        
        # Resource metrics
        self.active_connections = Gauge(
            f"{self.app_name}_active_connections",
            f"Active {self.app_name} connections",
            registry=config.registry,
        )
        
        self.cache_hits = Counter(
            f"{self.app_name}_cache_hits_total",
            f"{self.app_name} cache hits",
            ["cache_name"],
            registry=config.registry,
        )
        
        self.cache_misses = Counter(
            f"{self.app_name}_cache_misses_total",
            f"{self.app_name} cache misses",
            ["cache_name"],
            registry=config.registry,
        )
        
        # Health check state
        self._health_checks: Dict[str, Callable[[], bool]] = {}
        self._last_health_check: Optional[HealthCheckResult] = None
    
    def record_request(
        self,
        method: str,
        endpoint: str,
        status_code: int,
        duration_seconds: float,
    ) -> None:
        """Record HTTP request metrics."""
        self.requests_total.labels(
            method=method,
            endpoint=endpoint,
            status=str(status_code),
        ).inc()
        
        self.request_duration.labels(
            method=method,
            endpoint=endpoint,
        ).observe(duration_seconds)
        
        if self.config.enable_histograms:
            self.request_latency.labels(
                method=method,
                endpoint=endpoint,
            ).observe(duration_seconds)
    
    def record_error(self, error_type: str) -> None:
        """Record error occurrence."""
        self.errors_total.labels(error_type=error_type).inc()
    
    def record_operation(
        self,
        operation: str,
        status: str,
        duration_seconds: float,
    ) -> None:
        """Record business operation metrics."""
        self.operations_total.labels(
            operation=operation,
            status=status,
        ).inc()
        
        self.operation_duration.labels(operation=operation).observe(duration_seconds)
    
    def set_active_connections(self, count: int) -> None:
        """Set current active connection count."""
        self.active_connections.set(count)
    
    def record_cache_hit(self, cache_name: str) -> None:
        """Record cache hit."""
        self.cache_hits.labels(cache_name=cache_name).inc()
    
    def record_cache_miss(self, cache_name: str) -> None:
        """Record cache miss."""
        self.cache_misses.labels(cache_name=cache_name).inc()
    
    def register_health_check(
        self,
        name: str,
        check_func: Callable[[], bool],
    ) -> None:
        """Register a health check function."""
        self._health_checks[name] = check_func
    
    async def perform_health_check(self) -> HealthCheckResult:
        """Perform all registered health checks."""
        start_time = time.time()
        checks = {}
        overall_status = HealthStatus.HEALTHY
        
        for name, check_func in self._health_checks.items():
            try:
                result = check_func()
                checks[name] = {
                    "status": "pass" if result else "fail",
                    "timestamp": datetime.utcnow().isoformat(),
                }
                if not result:
                    overall_status = HealthStatus.DEGRADED
            except Exception as e:
                checks[name] = {
                    "status": "error",
                    "error": str(e),
                    "timestamp": datetime.utcnow().isoformat(),
                }
                overall_status = HealthStatus.UNHEALTHY
        
        duration_ms = (time.time() - start_time) * 1000
        
        result = HealthCheckResult(
            status=overall_status,
            message=f"Health check completed with {len(checks)} checks",
            checks=checks,
            duration_ms=duration_ms,
        )
        
        self._last_health_check = result
        return result
    
    def get_metrics(self) -> bytes:
        """Get Prometheus metrics exposition."""
        return generate_latest(self.config.registry)


def track_metrics(
    metrics: ApplicationMetrics,
    method: str = "GET",
    endpoint: str = "/api/unknown",
):
    """Decorator for tracking request metrics."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs) -> Any:
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                status_code = 200
            except Exception as e:
                metrics.record_error(type(e).__name__)
                status_code = 500
                raise
            finally:
                duration = time.time() - start_time
                metrics.record_request(method, endpoint, status_code, duration)
            return result
        
        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs) -> Any:
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                status_code = 200
            except Exception as e:
                metrics.record_error(type(e).__name__)
                status_code = 500
                raise
            finally:
                duration = time.time() - start_time
                metrics.record_request(method, endpoint, status_code, duration)
            return result
        
        # Determine if function is async
        if inspect.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper
    
    return decorator


def track_operation(metrics: ApplicationMetrics, operation: str):
    """Decorator for tracking operation metrics."""
    def decorator(func: Callable) -> Callable:
        @functools.wraps(func)
        async def async_wrapper(*args, **kwargs) -> Any:
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                status = "success"
            except Exception as e:
                metrics.record_error(type(e).__name__)
                status = "error"
                raise
            finally:
                duration = time.time() - start_time
                metrics.record_operation(operation, status, duration)
            return result
        
        @functools.wraps(func)
        def sync_wrapper(*args, **kwargs) -> Any:
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                status = "success"
            except Exception as e:
                metrics.record_error(type(e).__name__)
                status = "error"
                raise
            finally:
                duration = time.time() - start_time
                metrics.record_operation(operation, status, duration)
            return result
        
        if inspect.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper
    
    return decorator


__all__ = [
    "HealthStatus",
    "HealthCheckResult",
    "MonitoringConfig",
    "ApplicationMetrics",
    "track_metrics",
    "track_operation",
]
