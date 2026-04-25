"""
Unit Tests - Team and Organization Management
Issue #1345 Week 3: Team Management
"""
import pytest
from datetime import datetime, timedelta
from unittest.mock import Mock
import uuid

from src.team_service import TeamManagementService
from src.team_models import (
    OrganizationCreateRequest,
    TeamCreateRequest,
    TeamInvitationCreateRequest,
    MemberRole,
)


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def mock_db():
    """Mock database session"""
    return Mock()


@pytest.fixture
def mock_config():
    """Mock configuration"""
    config = Mock()
    config.JWT_ISSUER = "https://auth.kushnir.cloud"
    return config


@pytest.fixture
def team_service(mock_db, mock_config):
    """Team management service"""
    return TeamManagementService(mock_db, mock_config)


@pytest.fixture
def sample_user_id():
    """Sample user ID"""
    return str(uuid.uuid4())


@pytest.fixture
def sample_org_id():
    """Sample organization ID"""
    return str(uuid.uuid4())


@pytest.fixture
def sample_team_id():
    """Sample team ID"""
    return str(uuid.uuid4())


# ============================================================================
# Organization Tests
# ============================================================================

class TestOrganizationManagement:
    """Test organization management"""
    
    def test_create_organization(self, team_service, sample_user_id):
        """Test creating organization"""
        result = team_service.create_organization(
            owner_id=sample_user_id,
            name="Acme Corp",
            slug="acme-corp",
            description="Acme Corporation",
        )
        
        assert result["status"] == "created"
        assert result["name"] == "Acme Corp"
        assert result["slug"] == "acme-corp"
    
    def test_create_organization_duplicate_slug(self, team_service, sample_user_id):
        """Test creating organization with duplicate slug raises error"""
        # Mock: slug already exists
        team_service._org_slug_exists = Mock(return_value=True)
        
        with pytest.raises(ValueError):
            team_service.create_organization(
                owner_id=sample_user_id,
                name="Acme Corp",
                slug="acme-corp",
            )
    
    def test_get_organization(self, team_service, sample_org_id):
        """Test retrieving organization"""
        # Mock: organization exists
        mock_org = Mock(
            id=sample_org_id,
            name="Acme Corp",
            slug="acme-corp",
            plan="pro",
        )
        team_service._get_org = Mock(return_value=mock_org)
        
        result = team_service.get_organization(sample_org_id)
        
        assert result["name"] == "Acme Corp"
        assert result["slug"] == "acme-corp"
    
    def test_list_user_organizations(self, team_service, sample_user_id):
        """Test listing user's organizations"""
        # Mock: user has 2 organizations
        mock_orgs = [
            Mock(id=str(uuid.uuid4()), name="Org 1", slug="org-1"),
            Mock(id=str(uuid.uuid4()), name="Org 2", slug="org-2"),
        ]
        team_service._list_user_orgs = Mock(return_value=mock_orgs)
        team_service._get_user_org_role = Mock(return_value="owner")
        
        result = team_service.list_user_organizations(sample_user_id)
        
        assert len(result) == 2
        assert result[0]["name"] == "Org 1"
    
    def test_update_organization_owner_only(self, team_service, sample_org_id, sample_user_id):
        """Test updating organization (owner only)"""
        mock_org = Mock(owner_id=sample_user_id)
        team_service._get_org = Mock(return_value=mock_org)
        
        result = team_service.update_organization(
            org_id=sample_org_id,
            caller_id=sample_user_id,
            name="New Name",
        )
        
        assert result["status"] == "updated"
    
    def test_update_organization_non_owner_denied(self, team_service, sample_org_id):
        """Test updating organization as non-owner raises error"""
        owner_id = str(uuid.uuid4())
        caller_id = str(uuid.uuid4())
        
        mock_org = Mock(owner_id=owner_id)
        team_service._get_org = Mock(return_value=mock_org)
        
        with pytest.raises(PermissionError):
            team_service.update_organization(
                org_id=sample_org_id,
                caller_id=caller_id,
                name="New Name",
            )


# ============================================================================
# Team Tests
# ============================================================================

