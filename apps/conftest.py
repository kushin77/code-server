"""
Shared pytest fixtures and configuration for all app tests.
Provides common test infrastructure: fixtures, mocks, databases, etc.
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from typing import Generator, Any
import logging

# Configure test logging
logging.basicConfig(level=logging.DEBUG)


@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_logger():
    """Mock logger for unit tests"""
    return Mock(spec=logging.Logger)


@pytest.fixture
def mock_redis():
    """Mock Redis client"""
    redis_mock = AsyncMock()
    redis_mock.get = AsyncMock(return_value=None)
    redis_mock.set = AsyncMock(return_value=True)
    redis_mock.delete = AsyncMock(return_value=1)
    redis_mock.incr = AsyncMock(return_value=1)
    redis_mock.expire = AsyncMock(return_value=True)
    return redis_mock


@pytest.fixture
def mock_database():
    """Mock database session"""
    db_mock = AsyncMock()
    db_mock.execute = AsyncMock()
    db_mock.commit = AsyncMock()
    db_mock.rollback = AsyncMock()
    db_mock.close = AsyncMock()
    return db_mock


@pytest.fixture
def mock_kafka_producer():
    """Mock Kafka producer for event publishing"""
    producer = AsyncMock()
    producer.send = AsyncMock(return_value=None)
    producer.flush = AsyncMock()
    producer.close = AsyncMock()
    return producer


@pytest.fixture
def mock_kafka_consumer():
    """Mock Kafka consumer for event consumption"""
    consumer = AsyncMock()
    consumer.subscribe = AsyncMock()
    consumer.poll = AsyncMock(return_value={})
    consumer.commit = AsyncMock()
    consumer.close = AsyncMock()
    return consumer


@pytest.fixture
def test_user_data():
    """Standard test user data"""
    return {
        "id": "user-123",
        "username": "testuser",
        "email": "test@example.com",
        "password_hash": "hashed_password",
        "is_active": True,
        "created_at": "2026-05-01T00:00:00Z",
    }


@pytest.fixture
def test_team_data():
    """Standard test team data"""
    return {
        "id": "team-123",
        "name": "Test Team",
        "description": "A test team",
        "owner_id": "user-123",
        "created_at": "2026-05-01T00:00:00Z",
    }


@pytest.fixture
def test_api_key():
    """Standard test API key"""
    return "test-api-key-" + "x" * 32


@pytest.fixture
def test_config():
    """Standard test configuration"""
    return {
        "SERVICE_HOST": "0.0.0.0",
        "SERVICE_PORT": 8000,
        "DEBUG": True,
        "LOG_LEVEL": "DEBUG",
        "DATABASE_URL": "sqlite:///test.db",
        "REDIS_URL": "redis://localhost:6379/1",
        "KAFKA_BROKERS": "localhost:9092",
    }


# pytest hooks for test collection and setup/teardown
def pytest_configure(config):
    """Configure pytest"""
    config.addinivalue_line(
        "markers", "integration: mark test as an integration test"
    )
    config.addinivalue_line(
        "markers", "e2e: mark test as an end-to-end test"
    )
    config.addinivalue_line(
        "markers", "performance: mark test as a performance test"
    )


@pytest.fixture(autouse=True)
def reset_mocks():
    """Reset all mocks after each test"""
    yield
    # Cleanup happens here if needed


# Performance testing helpers
class PerformanceTimer:
    """Context manager for performance measurements"""
    def __init__(self, test_name: str):
        self.test_name = test_name
        self.start_time = None
        self.end_time = None

    def __enter__(self):
        self.start_time = asyncio.get_event_loop().time() if asyncio._get_running_loop() else __import__('time').time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.end_time = asyncio.get_event_loop().time() if asyncio._get_running_loop() else __import__('time').time()
        duration = self.end_time - self.start_time
        print(f"\n{self.test_name} took {duration:.3f}s")

    @property
    def duration(self):
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return None


@pytest.fixture
def performance_timer():
    """Provide performance timer fixture"""
    return PerformanceTimer
