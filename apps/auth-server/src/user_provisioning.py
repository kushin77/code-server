"""
User Provisioning Service - OAuth2 Provider User Sync
Issue #1345 Week 2: User Management from OAuth providers
"""
import uuid
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from enum import Enum
from log import get_logger

from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr, validator
import httpx

logger = get_logger(__name__)


# ============================================================================
# Data Models
# ============================================================================

class UserStatus(str, Enum):
    """User account status"""
    PENDING_VERIFICATION = "pending_verification"  # Email not verified
    ACTIVE = "active"  # Verified and active
    SUSPENDED = "suspended"  # Temporarily suspended
    DISABLED = "disabled"  # Permanently disabled


class EmailVerificationStatus(str, Enum):
    """Email verification status"""
    UNVERIFIED = "unverified"
    VERIFIED = "verified"
    BOUNCED = "bounced"


class ProvisioningStatus(str, Enum):
    """User provisioning status"""
    PENDING = "pending"  # Awaiting first OAuth login
    PROVISIONED = "provisioned"  # Successfully created/updated
    FAILED = "failed"  # Provisioning failed
    SKIPPED = "skipped"  # Provisioning skipped


# ============================================================================
# Request/Response Models
# ============================================================================

class UserProvisioningRequest(BaseModel):
    """Request to provision user from OAuth provider"""
    provider: str  # github, google, microsoft
    provider_user_id: str
    email: EmailStr
    name: str
    avatar_url: Optional[str] = None
    raw_data: Dict[str, Any]  # Full provider response
    
    @validator('provider')
    def validate_provider(cls, v):
        allowed = ['github', 'google', 'microsoft', 'okta']
        if v not in allowed:
            raise ValueError(f'Invalid provider. Must be one of: {", ".join(allowed)}')
        return v


class UserProvisioningResponse(BaseModel):
    """Response from user provisioning"""
    user_id: str
    status: ProvisioningStatus
    email: str
    name: str
    email_verification_status: EmailVerificationStatus
    message: Optional[str] = None


class EmailVerificationRequest(BaseModel):
    """Request to send email verification"""
    email: EmailStr
    verification_link_url: Optional[str] = None  # Custom verification URL


