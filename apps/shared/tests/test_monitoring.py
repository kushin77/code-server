import asyncio

import pytest
from prometheus_client import CollectorRegistry

from apps.shared.monitoring import ApplicationMetrics, HealthStatus, MonitoringConfig, track_metrics, track_operation


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
    assert "demo_active_connections 7.0" in exposition


@pytest.mark.asyncio
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