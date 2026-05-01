"""
Pytest configuration and fixtures for Testing Service.

Provides:
- sys.path setup for in-package imports
- Basic test fixtures: mock logger, test config overrides
"""
import os
import sys
import pytest
from unittest.mock import MagicMock

# Ensure app root is importable
_APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _APP_ROOT not in sys.path:
    sys.path.insert(0, _APP_ROOT)


@pytest.fixture(autouse=True)
def reset_env(monkeypatch):
    """Reset relevant environment variables before each test."""
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("LOG_LEVEL", "WARNING")


@pytest.fixture
def mock_logger():
    """Provide a no-op logger for unit tests."""
    logger = MagicMock()
    logger.info = MagicMock()
    logger.warning = MagicMock()
    logger.error = MagicMock()
    logger.debug = MagicMock()
    return logger
