"""
Unit Tests - Advanced Authentication Features
Issue #1345 Week 4: Advanced Features Testing
"""
import pytest
from datetime import datetime, timedelta
from unittest.mock import Mock, patch
import uuid

from src.session_service import SingleSignOutService, SessionManagementService
from src.recovery_service import AccountRecoveryService, RecoveryCodeService
from src.mfa_service import TwoFactorAuthService, MFAMethod


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def mock_db():
    """Mock database session"""
    return Mock()


@pytest.fixture
def mock_redis():
    """Mock Redis client"""
    return Mock()


@pytest.fixture
def mock_config():
    """Mock configuration"""
    config = Mock()
    config.JWT_ISSUER = "https://auth.kushnir.cloud"
    return config


@pytest.fixture
def mock_email_service():
    """Mock email service"""
    return Mock()


@pytest.fixture
def mock_sms_service():
    """Mock SMS service"""
    return Mock()


@pytest.fixture
def sso_service(mock_db, mock_redis, mock_config):
    """Single Sign-Out service"""
    return SingleSignOutService(mock_db, mock_redis, mock_config)


@pytest.fixture
def session_service(mock_db, mock_config):
    """Session management service"""
    return SessionManagementService(mock_db, mock_config)


@pytest.fixture
def recovery_service(mock_db, mock_config, mock_email_service):
    """Account recovery service"""
    return AccountRecoveryService(mock_db, mock_config, mock_email_service)


@pytest.fixture
def mfa_service(mock_db, mock_config, mock_email_service, mock_sms_service):
    """MFA service"""
    return TwoFactorAuthService(mock_db, mock_config, mock_email_service, mock_sms_service)


@pytest.fixture
def sample_user_id():
    """Sample user ID"""
    return str(uuid.uuid4())


@pytest.fixture
def sample_session_id():
    """Sample session ID"""
    return str(uuid.uuid4())


# ============================================================================
# Single Sign-Out Tests
# ============================================================================

class TestSingleSignOut:
    """Test single sign-out functionality"""
    
    def test_sign_out_current_session(self, sso_service, sample_user_id):
        """Test signing out current session"""
        mock_token = Mock(id=str(uuid.uuid4()))
        sso_service._get_user_refresh_tokens = Mock(return_value=[mock_token])
        sso_service._revoke_token = Mock()
        
        result = sso_service.sign_out_user(sample_user_id, revoke_all_sessions=False)
        
        assert result["status"] == "signed_out"
        assert result["revoked_sessions"] == 1
        sso_service._revoke_token.assert_called_once()
    
    def test_sign_out_all_sessions(self, sso_service, sample_user_id):
        """Test signing out all sessions"""
        mock_tokens = [
            Mock(id=str(uuid.uuid4())),
            Mock(id=str(uuid.uuid4())),
            Mock(id=str(uuid.uuid4())),
        ]
        sso_service._get_user_refresh_tokens = Mock(return_value=mock_tokens)
        sso_service._revoke_token = Mock()
        
        result = sso_service.sign_out_user(sample_user_id, revoke_all_sessions=True)
        
        assert result["status"] == "signed_out"
        assert result["revoked_sessions"] == 3
        assert sso_service._revoke_token.call_count == 3
    
    def test_revoke_device_session(self, sso_service, sample_user_id):
        """Test revoking sessions for specific device"""
        device_id = "device-12345"
        mock_sessions = [
            Mock(token_id=str(uuid.uuid4())),
            Mock(token_id=str(uuid.uuid4())),
        ]
        sso_service._get_device_sessions = Mock(return_value=mock_sessions)
        sso_service._revoke_token = Mock()
        
        result = sso_service.revoke_device_session(sample_user_id, device_id)
        
        assert result["status"] == "revoked"
        assert result["revoked_sessions"] == 2
    
    def test_get_active_sessions(self, sso_service, sample_user_id):
        """Test getting active sessions"""
        mock_sessions = [
            Mock(
                id=str(uuid.uuid4()),
                device_id="device-1",
                device_name="Chrome on MacOS",
                ip_address="192.168.1.1",
                user_agent="Mozilla/5.0...",
                last_activity=datetime.utcnow(),
                created_at=datetime.utcnow(),
            ),
        ]
        sso_service._get_user_sessions = Mock(return_value=mock_sessions)
        
        result = sso_service.get_active_sessions(sample_user_id)
        
        assert len(result) == 1
        assert result[0]["device_name"] == "Chrome on MacOS"


