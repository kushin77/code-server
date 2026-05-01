"""
Account Recovery Service - Password Reset, Email Changes
Issue #1345 Week 4: Advanced Authentication Features
"""
import uuid
import secrets
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from log import get_logger

from sqlalchemy.orm import Session

logger = get_logger(__name__)


# ============================================================================
# Account Recovery Service
# ============================================================================

class AccountRecoveryService:
    """Service for password reset and account recovery flows"""
    
    def __init__(self, db_session: Session, config, email_service):
        self.db = db_session
        self.config = config
        self.email_service = email_service
    
    def request_password_reset(self, email: str) -> Dict[str, Any]:
        """Initiate password reset flow"""
        
        try:
            # Get user by email
            user = self._get_user_by_email(email)
            if not user:
                # Don't reveal whether email exists
                logger.info(f"Password reset requested for non-existent email: {email}")
                return {
                    "status": "reset_requested",
                    "message": "If account exists, reset email will be sent",
                }
            
            # Generate reset token
            reset_token = secrets.token_urlsafe(32)
            expires_at = datetime.utcnow() + timedelta(hours=1)  # 1-hour expiry
            
            # Store reset request
            reset_request = self._create_password_reset(
                user_id=str(user.id),
                token=reset_token,
                expires_at=expires_at,
            )
            
            # Send reset email
            reset_url = f"{self.config.JWT_ISSUER}/auth/reset-password?token={reset_token}"
            self._send_password_reset_email(
                email=email,
                reset_url=reset_url,
                user_name=user.name,
            )
            
            logger.info(f"Password reset requested for user {user.id}")
            
            return {
                "status": "reset_requested",
                "message": "If account exists, reset email will be sent",
            }
        
        except Exception as e:
            logger.error(f"Failed to request password reset: {str(e)}")
            raise
    
    def reset_password(
        self,
        reset_token: str,
        new_password: str,
    ) -> Dict[str, Any]:
        """Complete password reset"""
        
        try:
            # Get reset request
            reset_request = self._get_password_reset_by_token(reset_token)
            if not reset_request:
                raise ValueError("Invalid or expired reset token")
            
            # Check expiry
            if reset_request.expires_at < datetime.utcnow():
                raise ValueError("Reset token has expired")
            
            # Check already used
            if reset_request.used_at:
                raise ValueError("Reset token has already been used")
            
            # Validate password strength
            self._validate_password_strength(new_password)
            
            # Update password
            user = self._get_user(str(reset_request.user_id))
            user_id = str(user.id)
            
            self._update_user_password(user_id, new_password)
            
            # Mark reset as used
            self._mark_reset_used(reset_request.id)
            
            # Invalidate all sessions (security: force re-login)
            self._invalidate_all_user_tokens(user_id)
            
            logger.info(f"Password reset completed for user {user_id}")
            
            return {
                "status": "password_reset",
                "message": "Password has been reset. Please log in with your new password.",
            }
        
        except Exception as e:
            logger.error(f"Failed to reset password: {str(e)}")
            raise
    
    def verify_reset_token(self, reset_token: str) -> Dict[str, Any]:
        """Verify reset token is valid"""
        
        reset_request = self._get_password_reset_by_token(reset_token)
        if not reset_request:
            return {"valid": False, "reason": "Token not found"}
        
        if reset_request.expires_at < datetime.utcnow():
            return {"valid": False, "reason": "Token expired"}
        
        if reset_request.used_at:
            return {"valid": False, "reason": "Token already used"}
        
        return {"valid": True}
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _get_user_by_email(self, email: str) -> Optional[Any]:
        """Get user by email"""
        # In production: query User where email=?
        return None
    
    def _get_user(self, user_id: str) -> Optional[Any]:
        """Get user by ID"""
        # In production: query User where id=?
        return None
    
    def _create_password_reset(
        self,
        user_id: str,
        token: str,
        expires_at: datetime,
    ) -> Any:
        """Create password reset request"""
        return type('PasswordResetRequest', (), {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "token": token,
            "expires_at": expires_at,
            "used_at": None,
        })()
    
    def _get_password_reset_by_token(self, token: str) -> Optional[Any]:
        """Get password reset by token"""
        # In production: query PasswordResetRequest where token=?
        return None
    
    def _mark_reset_used(self, reset_id: str) -> None:
        """Mark reset as used"""
        # In production: update PasswordResetRequest set used_at=now() where id=?
        pass
    
    def _update_user_password(self, user_id: str, new_password: str) -> None:
        """Update user password (hash it)"""
        # In production: hash password using bcrypt/argon2, update User set password_hash=?
        pass
    
    def _invalidate_all_user_tokens(self, user_id: str) -> None:
        """Invalidate all tokens for user"""
        # In production: increment token_version or delete all refresh tokens
        pass
    
    def _validate_password_strength(self, password: str) -> None:
        """Validate password meets requirements"""
        if len(password) < 12:
            raise ValueError("Password must be at least 12 characters")
        if not any(c.isupper() for c in password):
            raise ValueError("Password must contain uppercase letter")
        if not any(c.islower() for c in password):
            raise ValueError("Password must contain lowercase letter")
        if not any(c.isdigit() for c in password):
            raise ValueError("Password must contain digit")
        if not any(c in "!@#$%^&*" for c in password):
            raise ValueError("Password must contain special character")
    
    def _send_password_reset_email(
        self,
        email: str,
        reset_url: str,
        user_name: str,
    ) -> None:
        """Send password reset email"""
        logger.info(f"Sending password reset email to {email}")
        # In production: use email service (SendGrid, etc.)