class TestTeamManagement:
    """Test team management"""
    
    def test_create_team(self, team_service, sample_org_id, sample_user_id):
        """Test creating team"""
        mock_org = Mock(max_teams=10, max_members=50)
        team_service._get_org = Mock(return_value=mock_org)
        team_service._get_user_org_role = Mock(return_value="owner")
        team_service._team_slug_exists_in_org = Mock(return_value=False)
        team_service._count_org_teams = Mock(return_value=1)
        team_service._create_team = Mock(return_value=Mock(id=str(uuid.uuid4())))
        team_service._add_team_member = Mock()
        
        result = team_service.create_team(
            org_id=sample_org_id,
            creator_id=sample_user_id,
            name="Engineering",
            slug="engineering",
        )
        
        assert result["status"] == "created"
        assert result["name"] == "Engineering"
    
    def test_create_team_insufficient_permissions(self, team_service, sample_org_id, sample_user_id):
        """Test creating team without admin permissions raises error"""
        mock_org = Mock(max_teams=10)
        team_service._get_org = Mock(return_value=mock_org)
        team_service._get_user_org_role = Mock(return_value="viewer")  # Not admin
        
        with pytest.raises(PermissionError):
            team_service.create_team(
                org_id=sample_org_id,
                creator_id=sample_user_id,
                name="Engineering",
                slug="engineering",
            )
    
    def test_create_team_exceeds_limit(self, team_service, sample_org_id, sample_user_id):
        """Test creating team when org exceeds limit raises error"""
        mock_org = Mock(max_teams=3)
        team_service._get_org = Mock(return_value=mock_org)
        team_service._get_user_org_role = Mock(return_value="owner")
        team_service._team_slug_exists_in_org = Mock(return_value=False)
        team_service._count_org_teams = Mock(return_value=3)  # Already at limit
        
        with pytest.raises(ValueError):
            team_service.create_team(
                org_id=sample_org_id,
                creator_id=sample_user_id,
                name="Engineering",
                slug="engineering",
            )
    
    def test_get_team(self, team_service, sample_team_id):
        """Test retrieving team"""
        mock_team = Mock(
            id=sample_team_id,
            organization_id=str(uuid.uuid4()),
            name="Engineering",
            slug="engineering",
            status="active",
        )
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_team_members = Mock(return_value=[])
        
        result = team_service.get_team(sample_team_id)
        
        assert result["name"] == "Engineering"
        assert result["member_count"] == 0
    
    def test_list_team_members(self, team_service, sample_team_id, sample_user_id):
        """Test listing team members"""
        mock_members = [
            Mock(user_id=sample_user_id, role="owner", joined_at=datetime.utcnow()),
            Mock(user_id=str(uuid.uuid4()), role="developer", joined_at=datetime.utcnow()),
        ]
        team_service._get_team_members = Mock(return_value=mock_members)
        
        result = team_service.list_team_members(sample_team_id)
        
        assert len(result) == 2
        assert result[0]["role"] == "owner"


# ============================================================================
# Team Member Tests
# ============================================================================

class TestTeamMemberManagement:
    """Test team member management"""
    
    def test_add_team_member(self, team_service, sample_team_id, sample_user_id):
        """Test adding member to team"""
        caller_id = str(uuid.uuid4())
        new_user_id = str(uuid.uuid4())
        
        mock_team = Mock(organization_id=str(uuid.uuid4()))
        mock_org = Mock(max_members=50)
        
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(return_value="admin")
        team_service._get_user = Mock(return_value=Mock())
        team_service._is_team_member = Mock(return_value=False)
        team_service._count_team_members = Mock(return_value=5)
        team_service._get_org = Mock(return_value=mock_org)
        team_service._add_team_member = Mock()
        
        result = team_service.add_team_member(
            team_id=sample_team_id,
            caller_id=caller_id,
            user_id=new_user_id,
            role="developer",
        )
        
        assert result["status"] == "added"
        assert result["role"] == "developer"
    
    def test_add_team_member_already_member(self, team_service, sample_team_id):
        """Test adding member who is already member"""
        caller_id = str(uuid.uuid4())
        existing_user_id = str(uuid.uuid4())
        
        mock_team = Mock(organization_id=str(uuid.uuid4()))
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(return_value="admin")
        team_service._get_user = Mock(return_value=Mock())
        team_service._is_team_member = Mock(return_value=True)
        
        result = team_service.add_team_member(
            team_id=sample_team_id,
            caller_id=caller_id,
            user_id=existing_user_id,
            role="developer",
        )
        
        assert result["status"] == "already_member"
    
    def test_remove_team_member(self, team_service, sample_team_id):
        """Test removing member from team"""
        caller_id = str(uuid.uuid4())
        member_id = str(uuid.uuid4())
        
        mock_team = Mock()
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(side_effect=lambda uid, tid: "admin" if uid == caller_id else "developer")
        team_service._remove_team_member = Mock()
        
        result = team_service.remove_team_member(
            team_id=sample_team_id,
            caller_id=caller_id,
            user_id=member_id,
        )
        
        assert result["status"] == "removed"
    
    def test_remove_team_owner_denied(self, team_service, sample_team_id):
        """Test removing team owner raises error"""
        caller_id = str(uuid.uuid4())
        owner_id = str(uuid.uuid4())
        
        mock_team = Mock()
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(side_effect=lambda uid, tid: "admin" if uid == caller_id else "owner")
        
        with pytest.raises(ValueError):
            team_service.remove_team_member(
                team_id=sample_team_id,
                caller_id=caller_id,
                user_id=owner_id,
            )