# ============================================================================
# Session Management Tests
# ============================================================================

class TestSessionManagement:
    """Test session management"""
    
    def test_create_session(self, session_service, sample_user_id):
        """Test creating session"""
        session_service._create_user_session = Mock(
            return_value=Mock(id=str(uuid.uuid4()))
        )
        
        result = session_service.create_session(
            user_id=sample_user_id,
            device_id="device-123",
            device_name="Chrome on MacOS",
            ip_address="192.168.1.1",
            user_agent="Mozilla/5.0",
            refresh_token="token123",
        )
        
        assert result["status"] == "created"
    
    def test_update_session_activity(self, session_service):
        """Test updating session activity"""
        session_id = str(uuid.uuid4())
        session_service._update_session_activity = Mock()
        
        session_service.update_session_activity(session_id)
        
        session_service._update_session_activity.assert_called_once_with(session_id)


# ============================================================================
# Password Reset Tests
# ============================================================================

class TestPasswordReset:
    """Test password reset workflow"""
    
    def test_request_password_reset_user_exists(self, recovery_service):
        """Test requesting password reset for existing user"""
        mock_user = Mock(id=str(uuid.uuid4()), email="user@example.com", name="Test User")
        recovery_service._get_user_by_email = Mock(return_value=mock_user)
        recovery_service._create_password_reset = Mock(
            return_value=Mock(expires_at=datetime.utcnow() + timedelta(hours=1))
        )
        recovery_service._send_password_reset_email = Mock()
        
        result = recovery_service.request_password_reset("user@example.com")
        
        assert result["status"] == "reset_requested"
        recovery_service._send_password_reset_email.assert_called_once()
    
    def test_request_password_reset_non_existent_user(self, recovery_service):
        """Test requesting password reset for non-existent user (don't leak info)"""
        recovery_service._get_user_by_email = Mock(return_value=None)
        
        result = recovery_service.request_password_reset("nonexistent@example.com")
        
        # Should return same message for security
        assert "If account exists" in result["message"]
    
    def test_verify_reset_token_valid(self, recovery_service):
        """Test verifying valid reset token"""
        recovery_service._get_password_reset_by_token = Mock(
            return_value=Mock(
                expires_at=datetime.utcnow() + timedelta(hours=1),
                used_at=None,
            )
        )
        
        result = recovery_service.verify_reset_token("valid-token")
        
        assert result["valid"] is True
    
    def test_verify_reset_token_expired(self, recovery_service):
        """Test verifying expired reset token"""
        recovery_service._get_password_reset_by_token = Mock(
            return_value=Mock(
                expires_at=datetime.utcnow() - timedelta(hours=1),  # Expired
                used_at=None,
            )
        )
        
        result = recovery_service.verify_reset_token("expired-token")
        
        assert result["valid"] is False
        assert "expired" in result["reason"].lower()
    
    def test_reset_password_validates_strength(self, recovery_service):
        """Test password reset validates password strength"""
        recovery_service._get_password_reset_by_token = Mock(
            return_value=Mock(
                user_id=str(uuid.uuid4()),
                expires_at=datetime.utcnow() + timedelta(hours=1),
                used_at=None,
                id=str(uuid.uuid4()),
            )
        )
        recovery_service._get_user = Mock(return_value=Mock(id=str(uuid.uuid4())))
        
        # Test weak password
        with pytest.raises(ValueError):
            recovery_service.reset_password("token", "weak")  # Too short


# ============================================================================
# Recovery Code Tests
# ============================================================================

class TestRecoveryCodes:
    """Test recovery code generation and usage"""
    
    def test_generate_recovery_codes(self, recovery_service=None):
        """Test generating recovery codes"""
        # Create service without email dependency for this test
        mock_db = Mock()
        mock_config = Mock()
        service = RecoveryCodeService(mock_db, mock_config)
        
        service._store_recovery_codes = Mock()
        
        result = service.generate_recovery_codes(str(uuid.uuid4()), count=8)
        
        assert result["status"] == "generated"
        assert len(result["codes"]) == 8
        # Each code should be in format XXXX-XXXX-XXXX
        for code in result["codes"]:
            assert len(code) == 14  # 4 + 1 + 4 + 1 + 4
            assert code.count("-") == 2
    
    def test_use_recovery_code_success(self):
        """Test using valid recovery code"""
        mock_db = Mock()
        mock_config = Mock()
        service = RecoveryCodeService(mock_db, mock_config)
        
        user_id = str(uuid.uuid4())
        code = "1A2B-3C4D-5E6F"
        
        service._get_recovery_code = Mock(return_value=Mock(id=str(uuid.uuid4())))
        service._mark_code_used = Mock()
        
        result = service.use_recovery_code(user_id, code)
        
        assert result["status"] == "verified"
        service._mark_code_used.assert_called_once()


