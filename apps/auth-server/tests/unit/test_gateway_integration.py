"""
Unit Tests - API Gateway Integration
Issue #1345 Week 5: API Gateway Integration Testing
"""
import pytest
from unittest.mock import Mock, patch
import uuid
import jwt
from datetime import datetime, timedelta

from src.gateway_auth import OAuth2TokenValidator, APIKeyAuthenticator, ServiceAuthenticator
from src.gateway_permissions import PermissionEnforcer, RBACMiddleware
from src.gateway_ratelimit import RateLimiter, QuotaManager


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def mock_config():
    """Mock configuration"""
    config = Mock()
    config.JWT_ISSUER = "https://auth.kushnir.cloud"
    config.JWT_AUDIENCE = "api.kushnir.cloud"
    config.PUBLIC_KEY = "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAL/...\n-----END PUBLIC KEY-----"
    config.PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBA...\n-----END PRIVATE KEY-----"
    config.DEBUG = False
    return config


@pytest.fixture
def mock_cache():
    """Mock cache (Redis)"""
    return Mock()


@pytest.fixture
def mock_db():
    """Mock database"""
    return Mock()


@pytest.fixture
def mock_redis():
    """Mock Redis"""
    return Mock()


@pytest.fixture
def token_validator(mock_config, mock_cache):
    """Token validator"""
    return OAuth2TokenValidator(mock_config, mock_cache)


@pytest.fixture
def api_key_auth(mock_db, mock_config):
    """API key authenticator"""
    return APIKeyAuthenticator(mock_db, mock_config)


@pytest.fixture
def service_auth(mock_config):
    """Service authenticator"""
    return ServiceAuthenticator(mock_config)


@pytest.fixture
def permission_enforcer(mock_db, mock_config):
    """Permission enforcer"""
    return PermissionEnforcer(mock_db, mock_config)


@pytest.fixture
def rate_limiter(mock_redis, mock_config):
    """Rate limiter"""
    return RateLimiter(mock_redis, mock_config)


@pytest.fixture
def quota_manager(mock_redis, mock_db):
    """Quota manager"""
    return QuotaManager(mock_redis, mock_db)


# ============================================================================
# OAuth2 Token Validation Tests
# ============================================================================

class TestOAuth2TokenValidation:
    """Test OAuth2 token validation"""
    
    def test_validate_valid_token(self, token_validator):
        """Test validating valid token"""
        
        # Mock token decode
        with patch('src.gateway_auth.jwt.decode') as mock_decode:
            mock_decode.return_value = {
                "sub": str(uuid.uuid4()),
                "email": "user@example.com",
                "exp": datetime.utcnow().timestamp() + 3600,
                "iat": datetime.utcnow().timestamp(),
            }
            
            result = token_validator.validate_token("valid_token")
            
            assert result["sub"] is not None
            assert result["email"] == "user@example.com"
    
    def test_validate_expired_token(self, token_validator):
        """Test validating expired token"""
        
        with patch('src.gateway_auth.jwt.decode') as mock_decode:
            mock_decode.side_effect = jwt.ExpiredSignatureError()
            
            from fastapi import HTTPException
            with pytest.raises(HTTPException) as exc_info:
                token_validator.validate_token("expired_token")
            
            assert exc_info.value.status_code == 401
    
    def test_validate_blacklisted_token(self, token_validator, mock_cache):
        """Test validating blacklisted (revoked) token"""
        
        token = "revoked_token"
        mock_cache.exists.return_value = True
        
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as exc_info:
            token_validator.validate_token(token)
        
        assert exc_info.value.status_code == 401
    
    def test_get_current_user(self, token_validator):
        """Test extracting current user from token"""
        
        with patch.object(token_validator, 'validate_token') as mock_validate:
            mock_validate.return_value = {
                "sub": str(uuid.uuid4()),
                "email": "user@example.com",
                "org_id": str(uuid.uuid4()),
                "teams": ["team-1", "team-2"],
                "permissions": ["read", "write"],
            }
            
            result = token_validator.get_current_user("valid_token")
            
            assert result["user_id"] is not None
            assert result["email"] == "user@example.com"
            assert len(result["teams"]) == 2


# ============================================================================
# API Key Authentication Tests
# ============================================================================

class TestAPIKeyAuthentication:
    """Test API key authentication"""
    
    def test_create_api_key(self, api_key_auth):
        """Test creating API key"""
        user_id = str(uuid.uuid4())
        
        api_key_auth._create_api_key_record = Mock(
            return_value=Mock(id=str(uuid.uuid4()))
        )
        
        result = api_key_auth.create_api_key(
            user_id=user_id,
            name="Test Key",
            scopes=["read", "write"],
        )
        
        assert result["key_id"] is not None
        assert result["name"] == "Test Key"
        assert "key" in result
        assert result["message"] != ""
    
    def test_authenticate_api_key_valid(self, api_key_auth):
        """Test authenticating with valid API key"""
        
        api_key = "sk_live_test123456789"
        api_key_auth._get_api_key_by_hash = Mock(
            return_value=Mock(
                user_id=str(uuid.uuid4()),
                scopes=["read"],
                id=str(uuid.uuid4()),
                expires_at=datetime.utcnow() + timedelta(days=30),
            )
        )
        api_key_auth._update_key_last_used = Mock()
        
        result = api_key_auth.authenticate_api_key(api_key)
        
        assert result["user_id"] is not None
        assert result["scopes"] == ["read"]
    
    def test_authenticate_api_key_expired(self, api_key_auth):
        """Test authenticating with expired API key"""
        
        api_key = "sk_live_expired"
        api_key_auth._get_api_key_by_hash = Mock(
            return_value=Mock(
                user_id=str(uuid.uuid4()),
                expires_at=datetime.utcnow() - timedelta(days=1),  # Expired
            )
        )
        
        with pytest.raises(ValueError):
            api_key_auth.authenticate_api_key(api_key)
    
    def test_list_api_keys(self, api_key_auth):
        """Test listing API keys"""
        user_id = str(uuid.uuid4())
        
        now = datetime.utcnow()
        api_key_auth._get_user_api_keys = Mock(
            return_value=[
                Mock(
                    id=str(uuid.uuid4()),
                    name="Key 1",
                    scopes=["read"],
                    created_at=now,
                    last_used=now,
                    expires_at=now + timedelta(days=30),
                ),
                Mock(
                    id=str(uuid.uuid4()),
                    name="Key 2",
                    scopes=["write"],
                    created_at=now,
                    last_used=None,
                    expires_at=now + timedelta(days=60),
                ),
            ]
        )
        
        result = api_key_auth.list_api_keys(user_id)
        
        assert len(result) == 2
        assert result[0]["name"] == "Key 1"
        assert "key" not in result[0]  # Don't reveal secrets


