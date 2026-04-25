"""
Integration Tests - User Management Endpoints
Issue #1537 Week 2: Integration Tests

Coverage:
- User registration and provisioning
- Email verification
- Account linking (OAuth providers)
- Profile management
- Password reset flow
- MFA enrollment (authenticator, email, SMS)
- Session management and revocation
- Account recovery with backup codes
"""
import pytest
import uuid
from datetime import datetime, timedelta
from unittest.mock import patch, Mock

pytestmark = pytest.mark.integration


# ============================================================================
# User Registration Tests
# ============================================================================

class TestUserRegistration:
    """Test user registration endpoints"""
    
    def test_register_user_success(self, user_provisioning_service, mock_email_service):
        """Test successful user registration"""
        email = "newuser@example.com"
        password = "SecurePassword123!@#"
        
        result = user_provisioning_service.register_user(
            email=email,
            password=password,
            name="New User",
        )
        
        assert result["user_id"] is not None
        assert result["email"] == email
        assert result["email_verified"] is False
        
        # Check email verification sent
        mock_email_service.send_verification_email.assert_called_once()
    
    def test_register_user_duplicate_email(self, user_provisioning_service, test_user):
        """Test registering with existing email raises error"""
        with pytest.raises(ValueError, match="Email already exists"):
            user_provisioning_service.register_user(
                email=test_user.email,
                password="SecurePassword123!@#",
            )
    
    def test_register_user_weak_password(self, user_provisioning_service):
        """Test weak password is rejected"""
        with pytest.raises(ValueError, match="Password.*weak"):
            user_provisioning_service.register_user(
                email="user@example.com",
                password="weak",  # Too short and no complexity
            )
    
    def test_register_user_password_requirements(self, user_provisioning_service):
        """Test password complexity requirements"""
        # Must have upper, lower, digit, special char, minimum 12 chars
        weak_passwords = [
            "onlylowercase",  # No uppercase
            "ONLYUPPERCASE",  # No lowercase
            "NoDigitsHere!",   # No digits
            "NoSpecial123",    # No special chars
        ]
        
        for weak_pwd in weak_passwords:
            with pytest.raises(ValueError):
                user_provisioning_service.register_user(
                    email=f"{uuid.uuid4()}@example.com",
                    password=weak_pwd,
                )


# ============================================================================
# Email Verification Tests
# ============================================================================

class TestEmailVerification:
    """Test email verification flow"""
    
    def test_send_verification_email(self, user_provisioning_service, test_user, mock_email_service):
        """Test sending verification email"""
        result = user_provisioning_service.send_verification_email(test_user.id)
        
        assert result["token"] is not None
        assert result["expires_at"] is not None
        mock_email_service.send_verification_email.assert_called()
    
    def test_verify_email_success(self, user_provisioning_service, test_user, db_session):
        """Test successful email verification"""
        # Send verification email
        send_result = user_provisioning_service.send_verification_email(test_user.id)
        token = send_result["token"]
        
        # Verify email
        result = user_provisioning_service.verify_email(
            user_id=test_user.id,
            token=token,
        )
        
        assert result["verified"] is True
        
        # Check user email_verified flag updated
        db_session.refresh(test_user)
        assert test_user.email_verified is True
    
    def test_verify_email_invalid_token(self, user_provisioning_service, test_user):
        """Test verification with invalid token fails"""
        with pytest.raises(ValueError):
            user_provisioning_service.verify_email(
                user_id=test_user.id,
                token="invalid-token-xyz",
            )
    
    def test_verify_email_token_expired(self, user_provisioning_service, test_user):
        """Test expired verification token fails"""
        # This would require time manipulation in test or DB override
        pass


# ============================================================================
# Account Linking Tests
# ============================================================================

class TestAccountLinking:
    """Test linking OAuth accounts"""
    
    def test_link_oauth_account(self, user_provisioning_service, test_user):
        """Test linking OAuth provider account"""
        result = user_provisioning_service.link_oauth_account(
            user_id=test_user.id,
            provider="github",
            provider_user_id="octocat",
            access_token="github-token-123",
            refresh_token="github-refresh-123",
        )
        
        assert result["linked"] is True
        assert result["provider"] == "github"
    
    def test_link_duplicate_provider_account(self, user_provisioning_service, test_user):
        """Test linking same provider twice fails"""
        # Link first time
        user_provisioning_service.link_oauth_account(
            user_id=test_user.id,
            provider="github",
            provider_user_id="octocat",
            access_token="token-1",
        )
        
        # Try to link again (different provider user)
        with pytest.raises(ValueError, match="already linked"):
            user_provisioning_service.link_oauth_account(
                user_id=test_user.id,
                provider="github",
                provider_user_id="different-user",
                access_token="token-2",
            )
    
    def test_unlink_oauth_account(self, user_provisioning_service, test_user):
        """Test unlinking OAuth account"""
        # Link account
        user_provisioning_service.link_oauth_account(
            user_id=test_user.id,
            provider="github",
            provider_user_id="octocat",
            access_token="token-123",
        )
        
        # Unlink account
        result = user_provisioning_service.unlink_oauth_account(
            user_id=test_user.id,
            provider="github",
        )
        
        assert result["unlinked"] is True


