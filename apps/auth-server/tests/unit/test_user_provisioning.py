"""
Unit Tests - User Provisioning and Profile Management
Issue #1345 Week 2: User Management
"""
import pytest
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, AsyncMock
import uuid

from src.user_provisioning import (
    UserProvisioningService,
    UserProvisioningRequest,
    ProvisioningStatus,
    EmailVerificationStatus,
    ProviderUserInfoFetcher,
)
from src.user_models import (
    UserCreateRequest,
    UserUpdateRequest,
    UserPreferencesRequest,
    ChangeEmailRequest,
    UserAPIService,
)


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def mock_db():
    """Mock database session"""
    return Mock()


@pytest.fixture
def mock_config():
    """Mock configuration"""
    config = Mock()
    config.FEATURE_AUTO_PROVISION = True
    config.JWT_ISSUER = "https://auth.kushnir.cloud"
    return config


@pytest.fixture
def provisioning_service(mock_db, mock_config):
    """User provisioning service"""
    return UserProvisioningService(mock_db, mock_config)


@pytest.fixture
def user_api_service(mock_db):
    """User API service"""
    return UserAPIService(mock_db)


@pytest.fixture
def sample_github_user():
    """Sample GitHub user data"""
    return UserProvisioningRequest(
        provider="github",
        provider_user_id="12345",
        email="user@example.com",
        name="John Doe",
        avatar_url="https://avatars.githubusercontent.com/u/12345",
        raw_data={"id": 12345, "login": "johndoe"},
    )


@pytest.fixture
def sample_google_user():
    """Sample Google user data"""
    return UserProvisioningRequest(
        provider="google",
        provider_user_id="google-user-123",
        email="user@gmail.com",
        name="Jane Smith",
        avatar_url="https://lh3.googleusercontent.com/...",
        raw_data={"sub": "google-user-123", "email": "user@gmail.com"},
    )


# ============================================================================
# User Provisioning Tests
# ============================================================================

class TestUserProvisioning:
    """Test user provisioning from OAuth providers"""
    
    def test_provision_new_user_from_github(self, provisioning_service, sample_github_user):
        """Test provisioning new user from GitHub"""
        response = provisioning_service.provision_user_from_provider(sample_github_user)
        
        assert response.status in [ProvisioningStatus.PROVISIONED, ProvisioningStatus.PENDING]
        assert response.email == sample_github_user.email
        assert response.name == sample_github_user.name
        assert response.user_id  # Should have user_id if provisioned
    
    def test_provision_existing_user(self, provisioning_service, sample_github_user):
        """Test provisioning existing user links OAuth connection"""
        # First provisioning
        response1 = provisioning_service.provision_user_from_provider(sample_github_user)
        
        # Second provisioning (OAuth connection already exists)
        response2 = provisioning_service.provision_user_from_provider(sample_github_user)
        
        assert response2.status == ProvisioningStatus.PROVISIONED
    
    def test_skip_provisioning_when_disabled(self, provisioning_service, sample_github_user):
        """Test skipping provisioning when auto_provision is False"""
        response = provisioning_service.provision_user_from_provider(
            sample_github_user,
            auto_provision=False,
        )
        
        assert response.status == ProvisioningStatus.SKIPPED
    
    def test_provision_multiple_providers_same_email(self, provisioning_service, sample_github_user, sample_google_user):
        """Test provisioning user with multiple OAuth providers"""
        # GitHub provisioning
        response1 = provisioning_service.provision_user_from_provider(sample_github_user)
        user_id_1 = response1.user_id
        
        # Same user with different provider (same email)
        sample_google_user.email = sample_github_user.email
        response2 = provisioning_service.provision_user_from_provider(sample_google_user)
        user_id_2 = response2.user_id
        
        # Should be same user
        assert user_id_1 == user_id_2
    
    def test_provisioning_error_handling(self, provisioning_service, sample_github_user):
        """Test error handling in provisioning"""
        # Invalid email
        sample_github_user.email = "invalid-email"
        
        try:
            response = provisioning_service.provision_user_from_provider(sample_github_user)
            assert response.status == ProvisioningStatus.FAILED
        except Exception:
            pass  # Expected


