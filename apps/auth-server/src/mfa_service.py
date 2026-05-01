"""
Two-Factor Authentication (2FA) Service
Issue #1345 Week 4: Advanced Authentication Features
"""
import uuid
import secrets
import qrcode
import io
import base64
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from enum import Enum
from log import get_logger
import pyotp

from sqlalchemy.orm import Session

logger = get_logger(__name__)


# ============================================================================
# Enums
# ============================================================================

class MFAMethod(str, Enum):
    """MFA method types"""
    EMAIL = "email"                    # One-time code via email
    SMS = "sms"                        # One-time code via SMS
    AUTHENTICATOR = "authenticator"    # TOTP via authenticator app (Google Authenticator, Authy)
    BACKUP_CODE = "backup_code"        # Recovery codes


# ============================================================================
# Two-Factor Authentication Service
# ============================================================================

class TwoFactorAuthService:
    """Service for Two-Factor Authentication"""
    
    def __init__(self, db_session: Session, config, email_service, sms_service=None):
        self.db = db_session
        self.config = config
        self.email_service = email_service
        self.sms_service = sms_service
    
    def enable_mfa(
        self,
        user_id: str,
        method: MFAMethod,
        phone_number: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Enable MFA for user"""
        
        try:
            # Check if already enabled
            existing_mfa = self._get_user_mfa(user_id, method)
            if existing_mfa and existing_mfa.verified:
                return {"status": "already_enabled", "method": method}
            
            if method == MFAMethod.AUTHENTICATOR:
                return self._enable_authenticator_mfa(user_id)
            elif method == MFAMethod.EMAIL:
                return self._enable_email_mfa(user_id)
            elif method == MFAMethod.SMS:
                if not phone_number:
                    raise ValueError("Phone number required for SMS MFA")
                return self._enable_sms_mfa(user_id, phone_number)
            else:
                raise ValueError(f"Unknown MFA method: {method}")
        
        except Exception as e:
            logger.error(f"Failed to enable MFA: {str(e)}")
            raise
    
    def _enable_authenticator_mfa(self, user_id: str) -> Dict[str, Any]:
        """Set up authenticator app MFA"""
        
        # Generate secret key
        secret = pyotp.random_base32()
        user = self._get_user(user_id)
        
        # Generate QR code
        provisioning_uri = pyotp.TOTP(secret).provisioning_uri(
            name=user.email,
            issuer_name="Kushnir Cloud",
        )
        
        # Generate QR code image
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(provisioning_uri)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        img_io = io.BytesIO()
        img.save(img_io, "PNG")
        qr_code_base64 = base64.b64encode(img_io.getvalue()).decode()
        
        # Store pending MFA (unverified)
        mfa = self._create_pending_mfa(
            user_id=user_id,
            method=MFAMethod.AUTHENTICATOR,
            secret=secret,
        )
        
        logger.info(f"Initiating authenticator MFA for user {user_id}")
        
        return {
            "status": "pending_verification",
            "method": "authenticator",
            "secret": secret,
            "qr_code": f"data:image/png;base64,{qr_code_base64}",
            "manual_entry_key": secret,  # For manual entry if QR fails
        }
    
    def _enable_email_mfa(self, user_id: str) -> Dict[str, Any]:
        """Set up email MFA"""
        
        user = self._get_user(user_id)
        
        # Create pending MFA
        mfa = self._create_pending_mfa(
            user_id=user_id,
            method=MFAMethod.EMAIL,
            secret=None,  # No secret needed for email
        )
        
        # Send verification code
        verification_code = secrets.randbelow(999999)
        self._send_mfa_email(
            email=user.email,
            code=str(verification_code).zfill(6),
        )
        
        logger.info(f"Initiating email MFA for user {user_id}")
        
        return {
            "status": "verification_sent",
            "method": "email",
            "email": user.email,
            "message": "Verification code sent to your email",
        }
    
    def _enable_sms_mfa(self, user_id: str, phone_number: str) -> Dict[str, Any]:
        """Set up SMS MFA"""
        
        if not self.sms_service:
            raise ValueError("SMS service not configured")
        
        # Validate phone format
        self._validate_phone_number(phone_number)
        
        # Create pending MFA
        mfa = self._create_pending_mfa(
            user_id=user_id,
            method=MFAMethod.SMS,
            secret=phone_number,
        )
        
        # Send verification code
        verification_code = secrets.randbelow(999999)
        self.sms_service.send_sms(
            phone=phone_number,
            message=f"Your Kushnir Cloud verification code is: {str(verification_code).zfill(6)}",
        )
        
        logger.info(f"Initiating SMS MFA for user {user_id}")
        
        return {
            "status": "verification_sent",
            "method": "sms",
            "phone": phone_number,
            "message": "Verification code sent to your phone",
        }
    
    def verify_mfa_setup(
        self,
        user_id: str,
        method: MFAMethod,
        verification_code: str,
    ) -> Dict[str, Any]:
        """Verify MFA setup with code"""
        
        try:
            # Get pending MFA
            mfa = self._get_pending_mfa(user_id, method)
            if not mfa:
                raise ValueError(f"No pending {method} MFA setup found")
            
            # Verify code
            if method == MFAMethod.AUTHENTICATOR:
                totp = pyotp.TOTP(mfa.secret)
                if not totp.verify(verification_code):
                    raise ValueError("Invalid authenticator code")
            elif method in [MFAMethod.EMAIL, MFAMethod.SMS]:
                # In production: compare with stored code
                pass
            
            # Mark as verified
            self._mark_mfa_verified(mfa.id)
            
            logger.info(f"Verified {method} MFA for user {user_id}")
            
            return {
                "status": "mfa_enabled",
                "method": method,
                "message": "MFA has been successfully enabled",
            }
        
        except Exception as e:
            logger.error(f"Failed to verify MFA setup: {str(e)}")
            raise
    
    def verify_mfa_code(
        self,
        user_id: str,
        code: str,
    ) -> Dict[str, Any]:
        """Verify MFA code during login"""
        
        try:
            # Get active MFA method
            mfa = self._get_active_mfa(user_id)
            if not mfa:
                return {"verified": False, "reason": "No MFA enabled"}
            
            # Verify code based on method
            if mfa.method == MFAMethod.AUTHENTICATOR:
                totp = pyotp.TOTP(mfa.secret)
                if not totp.verify(code):
                    return {"verified": False, "reason": "Invalid code"}
            elif mfa.method in [MFAMethod.EMAIL, MFAMethod.SMS]:
                # In production: compare with stored code
                pass
            
            logger.info(f"MFA verified for user {user_id}")
            
            return {"verified": True, "method": mfa.method}
        
        except Exception as e:
            logger.error(f"Failed to verify MFA code: {str(e)}")
            raise
    
    def disable_mfa(
        self,
        user_id: str,
        method: MFAMethod,
        password: str,
    ) -> Dict[str, Any]:
        """Disable MFA (requires password confirmation)"""
        
        try:
            # Verify password
            if not self._verify_user_password(user_id, password):
                raise ValueError("Incorrect password")
            
            # Get MFA
            mfa = self._get_user_mfa(user_id, method)
            if not mfa:
                return {"status": "not_enabled"}
            
            # Disable MFA
            self._delete_mfa(mfa.id)
            
            logger.info(f"Disabled {method} MFA for user {user_id}")
            
            return {
                "status": "mfa_disabled",
                "method": method,
            }
        
        except Exception as e:
            logger.error(f"Failed to disable MFA: {str(e)}")
            raise
    
    def list_enabled_mfa(self, user_id: str) -> List[Dict[str, Any]]:
        """List all enabled MFA methods"""
        
        mfa_methods = self._get_user_enabled_mfa(user_id)
        
        return [
            {
                "method": mfa.method,
                "enabled_at": mfa.created_at.isoformat(),
                "last_used": mfa.last_used.isoformat() if mfa.last_used else None,
            }
            for mfa in mfa_methods
        ]
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _get_user(self, user_id: str) -> Optional[Any]:
        """Get user by ID"""
        # In production: query User where id=?
        return None
    
    def _get_user_mfa(self, user_id: str, method: MFAMethod) -> Optional[Any]:
        """Get MFA for user and method"""
        # In production: query MFA where user_id=? and method=?
        return None
    
    def _get_pending_mfa(self, user_id: str, method: MFAMethod) -> Optional[Any]:
        """Get pending MFA"""
        # In production: query MFA where user_id=? and method=? and verified_at IS NULL
        return None
    
    def _get_active_mfa(self, user_id: str) -> Optional[Any]:
        """Get active MFA for user"""
        # In production: query MFA where user_id=? and verified_at IS NOT NULL LIMIT 1
        return None
    
    def _get_user_enabled_mfa(self, user_id: str) -> List[Any]:
        """Get all enabled MFA methods"""
        # In production: query MFA where user_id=? and verified_at IS NOT NULL
        return []
    
    def _create_pending_mfa(
        self,
        user_id: str,
        method: MFAMethod,
        secret: Optional[str],
    ) -> Any:
        """Create pending MFA"""
        return type('MFA', (), {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "method": method,
            "secret": secret,
            "verified_at": None,
            "last_used": None,
            "created_at": datetime.utcnow(),
        })()
    
    def _mark_mfa_verified(self, mfa_id: str) -> None:
        """Mark MFA as verified"""
        # In production: update MFA set verified_at=now() where id=?
        pass
    
    def _delete_mfa(self, mfa_id: str) -> None:
        """Delete MFA"""
        # In production: delete from MFA where id=?
        pass
    
    def _verify_user_password(self, user_id: str, password: str) -> bool:
        """Verify user password"""
        # In production: get user, verify password hash
        return False
    
    def _validate_phone_number(self, phone_number: str) -> None:
        """Validate phone number format"""
        import re
        pattern = r"^\+?1?\d{9,15}$"
        if not re.match(pattern, phone_number):
            raise ValueError("Invalid phone number format")
    
    def _send_mfa_email(self, email: str, code: str) -> None:
        """Send MFA code via email"""
        logger.info(f"Sending MFA code to {email}")
        # In production: use email service
    
    def _update_mfa_last_used(self, mfa_id: str) -> None:
        """Update last used timestamp"""
        # In production: update MFA set last_used=now() where id=?
        pass