# ============================================================================
# Team Invitation Tests
# ============================================================================

class TestTeamInvitations:
    """Test team invitation workflow"""
    
    def test_invite_to_team(self, team_service, sample_team_id, sample_user_id):
        """Test inviting user to team"""
        mock_team = Mock(name="Engineering")
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(return_value="admin")
        team_service._get_user_by_email = Mock(return_value=None)
        team_service._create_invitation = Mock(
            return_value=Mock(expires_at=datetime.utcnow() + timedelta(days=7))
        )
        team_service._send_invitation_email = Mock()
        
        result = team_service.invite_to_team(
            team_id=sample_team_id,
            caller_id=sample_user_id,
            invitee_email="newuser@example.com",
            role="developer",
        )
        
        assert result["status"] == "invited"
        assert result["email"] == "newuser@example.com"
    
    def test_invite_existing_member_skipped(self, team_service, sample_team_id, sample_user_id):
        """Test inviting existing member is skipped"""
        existing_user_id = str(uuid.uuid4())
        
        mock_team = Mock(name="Engineering")
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_user_team_role = Mock(return_value="admin")
        team_service._get_user_by_email = Mock(return_value=Mock(id=existing_user_id))
        team_service._is_team_member = Mock(return_value=True)
        
        result = team_service.invite_to_team(
            team_id=sample_team_id,
            caller_id=sample_user_id,
            invitee_email="existing@example.com",
        )
        
        assert result["status"] == "already_member"
    
    def test_accept_team_invitation(self, team_service, sample_team_id, sample_user_id):
        """Test accepting team invitation"""
        mock_invitation = Mock(
            team_id=sample_team_id,
            role="developer",
            expires_at=datetime.utcnow() + timedelta(days=1),
        )
        team_service._get_invitation_by_token = Mock(return_value=mock_invitation)
        team_service._add_team_member = Mock()
        
        result = team_service.accept_team_invitation(
            token="valid-token",
            user_id=sample_user_id,
        )
        
        assert result["status"] == "accepted"
        assert result["team_id"] == sample_team_id


# ============================================================================
# Permission Tests
# ============================================================================

class TestPermissionChecking:
    """Test permission checking"""
    
    def test_check_team_permission_owner(self, team_service, sample_team_id, sample_user_id):
        """Test owner has all permissions"""
        team_service._get_user_team_role = Mock(return_value="owner")
        
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "read")
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "write")
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "admin")
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "delete")
    
    def test_check_team_permission_developer(self, team_service, sample_team_id, sample_user_id):
        """Test developer has limited permissions"""
        team_service._get_user_team_role = Mock(return_value="developer")
        
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "read")
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "write")
        assert not team_service.check_team_permission(sample_user_id, sample_team_id, "admin")
    
    def test_check_team_permission_viewer(self, team_service, sample_team_id, sample_user_id):
        """Test viewer has read-only permission"""
        team_service._get_user_team_role = Mock(return_value="viewer")
        
        assert team_service.check_team_permission(sample_user_id, sample_team_id, "read")
        assert not team_service.check_team_permission(sample_user_id, sample_team_id, "write")
        assert not team_service.check_team_permission(sample_user_id, sample_team_id, "admin")


# ============================================================================
# Integration Tests
# ============================================================================

class TestTeamManagementIntegration:
    """Integration tests for team management"""
    
    def test_complete_team_workflow(self, team_service, sample_org_id, sample_user_id):
        """Test complete team creation and member management workflow"""
        # 1. Create team
        mock_org = Mock(max_teams=10, max_members=50)
        mock_team = Mock(id=str(uuid.uuid4()), name="Engineering")
        
        team_service._get_org = Mock(return_value=mock_org)
        team_service._get_user_org_role = Mock(return_value="owner")
        team_service._team_slug_exists_in_org = Mock(return_value=False)
        team_service._count_org_teams = Mock(return_value=0)
        team_service._create_team = Mock(return_value=mock_team)
        team_service._add_team_member = Mock()
        
        result = team_service.create_team(
            org_id=sample_org_id,
            creator_id=sample_user_id,
            name="Engineering",
            slug="engineering",
        )
        
        assert result["status"] == "created"
        team_id = result["id"]
        
        # 2. Get team
        team_service._get_team = Mock(return_value=mock_team)
        team_service._get_team_members = Mock(return_value=[])
        
        team_info = team_service.get_team(team_id)
        assert team_info["name"] == "Engineering"
