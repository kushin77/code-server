"""
Integration Tests - Team Management Endpoints
Issue #1537 Week 2: Integration Tests

Coverage:
- Organization CRUD operations
- Team CRUD operations
- Member management and invitations
- Role-based permissions
- Member limits enforcement per plan
- Permission matrix validation (owner/admin/developer/viewer)
"""
import pytest
import uuid
from datetime import datetime, timedelta

pytestmark = pytest.mark.integration


# ============================================================================
# Organization Management Tests
# ============================================================================

class TestOrganizationManagement:
    """Test organization CRUD operations"""
    
    def test_create_organization_success(self, team_service, test_user):
        """Test creating organization"""
        result = team_service.create_organization(
            owner_id=test_user.id,
            name="Acme Corp",
            slug="acme-corp",
        )
        
        assert result["id"] is not None
        assert result["name"] == "Acme Corp"
        assert result["slug"] == "acme-corp"
        assert result["owner_id"] == str(test_user.id)
    
    def test_create_organization_duplicate_slug(self, team_service, test_org, test_user):
        """Test duplicate slug is rejected"""
        with pytest.raises(ValueError, match="Slug.*exists"):
            team_service.create_organization(
                owner_id=test_user.id,
                name="Different Name",
                slug=test_org.slug,  # Duplicate
            )
    
    def test_create_organization_plan_limits(self, team_service, test_user):
        """Test plan-based team limits"""
        # Free plan
        free_org = team_service.create_organization(
            owner_id=test_user.id,
            name="Free Org",
            slug="free-org",
            plan="free",
        )
        
        assert free_org["max_teams"] == 1
        assert free_org["max_members"] == 5
        
        # Pro plan
        pro_org = team_service.create_organization(
            owner_id=test_user.id,
            name="Pro Org",
            slug="pro-org",
            plan="pro",
        )
        
        assert pro_org["max_teams"] == 50
        assert pro_org["max_members"] == 100
    
    def test_get_organization(self, team_service, test_org):
        """Test retrieving organization"""
        result = team_service.get_organization(test_org.id)
        
        assert result["id"] == str(test_org.id)
        assert result["name"] == test_org.name
    
    def test_update_organization(self, team_service, test_org, test_user, db_session):
        """Test updating organization"""
        result = team_service.update_organization(
            org_id=test_org.id,
            caller_id=test_user.id,
            name="Updated Org Name",
        )
        
        assert result["name"] == "Updated Org Name"
        
        # Verify in database
        db_session.refresh(test_org)
        assert test_org.name == "Updated Org Name"
    
    def test_delete_organization(self, team_service, test_org):
        """Test deleting organization"""
        result = team_service.delete_organization(test_org.id)
        
        assert result["deleted"] is True


# ============================================================================
# Team Management Tests
# ============================================================================

class TestTeamManagement:
    """Test team CRUD operations"""
    
    def test_create_team_success(self, team_service, test_org, test_user):
        """Test creating team"""
        result = team_service.create_team(
            org_id=test_org.id,
            name="Engineering",
            slug="engineering",
            owner_id=test_user.id,
        )
        
        assert result["id"] is not None
        assert result["name"] == "Engineering"
        assert result["slug"] == "engineering"
        assert result["organization_id"] == str(test_org.id)
    
    def test_create_team_duplicate_slug_in_org(self, team_service, test_org, test_team, test_user):
        """Test duplicate slug within organization is rejected"""
        with pytest.raises(ValueError):
            team_service.create_team(
                org_id=test_org.id,
                name="Different Team",
                slug=test_team.slug,  # Duplicate in same org
                owner_id=test_user.id,
            )
    
    def test_create_team_member_limit_enforcement(self, team_service, test_org, test_user):
        """Test member limit enforcement per plan"""
        # Free plan allows 5 members
        free_org = team_service.create_organization(
            owner_id=test_user.id,
            name="Free Org",
            slug=f"free-org-{uuid.uuid4().hex[:4]}",
            plan="free",
        )
        
        team = team_service.create_team(
            org_id=free_org["id"],
            name="Test Team",
            slug="test-team",
            owner_id=test_user.id,
        )
        
        # Try to add more members than limit
        team_id = team["id"]
        for i in range(6):
            user_email = f"user{i}@example.com"
            if i < 5:
                result = team_service.add_team_member(
                    team_id=team_id,
                    user_id=str(uuid.uuid4()),
                    email=user_email,
                    role="developer",
                )
                assert result["added"] is True
            else:
                # 6th member should fail
                with pytest.raises(ValueError, match="member limit"):
                    team_service.add_team_member(
                        team_id=team_id,
                        user_id=str(uuid.uuid4()),
                        email=user_email,
                        role="developer",
                    )
    
    def test_get_team(self, team_service, test_team):
        """Test retrieving team"""
        result = team_service.get_team(test_team.id)
        
        assert result["id"] == str(test_team.id)
        assert result["name"] == test_team.name
    
    def test_update_team(self, team_service, test_team, db_session):
        """Test updating team"""
        result = team_service.update_team(
            team_id=test_team.id,
            name="Updated Team Name",
        )
        
        assert result["name"] == "Updated Team Name"
        
        db_session.refresh(test_team)
        assert test_team.name == "Updated Team Name"
    
    def test_delete_team(self, team_service, test_team):
        """Test deleting team"""
        result = team_service.delete_team(test_team.id)
        
        assert result["deleted"] is True


