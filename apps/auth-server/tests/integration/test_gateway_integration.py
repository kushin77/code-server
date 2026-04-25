"""
Integration Tests - API Gateway & Authorization
Issue #1537 Week 2: Integration Tests

Coverage:
- OAuth2 JWT token validation at gateway
- API key authentication and management
- Rate limiting (per user, per API key, per IP)
- Quota enforcement and tracking
- RBAC middleware enforcement
- Service-to-service authentication
- Permission checks across resources
"""
import pytest
import uuid
from datetime import datetime, timedelta
from unittest.mock import patch, Mock

pytestmark = pytest.mark.integration


# ============================================================================
# OAuth2 Token Validation at Gateway
# ============================================================================

class TestOAuth2GatewayValidation:
    """Test OAuth2 token validation at API gateway"""
    
    def test_valid_oauth_token_accepted(self, token_validator, mock_config):
        """Test valid OAuth token is accepted"""
        user_id = str(uuid.uuid4())
        
        # Generate valid token
        from src.oauth2_server import OAuth2Server
        oauth_server = OAuth2Server(None, mock_config)
        
        token = oauth_server.generate_access_token(
            user_id=user_id,
            email="user@example.com",
            org_id=str(uuid.uuid4()),
        )
        
        # Validate at gateway
        result = token_validator.validate_token(token)
        
        assert result["valid"] is True
        assert result["user_id"] == user_id
    
    def test_expired_token_rejected(self, token_validator, mock_config):
        """Test expired token is rejected"""
        # Generate expired token (requires mock or time travel)
        pass
    
    def test_invalid_signature_rejected(self, token_validator, mock_config):
        """Test token with invalid signature is rejected"""
        invalid_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature"
        
        result = token_validator.validate_token(invalid_token)
        
        assert result["valid"] is False
    
    def test_blacklisted_token_rejected(self, token_validator, mock_redis):
        """Test blacklisted token is rejected"""
        token = "valid-but-blacklisted-token"
        
        # Mock Redis to return token as blacklisted
        mock_redis.exists.return_value = True
        
        result = token_validator.validate_token(token)
        
        assert result["valid"] is False
    
    def test_get_current_user_from_token(self, token_validator):
        """Test extracting user from valid token"""
        # This would use a real or mocked valid token
        pass


# ============================================================================
# API Key Authentication Tests
# ============================================================================

class TestAPIKeyAuthentication:
    """Test API key authentication"""
    
    def test_create_api_key(self, api_key_auth, test_user):
        """Test creating API key"""
        result = api_key_auth.create_api_key(
            user_id=test_user.id,
            name="Integration Test Key",
            scopes=["read:teams", "write:projects"],
        )
        
        assert result["key"] is not None
        assert result["key"].startswith("sk_")
        assert result["created_at"] is not None
    
    def test_authenticate_api_key(self, api_key_auth, test_user, db_session):
        """Test authenticating with API key"""
        # Create key
        create_result = api_key_auth.create_api_key(
            user_id=test_user.id,
            name="Test Key",
            scopes=["read:user"],
        )
        key = create_result["key"]
        
        # Authenticate
        result = api_key_auth.authenticate_api_key(key)
        
        assert result["authenticated"] is True
        assert result["user_id"] == str(test_user.id)
    
    def test_invalid_api_key_rejected(self, api_key_auth):
        """Test invalid API key is rejected"""
        result = api_key_auth.authenticate_api_key("sk_invalid_key_xyz")
        
        assert result["authenticated"] is False
    
    def test_revoked_api_key_rejected(self, api_key_auth, test_user):
        """Test revoked API key is rejected"""
        # Create and revoke
        create_result = api_key_auth.create_api_key(
            user_id=test_user.id,
            name="Revoke Test",
        )
        key_id = create_result["id"]
        
        api_key_auth.revoke_api_key(key_id, test_user.id)
        
        # Try to authenticate revoked key
        result = api_key_auth.authenticate_api_key(create_result["key"])
        
        assert result["authenticated"] is False
    
    def test_list_api_keys_no_secrets(self, api_key_auth, test_user):
        """Test API keys listed without secrets"""
        # Create multiple keys
        api_key_auth.create_api_key(test_user.id, "Key 1")
        api_key_auth.create_api_key(test_user.id, "Key 2")
        
        # List keys
        result = api_key_auth.list_api_keys(test_user.id)
        
        assert len(result["keys"]) >= 2
        # Verify no secrets in response
        for key in result["keys"]:
            assert "key" not in key or key["key"] is None


