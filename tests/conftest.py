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


# ============================================================================
# FIXTURES: Phase 6 Qdrant & Multi-Tenant Testing
# ============================================================================

@pytest.fixture
def sample_vector():
    """Generate a sample 1536-dimensional vector (OpenAI text-embedding-3-small)."""
    import random
    return [random.uniform(-1.0, 1.0) for _ in range(1536)]


@pytest.fixture
def sample_embedding_document():
    """Provide a sample document for embedding tests."""
    return {
        "id": "doc-test-001",
        "title": "Test Document",
        "content": "This is a test document for unit testing organizational memory.",
        "source_url": "https://example.com/docs/test",
        "tags": ["test", "unit", "phase6"],
        "confidence_score": 0.95,
        "timestamp": "2026-04-25T12:00:00Z",
    }


@pytest.fixture
def tenant_context_standard():
    """Provide a standard tier tenant context."""
    return {
        "tenant_id": "tenant-unit-test-001",
        "namespace": "default",
        "tier": "standard",
        "quota_limit": 100000,
    }


@pytest.fixture
def tenant_context_enterprise():
    """Provide an enterprise tier tenant context."""
    return {
        "tenant_id": "tenant-unit-test-enterprise",
        "namespace": "production",
        "tier": "enterprise",
        "quota_limit": 1000000,
    }


@pytest.fixture
def qdrant_collection_config():
    """Provide standard Qdrant collection configuration."""
    return {
        "name": "test-collection",
        "vectors": {
            "size": 1536,
            "distance": "Cosine",
            "on_disk": False,
        },
        "replication_factor": 2,
        "write_consistency_factor": 1,
        "optimizers_config": {
            "default_segment_number": 2,
            "memmap_threshold": 20000,
        },
    }


@pytest.fixture
def mock_qdrant_client(mocker):
    """Mock Qdrant client with common methods."""
    mock = mocker.MagicMock()
    mock.create_collection = mocker.AsyncMock()
    mock.delete_collection = mocker.AsyncMock()
    mock.collection_exists = mocker.AsyncMock(return_value=True)
    mock.upsert = mocker.AsyncMock()
    mock.search = mocker.AsyncMock(return_value=[])
    mock.delete = mocker.AsyncMock()
    mock.get = mocker.AsyncMock()
    mock.get_collection = mocker.AsyncMock()
    mock.create_payload_index = mocker.AsyncMock()
    return mock


@pytest.fixture
def multi_tenant_filter_document():
    """Provide a document with multi-tenant payload for filtering."""
    return {
        "id": "doc-mt-001",
        "title": "Multi-tenant Test",
        "content": "Testing multi-tenant isolation and filtering.",
        "tenant_id": "tenant-unit-test-001",
        "namespace": "test",
        "created_at": "2026-04-25T12:00:00Z",
        "tags": ["isolation", "filtering"],
    }


# ============================================================================
# FIXTURES: Integration Testing (Phase 2)
# ============================================================================

@pytest.fixture
async def async_http_client():
    """Provide async HTTP client for API testing."""
    import httpx
    async with httpx.AsyncClient() as client:
        yield client


@pytest.fixture
async def authenticated_client(async_http_client, app_env):
    """Provide authenticated HTTP client with auth token."""
    # Mock auth token for integration tests
    auth_token = "test-jwt-token-" + fake.sha1()
    
    async_http_client.headers.update({
        "Authorization": f"Bearer {auth_token}",
        "X-Tenant-ID": "tenant-int-test-001",
    })
    
    return async_http_client, auth_token


@pytest.fixture
def auth_token(faker):
    """Provide mock authentication token."""
    return f"test-token-{faker.sha256()}"


@pytest.fixture
def api_headers(auth_token):
    """Provide standard API headers with authentication."""
    return {
        "Authorization": f"Bearer {auth_token}",
        "Content-Type": "application/json",
        "X-Tenant-ID": "tenant-int-test-001",
        "User-Agent": "test-client/1.0",
    }


# ============================================================================
# FIXTURES: Mock Responses
# ============================================================================

@pytest.fixture
def mock_team_response():
    """Provide mock team API response."""
    return {
        "id": "team-test-001",
        "name": "Integration Test Team",
        "slug": "integration-test-team",
        "description": "Team for integration testing",
        "org_id": "org-test-001",
        "created_at": "2026-04-25T12:00:00Z",
        "created_by": "user-test-001",
        "member_count": 3,
    }


@pytest.fixture
def mock_user_response():
    """Provide mock user API response."""
    return {
        "id": "user-test-001",
        "email": "test@example.com",
        "username": "testuser",
        "first_name": "Test",
        "last_name": "User",
        "avatar_url": "https://example.com/avatar.png",
        "created_at": "2026-04-25T12:00:00Z",
    }


@pytest.fixture
def mock_memory_response():
    """Provide mock memory API response."""
    return {
        "id": "memory-test-001",
        "title": "Integration Test Memory",
        "content": "This is a memory entry for integration testing.",
        "collection": "organizational-memory",
        "confidence_score": 0.92,
        "created_at": "2026-04-25T12:00:00Z",
        "tenant_id": "tenant-int-test-001",
    }


# ============================================================================
# FIXTURES: Parametrized Test Data
# ============================================================================

@pytest.fixture(params=["GET", "POST", "PUT", "DELETE", "PATCH"])
def http_methods(request):
    """Parametrize HTTP methods for testing."""
    return request.param


@pytest.fixture(params=[
    "application/json",
    "application/xml",
    "text/plain",
    "application/octet-stream",
])
def content_types(request):
    """Parametrize content types for testing."""
    return request.param


# ============================================================================
# FIXTURES: Error Scenarios
# ============================================================================

@pytest.fixture(params=[
    {"status": 400, "error": "Bad Request", "message": "Invalid request format"},
    {"status": 401, "error": "Unauthorized", "message": "Authentication required"},
    {"status": 403, "error": "Forbidden", "message": "Insufficient permissions"},
    {"status": 404, "error": "Not Found", "message": "Resource not found"},
    {"status": 409, "error": "Conflict", "message": "Resource already exists"},
    {"status": 422, "error": "Validation Error", "message": "Invalid input data"},
    {"status": 429, "error": "Too Many Requests", "message": "Rate limit exceeded"},
    {"status": 500, "error": "Internal Server Error", "message": "Server error"},
])
def error_responses(request):
    """Parametrize error response scenarios."""
    return request.param