# ============================================================================
# Team Member Management Tests
# ============================================================================

class TestTeamMemberManagement:
    """Test team member operations"""
    
    def test_add_team_member_success(self, team_service, test_team, db_session, create_test_user):
        """Test adding member to team"""
        new_user = create_test_user(db_session, "newmember@example.com")
        
        result = team_service.add_team_member(
            team_id=test_team.id,
            user_id=new_user.id,
            role="developer",
        )
        
        assert result["added"] is True
        assert result["role"] == "developer"
    
    def test_add_duplicate_team_member(self, team_service, test_team, test_user):
        """Test adding same member twice fails"""
        # Add member first time
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=test_user.id,
            role="developer",
        )
        
        # Try to add again
        with pytest.raises(ValueError):
            team_service.add_team_member(
                team_id=test_team.id,
                user_id=test_user.id,
                role="developer",
            )
    
    def test_update_member_role(self, team_service, test_team, test_user):
        """Test updating member role"""
        # Add member
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=test_user.id,
            role="developer",
        )
        
        # Update role
        result = team_service.update_member_role(
            team_id=test_team.id,
            user_id=test_user.id,
            role="maintainer",
        )
        
        assert result["role"] == "maintainer"
    
    def test_remove_team_member(self, team_service, test_team, test_user):
        """Test removing member from team"""
        # Add member
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=test_user.id,
            role="developer",
        )
        
        # Remove member
        result = team_service.remove_team_member(
            team_id=test_team.id,
            user_id=test_user.id,
        )
        
        assert result["removed"] is True


# ============================================================================
# Team Invitation Tests
# ============================================================================

class TestTeamInvitations:
    """Test team invitation workflow"""
    
    def test_invite_to_team(self, team_service, test_team, test_user):
        """Test inviting user to team"""
        result = team_service.invite_to_team(
            team_id=test_team.id,
            email="newuser@example.com",
            role="developer",
            invited_by=test_user.id,
        )
        
        assert result["token"] is not None
        assert result["email"] == "newuser@example.com"
        assert result["expires_in"] == 604800  # 7 days
    
    def test_accept_team_invitation(self, team_service, test_team):
        """Test accepting team invitation"""
        # Create invitation
        invite_result = team_service.invite_to_team(
            team_id=test_team.id,
            email="newuser@example.com",
            role="developer",
            invited_by=test_team.owner_id,
        )
        token = invite_result["token"]
        
        # Accept invitation
        accept_result = team_service.accept_team_invitation(
            token=token,
            user_id=str(uuid.uuid4()),
        )
        
        assert accept_result["accepted"] is True
    
    def test_invitation_expires(self, team_service, test_team, test_user):
        """Test invitation expiration"""
        # This would require time manipulation in test
        pass
    
    def test_revoke_invitation(self, team_service, test_team, test_user):
        """Test revoking invitation"""
        invite_result = team_service.invite_to_team(
            team_id=test_team.id,
            email="newuser@example.com",
            role="developer",
            invited_by=test_user.id,
        )
        token = invite_result["token"]
        
        result = team_service.revoke_invitation(token)
        
        assert result["revoked"] is True