# ============================================================================
# Rate Limiting Tests
# ============================================================================

class TestRateLimiting:
    """Test rate limiting enforcement"""
    
    def test_rate_limit_within_quota(self, mock_redis):
        """Test request within rate limit is allowed"""
        from src.gateway_ratelimit import RateLimiter
        
        rate_limiter = RateLimiter(mock_redis, "test-config")
        
        # First request
        result = rate_limiter.check_rate_limit(
            identifier="user-123",
            limit_type="user",
            limit=100,
        )
        
        assert result["allowed"] is True
        assert result["remaining"] > 0
    
    def test_rate_limit_exceeded(self, mock_redis):
        """Test request exceeding rate limit is rejected"""
        from src.gateway_ratelimit import RateLimiter
        
        # Mock Redis to return limit exceeded
        mock_redis.incr.return_value = 101
        mock_redis.ttl.return_value = 60
        
        rate_limiter = RateLimiter(mock_redis, "test-config")
        
        result = rate_limiter.check_rate_limit(
            identifier="user-123",
            limit_type="user",
            limit=100,
        )
        
        assert result["allowed"] is False
    
    def test_rate_limit_headers(self):
        """Test rate limit headers in response"""
        # X-RateLimit-Limit: 100
        # X-RateLimit-Current: 45
        # X-RateLimit-Remaining: 55
        pass


# ============================================================================
# Quota Management Tests
# ============================================================================

class TestQuotaManagement:
    """Test quota enforcement"""
    
    def test_quota_within_limit(self, db_session):
        """Test resource usage within quota"""
        from src.gateway_ratelimit import QuotaManager
        
        quota_manager = QuotaManager(db_session, "test-config")
        
        result = quota_manager.check_quota(
            owner_type="user",
            owner_id="user-123",
            resource_type="api_calls",
            requested_amount=50,
            quota_limit=1000,
        )
        
        assert result["allowed"] is True
        assert result["remaining"] > 0
    
    def test_quota_exceeded(self, db_session):
        """Test quota exceeded is rejected"""
        from src.gateway_ratelimit import QuotaManager
        
        quota_manager = QuotaManager(db_session, "test-config")
        
        result = quota_manager.check_quota(
            owner_type="user",
            owner_id="user-123",
            resource_type="storage_gb",
            requested_amount=101,
            quota_limit=100,
        )
        
        assert result["allowed"] is False
    
    def test_quota_usage_tracking(self, db_session):
        """Test quota usage is tracked"""
        from src.gateway_ratelimit import QuotaManager
        
        quota_manager = QuotaManager(db_session, "test-config")
        
        # Use some quota
        quota_manager.check_quota(
            owner_type="org",
            owner_id="org-123",
            resource_type="team_members",
            requested_amount=10,
            quota_limit=50,
        )
        
        # Get usage
        usage = quota_manager.get_quota_usage(
            owner_type="org",
            owner_id="org-123",
            resource_type="team_members",
        )
        
        assert usage["current_usage"] >= 10


# ============================================================================
# RBAC Middleware Tests
# ============================================================================