# ============================================================================
# MFA Tests
# ============================================================================

class TestTwoFactorAuth:
    """Test Two-Factor Authentication"""
    
    def test_enable_authenticator_mfa(self, mfa_service, sample_user_id):
        """Test enabling authenticator MFA"""
        mock_user = Mock(id=sample_user_id, email="user@example.com")
        mfa_service._get_user = Mock(return_value=mock_user)
        mfa_service._get_user_mfa = Mock(return_value=None)
        mfa_service._create_pending_mfa = Mock()
        
        result = mfa_service._enable_authenticator_mfa(sample_user_id)
        
        assert result["status"] == "pending_verification"
        assert "secret" in result
        assert "qr_code" in result
    
    def test_enable_email_mfa(self, mfa_service, sample_user_id):
        """Test enabling email MFA"""
        mock_user = Mock(id=sample_user_id, email="user@example.com")
        mfa_service._get_user = Mock(return_value=mock_user)
        mfa_service._get_user_mfa = Mock(return_value=None)
        mfa_service._create_pending_mfa = Mock()
        mfa_service._send_mfa_email = Mock()
        
        result = mfa_service._enable_email_mfa(sample_user_id)
        
        assert result["status"] == "verification_sent"
        assert result["method"] == "email"
        mfa_service._send_mfa_email.assert_called_once()
    
    def test_enable_sms_mfa_requires_phone(self, mfa_service, sample_user_id):
        """Test enabling SMS MFA requires phone number"""
        with pytest.raises(ValueError):
            mfa_service.enable_mfa(sample_user_id, MFAMethod.SMS, phone_number=None)
    
    def test_disable_mfa_requires_password(self, mfa_service, sample_user_id):
        """Test disabling MFA requires password verification"""
        mfa_service._verify_user_password = Mock(return_value=False)
        mfa_service._get_user_mfa = Mock(return_value=Mock())
        
        with pytest.raises(ValueError):
            mfa_service.disable_mfa(sample_user_id, MFAMethod.EMAIL, "wrong-password")
    
    def test_list_enabled_mfa(self, mfa_service, sample_user_id):
        """Test listing enabled MFA methods"""
        now = datetime.utcnow()
        mock_mfa_methods = [
            Mock(method="email", created_at=now, last_used=now),
            Mock(method="authenticator", created_at=now, last_used=None),
        ]
        mfa_service._get_user_enabled_mfa = Mock(return_value=mock_mfa_methods)
        
        result = mfa_service.list_enabled_mfa(sample_user_id)
        
        assert len(result) == 2
        assert result[0]["method"] == "email"


# ============================================================================
# Integration Tests
# ============================================================================

class TestAdvancedAuthIntegration:
    """Integration tests for advanced features"""
    
    def test_complete_password_reset_flow(self, recovery_service):
        """Test complete password reset workflow"""
        user_id = str(uuid.uuid4())
        email = "user@example.com"
        
        # 1. Request reset
        mock_user = Mock(id=user_id, email=email, name="Test User")
        recovery_service._get_user_by_email = Mock(return_value=mock_user)
        recovery_service._create_password_reset = Mock(
            return_value=Mock(expires_at=datetime.utcnow() + timedelta(hours=1))
        )
        recovery_service._send_password_reset_email = Mock()
        
        result = recovery_service.request_password_reset(email)
        assert result["status"] == "reset_requested"
        
        # 2. Verify token (in real flow)
        recovery_service._get_password_reset_by_token = Mock(
            return_value=Mock(
                user_id=user_id,
                expires_at=datetime.utcnow() + timedelta(hours=1),
                used_at=None,
                id=str(uuid.uuid4()),
            )
        )
        recovery_service._get_user = Mock(return_value=mock_user)
        recovery_service._update_user_password = Mock()
        recovery_service._mark_reset_used = Mock()
        recovery_service._invalidate_all_user_tokens = Mock()
        
        # 3. Complete reset with strong password
        result = recovery_service.reset_password(
            "valid-token",
            "SecurePass123!@#"
        )
        assert result["status"] == "password_reset"