# ============================================================================
# Recovery Code Service
# ============================================================================

class RecoveryCodeService:
    """Service for MFA recovery codes"""
    
    def __init__(self, db_session: Session, config):
        self.db = db_session
        self.config = config
    
    def generate_recovery_codes(self, user_id: str, count: int = 8) -> Dict[str, Any]:
        """Generate backup recovery codes for MFA"""
        
        try:
            codes = []
            for _ in range(count):
                # Generate code like: XXXX-XXXX-XXXX (format: 4 chars - 4 chars - 4 chars)
                code = f"{secrets.token_hex(2).upper()}-{secrets.token_hex(2).upper()}-{secrets.token_hex(2).upper()}"
                codes.append(code)
            
            # Store codes (hashed)
            self._store_recovery_codes(user_id, codes)
            
            logger.info(f"Generated {count} recovery codes for user {user_id}")
            
            return {
                "status": "generated",
                "codes": codes,  # Only return once! User must save
                "message": "Save these codes in a secure location. Each code can be used once.",
            }
        
        except Exception as e:
            logger.error(f"Failed to generate recovery codes: {str(e)}")
            raise
    
    def use_recovery_code(self, user_id: str, code: str) -> Dict[str, Any]:
        """Use a recovery code to bypass MFA"""
        
        try:
            # Find and verify code
            recovery_code = self._get_recovery_code(user_id, code)
            if not recovery_code:
                raise ValueError("Invalid or already used recovery code")
            
            # Mark as used
            self._mark_code_used(recovery_code.id)
            
            logger.info(f"Recovery code used by user {user_id}")
            
            return {
                "status": "verified",
                "message": "MFA bypassed with recovery code",
            }
        
        except Exception as e:
            logger.error(f"Failed to use recovery code: {str(e)}")
            raise
    
    def list_recovery_codes(self, user_id: str) -> Dict[str, Any]:
        """List recovery codes status"""
        
        codes = self._get_user_recovery_codes(user_id)
        
        return {
            "total": len(codes),
            "used": len([c for c in codes if c.used_at]),
            "remaining": len([c for c in codes if not c.used_at]),
        }
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _store_recovery_codes(self, user_id: str, codes: List[str]) -> None:
        """Store recovery codes (hashed)"""
        # In production: hash codes and store in RecoveryCode table
        pass
    
    def _get_recovery_code(self, user_id: str, code: str) -> Optional[Any]:
        """Get recovery code"""
        # In production: query RecoveryCode where user_id=? and code_hash=hash(code) and used_at IS NULL
        return None
    
    def _get_user_recovery_codes(self, user_id: str) -> List[Any]:
        """Get all recovery codes for user"""
        # In production: query RecoveryCode where user_id=?
        return []
    
    def _mark_code_used(self, code_id: str) -> None:
        """Mark recovery code as used"""
        # In production: update RecoveryCode set used_at=now() where id=?
        pass
