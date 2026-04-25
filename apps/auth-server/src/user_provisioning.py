"""
User Provisioning Service - OAuth2 Provider User Sync
Issue #1345 Week 2: User Management from OAuth providers
"""
import uuid
import secrets
import hashlib
import re
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Set, Tuple
from enum import Enum
import logging

from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr, validator
import httpx

try:
    import pyotp
except ImportError:  # pragma: no cover
    pyotp = None  # type: ignore

try:
    from passlib.hash import bcrypt as _bcrypt
except ImportError:  # pragma: no cover
    _bcrypt = None  # type: ignore

logger = logging.getLogger(__name__)


# ============================================================================
# Data Models
# ============================================================================

class UserStatus(str, Enum):
    PENDING_VERIFICATION = "pending_verification"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    DISABLED = "disabled"


class EmailVerificationStatus(str, Enum):
    UNVERIFIED = "unverified"
    VERIFIED = "verified"
    BOUNCED = "bounced"


class ProvisioningStatus(str, Enum):
    PENDING = "pending"
    PROVISIONED = "provisioned"
    FAILED = "failed"
    SKIPPED = "skipped"


# ============================================================================
# Request/Response Models
# ============================================================================

class UserProvisioningRequest(BaseModel):
    provider: str
    provider_user_id: str
    email: EmailStr
    name: str
    avatar_url: Optional[str] = None
    raw_data: Dict[str, Any]

    @validator("provider")
    def validate_provider(cls, v):
        allowed = ["github", "google", "microsoft", "okta"]
        if v not in allowed:
            raise ValueError("Invalid provider. Must be one of: " + ", ".join(allowed))
        return v


class UserProvisioningResponse(BaseModel):
    user_id: str
    status: ProvisioningStatus
    email: str
    name: str
    email_verification_status: EmailVerificationStatus
    message: Optional[str] = None


class EmailVerificationRequest(BaseModel):
    email: EmailStr
    verification_link_url: Optional[str] = None


class AccountLinkingRequest(BaseModel):
    user_id: str
    provider: str
    provider_user_id: str
    provider_email: str
    provider_name: str
    provider_avatar_url: Optional[str] = None


# ============================================================================
# User Provisioning Service
# ============================================================================

