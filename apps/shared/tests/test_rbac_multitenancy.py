"""
Tests for RBAC and multi-tenancy system.
"""

import pytest
from datetime import datetime, timedelta
from apps.shared.rbac_multitenancy import (
    Permission, Role, RoleDefinition, Tenant, User, AccessToken,
    AuditLog, TenantScope, RBACManager, MultiTenancyManager,
    AccessControl, DataIsolation
)


class TestPermission:
    """Test permission enumeration."""
    
    def test_permission_values(self):
        """Test permission values."""
        assert Permission.DASHBOARD_VIEW.value == "dashboard:view"
        assert Permission.TRACE_VIEW.value == "trace:view"
        assert Permission.USER_MANAGE.value == "user:manage"


class TestRole:
    """Test role enumeration."""
    
    def test_role_values(self):
        """Test role values."""
        assert Role.ADMIN.value == "admin"
        assert Role.VIEWER.value == "viewer"


class TestRoleDefinition:
    """Test role definitions."""
    
    def test_create_role_definition(self):
        """Test creating role definition."""
        permissions = {Permission.DASHBOARD_VIEW, Permission.TRACE_VIEW}
        role_def = RoleDefinition(
            role=Role.VIEWER,
            permissions=permissions,
            description="View-only access"
        )
        
        assert role_def.role == Role.VIEWER
        assert len(role_def.permissions) == 2
    
    def test_role_to_dict(self):
        """Test converting role to dict."""
        role_def = RoleDefinition(
            role=Role.VIEWER,
            permissions={Permission.DASHBOARD_VIEW}
        )
        
        d = role_def.to_dict()
        assert d["role"] == "viewer"
        assert "dashboard:view" in d["permissions"]


class TestTenant:
    """Test tenant management."""
    
    def test_create_tenant(self):
        """Test creating tenant."""
        tenant = Tenant(
            name="Acme Corp",
            organization="acme"
        )
        
        assert tenant.name == "Acme Corp"
        assert tenant.active is True
    
    def test_tenant_to_dict(self):
        """Test converting tenant to dict."""
        tenant = Tenant(
            name="TechCorp",
            organization="techcorp",
            features={"tracing", "metrics"}
        )
        
        d = tenant.to_dict()
        assert d["name"] == "TechCorp"
        assert "tracing" in d["features"]


class TestUser:
    """Test user management."""
    
    def test_create_user(self):
        """Test creating user."""
        user = User(
            username="alice",
            email="alice@example.com",
            tenant_id="tenant_123",
            roles={Role.ANALYST}
        )
        
        assert user.username == "alice"
        assert Role.ANALYST in user.roles
    
    def test_user_to_dict(self):
        """Test converting user to dict (no password)."""
        user = User(
            username="bob",
            email="bob@example.com",
            tenant_id="tenant_123",
            roles={Role.OPERATOR, Role.ANALYST},
            password_hash="secret"
        )
        
        d = user.to_dict()
        assert "bob" in d["username"]
        assert "password" not in d  # Should not expose password
        assert "operator" in d["roles"]


class TestAccessToken:
    """Test access token management."""
    
    def test_create_token(self):
        """Test creating access token."""
        token = AccessToken(
            user_id="user_123",
            tenant_id="tenant_456"
        )
        
        assert token.user_id == "user_123"
        assert token.is_valid() is True
    
    def test_token_expiration(self):
        """Test token expiration."""
        expires = datetime.utcnow() - timedelta(hours=1)
        token = AccessToken(
            user_id="user_123",
            tenant_id="tenant_456",
            expires_at=expires
        )
        
        assert token.is_valid() is False
    
    def test_token_to_dict(self):
        """Test converting token to dict."""
        token = AccessToken(
            user_id="user_123",
            tenant_id="tenant_456",
            scopes={"dashboard:view", "trace:view"}
        )
        
        d = token.to_dict()
        assert d["user_id"] == "user_123"
        assert "dashboard:view" in d["scopes"]


