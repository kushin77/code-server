"""
Role-Based Access Control & Multi-Tenancy System

Implements enterprise-grade security with RBAC and multi-tenant data isolation:
- Role definitions and permissions
- Tenant isolation and scoping
- Resource access control
- Audit logging
- Token-based authentication
"""

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Set, Tuple, Any
from enum import Enum
from datetime import datetime, timedelta
import json
from uuid import uuid4
import hashlib
from abc import ABC, abstractmethod


class Permission(Enum):
    """Available permissions."""
    # Dashboard permissions
    DASHBOARD_VIEW = "dashboard:view"
    DASHBOARD_CREATE = "dashboard:create"
    DASHBOARD_EDIT = "dashboard:edit"
    DASHBOARD_DELETE = "dashboard:delete"
    DASHBOARD_SHARE = "dashboard:share"
    
    # Trace permissions
    TRACE_VIEW = "trace:view"
    TRACE_QUERY = "trace:query"
    TRACE_EXPORT = "trace:export"
    
    # Metrics permissions
    METRICS_VIEW = "metrics:view"
    METRICS_QUERY = "metrics:query"
    METRICS_AGGREGATE = "metrics:aggregate"
    
    # Alert permissions
    ALERT_VIEW = "alert:view"
    ALERT_CREATE = "alert:create"
    ALERT_EDIT = "alert:edit"
    ALERT_DELETE = "alert:delete"
    
    # Admin permissions
    USER_MANAGE = "user:manage"
    ROLE_MANAGE = "role:manage"
    TENANT_MANAGE = "tenant:manage"
    AUDIT_VIEW = "audit:view"


class Role(Enum):
    """Predefined roles."""
    ADMIN = "admin"
    OPERATOR = "operator"
    ANALYST = "analyst"
    VIEWER = "viewer"
    DEVELOPER = "developer"


@dataclass
class RoleDefinition:
    """Role with permissions."""
    role: Role
    permissions: Set[Permission] = field(default_factory=set)
    description: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "role": self.role.value,
            "permissions": [p.value for p in self.permissions],
            "description": self.description,
        }


@dataclass
class Tenant:
    """Multi-tenant organization."""
    id: str = field(default_factory=lambda: str(uuid4()))
    name: str = ""
    organization: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)
    created_by: str = ""
    features: Set[str] = field(default_factory=set)
    settings: Dict[str, Any] = field(default_factory=dict)
    active: bool = True
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "name": self.name,
            "organization": self.organization,
            "created_at": self.created_at.isoformat(),
            "created_by": self.created_by,
            "features": list(self.features),
            "settings": self.settings,
            "active": self.active,
        }


