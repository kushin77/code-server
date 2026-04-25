"""
User Profile Models and API
Issue #1345 Week 2: User Management
"""
from datetime import datetime
from typing import Optional, List
from enum import Enum
import uuid

from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, Text, Index, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from pydantic import BaseModel, EmailStr, Field, validator
from src.models import Base


# ============================================================================
# SQLAlchemy Models
# ============================================================================

class User(Base):
    """User Account"""
    __tablename__ = "users"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Account Information
    email = Column(String(255), nullable=False, unique=True, index=True)
    name = Column(String(255), nullable=False)
    avatar_url = Column(String(512), nullable=True)
    
    # Account Status
    status = Column(String(32), default="pending_verification")  # pending_verification, active, suspended, disabled
    email_verified = Column(Boolean, default=False)
    email_verified_at = Column(DateTime, nullable=True)
    last_verified_email = Column(String(255), nullable=True)  # Track email changes
    
    # Profile Information
    bio = Column(Text, nullable=True)
    company = Column(String(255), nullable=True)
    location = Column(String(255), nullable=True)
    website = Column(String(512), nullable=True)
    
    # Preferences
    locale = Column(String(16), default="en_US")  # en_US, es_ES, etc.
    timezone = Column(String(32), default="UTC")
    preferences = Column(JSON, default=dict)  # Custom user preferences
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login_at = Column(DateTime, nullable=True)
    last_login_ip = Column(String(45), nullable=True)
    
    # Relationships
    oauth_connections = relationship("OAuthConnection", back_populates="user", cascade="all, delete-orphan")
    oauth_tokens = relationship("OAuthToken", back_populates="user", cascade="all, delete-orphan")
    
    __table_args__ = (
        Index("ix_users_email_verified", "email", "email_verified"),
        Index("ix_users_created_at", "created_at"),
    )


class UserProfile(Base):
    """Extended User Profile Information"""
    __tablename__ = "user_profiles"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, unique=True)
    
    # Public Profile Information
    display_name = Column(String(255), nullable=True)
    bio = Column(Text, nullable=True)
    avatar_url = Column(String(512), nullable=True)
    profile_url = Column(String(512), nullable=True)  # Public profile URL
    
    # Professional Information
    job_title = Column(String(255), nullable=True)
    company = Column(String(255), nullable=True)
    industry = Column(String(128), nullable=True)
    
    # Location & Contact
    country = Column(String(128), nullable=True)
    city = Column(String(128), nullable=True)
    timezone = Column(String(32), nullable=True)
    phone_number = Column(String(20), nullable=True)
    phone_verified = Column(Boolean, default=False)
    
    # Social Links
    social_links = Column(JSON, default=dict)  # {"github": "...", "twitter": "...", etc.}
    
    # Privacy & Visibility
    is_public = Column(Boolean, default=True)
    show_email = Column(Boolean, default=False)
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# ============================================================================
# Pydantic Request/Response Models
# ============================================================================

class UserCreateRequest(BaseModel):
    """Request to create user"""
    email: EmailStr
    name: str = Field(..., min_length=1, max_length=255)
    avatar_url: Optional[str] = None


class UserUpdateRequest(BaseModel):
    """Request to update user profile"""
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    avatar_url: Optional[str] = None
    bio: Optional[str] = Field(None, max_length=500)
    company: Optional[str] = Field(None, max_length=255)
    location: Optional[str] = Field(None, max_length=255)
    website: Optional[str] = None
    timezone: Optional[str] = None
    locale: Optional[str] = None
    
    @validator('locale')
    def validate_locale(cls, v):
        if v:
            valid_locales = ['en_US', 'es_ES', 'fr_FR', 'de_DE', 'ja_JP', 'zh_CN']
            if v not in valid_locales:
                raise ValueError(f'Invalid locale. Must be one of: {", ".join(valid_locales)}')
        return v


class UserResponse(BaseModel):
    """User response model"""
    id: str
    email: str
    name: str
    avatar_url: Optional[str] = None
    status: str
    email_verified: bool
    email_verified_at: Optional[datetime] = None
    bio: Optional[str] = None
    company: Optional[str] = None
    location: Optional[str] = None
    website: Optional[str] = None
    locale: str
    timezone: str
    created_at: datetime
    updated_at: datetime
    last_login_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class UserProfileResponse(BaseModel):
    """User profile response"""
    id: str
    user_id: str
    display_name: Optional[str] = None
    bio: Optional[str] = None
    avatar_url: Optional[str] = None
    profile_url: Optional[str] = None
    job_title: Optional[str] = None
    company: Optional[str] = None
    industry: Optional[str] = None
    country: Optional[str] = None
    city: Optional[str] = None
    timezone: Optional[str] = None
    is_public: bool
    social_links: dict
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class UserListResponse(BaseModel):
    """Paginated user list response"""
    items: List[UserResponse]
    total: int
    page: int
    page_size: int
    total_pages: int


class UserPreferencesRequest(BaseModel):
    """Request to update user preferences"""
    locale: Optional[str] = None
    timezone: Optional[str] = None
    preferences: Optional[dict] = Field(default_factory=dict)


class ChangeEmailRequest(BaseModel):
    """Request to change user email"""
    new_email: EmailStr
    confirmation_required: bool = True


class ChangeEmailResponse(BaseModel):
    """Response from email change request"""
    status: str  # pending_verification, completed
    message: str
    verification_token: Optional[str] = None


# ============================================================================
# User API Service
# ============================================================================

class UserAPIService:
    """Service for user profile management"""
    
    def __init__(self, db_session):
        self.db = db_session
    
    def get_user(self, user_id: str) -> Optional[UserResponse]:
        """Get user by ID"""
        # In production: return self.db.query(User).filter(User.id == user_id).first()
        pass
    
    def get_user_by_email(self, email: str) -> Optional[UserResponse]:
        """Get user by email"""
        pass
    
    def list_users(self, page: int = 1, page_size: int = 20) -> UserListResponse:
        """List all users with pagination"""
        pass
    
    def update_user_profile(self, user_id: str, request: UserUpdateRequest) -> UserResponse:
        """Update user profile"""
        pass
    
    def update_user_preferences(self, user_id: str, request: UserPreferencesRequest) -> dict:
        """Update user preferences (locale, timezone, etc.)"""
        pass
    
    def change_email(self, user_id: str, request: ChangeEmailRequest) -> ChangeEmailResponse:
        """Request email address change"""
        pass
    
    def verify_email_change(self, token: str) -> dict:
        """Verify email change with token"""
        pass
    
    def delete_user(self, user_id: str) -> dict:
        """Delete user account (soft or hard delete)"""
        pass


# ============================================================================
# User Activity & Audit
# ============================================================================

class UserActivityLog(Base):
    """Track user activity for security and auditing"""
    __tablename__ = "user_activity_logs"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    
    # Activity Information
    activity_type = Column(String(64), nullable=False)  # login, logout, profile_update, password_change, etc.
    activity_description = Column(Text, nullable=True)
    status = Column(String(32), default="success")  # success, failure
    
    # Request Context
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(512), nullable=True)
    country = Column(String(128), nullable=True)  # GeoIP lookup
    
    # Metadata
    activity_metadata = Column("metadata", JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    __table_args__ = (
        Index("ix_user_activity_type", "activity_type"),
        Index("ix_user_activity_created", "user_id", "created_at"),
    )