# ============================================================================
# Permission Tests
# ============================================================================

class TestTeamPermissions:
    """Test role-based permissions"""
    
    def test_owner_has_all_permissions(self, team_service, test_team, test_user):
        """Test owner role has all permissions"""
        permissions = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=test_user.id,
            permission="admin",
        )
        
        assert permissions["allowed"] is True
    
    def test_admin_permissions(self, team_service, test_team, test_user, db_session, create_test_user):
        """Test admin role permissions"""
        admin_user = create_test_user(db_session, "admin@example.com")
        
        # Add as admin
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=admin_user.id,
            role="admin",
        )
        
        # Admin can write
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=admin_user.id,
            permission="write",
        )
        assert result["allowed"] is True
        
        # Admin can admin
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=admin_user.id,
            permission="admin",
        )
        assert result["allowed"] is True
    
    def test_developer_permissions(self, team_service, test_team, db_session, create_test_user):
        """Test developer role limited permissions"""
        dev_user = create_test_user(db_session, "dev@example.com")
        
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=dev_user.id,
            role="developer",
        )
        
        # Developer can read
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=dev_user.id,
            permission="read",
        )
        assert result["allowed"] is True
        
        # Developer can write
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=dev_user.id,
            permission="write",
        )
        assert result["allowed"] is True
        
        # Developer cannot admin
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=dev_user.id,
            permission="admin",
        )
        assert result["allowed"] is False
    
    def test_viewer_permissions(self, team_service, test_team, db_session, create_test_user):
        """Test viewer role read-only permissions"""
        viewer_user = create_test_user(db_session, "viewer@example.com")
        
        team_service.add_team_member(
            team_id=test_team.id,
            user_id=viewer_user.id,
            role="viewer",
        )
        
        # Viewer can read
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=viewer_user.id,
            permission="read",
        )
        assert result["allowed"] is True
        
        # Viewer cannot write
        result = team_service.check_team_permission(
            team_id=test_team.id,
            user_id=viewer_user.id,
            permission="write",
        )
        assert result["allowed"] is False


# ============================================================================
# Organization Member Management Tests
# ============================================================================

class TestOrganizationMembers:
    """Test organization-level member management"""
    
    def test_add_org_member(self, team_service, test_org, test_user, db_session, create_test_user):
        """Test adding member to organization"""
        new_user = create_test_user(db_session, "orgmember@example.com")
        
        result = team_service.add_org_member(
            org_id=test_org.id,
            user_id=new_user.id,
            role="member",
        )
        
        assert result["added"] is True
    
    def test_list_org_members(self, team_service, test_org):
        """Test listing organization members"""
        result = team_service.list_org_members(test_org.id)
        
        assert "members" in result
        assert isinstance(result["members"], list)


# ============================================================================
# Integration Tests
# ============================================================================

class TestTeamManagementIntegration:
    """End-to-end team management workflows"""
    
    def test_complete_team_setup_workflow(
        self,
        team_service,
        test_user,
        db_session,
        create_test_user,
    ):
        """Test complete team setup: org → team → members"""
        # Step 1: Create organization
        org = team_service.create_organization(
            owner_id=test_user.id,
            name="Startup Inc",
            slug=f"startup-{uuid.uuid4().hex[:4]}",
        )
        
        # Step 2: Create teams
        eng_team = team_service.create_team(
            org_id=org["id"],
            name="Engineering",
            slug="engineering",
            owner_id=test_user.id,
        )
        
        prod_team = team_service.create_team(
            org_id=org["id"],
            name="Product",
            slug="product",
            owner_id=test_user.id,
        )
        
        # Step 3: Add members to teams
        eng_member = create_test_user(db_session, "engineer@startup.com")
        prod_member = create_test_user(db_session, "product@startup.com")
        
        team_service.add_team_member(
            team_id=eng_team["id"],
            user_id=eng_member.id,
            role="developer",
        )
        
        team_service.add_team_member(
            team_id=prod_team["id"],
            user_id=prod_member.id,
            role="maintainer",
        )
        
        # Verify structure
        assert org["name"] == "Startup Inc"
        assert eng_team["organization_id"] == str(org["id"])
        assert prod_team["organization_id"] == str(org["id"])
