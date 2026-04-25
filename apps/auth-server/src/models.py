"""
OAuth2 Authorization Server - Database Models
Issue #1545: Enterprise SSO Portal
"""
from datetime import datetime, timedelta
from typing import Optional, List
from enum import Enum
import uuid

from sqlalchemy import Column, String, Integer, DateTime, Boolean, ForeignKey, Text, Enum as SQLEnum, JSON, UniqueConstraint
from sqlalchemy.orm import relationship, declarative_base
from sqlalchemy.dialects.postgresql import UUID as PG_UUID

Base = declarative_base()


# ============================================================================
# Enums
# ============================================================================

class OAuthProviderType(str, Enum):
    """Supported OAuth2 providers"""
    GITHUB = "github"
    GOOGLE = "google"
    MICROSOFT = "microsoft"
    OKTA = "okta"


class TokenType(str, Enum):
    """OAuth2 token types"""
    ACCESS = "access"
    REFRESH = "refresh"
    ID = "id"


# ============================================================================
# OAuth2 Provider Configuration
# ============================================================================

class OAuthProvider(Base):
    """OAuth2 Provider Configuration"""
    __tablename__ = "oauth_providers"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider_type = Column(SQLEnum(OAuthProviderType), nullable=False, unique=True)
    client_id = Column(String(255), nullable=False, index=True)
    client_secret = Column(String(512), nullable=False)  # Store encrypted in production
    auth_url = Column(String(512), nullable=False)
    token_url = Column(String(512), nullable=False)
    user_info_url = Column(String(512), nullable=False)
    redirect_uri = Column(String(512), nullable=False)
    scopes = Column(JSON, nullable=False, default=list)  # ["user:email", "read:user"]
    
    # Configuration
    enabled = Column(Boolean, default=True)
    auto_provision_users = Column(Boolean, default=True)  # Auto-create users on first login
    require_email_verified = Column(Boolean, default=True)
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    connections = relationship("OAuthConnection", back_populates="provider", cascade="all, delete-orphan")
    
    __table_args__ = (
        UniqueConstraint("provider_type", name="uq_oauth_provider_type"),
    )


# ============================================================================
# OAuth2 Authorization Codes & Tokens
# ============================================================================

class AuthorizationCode(Base):
    """OAuth2 Authorization Code"""
    __tablename__ = "oauth_authorization_codes"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(256), nullable=False, unique=True, index=True)
    
    # Authorization request details
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    client_id = Column(String(255), nullable=False)
    redirect_uri = Column(String(512), nullable=False)
    scope = Column(String(1024), nullable=False)
    
    # PKCE support
    code_challenge = Column(String(128), nullable=True)
    code_challenge_method = Column(String(16), nullable=True)  # S256 or plain
    
    # State tracking
    is_used = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, default=lambda: datetime.utcnow() + timedelta(minutes=10))
    used_at = Column(DateTime, nullable=True)
    
    # Metadata
    ip_address = Column(String(45), nullable=True)  # IPv4 or IPv6


class OAuthToken(Base):
    """OAuth2 Token (Access, Refresh, ID Token)"""
    __tablename__ = "oauth_tokens"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    token = Column(Text, nullable=False, index=True)
    
    # Token details
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    client_id = Column(String(255), nullable=False)
    token_type = Column(SQLEnum(TokenType), nullable=False)
    
    # Expiry
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
    revoked = Column(Boolean, default=False)
    
    # Relationships
    user = relationship("User", back_populates="oauth_tokens")


# ============================================================================
# OAuth2 Connections (User <-> Provider)
# ============================================================================

class OAuthConnection(Base):
    """User OAuth2 Connection to External Provider"""
    __tablename__ = "oauth_connections"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # User reference
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    
    # Provider reference
    provider_id = Column(PG_UUID(as_uuid=True), ForeignKey("oauth_providers.id"), nullable=False)
    provider_user_id = Column(String(255), nullable=False)  # External provider's user ID
    
    # Connection details
    access_token = Column(Text, nullable=True)  # Store encrypted
    refresh_token = Column(Text, nullable=True)  # Store encrypted
    id_token = Column(Text, nullable=True)
    scope = Column(String(1024), nullable=False)
    
    # User info from provider
    provider_email = Column(String(255), nullable=True)
    provider_name = Column(String(255), nullable=True)
    provider_avatar_url = Column(String(512), nullable=True)
    provider_raw_data = Column(JSON, nullable=True)  # Store full provider response
    
    # Metadata
    is_primary = Column(Boolean, default=False)  # Primary auth method for user
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_used = Column(DateTime, nullable=True)
    
    # Relationships
    user = relationship("User", back_populates="oauth_connections")
    provider = relationship("OAuthProvider", back_populates="connections")
    
    __table_args__ = (
        UniqueConstraint("provider_id", "provider_user_id", name="uq_provider_user"),
    )


# ============================================================================
# OAuth2 Application/Client
# ============================================================================

class OAuthClient(Base):
    """OAuth2 Client Application (apps that use our auth server)"""
    __tablename__ = "oauth_clients"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Client details
    client_id = Column(String(255), nullable=False, unique=True, index=True)
    client_secret = Column(String(512), nullable=False)  # Store hashed in production
    client_name = Column(String(255), nullable=False)
    client_description = Column(Text, nullable=True)
    
    # Configuration
    redirect_uris = Column(JSON, nullable=False, default=list)  # ["https://app.example.com/callback"]
    allowed_scopes = Column(JSON, nullable=False, default=list)  # ["openid", "profile", "email"]
    grant_types = Column(JSON, nullable=False, default=list)  # ["authorization_code", "refresh_token"]
    
    # Authorization
    require_auth = Column(Boolean, default=True)
    require_pkce = Column(Boolean, default=True)
    token_endpoint_auth_method = Column(String(32), default="client_secret_basic")
    
    # Metadata
    logo_url = Column(String(512), nullable=True)
    owner_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    organization_id = Column(PG_UUID(as_uuid=True), ForeignKey("organizations.id"), nullable=True)
    
    enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    owner = relationship("User", back_populates="oauth_clients")
    organization = relationship("Organization")


# ============================================================================
# Audit Log
# ============================================================================

class OAuthAuditLog(Base):
    """OAuth2 Authorization & Token Audit Log"""
    __tablename__ = "oauth_audit_logs"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Event details
    event_type = Column(String(64), nullable=False, index=True)  # authorize, token_exchange, refresh, revoke
    status = Column(String(32), nullable=False)  # success, failure, denied
    
    # User/Client info
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    client_id = Column(String(255), nullable=True)
    provider = Column(String(64), nullable=True)  # github, google, etc.
    
    # Request details
    scope = Column(String(1024), nullable=True)
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(512), nullable=True)
    
    # Result
    error_message = Column(Text, nullable=True)
    audit_metadata = Column("metadata", JSON, nullable=True)
    
    # Timestamp
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    __table_args__ = (
        # Index for querying audit logs by user and date
        # create_index("ix_oauth_audit_user_date", "user_id", "created_at"),
    )


# ============================================================================
# Sessions (Reference to User & Organization models)
# ============================================================================

# Note: This file assumes User and Organization models exist in users.py
# We reference them via ForeignKey but don't define them here to avoid circular imports
# Expected schema:
# - users.id (UUID)
# - organizations.id (UUID)