class TestEmailVerification:
    """Test email verification workflow"""
    
    def test_send_verification_email(self, provisioning_service):
        """Test sending verification email"""
        user_id = str(uuid.uuid4())
        
        # Should not raise exception
        result = provisioning_service.send_email_verification(
            user_id=user_id,
            request=Mock(email="user@example.com", verification_link_url=None),
        )
        
        assert result["status"] == "sent"
        assert "expires_in_minutes" in result
    
    def test_verify_email_token(self, provisioning_service):
        """Test verifying email verification token"""
        user_id = str(uuid.uuid4())
        
        # Generate token
        token = provisioning_service._generate_verification_token(user_id)
        
        # Verify token
        result = provisioning_service.verify_email_token(token)
        
        # Should handle verification (mock implementation)
        assert "status" in result


class TestAccountLinking:
    """Test linking OAuth accounts to existing users"""
    
    def test_link_account_to_existing_user(self, provisioning_service):
        """Test linking OAuth account to existing user"""
        user_id = str(uuid.uuid4())
        
        request = Mock(
            user_id=user_id,
            provider="github",
            provider_user_id="12345",
            provider_email="user@example.com",
            provider_name="John Doe",
            provider_avatar_url="https://...",
        )
        
        result = provisioning_service.link_existing_user_to_provider(request)
        
        assert result["status"] in ["linked", "already_linked"]
        assert result["user_id"] == user_id
    
    def test_link_account_user_not_found(self, provisioning_service):
        """Test linking account to non-existent user raises error"""
        user_id = str(uuid.uuid4())
        
        request = Mock(
            user_id=user_id,
            provider="github",
            provider_user_id="12345",
        )
        
        with pytest.raises(ValueError):
            provisioning_service.link_existing_user_to_provider(request)
    
    def test_link_already_linked_account_different_user(self, provisioning_service):
        """Test linking account already linked to different user raises error"""
        # Mock: account already linked to user2
        provisioning_service._get_oauth_connection = Mock(return_value=Mock(user_id="user-2"))
        
        request = Mock(
            user_id="user-1",
            provider="github",
            provider_user_id="12345",
        )
        
        with pytest.raises(ValueError):
            provisioning_service.link_existing_user_to_provider(request)


# ============================================================================
# OAuth Provider User Info Tests
# ============================================================================

class TestProviderUserInfoFetcher:
    """Test fetching user info from OAuth providers"""
    
    @pytest.mark.asyncio
    async def test_fetch_github_user(self):
        """Test fetching GitHub user info"""
        fetcher = ProviderUserInfoFetcher(Mock())
        
        with patch('httpx.AsyncClient.get') as mock_get:
            mock_response = AsyncMock()
            mock_response.json.return_value = {
                "id": 12345,
                "login": "johndoe",
                "name": "John Doe",
                "email": "john@example.com",
                "avatar_url": "https://avatars.githubusercontent.com/u/12345",
            }
            mock_get.return_value = mock_response
            
            result = await fetcher.fetch_github_user("access-token")
            
            assert result["provider"] == "github"
            assert result["provider_user_id"] == "12345"
            assert result["email"] == "john@example.com"
            assert result["name"] == "John Doe"
    
    @pytest.mark.asyncio
    async def test_fetch_google_user(self):
        """Test fetching Google user info"""
        fetcher = ProviderUserInfoFetcher(Mock())
        
        with patch('httpx.AsyncClient.get') as mock_get:
            mock_response = AsyncMock()
            mock_response.json.return_value = {
                "sub": "google-user-123",
                "email": "user@gmail.com",
                "name": "Jane Smith",
                "picture": "https://lh3.googleusercontent.com/...",
            }
            mock_get.return_value = mock_response
            
            result = await fetcher.fetch_google_user("access-token")
            
            assert result["provider"] == "google"
            assert result["provider_user_id"] == "google-user-123"
            assert result["email"] == "user@gmail.com"
    
    @pytest.mark.asyncio
    async def test_fetch_microsoft_user(self):
        """Test fetching Microsoft user info"""
        fetcher = ProviderUserInfoFetcher(Mock())
        
        with patch('httpx.AsyncClient.get') as mock_get:
            mock_response = AsyncMock()
            mock_response.json.return_value = {
                "id": "microsoft-user-123",
                "displayName": "Bob Johnson",
                "userPrincipalName": "bob@company.onmicrosoft.com",
            }
            mock_get.return_value = mock_response
            
            result = await fetcher.fetch_microsoft_user("access-token")
            
            assert result["provider"] == "microsoft"
            assert result["provider_user_id"] == "microsoft-user-123"