# ============================================================================
# Permission Enforcement Tests
# ============================================================================

class TestPermissionEnforcement:
    """Test permission enforcement"""
    
    def test_check_permission_admin(self, permission_enforcer):
        """Test admin has all permissions"""
        user_id = str(uuid.uuid4())
        
        permission_enforcer._get_user_roles = Mock(return_value=["admin"])
        
        assert permission_enforcer.check_permission(user_id, "read") is True
        assert permission_enforcer.check_permission(user_id, "write") is True
        assert permission_enforcer.check_permission(user_id, "delete") is True
    
    def test_check_permission_developer(self, permission_enforcer):
        """Test developer limited permissions"""
        user_id = str(uuid.uuid4())
        
        permission_enforcer._get_user_roles = Mock(return_value=["developer"])
        
        assert permission_enforcer.check_permission(user_id, "read") is True
        assert permission_enforcer.check_permission(user_id, "write") is True
        assert permission_enforcer.check_permission(user_id, "delete") is False
    
    def test_check_team_access(self, permission_enforcer):
        """Test checking team access"""
        user_id = str(uuid.uuid4())
        team_id = str(uuid.uuid4())
        
        permission_enforcer._is_team_member = Mock(return_value=True)
        
        assert permission_enforcer.check_team_access(user_id, team_id) is True


# ============================================================================
# Rate Limiting Tests
# ============================================================================

class TestRateLimiting:
    """Test rate limiting"""
    
    def test_check_rate_limit_allowed(self, rate_limiter, mock_redis):
        """Test request allowed under rate limit"""
        user_id = str(uuid.uuid4())
        
        mock_redis.get.return_value = b"50"  # Current count
        mock_redis.ttl.return_value = 30
        rate_limiter._get_rate_limit = Mock(return_value=100)
        
        allowed, stats = rate_limiter.check_rate_limit(user_id)
        
        assert allowed is True
        assert stats["remaining"] > 0
    
    def test_check_rate_limit_exceeded(self, rate_limiter, mock_redis):
        """Test request exceeded rate limit"""
        user_id = str(uuid.uuid4())
        
        mock_redis.get.return_value = b"100"  # At limit
        mock_redis.ttl.return_value = 30
        rate_limiter._get_rate_limit = Mock(return_value=100)
        
        allowed, stats = rate_limiter.check_rate_limit(user_id)
        
        assert allowed is False
        assert stats["remaining"] == 0


# ============================================================================
# Quota Management Tests
# ============================================================================

class TestQuotaManagement:
    """Test quota management"""
    
    def test_check_quota_allowed(self, quota_manager, mock_redis):
        """Test request allowed under quota"""
        owner_id = str(uuid.uuid4())
        
        mock_redis.get.return_value = b"50000"  # Current usage
        quota_manager._get_quota_limit = Mock(return_value=1000000)
        
        allowed, stats = quota_manager.check_quota("api_calls", owner_id, amount=1000)
        
        assert allowed is True
        assert stats["remaining"] > 0
    
    def test_check_quota_exceeded(self, quota_manager, mock_redis):
        """Test request exceeded quota"""
        owner_id = str(uuid.uuid4())
        
        mock_redis.get.return_value = b"1000000"  # At limit
        quota_manager._get_quota_limit = Mock(return_value=1000000)
        
        allowed, stats = quota_manager.check_quota("api_calls", owner_id, amount=1)
        
        assert allowed is False
        assert stats["exceeded_by"] > 0
    
    def test_get_quota_usage(self, quota_manager, mock_redis):
        """Test getting quota usage"""
        owner_id = str(uuid.uuid4())
        
        mock_redis.get.return_value = b"250000"
        quota_manager._get_quota_limit = Mock(return_value=1000000)
        
        usage = quota_manager.get_quota_usage("api_calls", owner_id)
        
        assert usage["quota_limit"] == 1000000
        assert usage["current_usage"] == 250000
        assert usage["percent_used"] == 25


# ============================================================================
# Service-to-Service Tests
# ============================================================================

class TestServiceAuthentication:
    """Test service-to-service authentication"""
    
    def test_generate_service_token(self, service_auth):
        """Test generating service token"""
        
        token = service_auth.generate_service_token(
            service_id=str(uuid.uuid4()),
            service_name="auth-service",
            scopes=["read:users", "write:teams"],
        )
        
        assert token is not None
        assert len(token) > 0
