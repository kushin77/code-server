"""
Pytest Configuration & Fixtures - Integration Testing
Issue #1537 Week 2: Integration Tests

Provides:
- PostgreSQL test database fixtures with transaction rollback
- Mock Redis client
- OAuth provider mocks
- Email service mocks
- Test data factories
"""
import os
import pytest
from unittest.mock import Mock, MagicMock, patch
from datetime import datetime, timedelta
import uuid
import asyncio
from typing import Generator

# Database
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool

# Application
from src.oauth2_server import OAuth2Server
from src.user_provisioning import UserProvisioningService
from src.team_service import TeamManagementService
from src.session_service import SingleSignOutService
from src.gateway_auth import OAuth2TokenValidator, APIKeyAuthenticator
import os


# ============================================================================
# Database Configuration
# ============================================================================

# Use in-memory SQLite for tests (or PostgreSQL for more realistic testing)
TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://test:test@localhost:5432/paperclip_test"
)

# Alternative in-memory SQLite for faster tests
if os.getenv("USE_SQLITE_TESTS", "false").lower() == "true":
    TEST_DATABASE_URL = "sqlite:///:memory:"


@pytest.fixture(scope="session")
def engine():
    """Create database engine for tests"""
    
    if "sqlite" in TEST_DATABASE_URL:
        # SQLite with in-memory database
        engine = create_engine(
            TEST_DATABASE_URL,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    else:
        # PostgreSQL
        engine = create_engine(
            TEST_DATABASE_URL,
            poolclass=StaticPool,
        )
    
    # Create all tables from Base
    from src.oauth2_server import Base as OAuth2Base
    from src.user_models import Base as UserBase
    from src.team_models import Base as TeamBase
    from src.advanced_models import Base as AdvancedBase
    from src.gateway_models import Base as GatewayBase
    
    for base in [OAuth2Base, UserBase, TeamBase, AdvancedBase, GatewayBase]:
        base.metadata.create_all(bind=engine)
    
    yield engine
    
    # Drop all tables after tests
    for base in [OAuth2Base, UserBase, TeamBase, AdvancedBase, GatewayBase]:
        base.metadata.drop_all(bind=engine)


@pytest.fixture
def db_session(engine) -> Generator[Session, None, None]:
    """Create database session with transaction rollback"""
    
    # Start transaction
    connection = engine.connect()
    transaction = connection.begin()
    
    # Create session bound to transaction
    session_factory = sessionmaker(bind=connection)
    session = session_factory()
    
    yield session
    
    # Rollback after test
    session.close()
    transaction.rollback()
    connection.close()


# ============================================================================
# Mock Services
# ============================================================================

@pytest.fixture
def mock_config():
    """Mock configuration"""
    config = Mock()
    config.JWT_ISSUER = "https://auth.test.local"
    config.JWT_AUDIENCE = "api.test.local"
    config.JWT_SECRET = "test-secret-key-1234567890abcdefghij"
    config.OAUTH_REDIRECT_URI = "http://localhost:3000/oauth/callback"
    config.PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAL/...\n-----END PUBLIC KEY-----"
    config.PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBA...\n-----END PRIVATE KEY-----"
    config.DEBUG = True
    return config


@pytest.fixture
def mock_redis():
    """Mock Redis client"""
    redis = Mock()
    redis.get.return_value = None
    redis.set.return_value = True
    redis.delete.return_value = True
    redis.exists.return_value = False
    redis.incr.return_value = 1
    redis.expire.return_value = True
    redis.ttl.return_value = 60
    redis.setex.return_value = True
    redis.incrby.return_value = 1
    return redis


@pytest.fixture
def mock_email_service():
    """Mock email service"""
    email_service = Mock()
    email_service.send_verification_email = Mock(return_value=True)
    email_service.send_password_reset_email = Mock(return_value=True)
    email_service.send_mfa_email = Mock(return_value=True)
    email_service.send_invitation_email = Mock(return_value=True)
    return email_service


@pytest.fixture
def mock_sms_service():
    """Mock SMS service"""
    sms_service = Mock()
    sms_service.send_sms = Mock(return_value=True)
    return sms_service


@pytest.fixture
def mock_oauth_providers():
    """Mock OAuth provider clients"""
    providers = {
        "github": Mock(
            get_user_info=Mock(return_value={
                "id": "12345",
                "login": "testuser",
                "email": "test@github.com",
                "name": "Test User",
            })
        ),
        "google": Mock(
            get_user_info=Mock(return_value={
                "id": "67890",
                "email": "test@gmail.com",
                "name": "Test User",
                "picture": "https://example.com/pic.jpg",
            })
        ),
        "microsoft": Mock(
            get_user_info=Mock(return_value={
                "id": "abcdef",
                "userPrincipalName": "test@microsoft.com",
                "displayName": "Test User",
            })
        ),
    }
    return providers


# ============================================================================
# Service Fixtures
# ============================================================================

@pytest.fixture
def oauth2_server(db_session, mock_config):
    """OAuth2 server instance"""
    return OAuth2Server(db_session, mock_config)


@pytest.fixture
def user_provisioning_service(db_session, mock_config, mock_email_service):
    """User provisioning service"""
    return UserProvisioningService(db_session, mock_config, mock_email_service)


@pytest.fixture
def team_service(db_session, mock_config):
    """Team management service"""
    return TeamManagementService(db_session, mock_config)


@pytest.fixture
def sso_service(db_session, mock_redis, mock_config):
    """Single Sign-Out service"""
    return SingleSignOutService(db_session, mock_redis, mock_config)


@pytest.fixture
def token_validator(mock_config, mock_redis):
    """OAuth2 token validator"""
    return OAuth2TokenValidator(mock_config, mock_redis)


@pytest.fixture
def api_key_auth(db_session, mock_config):
    """API key authenticator"""
    return APIKeyAuthenticator(db_session, mock_config)


# ============================================================================
# Test Data Factories
# ============================================================================

@pytest.fixture
def create_test_user():
    """Factory to create test user"""
    def _create_user(db_session, email=None, name=None):
        from src.user_models import User
        
        user = User(
            id=uuid.uuid4(),
            email=email or f"test-{uuid.uuid4().hex[:8]}@example.com",
            name=name or "Test User",
            status="active",
            email_verified=True,
            locale="en",
            timezone="UTC",
        )
        db_session.add(user)
        db_session.flush()
        return user
    
    return _create_user


@pytest.fixture
def create_test_org():
    """Factory to create test organization"""
    def _create_org(db_session, owner_id, name=None, slug=None):
        from src.team_models import Organization
        
        org = Organization(
            id=uuid.uuid4(),
            owner_id=owner_id,
            name=name or f"Test Org {uuid.uuid4().hex[:4]}",
            slug=slug or f"org-{uuid.uuid4().hex[:8]}",
            plan="pro",
            max_teams=50,
            max_members=100,
        )
        db_session.add(org)
        db_session.flush()
        return org
    
    return _create_org


@pytest.fixture
def create_test_team():
    """Factory to create test team"""
    def _create_team(db_session, org_id, owner_id, name=None, slug=None):
        from src.team_models import Team
        
        team = Team(
            id=uuid.uuid4(),
            organization_id=org_id,
            owner_id=owner_id,
            name=name or f"Test Team {uuid.uuid4().hex[:4]}",
            slug=slug or f"team-{uuid.uuid4().hex[:8]}",
            status="active",
        )
        db_session.add(team)
        db_session.flush()
        return team
    
    return _create_team


@pytest.fixture
def create_test_oauth_connection():
    """Factory to create OAuth connection"""
    def _create_connection(db_session, user_id, provider, provider_user_id):
        from src.oauth2_server import OAuthConnection
        
        connection = OAuthConnection(
            id=uuid.uuid4(),
            user_id=user_id,
            provider=provider,
            provider_user_id=provider_user_id,
            access_token="mock-access-token",
            refresh_token="mock-refresh-token",
            token_expires_at=datetime.utcnow() + timedelta(days=30),
        )
        db_session.add(connection)
        db_session.flush()
        return connection
    
    return _create_connection


@pytest.fixture
def create_test_api_key():
    """Factory to create test API key"""
    def _create_api_key(db_session, user_id, name=None, scopes=None):
        from src.gateway_models import APIKey
        import secrets
        
        api_key = APIKey(
            id=uuid.uuid4(),
            user_id=user_id,
            name=name or f"Test API Key {uuid.uuid4().hex[:4]}",
            key_hash=secrets.token_hex(32),
            scopes=scopes or ["read", "write"],
            expires_at=datetime.utcnow() + timedelta(days=365),
        )
        db_session.add(api_key)
        db_session.flush()
        return api_key
    
    return _create_api_key


# ============================================================================
# Test Data Fixtures
# ============================================================================

@pytest.fixture
def test_user(db_session, create_test_user):
    """Create a test user"""
    return create_test_user(db_session, "testuser@example.com", "Test User")


@pytest.fixture
def test_org(db_session, test_user, create_test_org):
    """Create a test organization"""
    return create_test_org(db_session, test_user.id, "Test Organization", "test-org")


@pytest.fixture
def test_team(db_session, test_org, test_user, create_test_team):
    """Create a test team"""
    return create_test_team(db_session, test_org.id, test_user.id, "Engineering", "eng")


# ============================================================================
# Async Support
# ============================================================================

@pytest.fixture(scope="session")
def event_loop():
    """Provide event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


# ============================================================================
# Pytest Hooks
# ============================================================================

def pytest_configure(config):
    """Configure pytest"""
    config.addinivalue_line(
        "markers",
        "integration: mark test as integration test (requires database)"
    )
    config.addinivalue_line(
        "markers",
        "unit: mark test as unit test (no external dependencies)"
    )


@pytest.fixture(autouse=True)
def reset_mocks():
    """Reset mocks between tests"""
    yield
    # Mocks are automatically reset between tests