@dataclass
class User:
    """User in the system."""
    id: str = field(default_factory=lambda: str(uuid4()))
    username: str = ""
    email: str = ""
    tenant_id: str = ""
    roles: Set[Role] = field(default_factory=set)
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_login: Optional[datetime] = None
    active: bool = True
    password_hash: str = ""  # Should be bcrypt in production
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary (excluding password)."""
        return {
            "id": self.id,
            "username": self.username,
            "email": self.email,
            "tenant_id": self.tenant_id,
            "roles": [r.value for r in self.roles],
            "created_at": self.created_at.isoformat(),
            "last_login": self.last_login.isoformat() if self.last_login else None,
            "active": self.active,
        }


@dataclass
class AccessToken:
    """Authentication token."""
    token: str = field(default_factory=lambda: str(uuid4()))
    user_id: str = ""
    tenant_id: str = ""
    created_at: datetime = field(default_factory=datetime.utcnow)
    expires_at: datetime = field(default_factory=lambda: datetime.utcnow() + timedelta(hours=24))
    scopes: Set[str] = field(default_factory=set)
    
    def is_valid(self) -> bool:
        """Check if token is valid."""
        return datetime.utcnow() < self.expires_at
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "token": self.token,
            "user_id": self.user_id,
            "tenant_id": self.tenant_id,
            "created_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
            "scopes": list(self.scopes),
        }


@dataclass
class AuditLog:
    """Audit log entry."""
    id: str = field(default_factory=lambda: str(uuid4()))
    timestamp: datetime = field(default_factory=datetime.utcnow)
    tenant_id: str = ""
    user_id: str = ""
    action: str = ""
    resource_type: str = ""
    resource_id: str = ""
    changes: Dict[str, Any] = field(default_factory=dict)
    ip_address: str = ""
    status: str = "success"  # success, failure
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat(),
            "tenant_id": self.tenant_id,
            "user_id": self.user_id,
            "action": self.action,
            "resource_type": self.resource_type,
            "resource_id": self.resource_id,
            "changes": self.changes,
            "ip_address": self.ip_address,
            "status": self.status,
        }


@dataclass
class TenantScope:
    """Scoped query context for multi-tenancy."""
    tenant_id: str
    user_id: str
    permissions: Set[Permission] = field(default_factory=set)
    
    def has_permission(self, permission: Permission) -> bool:
        """Check if user has permission."""
        return permission in self.permissions


class RBACManager:
    """Manages role-based access control."""
    
    # Predefined role mappings
    DEFAULT_ROLES = {
        Role.ADMIN: RoleDefinition(
            role=Role.ADMIN,
            permissions={
                Permission.DASHBOARD_VIEW, Permission.DASHBOARD_CREATE,
                Permission.DASHBOARD_EDIT, Permission.DASHBOARD_DELETE,
                Permission.DASHBOARD_SHARE,
                Permission.TRACE_VIEW, Permission.TRACE_QUERY, Permission.TRACE_EXPORT,
                Permission.METRICS_VIEW, Permission.METRICS_QUERY, Permission.METRICS_AGGREGATE,
                Permission.ALERT_VIEW, Permission.ALERT_CREATE, Permission.ALERT_EDIT,
                Permission.ALERT_DELETE,
                Permission.USER_MANAGE, Permission.ROLE_MANAGE,
                Permission.TENANT_MANAGE, Permission.AUDIT_VIEW,
            },
            description="Full administrative access"
        ),
        Role.OPERATOR: RoleDefinition(
            role=Role.OPERATOR,
            permissions={
                Permission.DASHBOARD_VIEW, Permission.DASHBOARD_CREATE,
                Permission.DASHBOARD_EDIT, Permission.DASHBOARD_SHARE,
                Permission.TRACE_VIEW, Permission.TRACE_QUERY,
                Permission.METRICS_VIEW, Permission.METRICS_QUERY,
                Permission.ALERT_VIEW, Permission.ALERT_CREATE,
                Permission.ALERT_EDIT,
            },
            description="Operations team access"
        ),
        Role.ANALYST: RoleDefinition(
            role=Role.ANALYST,
            permissions={
                Permission.DASHBOARD_VIEW, Permission.DASHBOARD_CREATE,
                Permission.TRACE_VIEW, Permission.TRACE_QUERY,
                Permission.METRICS_VIEW, Permission.METRICS_QUERY,
                Permission.METRICS_AGGREGATE,
            },
            description="Data analyst access"
        ),
        Role.VIEWER: RoleDefinition(
            role=Role.VIEWER,
            permissions={
                Permission.DASHBOARD_VIEW,
                Permission.TRACE_VIEW,
                Permission.METRICS_VIEW,
            },
            description="Read-only access"
        ),
        Role.DEVELOPER: RoleDefinition(
            role=Role.DEVELOPER,
            permissions={
                Permission.DASHBOARD_VIEW,
                Permission.TRACE_VIEW, Permission.TRACE_QUERY, Permission.TRACE_EXPORT,
                Permission.METRICS_VIEW, Permission.METRICS_QUERY,
            },
            description="Developer/application access"
        ),
    }
    
    def __init__(self):
        self.roles = self.DEFAULT_ROLES.copy()
    
    def get_role_permissions(self, role: Role) -> Set[Permission]:
        """Get permissions for role."""
        if role in self.roles:
            return self.roles[role].permissions
        return set()
    
    def add_custom_role(self, role_def: RoleDefinition) -> bool:
        """Add custom role."""
        # In production, validate against policy
        self.roles[role_def.role] = role_def
        return True
    
    def get_user_permissions(self, roles: Set[Role]) -> Set[Permission]:
        """Aggregate permissions from all user roles."""
        permissions = set()
        for role in roles:
            permissions.update(self.get_role_permissions(role))
        return permissions


class MultiTenancyManager:
    """Manages multi-tenant data isolation."""
    
    def __init__(self):
        self.tenants: Dict[str, Tenant] = {}
        self.users: Dict[str, User] = {}
        self.tokens: Dict[str, AccessToken] = {}
    
    def create_tenant(self, name: str, organization: str, 
                     created_by: str) -> Tenant:
        """Create new tenant."""
        tenant = Tenant(
            name=name,
            organization=organization,
            created_by=created_by
        )
        self.tenants[tenant.id] = tenant
        return tenant
    
    def get_tenant(self, tenant_id: str) -> Optional[Tenant]:
        """Get tenant by ID."""
        return self.tenants.get(tenant_id)
    
    def list_tenants(self) -> List[Tenant]:
        """List all tenants."""
        return list(self.tenants.values())
    
    def create_user(self, username: str, email: str, tenant_id: str,
                   roles: Optional[Set[Role]] = None) -> User:
        """Create user in tenant."""
        if tenant_id not in self.tenants:
            raise ValueError(f"Tenant {tenant_id} not found")
        
        user = User(
            username=username,
            email=email,
            tenant_id=tenant_id,
            roles=roles or {Role.VIEWER}
        )
        self.users[user.id] = user
        return user
    
    def get_user(self, user_id: str) -> Optional[User]:
        """Get user by ID."""
        return self.users.get(user_id)
    
    def list_tenant_users(self, tenant_id: str) -> List[User]:
        """List users in tenant."""
        return [u for u in self.users.values() if u.tenant_id == tenant_id]
    
    def generate_token(self, user_id: str, scopes: Optional[Set[str]] = None,
                      expires_in_hours: int = 24) -> AccessToken:
        """Generate access token for user."""
        user = self.users.get(user_id)
        if not user:
            raise ValueError(f"User {user_id} not found")
        
        token = AccessToken(
            user_id=user_id,
            tenant_id=user.tenant_id,
            expires_at=datetime.utcnow() + timedelta(hours=expires_in_hours),
            scopes=scopes or set()
        )
        self.tokens[token.token] = token
        return token
    
    def validate_token(self, token_str: str) -> Optional[AccessToken]:
        """Validate access token."""
        token = self.tokens.get(token_str)
        if token and token.is_valid():
            return token
        return None
    
    def revoke_token(self, token_str: str) -> bool:
        """Revoke access token."""
        if token_str in self.tokens:
            del self.tokens[token_str]
            return True
        return False


class AccessControl:
    """Request-level access control."""
    
    def __init__(self, rbac_manager: RBACManager, 
                 tenancy_manager: MultiTenancyManager):
        self.rbac = rbac_manager
        self.tenancy = tenancy_manager
        self.audit_logs: List[AuditLog] = []
    
    def check_access(self, token: AccessToken, permission: Permission,
                    resource_type: str, resource_id: str) -> bool:
        """Check if user has access to resource."""
        # Get user
        user = self.tenancy.get_user(token.user_id)
        if not user or not user.active:
            return False
        
        # Verify tenant match
        if user.tenant_id != token.tenant_id:
            return False
        
        # Check permission
        user_permissions = self.rbac.get_user_permissions(user.roles)
        
        has_permission = permission in user_permissions
        
        # Log access attempt
        self.log_audit(
            tenant_id=token.tenant_id,
            user_id=token.user_id,
            action="access_check",
            resource_type=resource_type,
            resource_id=resource_id,
            status="success" if has_permission else "failure"
        )
        
        return has_permission
    
    def authorize_action(self, token: AccessToken, permission: Permission,
                        resource_type: str, resource_id: str) -> TenantScope:
        """Get scoped context if authorized."""
        if not self.check_access(token, permission, resource_type, resource_id):
            raise PermissionError(f"User {token.user_id} not authorized")
        
        user = self.tenancy.get_user(token.user_id)
        user_permissions = self.rbac.get_user_permissions(user.roles)
        
        return TenantScope(
            tenant_id=token.tenant_id,
            user_id=token.user_id,
            permissions=user_permissions
        )
    
    def log_audit(self, tenant_id: str, user_id: str, action: str,
                 resource_type: str, resource_id: str,
                 changes: Optional[Dict] = None,
                 ip_address: str = "",
                 status: str = "success"):
        """Log audit entry."""
        entry = AuditLog(
            tenant_id=tenant_id,
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            changes=changes or {},
            ip_address=ip_address,
            status=status
        )
        self.audit_logs.append(entry)
    
    def get_audit_logs(self, tenant_id: str, 
                      since: Optional[datetime] = None,
                      limit: int = 1000) -> List[AuditLog]:
        """Get audit logs for tenant."""
        logs = [l for l in self.audit_logs if l.tenant_id == tenant_id]
        
        if since:
            logs = [l for l in logs if l.timestamp >= since]
        
        return logs[-limit:]


class DataIsolation:
    """Ensures tenant data isolation in queries."""
    
    @staticmethod
    def scope_query(base_query: str, scope: TenantScope,
                   resource_type: str) -> str:
        """Add tenant scope to query."""
        # In production, this would be more sophisticated
        tenant_filter = f"tenant_id={scope.tenant_id}"
        
        if "WHERE" in base_query:
            return base_query.replace("WHERE", f"WHERE {tenant_filter} AND")
        else:
            return f"{base_query} WHERE {tenant_filter}"
    
    @staticmethod
    def filter_results(results: List[Dict[str, Any]], scope: TenantScope) -> List[Dict[str, Any]]:
        """Filter results to tenant scope."""
        return [r for r in results if r.get("tenant_id") == scope.tenant_id]


__all__ = [
    'Permission',
    'Role',
    'RoleDefinition',
    'Tenant',
    'User',
    'AccessToken',
    'AuditLog',
    'TenantScope',
    'RBACManager',
    'MultiTenancyManager',
    'AccessControl',
    'DataIsolation',
]
