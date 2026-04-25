"""
API Gateway Models - API Keys, Quota, Rate Limits
Issue #1345 Week 5: API Gateway Integration
"""
from datetime import datetime
from typing import Optional
import uuid

from sqlalchemy import (
    Column, String, DateTime, Boolean, ForeignKey, Text, JSON, Integer, Index
)
from sqlalchemy.orm import relationship, declarative_base
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from pydantic import BaseModel, Field

Base = declarative_base()


# ============================================================================
# API Keys
# ============================================================================

class APIKey(Base):
    """API key for programmatic access"""
    __tablename__ = "api_keys"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)

    name = Column(String(255), nullable=False)
    key_hash = Column(String(255), nullable=False, unique=True)

    # Scopes/permissions for this key
    scopes = Column(JSON, default=list)

    # Usage tracking
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_used = Column(DateTime, nullable=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)

    # Metadata
    ip_whitelist = Column(JSON, nullable=True)  # List of allowed IPs
    user_agent_pattern = Column(String(255), nullable=True)  # Regex pattern for User-Agent

    __table_args__ = (
        Index("ix_api_keys_user_id_not_revoked", "user_id"),
    )


# ============================================================================
# Quotas
# ============================================================================

class QuotaUsage(Base):
    """Track quota usage"""
    __tablename__ = "quota_usage"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_type = Column(String(32), nullable=False)  # user, team, org
    owner_id = Column(PG_UUID(as_uuid=True), nullable=False, index=True)

    resource_type = Column(String(64), nullable=False)  # api_calls, storage, etc
    quota_limit = Column(Integer, nullable=False)
    current_usage = Column(Integer, default=0)

    # Billing period
    period_start = Column(DateTime, nullable=False, index=True)
    period_end = Column(DateTime, nullable=False, index=True)

    # Alerts
    warning_sent_at = Column(DateTime, nullable=True)  # 80% usage alert

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        Index("ix_quota_owner_type_id", "owner_type", "owner_id"),
        Index("ix_quota_resource_period", "resource_type", "period_start", "period_end"),
    )


class QuotaWarning(Base):
    """Track quota warnings sent"""
    __tablename__ = "quota_warnings"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    quota_usage_id = Column(PG_UUID(as_uuid=True), ForeignKey("quota_usage.id"), nullable=False)

    warning_level = Column(Integer, nullable=False)  # 50, 80, 100
    sent_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    acknowledged_at = Column(DateTime, nullable=True)

    __table_args__ = (
        Index("ix_quota_warnings_sent_at", "sent_at"),
    )


# ============================================================================
# Rate Limit Records
# ============================================================================

class RateLimitRecord(Base):
    """Track rate limit events"""
    __tablename__ = "rate_limit_records"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    api_key_id = Column(PG_UUID(as_uuid=True), ForeignKey("api_keys.id"), nullable=True)

    limit_type = Column(String(32), nullable=False)  # user, api_key, ip
    identifier = Column(String(255), nullable=False)

    limit = Column(Integer, nullable=False)
    exceeded = Column(Boolean, default=False)

    ip_address = Column(String(45))
    user_agent = Column(Text)
    endpoint = Column(String(255))
    method = Column(String(10))  # GET, POST, etc

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    __table_args__ = (
        Index("ix_rate_limit_user_id_created", "user_id", "created_at"),
    )


# ============================================================================
# Pydantic Models
# ============================================================================

class APIKeyCreateRequest(BaseModel):
    """Create API key request"""
    name: str = Field(..., min_length=1, max_length=255)
    scopes: list = Field(default_factory=list)
    expires_in_days: int = Field(default=365, ge=1, le=3650)


class APIKeyResponse(BaseModel):
    """API key response (without secret)"""
    key_id: str
    name: str
    scopes: list
    created_at: datetime
    last_used: Optional[datetime]
    expires_at: datetime


class APIKeyFullResponse(APIKeyResponse):
    """Full API key response (with secret - only on creation)"""
    key: str


class QuotaUsageResponse(BaseModel):
    """Quota usage response"""
    resource_type: str
    quota_limit: int
    current_usage: int
    remaining: int
    percent_used: int
    period_start: datetime
    period_end: datetime


class RateLimitStatsResponse(BaseModel):
    """Rate limit statistics"""
    limit: int
    current: int
    remaining: int
    reset_in_seconds: int


class APIAccessTokenRequest(BaseModel):
    """Request API access token"""
    api_key: str
    requested_scopes: list = Field(default_factory=list)
