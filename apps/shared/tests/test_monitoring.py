import asyncio
import importlib.util
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class _MetricChild:
    def __init__(self, metric, labels):
        self.metric = metric
        self.labels = labels

    def inc(self, amount: float = 1.0):
        self.metric.samples.append((self.labels, self.metric.value + amount))
        self.metric.value += amount

    def observe(self, value: float):
        self.metric.samples.append((self.labels, value))

    def set(self, value: float):
        self.metric.samples.append((self.labels, value))
        self.metric.value = value


class _Metric:
    def __init__(self, *args, **kwargs):
        self.name = args[0] if args else kwargs.get("name", "metric")
        self.registry = kwargs.get("registry")
        self.samples = []
        self.value = 0.0
        if self.registry is not None:
            self.registry.metrics.append(self)

    def labels(self, **labels):
        return _MetricChild(self, labels)

    def info(self, data):
        self.samples.append((data, 1.0))

    def inc(self, amount: float = 1.0):
        self.samples.append(({}, self.value + amount))
        self.value += amount

    def observe(self, value: float):
        self.samples.append(({}, value))

    def set(self, value: float):
        self.samples.append(({}, value))
        self.value = value


class _CollectorRegistry:
    def __init__(self):
        self.metrics = []


def _generate_latest(registry):
    lines = []
    for metric in registry.metrics:
        if metric.samples:
            for labels, value in metric.samples:
                if isinstance(labels, dict) and labels:
                    label_text = ",".join(f'{key}="{val}"' for key, val in labels.items())
                    lines.append(f"{metric.name}{{{label_text}}} {value}")
                else:
                    lines.append(f"{metric.name} {value}")
        else:
            lines.append(f"{metric.name} {metric.value}")
    return "\n".join(lines).encode("utf-8")


prometheus_stub = types.ModuleType("prometheus_client")
prometheus_stub.CollectorRegistry = _CollectorRegistry
prometheus_stub.Counter = _Metric
prometheus_stub.Gauge = _Metric
prometheus_stub.Histogram = _Metric
prometheus_stub.Info = _Metric
prometheus_stub.Summary = _Metric
prometheus_stub.REGISTRY = _CollectorRegistry()
prometheus_stub.generate_latest = _generate_latest
sys.modules.setdefault("prometheus_client", prometheus_stub)

CollectorRegistry = _CollectorRegistry

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


MONITORING = _load_module("apps.shared.monitoring", "monitoring.py")

ApplicationMetrics = MONITORING.ApplicationMetrics
HealthStatus = MONITORING.HealthStatus
MonitoringConfig = MONITORING.MonitoringConfig
track_metrics = MONITORING.track_metrics
track_operation = MONITORING.track_operation


def test_record_request_and_metrics_exposition() -> None:
    registry = CollectorRegistry()
    config = MonitoringConfig(app_name="demo", app_version="1.2.3", environment="test", registry=registry)
    metrics = ApplicationMetrics(config)

    metrics.record_request("GET", "/health", 200, 0.123)
    metrics.record_error("ValueError")
    metrics.record_operation("sync_job", "success", 0.456)
    metrics.set_active_connections(7)
    metrics.record_cache_hit("default")
    metrics.record_cache_miss("default")

    exposition = metrics.get_metrics().decode("utf-8")

    assert "demo_requests_total" in exposition
    assert 'status="200"' in exposition
    assert "demo_errors_total" in exposition
    assert "demo_active_connections 7" in exposition


async def test_health_check_and_async_decorators() -> None:
    registry = CollectorRegistry()
    metrics = ApplicationMetrics(
        MonitoringConfig(app_name="demo", app_version="1.2.3", environment="test", registry=registry)
    )
    metrics.register_health_check("ok", lambda: True)
    metrics.register_health_check("fail", lambda: False)

    result = await metrics.perform_health_check()

    assert result.status == HealthStatus.DEGRADED
    assert result.checks["ok"]["status"] == "pass"
    assert result.checks["fail"]["status"] == "fail"

    @track_metrics(metrics, method="POST", endpoint="/demo")
    async def sample_async() -> str:
        await asyncio.sleep(0)
        return "ok"

    @track_operation(metrics, "sample")
    def sample_sync() -> str:
        return "ok"

    assert await sample_async() == "ok"
    assert sample_sync() == "ok"


def test_health_check_and_async_decorators_sync_wrapper() -> None:
    asyncio.run(test_health_check_and_async_decorators())