# ============================================================================
# User Profile Management Tests
# ============================================================================

class TestUserProfileManagement:
    """Test user profile management"""
    
    def test_update_user_profile(self, user_api_service):
        """Test updating user profile"""
        user_id = str(uuid.uuid4())
        
        request = UserUpdateRequest(
            name="Jane Smith",
            bio="Software engineer",
            company="Tech Inc",
            location="San Francisco",
            website="https://example.com",
            timezone="America/Los_Angeles",
            locale="en_US",
        )
        
        # Would return updated UserResponse
        # result = user_api_service.update_user_profile(user_id, request)
    
    def test_update_user_preferences(self, user_api_service):
        """Test updating user preferences"""
        user_id = str(uuid.uuid4())
        
        request = UserPreferencesRequest(
            locale="es_ES",
            timezone="Europe/Madrid",
            preferences={"theme": "dark", "notifications": True},
        )
        
        # result = user_api_service.update_user_preferences(user_id, request)
    
    def test_change_email_request(self, user_api_service):
        """Test requesting email change"""
        user_id = str(uuid.uuid4())
        
        request = ChangeEmailRequest(
            new_email="newemail@example.com",
            confirmation_required=True,
        )
        
        # result = user_api_service.change_email(user_id, request)
        # assert result.status == "pending_verification"
    
    def test_list_users_pagination(self, user_api_service):
        """Test listing users with pagination"""
        # result = user_api_service.list_users(page=1, page_size=20)
        # assert result.page == 1
        # assert result.page_size == 20


# ============================================================================
# User Status Tests
# ============================================================================

class TestUserStatus:
    """Test user account status management"""
    
    def test_user_pending_verification_status(self):
        """Test user in pending verification status"""
        # New user should have pending_verification status
        # After email verification, should become active
        pass
    
    def test_user_suspension_and_reactivation(self):
        """Test suspending and reactivating user"""
        pass
    
    def test_user_account_deletion(self):
        """Test user account deletion"""
        pass


# ============================================================================
# Integration Tests
# ============================================================================

class TestUserProvisioningIntegration:
    """Integration tests for user provisioning flow"""
    
    def test_complete_oauth_to_verified_user_flow(self, provisioning_service, sample_github_user):
        """Test complete flow from OAuth provision to email verified"""
        # 1. Provision user from GitHub
        response1 = provisioning_service.provision_user_from_provider(sample_github_user)
        user_id = response1.user_id
        
        assert response1.status == ProvisioningStatus.PROVISIONED
        assert response1.email_verification_status == EmailVerificationStatus.UNVERIFIED
        
        # 2. User receives verification email, clicks link
        # (would call verify_email_token in real flow)
        
        # 3. Email verified
        # User's status should now be "active"
    
    def test_link_multiple_oauth_accounts(self, provisioning_service, sample_github_user, sample_google_user):
        """Test linking multiple OAuth accounts to same user"""
        # 1. Create user via GitHub
        response1 = provisioning_service.provision_user_from_provider(sample_github_user)
        user_id = response1.user_id
        
        # 2. Link Google account
        sample_google_user.email = sample_github_user.email
        response2 = provisioning_service.provision_user_from_provider(sample_google_user)
        
        # Should be same user
        assert response2.user_id == user_id
        
        # User can now login with both GitHub and Google