class AccountLinkingRequest(BaseModel):
    """Request to link OAuth connection to existing user"""
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
    
    def __init__(self, db_session: Session, config):
        self.db = db_session
        self.config = config
        self.email_service = None  # Injected via dependency
    
    def provision_user_from_provider(
        self,
        request: UserProvisioningRequest,
        auto_provision: bool = True,
    ) -> UserProvisioningResponse:
        """
        Provision user from OAuth provider
        
        Flow:
        1. Check if user already exists by email
        2. Check if OAuth connection already exists
        3. Create user if auto_provision is True
        4. Create OAuth connection
        5. Send verification email
        """
        
        try:
            # Check if OAuth connection already exists
            oauth_connection = self._get_oauth_connection(
                provider=request.provider,
                provider_user_id=request.provider_user_id,
            )
            
            if oauth_connection:
                logger.info(
                    f"OAuth connection already exists for {request.provider}:{request.provider_user_id}"
                )
                return UserProvisioningResponse(
                    user_id=str(oauth_connection.user_id),
                    status=ProvisioningStatus.PROVISIONED,
                    email=oauth_connection.provider_email,
                    name=oauth_connection.provider_name,
                    email_verification_status=self._check_email_verified(
                        oauth_connection.user_id
                    ),
                )
            
            # Check if user exists by email
            user = self._get_user_by_email(request.email)
            
            if user:
                logger.info(f"User exists for email {request.email}, linking OAuth connection")
                # Link OAuth connection to existing user
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
            
            # User doesn't exist - create if auto_provision is True
            if not auto_provision:
                logger.info(
                    f"User not found for {request.email} and auto_provision is False"
                )
                return UserProvisioningResponse(
                    user_id="",
                    status=ProvisioningStatus.SKIPPED,
                    email=request.email,
                    name=request.name,
                    email_verification_status=EmailVerificationStatus.UNVERIFIED,
                    message="Auto provisioning disabled",
                )
            
            # Create user
            logger.info(f"Creating new user from {request.provider} provider")
            user = self._create_user(
                email=request.email,
                name=request.name,
                provider=request.provider,
            )
            
            # Create OAuth connection
            oauth_connection = self._link_oauth_connection(
                user_id=user.id,
                provider=request.provider,
                provider_user_id=request.provider_user_id,
                email=request.email,
                name=request.name,
                avatar_url=request.avatar_url,
                raw_data=request.raw_data,
                is_primary=True,  # First connection is primary
            )
            
            # Send verification email if email verification is required
            if self.config.FEATURE_AUTO_PROVISION and request.email:
                self._send_verification_email(
                    user_id=user.id,
                    email=request.email,
                    name=request.name,
                )
            
            logger.info(f"Successfully provisioned user {user.id}")
            
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
    
    def link_existing_user_to_provider(
        self,
        request: AccountLinkingRequest,
    ) -> Dict[str, Any]:
        """
        Link existing user account to additional OAuth provider
        Allows users to authenticate via multiple providers
        """
        
        try:
            # Verify user exists
            user = self._get_user_by_id(request.user_id)
            if not user:
                raise ValueError(f"User {request.user_id} not found")
            
            # Check if connection already exists
            oauth_connection = self._get_oauth_connection(
                provider=request.provider,
                provider_user_id=request.provider_user_id,
            )
            
            if oauth_connection:
                if oauth_connection.user_id != request.user_id:
                    raise ValueError(
                        f"OAuth connection already linked to different user"
                    )
                logger.info(
                    f"OAuth connection already linked for user {request.user_id}"
                )
                return {
                    "status": "already_linked",
                    "user_id": request.user_id,
                }
            
            # Link OAuth connection
            self._link_oauth_connection(
                user_id=request.user_id,
                provider=request.provider,
                provider_user_id=request.provider_user_id,
                email=request.provider_email,
                name=request.provider_name,
                avatar_url=request.provider_avatar_url,
            )
            
            logger.info(
                f"Successfully linked {request.provider} to user {request.user_id}"
            )
            
            return {
                "status": "linked",
                "user_id": request.user_id,
                "provider": request.provider,
            }
        
        except Exception as e:
            logger.error(f"Account linking failed: {str(e)}")
            raise
    
    def send_email_verification(
        self,
        user_id: str,
        request: EmailVerificationRequest,
    ) -> Dict[str, Any]:
        """Send email verification link to user"""
        
        try:
            user = self._get_user_by_id(user_id)
            if not user:
                raise ValueError(f"User {user_id} not found")
            
            # Generate verification token
            verification_token = self._generate_verification_token(user_id)
            
            # Build verification link
            if request.verification_link_url:
                verification_url = f"{request.verification_link_url}?token={verification_token}"
            else:
                verification_url = f"{self.config.JWT_ISSUER}/verify-email?token={verification_token}"
            
            # Send email
            self._send_verification_email(
                user_id=user_id,
                email=request.email,
                name=user.name,  # type: ignore
                verification_url=verification_url,
            )
            
            logger.info(f"Verification email sent to {request.email}")
            
            return {
                "status": "sent",
                "email": request.email,
                "expires_in_minutes": 1440,  # 24 hours
            }
        
        except Exception as e:
            logger.error(f"Email verification failed: {str(e)}")
            raise
    
    def verify_email_token(self, token: str) -> Dict[str, Any]:
        """Verify email verification token and mark user's email as verified"""
        
        try:
            # Decode token and get user_id
            user_id = self._verify_token(token)
            
            # Mark email as verified
            self._mark_email_verified(user_id)
            
            logger.info(f"Email verified for user {user_id}")
            
            return {
                "status": "verified",
                "user_id": user_id,
                "message": "Email successfully verified",
            }
        
        except Exception as e:
            logger.error(f"Email verification failed: {str(e)}")
            raise
    
    # ========================================================================
    # Private Helper Methods
    # ========================================================================
    
    def _create_user(self, email: str, name: str, provider: str) -> Any:
        """Create new user from OAuth provider"""
        # In production, import User model and create
        # For this example, return mock user
        return type('User', (), {
            'id': str(uuid.uuid4()),
            'email': email,
            'name': name,
            'created_at': datetime.utcnow(),
        })()
    
    def _get_user_by_id(self, user_id: str) -> Optional[Any]:
        """Get user by ID"""
        # In production: return self.db.query(User).filter(User.id == user_id).first()
        return None
    
    def _get_user_by_email(self, email: str) -> Optional[Any]:
        """Get user by email"""
        # In production: return self.db.query(User).filter(User.email == email).first()
        return None
    
    def _get_oauth_connection(
        self,
        provider: str,
        provider_user_id: str,
    ) -> Optional[Any]:
        """Get OAuth connection"""
        # In production: return self.db.query(OAuthConnection).filter(...).first()
        return None
    
    def _link_oauth_connection(
        self,
        user_id: str,
        provider: str,
        provider_user_id: str,
        email: str,
        name: str,
        avatar_url: Optional[str] = None,
        raw_data: Optional[Dict] = None,
        is_primary: bool = False,
    ) -> Any:
        """Create OAuth connection"""
        # In production: create OAuthConnection and commit
        return type('OAuthConnection', (), {
            'id': str(uuid.uuid4()),
            'user_id': user_id,
            'provider': provider,
            'provider_user_id': provider_user_id,
        })()
    
    def _check_email_verified(self, user_id: str) -> EmailVerificationStatus:
        """Check if user's email is verified"""
        # In production: query user's email_verified field
        return EmailVerificationStatus.UNVERIFIED
    
    def _mark_email_verified(self, user_id: str) -> None:
        """Mark user's email as verified"""
        # In production: update user.email_verified = True
        pass
    
    def _send_verification_email(
        self,
        user_id: str,
        email: str,
        name: str,
        verification_url: Optional[str] = None,
    ) -> None:
        """Send email verification email"""
        if not verification_url:
            verification_url = f"{self.config.JWT_ISSUER}/verify-email?user_id={user_id}"
        
        # In production: use email service (SendGrid, etc.)
        logger.info(f"Sending verification email to {email}")
    
    def _generate_verification_token(self, user_id: str) -> str:
        """Generate email verification token"""
        import secrets
        import hashlib
        
        token = secrets.token_urlsafe(32)
        # In production: store hashed token with expiry in database
        return token
    
    def _verify_token(self, token: str) -> str:
        """Verify token and return user_id"""
        # In production: decode JWT or lookup in database
        return ""


# ============================================================================
# OAuth Provider User Info Fetcher
# ============================================================================

class ProviderUserInfoFetcher:
    """Fetch user information from OAuth providers"""
    
    def __init__(self, config):
        self.config = config
    
    async def fetch_github_user(self, access_token: str) -> Dict[str, Any]:
        """Fetch user info from GitHub API"""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.github.com/user",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github+json",
                }
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
        """Fetch user info from Google"""
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
        """Fetch user info from Microsoft"""
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
                "avatar_url": None,  # Microsoft doesn't provide avatar URL directly
                "raw_data": data,
            }