class TestAuditLog:
    """Test audit logging."""
    
    def test_create_audit_log(self):
        """Test creating audit log."""
        log = AuditLog(
            tenant_id="tenant_123",
            user_id="user_456",
            action="dashboard_created",
            resource_type="dashboard",
            resource_id="dash_789"
        )
        
        assert log.action == "dashboard_created"
        assert log.status == "success"
    
    def test_audit_log_to_dict(self):
        """Test converting audit log to dict."""
        log = AuditLog(
            tenant_id="tenant_123",
            user_id="user_456",
            action="user_updated",
            resource_type="user",
            resource_id="user_789",
            changes={"role": "admin"}
        )
        
        d = log.to_dict()
        assert d["action"] == "user_updated"
        assert d["changes"]["role"] == "admin"


class TestRBACManager:
    """Test RBAC management."""
    
    def setup_method(self):
        """Setup for each test."""
        self.rbac = RBACManager()
    
    def test_default_roles_exist(self):
        """Test that default roles exist."""
        assert Role.ADMIN in self.rbac.roles
        assert Role.VIEWER in self.rbac.roles
    
    def test_admin_has_all_permissions(self):
        """Test admin role has all permissions."""
        admin_perms = self.rbac.get_role_permissions(Role.ADMIN)
        
        assert Permission.USER_MANAGE in admin_perms
        assert Permission.ROLE_MANAGE in admin_perms
        assert Permission.DASHBOARD_DELETE in admin_perms
    
    def test_viewer_has_limited_permissions(self):
        """Test viewer role has limited permissions."""
        viewer_perms = self.rbac.get_role_permissions(Role.VIEWER)
        
        assert Permission.DASHBOARD_VIEW in viewer_perms
        assert Permission.DASHBOARD_CREATE not in viewer_perms
        assert Permission.USER_MANAGE not in viewer_perms
    
    def test_operator_permissions(self):
        """Test operator role permissions."""
        operator_perms = self.rbac.get_role_permissions(Role.OPERATOR)
        
        assert Permission.DASHBOARD_VIEW in operator_perms
        assert Permission.DASHBOARD_EDIT in operator_perms
        assert Permission.ALERT_CREATE in operator_perms
    
    def test_get_aggregated_permissions(self):
        """Test aggregating permissions from multiple roles."""
        roles = {Role.VIEWER, Role.DEVELOPER}
        perms = self.rbac.get_user_permissions(roles)
        
        assert Permission.DASHBOARD_VIEW in perms
        assert Permission.TRACE_EXPORT in perms


