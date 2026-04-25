"""
Shared pytest configuration and fixtures
Issue #1537 Week 1: Unit Testing Infrastructure
"""
import os
import sys
from typing import Generator, Any
import pytest
from faker import Faker
from pathlib import Path

# Add src to path for imports
REPO_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(REPO_ROOT / "src"))

# Initialize faker for test data generation
fake = Faker()


# ============================================================================
# FIXTURES: Data Generation
# ============================================================================

@pytest.fixture
def faker():
    """Provide Faker instance for test data generation"""
    return Faker()


@pytest.fixture
def test_user_data(faker):
    """Provide test user data"""
    return {
        "id": faker.uuid4(),
        "email": faker.email(),
        "username": faker.user_name(),
        "first_name": faker.first_name(),
        "last_name": faker.last_name(),
        "created_at": faker.date_time(),
    }


@pytest.fixture
def test_team_data(faker):
    """Provide test team data"""
    return {
        "id": faker.uuid4(),
        "name": faker.word().title(),
        "slug": faker.slug(),
        "description": faker.sentence(),
        "org_id": faker.uuid4(),
        "created_by": faker.uuid4(),
    }


# ============================================================================
# FIXTURES: Environment & Configuration
# ============================================================================

@pytest.fixture
def test_env(monkeypatch):
    """Provide test environment variables"""
    test_vars = {
        "ENVIRONMENT": "test",
        "LOG_LEVEL": "DEBUG",
        "DATABASE_URL": "sqlite:///:memory:",
        "REDIS_URL": "redis://localhost:6379/1",
        "SECRET_KEY": "test-secret-key-do-not-use-in-production",
        "API_KEY": faker.sha256(),
    }
    
    for key, value in test_vars.items():
        monkeypatch.setenv(key, str(value))
    
    return test_vars


@pytest.fixture
def test_config(test_env):
    """Provide test configuration object"""
    return {
        "testing": True,
        "debug": True,
        "database": {
            "url": "sqlite:///:memory:",
            "echo": False,
            "pool_size": 5,
        },
        "cache": {
            "url": "redis://localhost:6379/1",
            "ttl": 3600,
        },
        "security": {
            "secret_key": test_env["SECRET_KEY"],
            "algorithm": "HS256",
        },
    }


# ============================================================================
# FIXTURES: Cleanup & Reset
# ============================================================================

@pytest.fixture(autouse=True)
def reset_singletons():
    """Reset singleton instances between tests (auto-used)"""
    yield
    # Add cleanup code here if needed


@pytest.fixture
def temp_dir(tmp_path):
    """Provide temporary directory for test files"""
    return tmp_path


@pytest.fixture
def cleanup():
    """Provide cleanup context manager"""
    class Cleanup:
        def __init__(self):
            self.items = []
        
        def add(self, item):
            self.items.append(item)
        
        def clear_all(self):
            for item in reversed(self.items):
                try:
                    item()
                except Exception:
                    pass
    
    c = Cleanup()
    yield c
    c.clear_all()


# ============================================================================
# FIXTURES: Logging
# ============================================================================

@pytest.fixture
def caplog_handler(caplog):
    """Configure caplog for testing"""
    import logging
    caplog.set_level(logging.DEBUG)
    return caplog


# ============================================================================
# PYTEST CONFIGURATION HOOKS
# ============================================================================

def pytest_configure(config):
    """Configure pytest with custom markers"""
    markers = [
        "unit: mark test as a unit test (fast, isolated)",
        "integration: mark test as an integration test (medium speed)",
        "e2e: mark test as an end-to-end test (slow, comprehensive)",
        "slow: mark test as slow (timeout > 10s)",
        "skip_ci: skip test in CI environment",
        "requires_db: test requires database connection",
        "requires_cache: test requires cache (Redis)",
    ]
    
    for marker in markers:
        config.addinivalue_line("markers", marker)


def pytest_collection_modifyitems(config, items):
    """Modify test collection"""
    for item in items:
        # Auto-mark tests based on file path
        if "unit" in item.nodeid:
            item.add_marker(pytest.mark.unit)
        elif "integration" in item.nodeid:
            item.add_marker(pytest.mark.integration)
        elif "e2e" in item.nodeid:
            item.add_marker(pytest.mark.e2e)


# ============================================================================
# PYTEST HOOKS: Reporting
# ============================================================================

def pytest_runtest_logreport(report):
    """Hook for test result reporting"""
    if report.when == "call":
        if report.outcome == "failed":
            # Log failed tests for debugging
            pass


# ============================================================================
# Parametrize Helpers
# ============================================================================

def invalid_email_addresses():
    """Return list of invalid email addresses for parametrized tests"""
    return [
        "",
        "plainaddress",
        "@example.com",
        "user@",
        "user name@example.com",
        "user@example.c",
        "user@@example.com",
    ]


def invalid_usernames():
    """Return list of invalid usernames for parametrized tests"""
    return [
        "",  # Empty
        "x",  # Too short
        "a" * 256,  # Too long
        "user@name",  # Invalid chars
        "user name",  # Spaces
        "user-",  # Ends with dash
        "-user",  # Starts with dash
    ]


def invalid_passwords():
    """Return list of invalid passwords for parametrized tests"""
    return [
        "",  # Empty
        "short",  # Too short
        "nouppercase123!",  # No uppercase
        "NOLOWERCASE123!",  # No lowercase
        "NoNumbers!",  # No numbers
        "NoSpecialChar1",  # No special char
    ]