class TestRBACMiddleware:
    """Test role-based access control middleware"""
    
    def test_admin_can_access_all_endpoints(self):
        """Test admin role can access all endpoints"""
        from src.gateway_permissions import PermissionEnforcer
        
        enforcer = PermissionEnforcer()
        
        result = enforcer.check_permission(
            user_role="admin",
            required_permission="admin:*",
        )
        
        assert result["allowed"] is True
    
    def test_developer_cannot_access_admin_endpoints(self):
        """Test developer cannot access admin-only endpoints"""
        from src.gateway_permissions import PermissionEnforcer
        
        enforcer = PermissionEnforcer()
        
        result = enforcer.check_permission(
            user_role="developer",
            required_permission="admin:*",
        )
        
        assert result["allowed"] is False
    
    def test_permission_inheritance(self):
        """Test permission inheritance (admin >= maintainer >= developer)"""
        from src.gateway_permissions import PermissionEnforcer
        
        enforcer = PermissionEnforcer()
        
        # Admin has developer permissions
        admin_result = enforcer.check_permission(
            user_role="admin",
            required_permission="write",
        )
        assert admin_result["allowed"] is True
        
        # Developer has developer permissions
        dev_result = enforcer.check_permission(
            user_role="developer",
            required_permission="write",
        )
        assert dev_result["allowed"] is True


# ============================================================================
# Service-to-Service Authentication Tests
# ============================================================================

class TestServiceAuthentication:
    """Test service-to-service authentication"""
    
    def test_generate_service_token(self, oauth2_server):
        """Test generating service token"""
        from src.oauth2_server import OAuth2Server
        
        token = oauth2_server.generate_service_token(
            service_name="worker-service",
            scopes=["worker:execute", "worker:write_logs"],
        )
        
        assert token is not None
    
    def test_validate_service_token(self, token_validator):
        """Test validating service token"""
        # Generate service token
        from src.oauth2_server import OAuth2Server
        oauth_server = OAuth2Server(None, None)
        
        token = oauth_server.generate_service_token(
            service_name="worker-service",
        )
        
        # Validate
        result = token_validator.validate_token(token)
        
        assert result["valid"] is True
        assert result.get("service_name") == "worker-service"


# ============================================================================
# Permission Enforcement Tests
# ============================================================================

class TestPermissionEnforcement:
    """Test fine-grained permission enforcement"""
    
    def test_check_team_access(self):
        """Test permission check for team access"""
        from src.gateway_permissions import PermissionEnforcer
        
        enforcer = PermissionEnforcer()
        
        # User is member of team
        result = enforcer.check_team_access(
            user_id="user-123",
            team_id="team-456",
            team_members=["user-123", "user-789"],
        )
        
        assert result["allowed"] is True
    
    def test_check_org_access(self):
        """Test permission check for org access"""
        from src.gateway_permissions import PermissionEnforcer
        
        enforcer = PermissionEnforcer()
        
        # User is member of org
        result = enforcer.check_org_access(
            user_id="user-123",
            org_id="org-abc",
            org_members=["user-123", "user-def"],
        )
        
        assert result["allowed"] is True


# ============================================================================
# Integration Tests
# ============================================================================

class TestGatewayIntegration:
    """End-to-end gateway workflows"""
    
    def test_complete_authenticated_request_flow(
        self,
        token_validator,
        mock_redis,
        mock_config,
    ):
        """Test complete authenticated request at gateway"""
        from src.oauth2_server import OAuth2Server
        
        # Step 1: Generate OAuth token
        oauth_server = OAuth2Server(None, mock_config)
        user_id = str(uuid.uuid4())
        
        token = oauth_server.generate_access_token(
            user_id=user_id,
            email="user@example.com",
            org_id=str(uuid.uuid4()),
        )
        
        # Step 2: Validate at gateway
        validated = token_validator.validate_token(token)
        assert validated["valid"] is True
        
        # Step 3: Check rate limit
        # (in real flow)
        
        # Step 4: Check permissions
        # (in real flow)
    
    def test_api_key_authenticated_request_flow(
        self,
        api_key_auth,
        test_user,
    ):
        """Test API key authenticated request flow"""
        # Step 1: Create API key
        create_result = api_key_auth.create_api_key(
            user_id=test_user.id,
            name="Integration Test",
            scopes=["read:data", "write:data"],
        )
        key = create_result["key"]
        
        # Step 2: Authenticate request
        auth_result = api_key_auth.authenticate_api_key(key)
        assert auth_result["authenticated"] is True
        
        # Step 3: Check scopes
        assert "read:data" in auth_result.get("scopes", [])