class TestMultiTenancyManager:
    """Test multi-tenancy management."""
    
    def setup_method(self):
        """Setup for each test."""
        self.tenancy = MultiTenancyManager()
    
    def test_create_tenant(self):
        """Test creating tenant."""
        tenant = self.tenancy.create_tenant(
            "Acme", "acme", "admin"
        )
        
        assert tenant.name == "Acme"
        assert tenant.id in self.tenancy.tenants
    
    def test_get_tenant(self):
        """Test retrieving tenant."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        retrieved = self.tenancy.get_tenant(tenant.id)
        
        assert retrieved is not None
        assert retrieved.name == "Corp"
    
    def test_list_tenants(self):
        """Test listing tenants."""
        self.tenancy.create_tenant("Tenant1", "org1", "admin")
        self.tenancy.create_tenant("Tenant2", "org2", "admin")
        
        tenants = self.tenancy.list_tenants()
        assert len(tenants) == 2
    
    def test_create_user_in_tenant(self):
        """Test creating user in tenant."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        
        user = self.tenancy.create_user(
            "alice", "alice@corp.com", tenant.id,
            roles={Role.ANALYST}
        )
        
        assert user.tenant_id == tenant.id
        assert user.username == "alice"
    
    def test_create_user_invalid_tenant(self):
        """Test creating user in non-existent tenant."""
        with pytest.raises(ValueError):
            self.tenancy.create_user(
                "bob", "bob@corp.com", "invalid_tenant"
            )
    
    def test_list_tenant_users(self):
        """Test listing users in tenant."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        
        self.tenancy.create_user("alice", "alice@corp.com", tenant.id)
        self.tenancy.create_user("bob", "bob@corp.com", tenant.id)
        
        users = self.tenancy.list_tenant_users(tenant.id)
        assert len(users) == 2
    
    def test_generate_token(self):
        """Test generating access token."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user("alice", "alice@corp.com", tenant.id)
        
        token = self.tenancy.generate_token(user.id)
        
        assert token.user_id == user.id
        assert token.tenant_id == tenant.id
        assert token.is_valid() is True
    
    def test_validate_token(self):
        """Test validating token."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user("alice", "alice@corp.com", tenant.id)
        
        token = self.tenancy.generate_token(user.id)
        validated = self.tenancy.validate_token(token.token)
        
        assert validated is not None
        assert validated.user_id == user.id
    
    def test_revoke_token(self):
        """Test revoking token."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user("alice", "alice@corp.com", tenant.id)
        
        token = self.tenancy.generate_token(user.id)
        revoked = self.tenancy.revoke_token(token.token)
        
        assert revoked is True
        assert self.tenancy.validate_token(token.token) is None


