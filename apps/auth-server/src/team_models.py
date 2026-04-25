"""
Team Management Models
Issue #1345 Week 3: Team and Organization Management
"""
from datetime import datetime
from typing import Optional, List
from enum import Enum
import uuid

from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, Text, JSON, Integer, Index
from sqlalchemy.orm import relationship
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from pydantic import BaseModel, EmailStr, Field, validator
from src.models import Base


# ============================================================================
# Enums
# ============================================================================

class MemberRole(str, Enum):
    """Team member role"""
    OWNER = "owner"        # Full control, can delete team
    ADMIN = "admin"        # Can manage members and settings
    MAINTAINER = "maintainer"  # Can manage project, approve changes
    DEVELOPER = "developer"    # Can create/modify resources
    REVIEWER = "reviewer"      # Can review but not approve
    VIEWER = "viewer"          # Read-only access


class TeamStatus(str, Enum):
    """Team status"""
    ACTIVE = "active"
    ARCHIVED = "archived"
    SUSPENDED = "suspended"


class OrganizationPlan(str, Enum):
    """Organization subscription plan"""
    FREE = "free"              # Up to 3 teams, 5 members
    PRO = "pro"                # Up to 50 teams, 100 members
    ENTERPRISE = "enterprise"  # Unlimited


# ============================================================================
# SQLAlchemy Models
# ============================================================================

class Organization(Base):
    """Organization"""
    __tablename__ = "organizations"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Basic Information
    name = Column(String(255), nullable=False)
    slug = Column(String(255), nullable=False, unique=True, index=True)  # URL-friendly name
    description = Column(Text, nullable=True)
    logo_url = Column(String(512), nullable=True)
    website_url = Column(String(512), nullable=True)
    
    # Billing & Plan
    plan = Column(String(32), default=OrganizationPlan.FREE)
    max_teams = Column(Integer, default=3)  # Depends on plan
    max_members = Column(Integer, default=5)
    
    # Metadata
    owner_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Settings
    settings = Column(JSON, default=dict)  # Custom organization settings
    
    # Relationships
    owner = relationship("User", foreign_keys=[owner_id])
    teams = relationship("Team", back_populates="organization", cascade="all, delete-orphan")
    members = relationship("OrganizationMember", back_populates="organization", cascade="all, delete-orphan")
    
    __table_args__ = (
        Index("ix_organizations_slug", "slug"),
        Index("ix_organizations_owner_id", "owner_id"),
    )


class Team(Base):
    """Team within an organization"""
    __tablename__ = "teams"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # Organization reference
    organization_id = Column(PG_UUID(as_uuid=True), ForeignKey("organizations.id"), nullable=False)
    
    # Basic Information
    name = Column(String(255), nullable=False)
    slug = Column(String(255), nullable=False)  # Unique within org
    description = Column(Text, nullable=True)
    avatar_url = Column(String(512), nullable=True)
    
    # Team Status
    status = Column(String(32), default=TeamStatus.ACTIVE)
    
    # Metadata
    owner_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Settings
    settings = Column(JSON, default=dict)
    
    # Relationships
    organization = relationship("Organization", back_populates="teams")
    owner = relationship("User", foreign_keys=[owner_id])
    members = relationship("TeamMember", back_populates="team", cascade="all, delete-orphan")
    
    __table_args__ = (
        Index("ix_teams_org_id_slug", "organization_id", "slug"),
        Index("ix_teams_owner_id", "owner_id"),
    )


class TeamMember(Base):
    """Team membership"""
    __tablename__ = "team_members"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # References
    team_id = Column(PG_UUID(as_uuid=True), ForeignKey("teams.id"), nullable=False)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    
    # Role
    role = Column(String(32), default=MemberRole.DEVELOPER)
    
    # Status
    invited_at = Column(DateTime, default=datetime.utcnow)
    joined_at = Column(DateTime, nullable=True)  # When user accepted invitation
    
    # Permissions (per-member overrides)
    custom_permissions = Column(JSON, default=dict)  # Override default role permissions
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    team = relationship("Team", back_populates="members")
    user = relationship("User", back_populates="team_memberships")
    
    __table_args__ = (
        Index("ix_team_members_team_id_user_id", "team_id", "user_id"),
        Index("ix_team_members_user_id", "user_id"),
    )