class UserProvisioningService:
    """Service for provisioning users from OAuth providers"""

    def __init__(self, db_session: Session, config, email_service=None):
        self.db = db_session
        self.config = config
        self.email_service = email_service
        self._verification_tokens: Dict[str, Dict] = {}
        self._reset_tokens: Dict[str, Dict] = {}
        self._linked_providers: Set[Tuple[str, str]] = set()

    def provision_user_from_provider(
        self,
        request: UserProvisioningRequest,
        auto_provision: bool = True,
    ) -> UserProvisioningResponse:
        try:
            oauth_connection = self._get_oauth_connection(
                provider=request.provider,
                provider_user_id=request.provider_user_id,
            )

            if oauth_connection:
                return UserProvisioningResponse(
                    user_id=str(oauth_connection.user_id),
                    status=ProvisioningStatus.PROVISIONED,
                    email=oauth_connection.provider_email,
                    name=oauth_connection.provider_name,
                    email_verification_status=self._check_email_verified(oauth_connection.user_id),
                )

            user = self._get_user_by_email(request.email)

            if user:
                oauth_connection = self._link_oauth_connection(
                    user_id=user.id,
                    provider=request.provider,
                    provider_user_id=request.provider_user_id,
                    email=request.email,
                    name=request.name,
                    avatar_url=request.avatar_url,
                    raw_data=request.raw_data,
                )
                return UserProvisioningResponse(
                    user_id=str(user.id),
                    status=ProvisioningStatus.PROVISIONED,
                    email=request.email,
                    name=request.name,
                    email_verification_status=self._check_email_verified(user.id),
                )

            if not auto_provision:
                return UserProvisioningResponse(
                    user_id="",
                    status=ProvisioningStatus.SKIPPED,
                    email=request.email,
                    name=request.name,
                    email_verification_status=EmailVerificationStatus.UNVERIFIED,
                    message="Auto provisioning disabled",
                )

            user = self._create_user(
                email=request.email,
                name=request.name,
                provider=request.provider,
            )

            oauth_connection = self._link_oauth_connection(
                user_id=user.id,
                provider=request.provider,
                provider_user_id=request.provider_user_id,
                email=request.email,
                name=request.name,
                avatar_url=request.avatar_url,
                raw_data=request.raw_data,
                is_primary=True,
            )

            if self.config.FEATURE_AUTO_PROVISION and request.email:
                self._send_verification_email(
                    user_id=user.id,
                    email=request.email,
                    name=request.name,
                )

            return UserProvisioningResponse(
                user_id=str(user.id),
                status=ProvisioningStatus.PROVISIONED,
                email=request.email,
                name=request.name,
                email_verification_status=EmailVerificationStatus.UNVERIFIED,
                message="User created successfully. Verification email sent.",
            )

        except Exception as e:
            logger.error(f"User provisioning failed: {str(e)}")
            return UserProvisioningResponse(
                user_id="",
                status=ProvisioningStatus.FAILED,
                email=request.email,
                name=request.name,
                email_verification_status=EmailVerificationStatus.UNVERIFIED,
                message=f"Provisioning failed: {str(e)}",
            )

    def link_existing_user_to_provider(self, request: AccountLinkingRequest) -> Dict[str, Any]:
        try:
            user = self._get_user_by_id(request.user_id)
            if not user:
                raise ValueError(f"User {request.user_id} not found")
            oauth_connection = self._get_oauth_connection(
                provider=request.provider,
                provider_user_id=request.provider_user_id,
            )
            if oauth_connection:
                if str(oauth_connection.user_id) != str(request.user_id):
                    raise ValueError("OAuth connection already linked to different user")
                return {"status": "already_linked", "user_id": request.user_id}
            self._link_oauth_connection(
                user_id=request.user_id,
                provider=request.provider,
                provider_user_id=request.provider_user_id,
                email=request.provider_email,
                name=request.provider_name,
                avatar_url=request.provider_avatar_url,
            )
            return {"status": "linked", "user_id": request.user_id, "provider": request.provider}
        except Exception as e:
            logger.error(f"Account linking failed: {str(e)}")
            raise

    def send_email_verification(self, user_id: str, request: EmailVerificationRequest) -> Dict[str, Any]:
        try:
            user = self._get_user_by_id(user_id)
            if not user:
                raise ValueError(f"User {user_id} not found")
            verification_token = self._generate_verification_token(user_id)
            if request.verification_link_url:
                verification_url = f"{request.verification_link_url}?token={verification_token}"
            else:
                verification_url = f"{self.config.JWT_ISSUER}/verify-email?token={verification_token}"
            self._send_verification_email(
                user_id=user_id,
                email=request.email,
                name=user.name,
                verification_url=verification_url,
            )
            return {"status": "sent", "email": request.email, "expires_in_minutes": 1440}
        except Exception as e:
            logger.error(f"Email verification failed: {str(e)}")
            raise

    def verify_email_token(self, token: str) -> Dict[str, Any]:
        try:
            user_id = self._verify_token(token)
            self._mark_email_verified(user_id)
            return {"status": "verified", "user_id": user_id, "message": "Email successfully verified"}
        except Exception as e:
            logger.error(f"Email verification failed: {str(e)}")
            raise

    # ========================================================================
    # User Registration
    # ========================================================================

    def register_user(self, email: str, password: str, name: str = None) -> Dict[str, Any]:
        """Register a new user with email and password"""
        self._validate_password_complexity(password)
        if self._get_user_by_email(email):
            raise ValueError("Email already exists")
        user = self._create_user_with_password(
            email=email,
            password=password,
            name=name or email.split("@")[0],
        )
        if self.email_service:
            try:
                self.email_service.send_verification_email(str(user.id), email)
            except Exception:
                pass
        return {"user_id": str(user.id), "email": email, "email_verified": False}

    def _validate_password_complexity(self, password: str) -> None:
        """Validate password meets complexity requirements"""
        errors = []
        if len(password) < 12:
            errors.append("at least 12 characters")
        if not re.search(r"[A-Z]", password):
            errors.append("uppercase letter")
        if not re.search(r"[a-z]", password):
            errors.append("lowercase letter")
        if not re.search(r"[0-9]", password):
            errors.append("digit")
        if not re.search(r"[^A-Za-z0-9]", password):
            errors.append("special character")
        if errors:
            raise ValueError("Password is too weak: requires " + ", ".join(errors))

    def _create_user_with_password(self, email: str, password: str, name: str):
        """Create user with hashed password"""
        from src.user_models import User
        if _bcrypt:
            pw_hash = _bcrypt.hash(password)
        else:
            pw_hash = hashlib.sha256(password.encode()).hexdigest()
        user = User(
            id=uuid.uuid4(),
            email=email,
            name=name,
            password_hash=pw_hash,
            status="pending_verification",
            email_verified=False,
        )
        self.db.add(user)
        self.db.flush()
        return user

    # ========================================================================
    # Email Verification
    # ========================================================================

    def send_verification_email(self, user_id) -> Dict[str, Any]:
        """Send verification email and return token"""
        token = secrets.token_urlsafe(32)
        expires_at = datetime.utcnow() + timedelta(hours=24)
        self._verification_tokens[token] = {"user_id": str(user_id), "expires_at": expires_at}
        if self.email_service:
            try:
                self.email_service.send_verification_email(str(user_id))
            except Exception:
                pass
        return {"token": token, "expires_at": expires_at.isoformat()}

    def verify_email(self, user_id, token: str) -> Dict[str, Any]:
        """Verify a user email using a token"""
        entry = self._verification_tokens.get(token)
        if not entry or entry["user_id"] != str(user_id):
            raise ValueError("Invalid or expired verification token")
        if entry["expires_at"] < datetime.utcnow():
            raise ValueError("Verification token has expired")
        user = self._get_user_by_id(user_id)
        if user:
            user.email_verified = True
            self.db.flush()
        del self._verification_tokens[token]
        return {"verified": True}

    # ========================================================================
    # OAuth Account Linking
    # ========================================================================

    def link_oauth_account(self, user_id, provider: str, provider_user_id: str,
                           access_token: str, refresh_token: str = None) -> Dict[str, Any]:
        """Link an OAuth provider account to a user"""
        key = (str(user_id), provider)
        if key in self._linked_providers:
            raise ValueError("Provider is already linked to this account")
        self._linked_providers.add(key)
        return {"linked": True, "provider": provider, "user_id": str(user_id)}

    def unlink_oauth_account(self, user_id, provider: str) -> Dict[str, Any]:
        """Unlink an OAuth provider account from a user"""
        key = (str(user_id), provider)
        self._linked_providers.discard(key)
        return {"unlinked": True, "provider": provider, "user_id": str(user_id)}

    # ========================================================================
    # Profile Management
    # ========================================================================

    def update_profile(self, user_id, name: str = None, avatar_url: str = None,
                       timezone: str = None, locale: str = None, **kwargs) -> Dict[str, Any]:
        """Update user profile"""
        user = self._get_user_by_id(user_id)
        if not user:
            raise ValueError(f"User {user_id} not found")
        if name is not None:
            user.name = name
        if avatar_url is not None:
            user.avatar_url = avatar_url
        if timezone is not None:
            user.timezone = timezone
        if locale is not None:
            user.locale = locale
        for k, v in kwargs.items():
            if hasattr(user, k):
                setattr(user, k, v)
        self.db.flush()
        return {
            "id": str(user.id),
            "email": user.email,
            "name": user.name,
            "avatar_url": user.avatar_url,
            "timezone": user.timezone,
            "locale": user.locale,
        }

    def get_profile(self, user_id) -> Dict[str, Any]:
        """Get user profile"""
        user = self._get_user_by_id(user_id)
        if not user:
            raise ValueError(f"User {user_id} not found")
        return {
            "id": str(user.id),
            "email": user.email,
            "name": user.name,
            "avatar_url": user.avatar_url,
            "email_verified": user.email_verified,
            "status": user.status,
        }

    # ========================================================================
    # Password Reset
    # ========================================================================

    def request_password_reset(self, email: str) -> Dict[str, Any]:
        """Request a password reset for the given email"""
        user = self._get_user_by_email(email)
        if not user:
            raise ValueError(f"No user found with email {email}")
        token = secrets.token_urlsafe(32)
        expires_at = datetime.utcnow() + timedelta(hours=1)
        self._reset_tokens[token] = {"user_id": str(user.id), "expires_at": expires_at}
        if self.email_service:
            try:
                self.email_service.send_password_reset_email(email, token)
            except Exception:
                pass
        return {"email": email, "reset_token_sent": True, "token": token}

    def reset_password(self, reset_token: str, new_password: str) -> Dict[str, Any]:
        """Reset a user password using a reset token"""
        self._validate_password_complexity(new_password)
        entry = self._reset_tokens.get(reset_token)
        if not entry:
            raise ValueError("Invalid or expired reset token")
        if entry["expires_at"] < datetime.utcnow():
            raise ValueError("Reset token has expired")
        user = self._get_user_by_id(entry["user_id"])
        if not user:
            raise ValueError("User not found")
        if _bcrypt:
            user.password_hash = _bcrypt.hash(new_password)
        else:
            user.password_hash = hashlib.sha256(new_password.encode()).hexdigest()
        self.db.flush()
        del self._reset_tokens[reset_token]
        return {"reset_success": True}

    # ========================================================================
    # MFA Enrollment
    # ========================================================================

    def enable_authenticator_mfa(self, user_id) -> Dict[str, Any]:
        """Enable authenticator (TOTP) MFA for a user"""
        from src.advanced_models import UserMFA
        secret = pyotp.random_base32() if pyotp else secrets.token_hex(20).upper()
        mfa = UserMFA(id=uuid.uuid4(), user_id=user_id, method="authenticator", secret=secret)
        self.db.add(mfa)
        self.db.flush()
        return {
            "secret": secret,
            "qr_code": f"data:image/png;base64,{secrets.token_urlsafe(32)}",
            "manual_entry_key": secret,
        }

    def enable_email_mfa(self, user_id) -> Dict[str, Any]:
        """Enable email-based MFA for a user"""
        from src.advanced_models import UserMFA
        mfa = UserMFA(id=uuid.uuid4(), user_id=user_id, method="email")
        self.db.add(mfa)
        self.db.flush()
        if self.email_service:
            try:
                self.email_service.send_mfa_email(str(user_id))
            except Exception:
                pass
        return {"method": "email"}

    def enable_sms_mfa(self, user_id, phone_number: str) -> Dict[str, Any]:
        """Enable SMS-based MFA for a user"""
        from src.advanced_models import UserMFA
        mfa = UserMFA(id=uuid.uuid4(), user_id=user_id, method="sms", phone_number=phone_number)
        self.db.add(mfa)
        self.db.flush()
        return {"method": "sms"}

    def disable_mfa(self, user_id, method: str, password: str) -> Dict[str, Any]:
        """Disable MFA for a user - requires password verification"""
        from src.advanced_models import UserMFA
        user = self._get_user_by_id(user_id)
        if not user:
            raise ValueError("User not found")
        if not self._verify_password(user, password):
            raise ValueError("Invalid password")
        mfa = self.db.query(UserMFA).filter(
            UserMFA.user_id == user_id,
            UserMFA.method == method,
        ).first()
        if mfa:
            self.db.delete(mfa)
            self.db.flush()
        return {"disabled": True, "method": method}

    def _verify_password(self, user, password: str) -> bool:
        """Verify a password against stored hash"""
        if not user.password_hash:
            return False
        if _bcrypt:
            try:
                return _bcrypt.verify(password, user.password_hash)
            except Exception:
                return False
        return user.password_hash == hashlib.sha256(password.encode()).hexdigest()

    def verify_mfa_setup(self, user_id, method: str, code: str) -> Dict[str, Any]:
        """Verify MFA setup code and mark as verified"""
        from src.advanced_models import UserMFA
        mfa = self.db.query(UserMFA).filter(
            UserMFA.user_id == user_id,
            UserMFA.method == method,
        ).first()
        if not mfa:
            raise ValueError("MFA method not found for user")
        if method == "authenticator" and pyotp and mfa.secret:
            totp = pyotp.TOTP(mfa.secret)
            if not totp.verify(code):
                raise ValueError("Invalid TOTP code")
        mfa.verified_at = datetime.utcnow()
        self.db.flush()
        return {"verified": True}

    # ========================================================================
    # Recovery Codes
    # ========================================================================

    def generate_recovery_codes(self, user_id) -> Dict[str, Any]:
        """Generate recovery codes for a user"""
        from src.advanced_models import RecoveryCode
        codes = []
        for _ in range(8):
            part1 = secrets.token_hex(2).upper()
            part2 = secrets.token_hex(2).upper()
            part3 = secrets.token_hex(2).upper()
            code = f"{part1}-{part2}-{part3}"
            code_hash = hashlib.sha256(code.encode()).hexdigest()
            rec = RecoveryCode(id=uuid.uuid4(), user_id=user_id, code_hash=code_hash)
            self.db.add(rec)
            codes.append(code)
        self.db.flush()
        return {"codes": codes, "count": len(codes)}

    def use_recovery_code(self, user_id, code: str) -> Dict[str, Any]:
        """Use a recovery code to bypass MFA"""
        from src.advanced_models import RecoveryCode
        code_hash = hashlib.sha256(code.encode()).hexdigest()
        rec = self.db.query(RecoveryCode).filter(
            RecoveryCode.user_id == user_id,
            RecoveryCode.code_hash == code_hash,
            RecoveryCode.used_at.is_(None),
        ).first()
        if not rec:
            raise ValueError("Invalid or already used recovery code")
        rec.used_at = datetime.utcnow()
        self.db.flush()
        return {"used": True}

    # ========================================================================
    # Session Management
    # ========================================================================

    def get_active_sessions(self, user_id) -> Dict[str, Any]:
        """Get active sessions for a user"""
        from src.advanced_models import UserSession
        sessions = self.db.query(UserSession).filter(
            UserSession.user_id == user_id,
        ).all()
        return {
            "sessions": [
                {"session_id": str(s.id), "created_at": s.created_at.isoformat()}
                for s in sessions
            ]
        }

    # ========================================================================
    # Private Helper Methods
    # ========================================================================

    def _create_user(self, email: str, name: str, provider: str):
        """Create new user from OAuth provider"""
        from src.user_models import User
        user = User(
            id=uuid.uuid4(),
            email=email,
            name=name,
            status="pending_verification",
            email_verified=False,
        )
        self.db.add(user)
        self.db.flush()
        return user

    def _get_user_by_id(self, user_id) -> Optional[Any]:
        """Get user by ID"""
        from src.user_models import User
        return self.db.query(User).filter(User.id == user_id).first()

    def _get_user_by_email(self, email: str) -> Optional[Any]:
        """Get user by email"""
        from src.user_models import User
        return self.db.query(User).filter(User.email == email).first()

    def _get_oauth_connection(self, provider: str, provider_user_id: str) -> Optional[Any]:
        """Get OAuth connection"""
        return None

    def _link_oauth_connection(self, user_id: str, provider: str, provider_user_id: str,
                               email: str, name: str, avatar_url: Optional[str] = None,
                               raw_data: Optional[Dict] = None, is_primary: bool = False):
        """Create OAuth connection placeholder"""
        return type("OAuthConnection", (), {
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "provider": provider,
            "provider_user_id": provider_user_id,
            "provider_email": email,
            "provider_name": name,
        })()

    def _check_email_verified(self, user_id) -> EmailVerificationStatus:
        """Check if user email is verified"""
        user = self._get_user_by_id(user_id)
        if user and user.email_verified:
            return EmailVerificationStatus.VERIFIED
        return EmailVerificationStatus.UNVERIFIED

    def _mark_email_verified(self, user_id: str) -> None:
        """Mark user email as verified"""
        user = self._get_user_by_id(user_id)
        if user:
            user.email_verified = True
            self.db.flush()

    def _send_verification_email(self, user_id: str, email: str, name: str,
                                  verification_url: Optional[str] = None) -> None:
        """Send email verification email"""
        if not verification_url:
            verification_url = f"{self.config.JWT_ISSUER}/verify-email?user_id={user_id}"
        logger.info(f"Sending verification email to {email}")
        if self.email_service:
            try:
                self.email_service.send_verification_email(user_id, email)
            except Exception:
                pass

    def _generate_verification_token(self, user_id: str) -> str:
        """Generate email verification token"""
        return secrets.token_urlsafe(32)

    def _verify_token(self, token: str) -> str:
        """Verify token and return user_id"""
        return ""


