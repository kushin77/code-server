"""
Advanced Authentication Models
Issue #1345 Week 4: Advanced Features Models

Includes:
- Session/Device tracking
- MFA (Email, SMS, TOTP)
- Recovery codes
- Password reset requests
"""
from datetime import datetime
from typing import Optional
from enum import Enum
import uuid

from sqlalchemy import (
    Column, String, DateTime, Boolean, ForeignKey, Text, JSON, Integer, Index, LargeBinary
)
from sqlalchemy.orm import relationship, declarative_base
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from pydantic import BaseModel, EmailStr, Field

Base = declarative_base()


# ============================================================================
# Enums
# ============================================================================

class MFAMethodEnum(str, Enum):
    """MFA method types"""
    EMAIL = "email"
    SMS = "sms"
    AUTHENTICATOR = "authenticator"
    BACKUP_CODE = "backup_code"


# ============================================================================
# User Sessions & Devices
# ============================================================================

class UserSession(Base):
    """User session tracking"""
    __tablename__ = "user_sessions"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(String(255), nullable=False, index=True)
    device_name = Column(String(255))
    device_type = Column(String(32))  # desktop, mobile, tablet
    os = Column(String(64))
    browser = Column(String(64))
    ip_address = Column(String(45))  # IPv4 or IPv6
    user_agent = Column(Text)
    refresh_token_id = Column(PG_UUID(as_uuid=True), ForeignKey("refresh_tokens.id"))
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    last_activity = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    revoked_at = Column(DateTime, nullable=True, index=True)
    
    # Index for quick lookups
    __table_args__ = (
        Index("ix_user_sessions_user_device", "user_id", "device_id"),
    )


class UserDevice(Base):
    """User device information"""
    __tablename__ = "user_devices"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(String(255), nullable=False)
    device_name = Column(String(255), nullable=False)
    device_type = Column(String(32))
    os = Column(String(64))
    browser = Column(String(64))
    ip_address = Column(String(45))
    user_agent = Column(Text)
    
    is_current = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    last_seen = Column(DateTime, nullable=True)
    
    __table_args__ = (
        Index("ix_user_devices_user_id", "user_id"),
    )


# ============================================================================
# Refresh Tokens
# ============================================================================

class RefreshToken(Base):
    """Refresh token tracking"""
    __tablename__ = "refresh_tokens"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    token_hash = Column(String(255), nullable=False, unique=True)
    device_id = Column(String(255))
    ip_address = Column(String(45))
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    
    __table_args__ = (
        Index("ix_refresh_tokens_user_id_not_revoked", "user_id"),
    )


# ============================================================================
# Two-Factor Authentication
# ============================================================================

class UserMFA(Base):
    """User MFA configuration"""
    __tablename__ = "user_mfa"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    method = Column(String(32), nullable=False)  # email, sms, authenticator
    
    # For authenticator: TOTP secret (encrypted)
    secret = Column(String(255), nullable=True)
    
    # For SMS/phone: phone number (encrypted)
    phone_number = Column(String(20), nullable=True)
    
    # Verification tracking
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    verified_at = Column(DateTime, nullable=True)
    last_used = Column(DateTime, nullable=True)
    
    # Backup codes count
    backup_codes_remaining = Column(Integer, default=0)
    
    __table_args__ = (
        Index("ix_user_mfa_user_id_method", "user_id", "method"),
    )


class RecoveryCode(Base):
    """MFA recovery codes"""
    __tablename__ = "recovery_codes"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    code_hash = Column(String(255), nullable=False)  # Hashed for security
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    used_at = Column(DateTime, nullable=True, index=True)
    
    __table_args__ = (
        Index("ix_recovery_codes_user_id", "user_id"),
    )


# ============================================================================
# Password Reset
# ============================================================================

class PasswordResetRequest(Base):
    """Password reset token tracking"""
    __tablename__ = "password_reset_requests"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    token = Column(String(255), nullable=False, unique=True, index=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True)
    
    __table_args__ = (
        Index("ix_password_reset_user_id", "user_id"),
    )


# ============================================================================
# Email Change Requests
# ============================================================================

class EmailChangeRequest(Base):
    """Email change with verification"""
    __tablename__ = "email_change_requests"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    new_email = Column(String(255), nullable=False)
    token = Column(String(255), nullable=False, unique=True, index=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False)
    verified_at = Column(DateTime, nullable=True)
    
    __table_args__ = (
        Index("ix_email_change_user_id", "user_id"),
    )


# ============================================================================
# Login Events
# ============================================================================

class LoginEvent(Base):
    """Track all login attempts for security"""
    __tablename__ = "login_events"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    
    success = Column(Boolean, nullable=False)
    reason = Column(String(255))  # success, invalid_credentials, account_locked, mfa_required, etc.
    
    ip_address = Column(String(45))
    user_agent = Column(Text)
    device_id = Column(String(255))
    
    mfa_method_used = Column(String(32), nullable=True)  # If MFA was used
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    __table_args__ = (
        Index("ix_login_events_user_id_created", "user_id", "created_at"),
    )


# ============================================================================
# Pydantic Request/Response Models
# ============================================================================

class MFAEnableRequest(BaseModel):
    """Enable MFA request"""
    method: str  # email, sms, authenticator
    phone_number: Optional[str] = None


class MFAVerifyRequest(BaseModel):
    """Verify MFA code request"""
    code: str


class PasswordResetRequest(BaseModel):
    """Request password reset"""
    email: EmailStr


class PasswordResetCompleteRequest(BaseModel):
    """Complete password reset"""
    token: str
    new_password: str = Field(..., min_length=12)


class SessionResponse(BaseModel):
    """Session response"""
    session_id: str
    device_name: str
    device_id: str
    ip_address: str
    created_at: datetime
    last_activity: Optional[datetime]


class DeviceResponse(BaseModel):
    """Device response"""
    device_id: str
    device_name: str
    device_type: Optional[str]
    os: Optional[str]
    browser: Optional[str]
    last_seen: Optional[datetime]
    is_current: bool


class LoginEventResponse(BaseModel):
    """Login event response"""
    success: bool
    reason: str
    ip_address: str
    created_at: datetime
