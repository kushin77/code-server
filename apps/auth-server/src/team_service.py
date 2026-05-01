"""
Team Management Service
Issue #1345 Week 3: Team and Organization Management
"""
import uuid
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from log import get_logger
import secrets

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

logger = get_logger(__name__)


# ============================================================================
# Team Management Service
# ============================================================================

class TeamManagementService:
    """Service for team and organization management"""
    
    def __init__(self, db_session: Session, config):
        self.db = db_session
        self.config = config
    
    # ====================================================================
    # Organization Management
    # ====================================================================
    
    def create_organization(
        self,
        owner_id: str,
        name: str,
        slug: str,
        description: Optional[str] = None,
        website_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create new organization"""
        
        try:
            # Verify owner exists
            owner = self._get_user(owner_id)
            if not owner:
                raise ValueError(f"Owner user {owner_id} not found")
            
            # Check slug uniqueness
            if self._org_slug_exists(slug):
                raise ValueError(f"Organization slug '{slug}' already exists")
            
            # Create organization
            org = self._create_org(
                owner_id=owner_id,
                name=name,
                slug=slug,
                description=description,
                website_url=website_url,
            )
            
            logger.info(f"Created organization {org.id} ({name})")
            
            return {
                "id": str(org.id),
                "name": org.name,
                "slug": org.slug,
                "status": "created",
            }
        
        except Exception as e:
            logger.error(f"Failed to create organization: {str(e)}")
            raise
    
    def get_organization(self, org_id: str) -> Optional[Dict[str, Any]]:
        """Get organization by ID"""
        org = self._get_org(org_id)
        if not org:
            return None
        
        return {
            "id": str(org.id),
            "name": org.name,
            "slug": org.slug,
            "description": org.description,
            "plan": org.plan,
            "owner_id": str(org.owner_id),
            "created_at": org.created_at.isoformat(),
        }
    
    def list_user_organizations(self, user_id: str) -> List[Dict[str, Any]]:
        """List organizations where user is a member or owner"""
        orgs = self._list_user_orgs(user_id)
        
        return [
            {
                "id": str(org.id),
                "name": org.name,
                "slug": org.slug,
                "role": self._get_user_org_role(user_id, str(org.id)),
            }
            for org in orgs
        ]
    
    def update_organization(
        self,
        org_id: str,
        caller_id: str,
        **kwargs
    ) -> Dict[str, Any]:
        """Update organization (owner only)"""
        
        org = self._get_org(org_id)
        if not org:
            raise ValueError(f"Organization {org_id} not found")
        
        # Verify caller is owner
        if str(org.owner_id) != caller_id:
            raise PermissionError("Only organization owner can update organization")
        
        # Update fields
        updateable_fields = ["name", "description", "website_url", "logo_url"]
        for field in updateable_fields:
            if field in kwargs:
                setattr(org, field, kwargs[field])
        
        org.updated_at = datetime.utcnow()
        # In production: self.db.commit()
        
        logger.info(f"Updated organization {org_id}")
        
        return {"id": str(org.id), "status": "updated"}
    
    def delete_organization(self, org_id: str, caller_id: str) -> Dict[str, Any]:
        """Delete organization (owner only)"""
        
        org = self._get_org(org_id)
        if not org:
            raise ValueError(f"Organization {org_id} not found")
        
        if str(org.owner_id) != caller_id:
            raise PermissionError("Only organization owner can delete organization")
        
        # In production: self.db.delete(org); self.db.commit()
        logger.info(f"Deleted organization {org_id}")
        
        return {"id": str(org_id), "status": "deleted"}
    
    # ====================================================================
    # Team Management
    # ====================================================================
    
    def create_team(
        self,
        org_id: str,
        creator_id: str,
        name: str,
        slug: str,
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create new team within organization"""
        
        try:
            # Verify organization exists
            org = self._get_org(org_id)
            if not org:
                raise ValueError(f"Organization {org_id} not found")
            
            # Verify creator is organization admin or owner
            creator_role = self._get_user_org_role(creator_id, org_id)
            if creator_role not in ["owner", "admin"]:
                raise PermissionError("Only admins can create teams")
            
            # Check slug uniqueness within organization
            if self._team_slug_exists_in_org(org_id, slug):
                raise ValueError(f"Team slug '{slug}' already exists in organization")
            
            # Check team limits
            team_count = self._count_org_teams(org_id)
            if team_count >= org.max_teams:
                raise ValueError(f"Organization has reached maximum teams ({org.max_teams})")
            
            # Create team
            team = self._create_team(
                org_id=org_id,
                owner_id=creator_id,
                name=name,
                slug=slug,
                description=description,
            )
            
            # Add creator as team owner
            self._add_team_member(
                team_id=str(team.id),
                user_id=creator_id,
                role="owner",
            )
            
            logger.info(f"Created team {team.id} ({name}) in org {org_id}")
            
            return {
                "id": str(team.id),
                "organization_id": org_id,
                "name": team.name,
                "slug": team.slug,
                "status": "created",
            }
        
        except Exception as e:
            logger.error(f"Failed to create team: {str(e)}")
            raise
    
    def get_team(self, team_id: str) -> Optional[Dict[str, Any]]:
        """Get team by ID"""
        team = self._get_team(team_id)
        if not team:
            return None
        
        members = self._get_team_members(team_id)
        
        return {
            "id": str(team.id),
            "organization_id": str(team.organization_id),
            "name": team.name,
            "slug": team.slug,
            "description": team.description,
            "status": team.status,
            "member_count": len(members),
            "created_at": team.created_at.isoformat(),
        }
    
    def list_team_members(self, team_id: str) -> List[Dict[str, Any]]:
        """List team members"""
        members = self._get_team_members(team_id)
        
        return [
            {
                "user_id": str(member.user_id),
                "role": member.role,
                "joined_at": member.joined_at.isoformat() if member.joined_at else None,
            }
            for member in members
        ]
    
    def add_team_member(
        self,
        team_id: str,
        caller_id: str,
        user_id: str,
        role: str = "developer",
    ) -> Dict[str, Any]:
        """Add member to team"""
        
        try:
            team = self._get_team(team_id)
            if not team:
                raise ValueError(f"Team {team_id} not found")
            
            # Verify caller is team admin/owner
            caller_role = self._get_user_team_role(caller_id, team_id)
            if caller_role not in ["owner", "admin", "maintainer"]:
                raise PermissionError("Only admins can add team members")
            
            # Verify user exists
            user = self._get_user(user_id)
            if not user:
                raise ValueError(f"User {user_id} not found")
            
            # Check if already member
            if self._is_team_member(team_id, user_id):
                return {"status": "already_member", "user_id": user_id}
            
            # Check team member limit
            member_count = self._count_team_members(team_id)
            org = self._get_org(str(team.organization_id))
            if member_count >= org.max_members:
                raise ValueError("Team has reached member limit")
            
            # Add member
            membership = self._add_team_member(
                team_id=team_id,
                user_id=user_id,
                role=role,
            )
            
            logger.info(f"Added user {user_id} to team {team_id} as {role}")
            
            return {
                "status": "added",
                "team_id": team_id,
                "user_id": user_id,
                "role": role,
            }
        
        except Exception as e:
            logger.error(f"Failed to add team member: {str(e)}")
            raise
    
    def remove_team_member(
        self,
        team_id: str,
        caller_id: str,
        user_id: str,
    ) -> Dict[str, Any]:
        """Remove member from team"""
        
        team = self._get_team(team_id)
        if not team:
            raise ValueError(f"Team {team_id} not found")
        
        # Verify caller is team admin/owner
        caller_role = self._get_user_team_role(caller_id, team_id)
        if caller_role not in ["owner", "admin"]:
            raise PermissionError("Only admins can remove team members")
        
        # Cannot remove team owner
        user_role = self._get_user_team_role(user_id, team_id)
        if user_role == "owner":
            raise ValueError("Cannot remove team owner")
        
        # Remove member
        self._remove_team_member(team_id, user_id)
        
        logger.info(f"Removed user {user_id} from team {team_id}")
        
        return {"status": "removed", "team_id": team_id, "user_id": user_id}
    
    def update_team_member_role(
        self,
        team_id: str,
        caller_id: str,
        user_id: str,
        new_role: str,
    ) -> Dict[str, Any]:
        """Update team member role"""
        
        team = self._get_team(team_id)
        if not team:
            raise ValueError(f"Team {team_id} not found")
        
        # Verify caller is team admin/owner
        caller_role = self._get_user_team_role(caller_id, team_id)
        if caller_role not in ["owner", "admin"]:
            raise PermissionError("Only admins can update member roles")
        
        # Cannot change team owner role
        user_role = self._get_user_team_role(user_id, team_id)
        if user_role == "owner":
            raise ValueError("Cannot change team owner role")
        
        # Update role
        self._update_member_role(team_id, user_id, new_role)
        
        logger.info(f"Updated user {user_id} role in team {team_id} to {new_role}")
        
        return {
            "status": "updated",
            "team_id": team_id,
            "user_id": user_id,
            "role": new_role,
        }
    
    # ====================================================================
    # Team Invitations
    # ====================================================================
    
    def invite_to_team(
        self,
        team_id: str,
        caller_id: str,
        invitee_email: str,
        role: str = "developer",
    ) -> Dict[str, Any]:
        """Invite user to team via email"""
        
        try:
            team = self._get_team(team_id)
            if not team:
                raise ValueError(f"Team {team_id} not found")
            
            # Verify caller is team admin/owner
            caller_role = self._get_user_team_role(caller_id, team_id)
            if caller_role not in ["owner", "admin"]:
                raise PermissionError("Only admins can invite team members")
            
            # Check if user already exists and is member
            existing_user = self._get_user_by_email(invitee_email)
            if existing_user and self._is_team_member(team_id, str(existing_user.id)):
                return {"status": "already_member", "email": invitee_email}
            
            # Generate invitation token
            token = secrets.token_urlsafe(32)
            
            # Create invitation
            invitation = self._create_invitation(
                team_id=team_id,
                invitee_email=invitee_email,
                invited_by_id=caller_id,
                role=role,
                token=token,
                expires_in_days=7,
            )
            
            # Send invitation email (if email service configured)
            invitation_url = f"{self.config.JWT_ISSUER}/teams/invite/{token}"
            self._send_invitation_email(
                email=invitee_email,
                team_name=team.name,
                invitation_url=invitation_url,
            )
            
            logger.info(f"Invited {invitee_email} to team {team_id}")
            
            return {
                "status": "invited",
                "team_id": team_id,
                "email": invitee_email,
                "expires_at": invitation.expires_at.isoformat(),
            }
        
        except Exception as e:
            logger.error(f"Failed to invite to team: {str(e)}")
            raise
    
    def accept_team_invitation(self, token: str, user_id: str) -> Dict[str, Any]:
        """Accept team invitation"""
        
        try:
            # Get invitation
            invitation = self._get_invitation_by_token(token)
            if not invitation:
                raise ValueError("Invalid or expired invitation token")
            
            # Check expiry
            if invitation.expires_at < datetime.utcnow():
                raise ValueError("Invitation has expired")
            
            # Add user to team
            self._add_team_member(
                team_id=str(invitation.team_id),
                user_id=user_id,
                role=invitation.role,
            )
            
            # Mark invitation as accepted
            invitation.accepted_at = datetime.utcnow()
            # In production: self.db.commit()
            
            logger.info(f"User {user_id} accepted invitation to team {invitation.team_id}")
            
            return {
                "status": "accepted",
                "team_id": str(invitation.team_id),
                "user_id": user_id,
            }
        
        except Exception as e:
            logger.error(f"Failed to accept invitation: {str(e)}")
            raise
    
    # ====================================================================
    # Permission Checking
    # ====================================================================
    
    def check_team_permission(
        self,
        user_id: str,
        team_id: str,
        required_permission: str,
    ) -> bool:
        """Check if user has permission in team"""
        
        role = self._get_user_team_role(user_id, team_id)
        if not role:
            return False
        
        # Role-based permission mapping
        permissions_by_role = {
            "owner": ["read", "write", "admin", "delete"],
            "admin": ["read", "write", "admin"],
            "maintainer": ["read", "write", "approve"],
            "developer": ["read", "write"],
            "reviewer": ["read", "approve"],
            "viewer": ["read"],
        }
        
        allowed_permissions = permissions_by_role.get(role, [])
        return required_permission in allowed_permissions
    
    def check_org_permission(
        self,
        user_id: str,
        org_id: str,
        required_permission: str,
    ) -> bool:
        """Check if user has permission in organization"""
        
        role = self._get_user_org_role(user_id, org_id)
        if not role:
            return False
        
        # Role-based permission mapping
        permissions_by_role = {
            "owner": ["read", "write", "admin", "delete", "billing"],
            "admin": ["read", "write", "admin"],
            "maintainer": ["read", "write"],
            "developer": ["read", "write"],
            "viewer": ["read"],
        }
        
        allowed_permissions = permissions_by_role.get(role, [])
        return required_permission in allowed_permissions
    
    # ====================================================================
    # Private Helper Methods
    # ====================================================================
    
    def _get_user(self, user_id: str) -> Optional[Any]:
        """Get user by ID"""
        # In production: return self.db.query(User).filter(User.id == user_id).first()
        return None
    
    def _get_user_by_email(self, email: str) -> Optional[Any]:
        """Get user by email"""
        # In production: return self.db.query(User).filter(User.email == email).first()
        return None
    
    def _get_org(self, org_id: str) -> Optional[Any]:
        """Get organization by ID"""
        # In production: return self.db.query(Organization).filter(Organization.id == org_id).first()
        return None
    
    def _get_team(self, team_id: str) -> Optional[Any]:
        """Get team by ID"""
        # In production: return self.db.query(Team).filter(Team.id == team_id).first()
        return None
    
    def _create_org(self, **kwargs) -> Any:
        """Create organization"""
        # In production: create Organization object, add to session, commit
        return type('Organization', (), kwargs)()
    
    def _create_team(self, **kwargs) -> Any:
        """Create team"""
        return type('Team', (), kwargs)()
    
    def _org_slug_exists(self, slug: str) -> bool:
        """Check if org slug exists"""
        # In production: return self.db.query(Organization).filter(Organization.slug == slug).first() is not None
        return False
    
    def _team_slug_exists_in_org(self, org_id: str, slug: str) -> bool:
        """Check if team slug exists in org"""
        return False
    
    def _count_org_teams(self, org_id: str) -> int:
        """Count teams in organization"""
        return 0
    
    def _count_team_members(self, team_id: str) -> int:
        """Count team members"""
        return 0
    
    def _get_user_org_role(self, user_id: str, org_id: str) -> Optional[str]:
        """Get user's role in organization"""
        # In production: query OrganizationMember
        return None
    
    def _get_user_team_role(self, user_id: str, team_id: str) -> Optional[str]:
        """Get user's role in team"""
        # In production: query TeamMember
        return None
    
    def _is_team_member(self, team_id: str, user_id: str) -> bool:
        """Check if user is team member"""
        return False
    
    def _add_team_member(self, team_id: str, user_id: str, role: str) -> Any:
        """Add member to team"""
        return type('TeamMember', (), {"user_id": user_id, "role": role})()
    
    def _remove_team_member(self, team_id: str, user_id: str) -> None:
        """Remove member from team"""
        pass
    
    def _update_member_role(self, team_id: str, user_id: str, role: str) -> None:
        """Update member role"""
        pass
    
    def _get_team_members(self, team_id: str) -> List[Any]:
        """Get all team members"""
        return []
    
    def _list_user_orgs(self, user_id: str) -> List[Any]:
        """List user's organizations"""
        return []
    
    def _create_invitation(
        self,
        team_id: str,
        invitee_email: str,
        invited_by_id: str,
        role: str,
        token: str,
        expires_in_days: int,
    ) -> Any:
        """Create team invitation"""
        expires_at = datetime.utcnow() + timedelta(days=expires_in_days)
        return type('TeamInvitation', (), {
            "team_id": team_id,
            "invitee_email": invitee_email,
            "role": role,
            "token": token,
            "expires_at": expires_at,
        })()
    
    def _get_invitation_by_token(self, token: str) -> Optional[Any]:
        """Get invitation by token"""
        # In production: return self.db.query(TeamInvitation).filter(TeamInvitation.token == token).first()
        return None
    
    def _send_invitation_email(self, email: str, team_name: str, invitation_url: str) -> None:
        """Send invitation email"""
        logger.info(f"Sending invitation email to {email} for team {team_name}")
        # In production: use email service (SendGrid, etc.)