class TestAccessControl:
    """Test access control enforcement."""
    
    def setup_method(self):
        """Setup for each test."""
        self.rbac = RBACManager()
        self.tenancy = MultiTenancyManager()
        self.access_control = AccessControl(self.rbac, self.tenancy)
    
    def test_check_access_granted(self):
        """Test access granted."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user(
            "alice", "alice@corp.com", tenant.id,
            roles={Role.VIEWER}
        )
        
        token = self.tenancy.generate_token(user.id)
        
        has_access = self.access_control.check_access(
            token, Permission.DASHBOARD_VIEW,
            "dashboard", "dash_123"
        )
        
        assert has_access is True
    
    def test_check_access_denied(self):
        """Test access denied."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user(
            "alice", "alice@corp.com", tenant.id,
            roles={Role.VIEWER}
        )
        
        token = self.tenancy.generate_token(user.id)
        
        has_access = self.access_control.check_access(
            token, Permission.USER_MANAGE,
            "user", "user_123"
        )
        
        assert has_access is False
    
    def test_authorize_action_success(self):
        """Test authorizing action."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user(
            "alice", "alice@corp.com", tenant.id,
            roles={Role.ANALYST}
        )
        
        token = self.tenancy.generate_token(user.id)
        
        scope = self.access_control.authorize_action(
            token, Permission.DASHBOARD_VIEW,
            "dashboard", "dash_123"
        )
        
        assert scope.tenant_id == tenant.id
        assert scope.user_id == user.id
    
    def test_authorize_action_failure(self):
        """Test authorization failure."""
        tenant = self.tenancy.create_tenant("Corp", "corp", "admin")
        user = self.tenancy.create_user(
            "alice", "alice@corp.com", tenant.id,
            roles={Role.VIEWER}
        )
        
        token = self.tenancy.generate_token(user.id)
        
        with pytest.raises(PermissionError):
            self.access_control.authorize_action(
                token, Permission.DASHBOARD_DELETE,
                "dashboard", "dash_123"
            )
    
    def test_audit_logging(self):
        """Test audit logging."""
        self.access_control.log_audit(
            tenant_id="tenant_123",
            user_id="user_456",
            action="dashboard_created",
            resource_type="dashboard",
            resource_id="dash_789"
        )
        
        logs = self.access_control.get_audit_logs("tenant_123")
        assert len(logs) == 1
        assert logs[0].action == "dashboard_created"
    
    def test_audit_logs_filtered_by_tenant(self):
        """Test audit logs are tenant-scoped."""
        self.access_control.log_audit(
            "tenant_1", "user_1", "action1",
            "resource", "id1"
        )
        self.access_control.log_audit(
            "tenant_2", "user_2", "action2",
            "resource", "id2"
        )
        
        logs1 = self.access_control.get_audit_logs("tenant_1")
        logs2 = self.access_control.get_audit_logs("tenant_2")
        
        assert len(logs1) == 1
        assert len(logs2) == 1
        assert logs1[0].user_id == "user_1"


class TestDataIsolation:
    """Test data isolation."""
    
    def test_scope_query_where_clause(self):
        """Test scoping query with WHERE."""
        scope = TenantScope(tenant_id="tenant_123", user_id="user_456")
        base_query = "SELECT * FROM dashboards WHERE user_id = ?"
        
        scoped = DataIsolation.scope_query(base_query, scope, "dashboard")
        
        assert "tenant_id" in scoped
        assert "tenant_123" in scoped
    
    def test_scope_query_no_where_clause(self):
        """Test scoping query without WHERE."""
        scope = TenantScope(tenant_id="tenant_123", user_id="user_456")
        base_query = "SELECT * FROM dashboards"
        
        scoped = DataIsolation.scope_query(base_query, scope, "dashboard")
        
        assert "WHERE" in scoped
        assert "tenant_123" in scoped
    
    def test_filter_results_by_tenant(self):
        """Test filtering results by tenant."""
        scope = TenantScope(tenant_id="tenant_1", user_id="user_1")
        
        results = [
            {"id": "1", "tenant_id": "tenant_1", "name": "dash1"},
            {"id": "2", "tenant_id": "tenant_2", "name": "dash2"},
            {"id": "3", "tenant_id": "tenant_1", "name": "dash3"},
        ]
        
        filtered = DataIsolation.filter_results(results, scope)
        
        assert len(filtered) == 2
        assert all(r["tenant_id"] == "tenant_1" for r in filtered)


class TestTenantScope:
    """Test tenant scope context."""
    
    def test_has_permission(self):
        """Test permission check."""
        scope = TenantScope(
            tenant_id="tenant_1",
            user_id="user_1",
            permissions={Permission.DASHBOARD_VIEW, Permission.TRACE_VIEW}
        )
        
        assert scope.has_permission(Permission.DASHBOARD_VIEW) is True
        assert scope.has_permission(Permission.DASHBOARD_DELETE) is False


class TestIntegration:
    """Integration tests for RBAC and multi-tenancy."""
    
    def test_complete_rbac_workflow(self):
        """Test complete RBAC workflow."""
        # Setup
        rbac = RBACManager()
        tenancy = MultiTenancyManager()
        access_control = AccessControl(rbac, tenancy)
        
        # Create tenants
        tenant_1 = tenancy.create_tenant("Company A", "compa", "admin1")
        tenant_2 = tenancy.create_tenant("Company B", "compb", "admin2")
        
        # Create users
        user_a = tenancy.create_user(
            "alice", "alice@a.com", tenant_1.id,
            roles={Role.OPERATOR}
        )
        user_b = tenancy.create_user(
            "bob", "bob@b.com", tenant_2.id,
            roles={Role.VIEWER}
        )
        
        # Generate tokens
        token_a = tenancy.generate_token(user_a.id)
        token_b = tenancy.generate_token(user_b.id)
        
        # Check access
        access_a = access_control.check_access(
            token_a, Permission.DASHBOARD_EDIT,
            "dashboard", "dash_123"
        )
        access_b = access_control.check_access(
            token_b, Permission.DASHBOARD_EDIT,
            "dashboard", "dash_456"
        )
        
        assert access_a is True  # Operator can edit
        assert access_b is False  # Viewer cannot edit
        
        # Verify tenant isolation
        assert user_a.tenant_id != user_b.tenant_id
        assert token_a.tenant_id != token_b.tenant_id