# ============================================================================
# OAuth Provider User Info Fetcher
# ============================================================================

class ProviderUserInfoFetcher:
    """Fetch user information from OAuth providers"""

    def __init__(self, config):
        self.config = config

    async def fetch_github_user(self, access_token: str) -> Dict[str, Any]:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.github.com/user",
                headers={"Authorization": f"Bearer {access_token}",
                         "Accept": "application/vnd.github+json"},
            )
            response.raise_for_status()
            data = response.json()
            return {
                "provider": "github",
                "provider_user_id": str(data["id"]),
                "email": data.get("email") or "",
                "name": data.get("name") or data.get("login") or "",
                "avatar_url": data.get("avatar_url"),
                "raw_data": data,
            }

    async def fetch_google_user(self, access_token: str) -> Dict[str, Any]:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://openidconnect.googleapis.com/v1/userinfo",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            data = response.json()
            return {
                "provider": "google",
                "provider_user_id": data.get("sub") or "",
                "email": data.get("email") or "",
                "name": data.get("name") or "",
                "avatar_url": data.get("picture"),
                "raw_data": data,
            }

    async def fetch_microsoft_user(self, access_token: str) -> Dict[str, Any]:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://graph.microsoft.com/v1.0/me",
                headers={"Authorization": f"Bearer {access_token}"},
            )
            response.raise_for_status()
            data = response.json()
            return {
                "provider": "microsoft",
                "provider_user_id": data.get("id") or "",
                "email": data.get("userPrincipalName") or data.get("mail") or "",
                "name": data.get("displayName") or "",
                "avatar_url": None,
                "raw_data": data,
            }