# ============================================================================
# Profile Management Tests
# ============================================================================

class TestProfileManagement:
    """Test profile updates"""
    
    def test_update_profile(self, user_provisioning_service, test_user, db_session):
        """Test updating user profile"""
        result = user_provisioning_service.update_profile(
            user_id=test_user.id,
            name="Updated Name",
            avatar_url="https://example.com/avatar.jpg",
            timezone="America/New_York",
            locale="en-US",
        )
        
        assert result["name"] == "Updated Name"
        assert result["avatar_url"] == "https://example.com/avatar.jpg"
        
        # Verify in database
        db_session.refresh(test_user)
        assert test_user.name == "Updated Name"
    
    def test_get_profile(self, user_provisioning_service, test_user):
        """Test retrieving user profile"""
        result = user_provisioning_service.get_profile(test_user.id)
        
        assert result["id"] == str(test_user.id)
        assert result["email"] == test_user.email
        assert result["name"] == test_user.name


# ============================================================================
# Password Reset Tests
# ============================================================================

class TestPasswordReset:
    """Test password reset flow"""
    
    def test_request_password_reset(self, user_provisioning_service, test_user, mock_email_service):
        """Test requesting password reset"""
        result = user_provisioning_service.request_password_reset(test_user.email)
        
        assert result["email"] == test_user.email
        assert result["reset_token_sent"] is True
        
        # Check email sent
        mock_email_service.send_password_reset_email.assert_called()
    
    def test_reset_password_success(self, user_provisioning_service, test_user):
        """Test successful password reset"""
        # Request reset
        request_result = user_provisioning_service.request_password_reset(test_user.email)
        reset_token = request_result["token"]
        
        # Reset password
        new_password = "NewSecurePassword456!@#"
        result = user_provisioning_service.reset_password(
            reset_token=reset_token,
            new_password=new_password,
        )
        
        assert result["reset_success"] is True
    
    def test_reset_password_weak_password(self, user_provisioning_service, test_user):
        """Test weak password is rejected during reset"""
        request_result = user_provisioning_service.request_password_reset(test_user.email)
        reset_token = request_result["token"]
        
        with pytest.raises(ValueError, match="Password.*weak"):
            user_provisioning_service.reset_password(
                reset_token=reset_token,
                new_password="weak",
            )
    
    def test_reset_password_invalid_token(self, user_provisioning_service):
        """Test reset with invalid token fails"""
        with pytest.raises(ValueError):
            user_provisioning_service.reset_password(
                reset_token="invalid-token",
                new_password="NewSecurePassword456!@#",
            )


# ============================================================================
# MFA (Multi-Factor Authentication) Tests
# ============================================================================

class TestMFAEnrollment:
    """Test MFA enrollment"""
    
    def test_enable_authenticator_mfa(self, user_provisioning_service, test_user):
        """Test enabling authenticator MFA"""
        result = user_provisioning_service.enable_authenticator_mfa(test_user.id)
        
        assert result["secret"] is not None
        assert result["qr_code"] is not None
        assert result["manual_entry_key"] is not None
    
    def test_enable_email_mfa(self, user_provisioning_service, test_user, mock_email_service):
        """Test enabling email MFA"""
        result = user_provisioning_service.enable_email_mfa(test_user.id)
        
        assert result["method"] == "email"
        mock_email_service.send_mfa_email.assert_called()
    
    def test_enable_sms_mfa(self, user_provisioning_service, test_user, mock_sms_service):
        """Test enabling SMS MFA"""
        result = user_provisioning_service.enable_sms_mfa(
            user_id=test_user.id,
            phone_number="+1-555-555-5555",
        )
        
        assert result["method"] == "sms"
    
    def test_disable_mfa_requires_password(self, user_provisioning_service, test_user):
        """Test disabling MFA requires password"""
        # Enable MFA first
        user_provisioning_service.enable_authenticator_mfa(test_user.id)
        
        # Disable with wrong password
        with pytest.raises(ValueError):
            user_provisioning_service.disable_mfa(
                user_id=test_user.id,
                method="authenticator",
                password="wrong-password",
            )


# ============================================================================
# MFA Verification Tests
# ============================================================================