class OrganizationMember(Base):
    """Organization-level membership"""
    __tablename__ = "organization_members"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # References
    organization_id = Column(PG_UUID(as_uuid=True), ForeignKey("organizations.id"), nullable=False)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    
    # Role (at org level)
    role = Column(String(32), default=MemberRole.DEVELOPER)
    
    # Status
    invited_at = Column(DateTime, default=datetime.utcnow)
    joined_at = Column(DateTime, nullable=True)
    
    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    organization = relationship("Organization", back_populates="members")
    user = relationship("User", back_populates="org_memberships")
    
    __table_args__ = (
        Index("ix_org_members_org_id_user_id", "organization_id", "user_id"),
    )


class TeamInvitation(Base):
    """Pending team invitations"""
    __tablename__ = "team_invitations"
    
    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    
    # References
    team_id = Column(PG_UUID(as_uuid=True), ForeignKey("teams.id"), nullable=False)
    invited_by_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    
    # Invitee
    invitee_email = Column(String(255), nullable=False)
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # If user exists
    
    # Role
    role = Column(String(32), default=MemberRole.DEVELOPER)
    
    # Invitation Token
    token = Column(String(256), nullable=False, unique=True)
    
    # Status
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
    accepted_at = Column(DateTime, nullable=True)
    declined_at = Column(DateTime, nullable=True)
    
    # Relationships
    team = relationship("Team")
    invited_by = relationship("User", foreign_keys=[invited_by_id])
    user = relationship("User", foreign_keys=[user_id])


# ============================================================================
# User Relationships
# ============================================================================

# Add to User model (reference only, defined in user_models.py)
# team_memberships = relationship("TeamMember", back_populates="user")
# org_memberships = relationship("OrganizationMember", back_populates="user")


# ============================================================================
# Pydantic Models
# ============================================================================

class OrganizationCreateRequest(BaseModel):
    """Request to create organization"""
    name: str = Field(..., min_length=1, max_length=255)
    slug: str = Field(..., min_length=1, max_length=255, pattern="^[a-z0-9-]+$")
    description: Optional[str] = Field(None, max_length=500)
    website_url: Optional[str] = None


class OrganizationResponse(BaseModel):
    """Organization response"""
    id: str
    name: str
    slug: str
    description: Optional[str] = None
    logo_url: Optional[str] = None
    plan: str
    max_teams: int
    max_members: int
    owner_id: str
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class TeamCreateRequest(BaseModel):
    """Request to create team"""
    name: str = Field(..., min_length=1, max_length=255)
    slug: str = Field(..., min_length=1, max_length=255, pattern="^[a-z0-9-]+$")
    description: Optional[str] = Field(None, max_length=500)


class TeamResponse(BaseModel):
    """Team response"""
    id: str
    organization_id: str
    name: str
    slug: str
    description: Optional[str] = None
    avatar_url: Optional[str] = None
    status: str
    owner_id: str
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class TeamMemberResponse(BaseModel):
    """Team member response"""
    id: str
    team_id: str
    user_id: str
    role: str
    invited_at: datetime
    joined_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class TeamInvitationCreateRequest(BaseModel):
    """Request to invite user to team"""
    invitee_email: EmailStr
    role: str = Field(default=MemberRole.DEVELOPER)
    
    @validator('role')
    def validate_role(cls, v):
        allowed = [r.value for r in MemberRole]
        if v not in allowed:
            raise ValueError(f'Invalid role. Must be one of: {", ".join(allowed)}')
        return v


class TeamInvitationResponse(BaseModel):
    """Team invitation response"""
    id: str
    team_id: str
    invitee_email: str
    role: str
    created_at: datetime
    expires_at: datetime
    accepted_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True
