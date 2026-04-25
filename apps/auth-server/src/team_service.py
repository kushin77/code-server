"""
Team Management Service
Issue #1345 Week 3: Team and Organization Management
"""
import uuid
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
import logging
import secrets

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from src.user_models import User
from src.team_models import Organization, Team, TeamMember, OrganizationMember, TeamInvitation

logger = logging.getLogger(__name__)


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
    
    # Plan-based limits
    PLAN_LIMITS = {
        "free": {"max_teams": 1, "max_members": 5},
        "pro": {"max_teams": 50, "max_members": 100},
        "enterprise": {"max_teams": 999, "max_members": 9999},
    }

    def create_organization(
        self,
        owner_id: str,
        name: str,
        slug: str,
        description: Optional[str] = None,
        website_url: Optional[str] = None,
        plan: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Create new organization"""

        try:
            owner = self._get_user(owner_id)
            if not owner:
                raise ValueError(f"Owner user {owner_id} not found")

            if self._org_slug_exists(slug):
                raise ValueError(f"Slug '{slug}' already exists")

            limits = self.PLAN_LIMITS.get(plan or "free", self.PLAN_LIMITS["free"])

            org = self._create_org(
                owner_id=owner_id,
                name=name,
                slug=slug,
                description=description,
                website_url=website_url,
                plan=plan or "free",
                max_teams=limits["max_teams"],
                max_members=limits["max_members"],
            )

            logger.info(f"Created organization {org.id} ({name})")

            return {
                "id": str(org.id),
                "name": org.name,
                "slug": org.slug,
                "owner_id": str(org.owner_id),
                "plan": org.plan,
                "max_teams": org.max_teams,
                "max_members": org.max_members,
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
        """Update organization"""

        org = self._get_org(org_id)
        if not org:
            raise ValueError(f"Organization {org_id} not found")

        if str(org.owner_id) != str(caller_id):
            raise PermissionError("Only organization owner can update organization")

        updateable_fields = ["name", "description", "website_url", "logo_url"]
        for field in updateable_fields:
            if field in kwargs:
                setattr(org, field, kwargs[field])

        org.updated_at = datetime.utcnow()
        self.db.flush()

        logger.info(f"Updated organization {org_id}")

        return {
            "id": str(org.id),
            "name": org.name,
            "slug": org.slug,
            "status": "updated",
        }

    def delete_organization(self, org_id: str, caller_id: str = None) -> Dict[str, Any]:
        """Delete organization"""

        org = self._get_org(org_id)
        if not org:
            raise ValueError(f"Organization {org_id} not found")

        if caller_id and str(org.owner_id) != caller_id:
            raise PermissionError("Only organization owner can delete organization")

        self.db.delete(org)
        self.db.flush()
        logger.info(f"Deleted organization {org_id}")

        return {"id": str(org_id), "deleted": True, "status": "deleted"}
    
    # ====================================================================
    # Team Management
    # ====================================================================
    
    def update_team(
        self,
        team_id: str,
        caller_id: str = None,
        **kwargs
    ) -> Dict[str, Any]:
        """Update team"""

        team = self._get_team(team_id)
        if not team:
            raise ValueError(f"Team {team_id} not found")

        updateable_fields = ["name", "description", "slug"]
        for field in updateable_fields:
            if field in kwargs:
                setattr(team, field, kwargs[field])

        team.updated_at = datetime.utcnow()
        self.db.flush()

        return {"id": str(team.id), "name": team.name, "status": "updated"}

    def delete_team(self, team_id: str, caller_id: str = None) -> Dict[str, Any]:
        """Delete team"""

        team = self._get_team(team_id)
        if not team:
            raise ValueError(f"Team {team_id} not found")

        self.db.delete(team)
        self.db.flush()

        return {"id": str(team_id), "deleted": True, "status": "deleted"}

    def add_org_member(self, org_id: str, user_id: str, role: str = "member") -> Dict[str, Any]:
        """Add member to organization"""

        org = self._get_org(org_id)
        if not org:
            raise ValueError(f"Organization {org_id} not found")

        member = OrganizationMember(
            id=uuid.uuid4(),
            organization_id=org_id,
            user_id=user_id,
            role=role,
        )
        self.db.add(member)
        self.db.flush()

        return {"org_id": str(org_id), "user_id": str(user_id), "role": role, "added": True}

    def list_org_members(self, org_id: str) -> List[Dict[str, Any]]:
        """List organization members"""

        members = self.db.query(OrganizationMember).filter(
            OrganizationMember.organization_id == org_id
        ).all()

        return {"members": [
            {
                "user_id": str(m.user_id),
                "role": m.role,
            }
            for m in members
        ]}

    def create_team(
        self,
        org_id: str,
        creator_id: str = None,
        name: str = None,
        slug: str = None,
        description: Optional[str] = None,
        owner_id: str = None,
    ) -> Dict[str, Any]:
        """Create new team within organization"""
        
        effective_creator = creator_id or owner_id

        try:
            org = self._get_org(org_id)
            if not org:
                raise ValueError(f"Organization {org_id} not found")

            if slug and self._team_slug_exists_in_org(org_id, slug):
                raise ValueError(f"Team slug '{slug}' already exists in organization")

            team = self._create_team(
                organization_id=org_id,
                owner_id=effective_creator,
                name=name,
                slug=slug,
                description=description,
            )

            logger.info(f"Created team {team.id} ({name}) in org {org_id}")

            return {
                "id": str(team.id),
                "organization_id": str(org_id),
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
        user_id: str,
        role: str = "developer",
        caller_id: str = None,
        email: str = None,
    ) -> Dict[str, Any]:
        """Add member to team"""

        try:
            team = self._get_team(team_id)
            if not team:
                raise ValueError(f"Team {team_id} not found")

            if self._is_team_member(team_id, str(user_id)):
                raise ValueError(f"User {user_id} is already a member of this team")

            # Check org member limit
            org = self._get_org(str(team.organization_id))
            if org:
                member_count = self._count_team_members(team_id)
                if member_count >= org.max_members:
                    raise ValueError(f"Team has reached member limit ({org.max_members})")

            self._add_team_member(team_id=str(team_id), user_id=str(user_id), role=role)

            logger.info(f"Added user {user_id} to team {team_id} as {role}")

            return {
                "added": True,
                "team_id": str(team_id),
                "user_id": str(user_id),
                "role": role,
            }

        except Exception as e:
            logger.error(f"Failed to add team member: {str(e)}")
            raise
    
    def remove_team_member(
        self,
        team_id: str,
        user_id: str,
        caller_id: str = None,
    ) -> Dict[str, Any]:
        """Remove member from team"""

        team = self._get_team(team_id)
        if not team:
            raise ValueError(f"Team {team_id} not found")

        self._remove_team_member(str(team_id), str(user_id))

        logger.info(f"Removed user {user_id} from team {team_id}")

        return {"removed": True, "team_id": str(team_id), "user_id": str(user_id)}
    
    def update_member_role(
        self,
        team_id: str,
        user_id: str,
        role: str,
        caller_id: str = None,
    ) -> Dict[str, Any]:
        """Update team member role (alias for update_team_member_role)"""
        self._update_member_role(str(team_id), str(user_id), role)
        return {"role": role, "team_id": str(team_id), "user_id": str(user_id)}

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
        caller_id: str = None,
        invitee_email: str = None,
        email: str = None,
        role: str = "developer",
        invited_by: str = None,
    ) -> Dict[str, Any]:
        """Invite user to team via email"""
        
        invitee_email = invitee_email or email
        caller_id = caller_id or invited_by

        try:
            team = self._get_team(team_id)
            if not team:
                raise ValueError(f"Team {team_id} not found")

            existing_user = self._get_user_by_email(invitee_email) if invitee_email else None
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

            expires_in_seconds = 7 * 24 * 3600
            return {
                "token": token,
                "email": invitee_email,
                "expires_in": expires_in_seconds,
                "status": "invited",
                "team_id": team_id,
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
            self.db.flush()

            logger.info(f"User {user_id} accepted invitation to team {invitation.team_id}")

            return {"accepted": True, "team_id": str(invitation.team_id), "user_id": user_id}

        except Exception as e:
            logger.error(f"Failed to accept invitation: {str(e)}")
            raise
    
    def revoke_invitation(self, token: str) -> Dict[str, Any]:
        """Revoke a team invitation"""
        invitation = self._get_invitation_by_token(token)
        if not invitation:
            raise ValueError("Invitation not found")
        invitation.status = "revoked"
        self.db.flush()
        return {"revoked": True, "token": token}

    # ====================================================================
    # Permission Checking
    # ====================================================================

    def check_team_permission(
        self,
        user_id: str,
        team_id: str,
        required_permission: str = None,
        permission: str = None,
    ) -> Dict[str, Any]:
        """Check if user has permission in team, returns dict with 'allowed' key"""

        effective_permission = required_permission or permission

        # Check if user is the team owner (owner has all permissions)
        team = self._get_team(team_id)
        if team and str(team.owner_id) == str(user_id):
            return {"allowed": True, "role": "owner", "permission": effective_permission}

        role = self._get_user_team_role(str(user_id), str(team_id))
        if not role:
            return {"allowed": False, "role": None, "permission": effective_permission}

        permissions_by_role = {
            "owner": ["read", "write", "admin", "delete"],
            "admin": ["read", "write", "admin"],
            "maintainer": ["read", "write", "approve"],
            "developer": ["read", "write"],
            "reviewer": ["read", "approve"],
            "viewer": ["read"],
        }

        allowed_permissions = permissions_by_role.get(role, [])
        allowed = (effective_permission in allowed_permissions) if effective_permission else bool(role)
        return {"allowed": allowed, "role": role, "permission": effective_permission}
    
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
        return self.db.query(User).filter(User.id == user_id).first()

    def _get_user_by_email(self, email: str) -> Optional[Any]:
        return self.db.query(User).filter(User.email == email).first()

    def _get_org(self, org_id: str) -> Optional[Any]:
        return self.db.query(Organization).filter(Organization.id == org_id).first()

    def _get_team(self, team_id: str) -> Optional[Any]:
        return self.db.query(Team).filter(Team.id == team_id).first()

    def _create_org(self, **kwargs) -> Any:
        org = Organization(**kwargs)
        self.db.add(org)
        self.db.flush()
        return org

    def _create_team(self, **kwargs) -> Any:
        team = Team(**kwargs)
        self.db.add(team)
        self.db.flush()
        return team

    def _org_slug_exists(self, slug: str) -> bool:
        return self.db.query(Organization).filter(Organization.slug == slug).first() is not None

    def _team_slug_exists_in_org(self, org_id: str, slug: str) -> bool:
        return self.db.query(Team).filter(
            and_(Team.organization_id == org_id, Team.slug == slug)
        ).first() is not None

    def _count_org_teams(self, org_id: str) -> int:
        return self.db.query(Team).filter(Team.organization_id == org_id).count()

    def _count_team_members(self, team_id: str) -> int:
        return self.db.query(TeamMember).filter(TeamMember.team_id == team_id).count()

    def _get_user_org_role(self, user_id: str, org_id: str) -> Optional[str]:
        member = self.db.query(OrganizationMember).filter(
            and_(OrganizationMember.user_id == user_id, OrganizationMember.organization_id == org_id)
        ).first()
        return member.role if member else None

    def _get_user_team_role(self, user_id: str, team_id: str) -> Optional[str]:
        member = self.db.query(TeamMember).filter(
            and_(TeamMember.user_id == user_id, TeamMember.team_id == team_id)
        ).first()
        return member.role if member else None

    def _is_team_member(self, team_id: str, user_id: str) -> bool:
        return self.db.query(TeamMember).filter(
            and_(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        ).first() is not None

    def _add_team_member(self, team_id: str, user_id: str, role: str) -> Any:
        member = TeamMember(
            id=uuid.uuid4(),
            team_id=team_id,
            user_id=user_id,
            role=role,
            joined_at=datetime.utcnow(),
        )
        self.db.add(member)
        self.db.flush()
        return member

    def _remove_team_member(self, team_id: str, user_id: str) -> None:
        member = self.db.query(TeamMember).filter(
            and_(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        ).first()
        if member:
            self.db.delete(member)
            self.db.flush()

    def _update_member_role(self, team_id: str, user_id: str, role: str) -> None:
        member = self.db.query(TeamMember).filter(
            and_(TeamMember.team_id == team_id, TeamMember.user_id == user_id)
        ).first()
        if member:
            member.role = role
            self.db.flush()

    def _get_team_members(self, team_id: str) -> List[Any]:
        return self.db.query(TeamMember).filter(TeamMember.team_id == team_id).all()

    def _list_user_orgs(self, user_id: str) -> List[Any]:
        return self.db.query(OrganizationMember).filter(OrganizationMember.user_id == user_id).all()

    def _create_invitation(
        self,
        team_id: str,
        invitee_email: str,
        invited_by_id: str,
        role: str,
        token: str,
        expires_in_days: int,
    ) -> Any:
        inv = TeamInvitation(
            id=uuid.uuid4(),
            team_id=team_id,
            invitee_email=invitee_email,
            invited_by_id=invited_by_id,
            role=role,
            token=token,
            expires_at=datetime.utcnow() + timedelta(days=expires_in_days),
            status="pending",
        )
        self.db.add(inv)
        self.db.flush()
        return inv

    def _get_invitation_by_token(self, token: str) -> Optional[Any]:
        return self.db.query(TeamInvitation).filter(TeamInvitation.token == token).first()

    def _send_invitation_email(self, email: str, team_name: str, invitation_url: str) -> None:
        logger.info(f"Sending invitation email to {email} for team {team_name}")
