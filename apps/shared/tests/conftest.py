"""
Shared test fixtures for monitoring tests.
"""

import pytest
from prometheus_client import CollectorRegistry

from apps.shared.monitoring import ApplicationMetrics, MonitoringConfig


@pytest.fixture
def test_registry() -> CollectorRegistry:
    """Provide a clean Prometheus registry for each test."""
    return CollectorRegistry()


@pytest.fixture
def monitoring_config(test_registry: CollectorRegistry) -> MonitoringConfig:
    """Provide a test monitoring configuration."""
    return MonitoringConfig(
        app_name="test-app",
        app_version="1.0.0",
        environment="test",
        registry=test_registry,
    )


@pytest.fixture
def app_metrics(monitoring_config: MonitoringConfig) -> ApplicationMetrics:
    """Provide an ApplicationMetrics instance for testing."""
    return ApplicationMetrics(monitoring_config)