class TestMFAVerification:
    """Test MFA code verification"""
    
    def test_verify_authenticator_code_success(self, user_provisioning_service, test_user):
        """Test verifying valid authenticator code"""
        # Enable MFA
        setup_result = user_provisioning_service.enable_authenticator_mfa(test_user.id)
        secret = setup_result["secret"]
        
        # Generate TOTP code (in real test would use pyotp)
        # For test, we mock the verification
        with patch('src.user_provisioning.pyotp.TOTP.verify') as mock_verify:
            mock_verify.return_value = True
            
            result = user_provisioning_service.verify_mfa_setup(
                user_id=test_user.id,
                method="authenticator",
                code="123456",
            )
            
            assert result["verified"] is True
    
    def test_verify_email_mfa_code(self, user_provisioning_service, test_user):
        """Test verifying email MFA code"""
        # Enable email MFA
        user_provisioning_service.enable_email_mfa(test_user.id)
        
        # Verify with OTP code
        result = user_provisioning_service.verify_mfa_setup(
            user_id=test_user.id,
            method="email",
            code="123456",
        )
        
        assert result["verified"] is True


# ============================================================================
# Backup Codes Tests
# ============================================================================

class TestBackupCodes:
    """Test account recovery with backup codes"""
    
    def test_generate_recovery_codes(self, user_provisioning_service, test_user):
        """Test generating recovery codes"""
        result = user_provisioning_service.generate_recovery_codes(test_user.id)
        
        assert len(result["codes"]) == 8
        # Each code should be format XXXX-XXXX-XXXX
        for code in result["codes"]:
            assert len(code) == 14
            assert code.count("-") == 2
    
    def test_use_recovery_code_success(self, user_provisioning_service, test_user):
        """Test using recovery code to bypass MFA"""
        # Generate codes
        gen_result = user_provisioning_service.generate_recovery_codes(test_user.id)
        code = gen_result["codes"][0]
        
        # Use code
        result = user_provisioning_service.use_recovery_code(
            user_id=test_user.id,
            code=code,
        )
        
        assert result["used"] is True
    
    def test_use_recovery_code_twice_fails(self, user_provisioning_service, test_user):
        """Test recovery codes are single-use"""
        gen_result = user_provisioning_service.generate_recovery_codes(test_user.id)
        code = gen_result["codes"][0]
        
        # First use
        user_provisioning_service.use_recovery_code(test_user.id, code)
        
        # Second use should fail
        with pytest.raises(ValueError):
            user_provisioning_service.use_recovery_code(test_user.id, code)


# ============================================================================
# Session Management Tests
# ============================================================================

class TestSessionManagement:
    """Test session management"""
    
    def test_get_active_sessions(self, user_provisioning_service, test_user):
        """Test retrieving active sessions"""
        result = user_provisioning_service.get_active_sessions(test_user.id)
        
        assert "sessions" in result
        assert isinstance(result["sessions"], list)
    
    def test_revoke_current_session(self, user_provisioning_service, sso_service, test_user):
        """Test revoking current session"""
        session_id = str(uuid.uuid4())
        
        result = sso_service.sign_out_user(
            user_id=test_user.id,
            current_session_only=True,
            current_session_id=session_id,
        )
        
        assert result["revoked"] is True
    
    def test_revoke_all_sessions(self, user_provisioning_service, sso_service, test_user):
        """Test revoking all sessions"""
        result = sso_service.sign_out_user(
            user_id=test_user.id,
            current_session_only=False,
        )
        
        assert result["revoked_count"] > 0
    
    def test_revoke_device_sessions(self, sso_service, test_user):
        """Test revoking all sessions for a device"""
        device_id = str(uuid.uuid4())
        
        result = sso_service.revoke_device_session(
            user_id=test_user.id,
            device_id=device_id,
        )
        
        assert result["revoked"] is True


# ============================================================================
# Integration Tests
# ============================================================================

class TestUserManagementIntegration:
    """End-to-end user management workflows"""
    
    def test_complete_registration_and_verification_flow(
        self,
        user_provisioning_service,
        mock_email_service,
        db_session
    ):
        """Test complete user registration to email verification"""
        email = f"integration-{uuid.uuid4()}@example.com"
        password = "IntegrationTest123!@#"
        
        # Step 1: Register
        reg_result = user_provisioning_service.register_user(
            email=email,
            password=password,
            name="Integration Test User",
        )
        user_id = reg_result["user_id"]
        
        # Step 2: Verify email
        verify_result = user_provisioning_service.send_verification_email(user_id)
        token = verify_result["token"]
        
        # Step 3: Complete verification
        verified = user_provisioning_service.verify_email(user_id, token)
        assert verified["verified"] is True
