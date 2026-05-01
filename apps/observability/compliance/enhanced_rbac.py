"""
Phase 25C: Enhanced RBAC & Access Control

Fine-grained role-based access control with dynamic roles:
- Dynamic role creation and assignment
- Resource-level access control
- Time-based access policies
- Access request/approval workflows
- Comprehensive audit trails

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Any
from datetime import datetime, timedelta
from enum import Enum
import hashlib

logger = logging.getLogger(__name__)


class Permission(Enum):
    """Granular permissions."""
    READ = "read"
    WRITE = "write"
    DELETE = "delete"
    ADMIN = "admin"
    AUDIT = "audit"
    APPROVE = "approve"
    MANAGE_USERS = "manage_users"
    MANAGE_ROLES = "manage_roles"
    MANAGE_KEYS = "manage_keys"


class ResourceType(Enum):
    """Types of resources."""
    DASHBOARD = "dashboard"
    ALERT = "alert"
    QUERY = "query"
    TRACE = "trace"
    METRIC = "metric"
    LOG = "log"
    USER = "user"
    ROLE = "role"
    SYSTEM = "system"
    API_KEY = "api_key"
    ENCRYPTION_KEY = "encryption_key"


class AccessRequestStatus(Enum):
    """Status of access requests."""
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    EXPIRED = "expired"
    REVOKED = "revoked"


@dataclass
class Permission:
    """Permission with resource constraints."""
    permission: str
    resource_type: ResourceType
    resource_id: Optional[str] = None
    constraints: Dict[str, Any] = field(default_factory=dict)


@dataclass
class TimeBasedPolicy:
    """Time-based access policy."""
    policy_id: str
    role_id: str
    start_time: datetime
    end_time: datetime
    days_of_week: Set[int] = field(default_factory=set)  # 0-6 (Mon-Sun)
    time_of_day_start: Optional[str] = None  # "09:00"
    time_of_day_end: Optional[str] = None    # "17:00"
    enabled: bool = True
    reason: Optional[str] = None
    
    @property
    def is_active(self) -> bool:
        """Check if policy is currently active."""
        now = datetime.utcnow()
        if not self.enabled or now < self.start_time or now > self.end_time:
            return False
        
        if self.days_of_week and now.weekday() not in self.days_of_week:
            return False
        
        if self.time_of_day_start and self.time_of_day_end:
            now_str = now.strftime("%H:%M")
            if not (self.time_of_day_start <= now_str <= self.time_of_day_end):
                return False
        
        return True


@dataclass
class Role:
    """Dynamic role with permissions."""
    role_id: str
    name: str
    description: str
    permissions: Set[str] = field(default_factory=set)
    resource_permissions: Dict[ResourceType, Set[str]] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    created_by: Optional[str] = None
    is_system_role: bool = False
    parent_role_id: Optional[str] = None  # For role inheritance
    
    def add_permission(self, permission: str, resource_type: Optional[ResourceType] = None) -> None:
        """Add permission to role."""
        if resource_type:
            if resource_type not in self.resource_permissions:
                self.resource_permissions[resource_type] = set()
            self.resource_permissions[resource_type].add(permission)
        else:
            self.permissions.add(permission)
        self.updated_at = datetime.utcnow()
    
    def remove_permission(self, permission: str, resource_type: Optional[ResourceType] = None) -> None:
        """Remove permission from role."""
        if resource_type and resource_type in self.resource_permissions:
            self.resource_permissions[resource_type].discard(permission)
        else:
            self.permissions.discard(permission)
        self.updated_at = datetime.utcnow()
    
    def has_permission(self, permission: str, resource_type: Optional[ResourceType] = None) -> bool:
        """Check if role has permission."""
        if resource_type:
            return permission in self.resource_permissions.get(resource_type, set())
        return permission in self.permissions


@dataclass
class AccessRequest:
    """Request for temporary access escalation."""
    request_id: str
    user_id: str
    requested_role_id: str
    resource_type: Optional[ResourceType] = None
    resource_id: Optional[str] = None
    reason: str = ""
    requested_at: datetime = field(default_factory=datetime.utcnow)
    requested_duration_hours: int = 2
    expires_at: Optional[datetime] = None
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    status: AccessRequestStatus = AccessRequestStatus.PENDING
    
    @property
    def is_expired(self) -> bool:
        """Check if request has expired."""
        if self.expires_at:
            return datetime.utcnow() > self.expires_at
        return False


@dataclass
class User:
    """User with assigned roles."""
    user_id: str
    name: str
    email: str
    roles: Set[str] = field(default_factory=set)
    temporary_roles: Dict[str, TimeBasedPolicy] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_login: Optional[datetime] = None
    is_active: bool = True
    mfa_enabled: bool = False
    password_last_changed: Optional[datetime] = None
    
    def add_role(self, role_id: str) -> None:
        """Add role to user."""
        self.roles.add(role_id)
    
    def remove_role(self, role_id: str) -> None:
        """Remove role from user."""
        self.roles.discard(role_id)
    
    def has_role(self, role_id: str) -> bool:
        """Check if user has role."""
        return role_id in self.roles


@dataclass
class AuditLogEntry:
    """Audit log entry for access changes."""
    entry_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
    actor_user_id: str = ""
    action: str = ""  # grant_role, revoke_role, access_check, etc.
    target_user_id: Optional[str] = None
    target_role_id: Optional[str] = None
    resource_type: Optional[ResourceType] = None
    resource_id: Optional[str] = None
    result: str = "success"  # success, denied, error
    details: Dict[str, Any] = field(default_factory=dict)
    ip_address: Optional[str] = None


class RBACEngine:
    """Enhanced RBAC engine."""
    
    def __init__(self):
        """Initialize RBAC engine."""
        self.roles: Dict[str, Role] = {}
        self.users: Dict[str, User] = {}
        self.time_policies: Dict[str, TimeBasedPolicy] = {}
        self.access_requests: Dict[str, AccessRequest] = {}
        self.audit_log: List[AuditLogEntry] = []
        self._init_default_roles()
    
    def _init_default_roles(self) -> None:
        """Initialize default system roles."""
        # Admin role
        admin_role = Role(
            role_id="admin",
            name="Administrator",
            description="Full platform access",
            permissions={
                "read", "write", "delete", "admin",
                "manage_users", "manage_roles", "manage_keys"
            },
            is_system_role=True,
        )
        self.roles["admin"] = admin_role
        
        # Editor role
        editor_role = Role(
            role_id="editor",
            name="Editor",
            description="Edit dashboards, alerts, queries",
            permissions={"read", "write"},
            is_system_role=True,
        )
        editor_role.add_permission("read", ResourceType.DASHBOARD)
        editor_role.add_permission("write", ResourceType.DASHBOARD)
        editor_role.add_permission("read", ResourceType.QUERY)
        editor_role.add_permission("write", ResourceType.QUERY)
        self.roles["editor"] = editor_role
        
        # Viewer role
        viewer_role = Role(
            role_id="viewer",
            name="Viewer",
            description="Read-only access",
            permissions={"read"},
            is_system_role=True,
        )
        viewer_role.add_permission("read", ResourceType.DASHBOARD)
        viewer_role.add_permission("read", ResourceType.QUERY)
        viewer_role.add_permission("read", ResourceType.METRIC)
        self.roles["viewer"] = viewer_role
        
        # Operator role
        operator_role = Role(
            role_id="operator",
            name="Operator",
            description="Manage incidents and operations",
            permissions={"read", "write"},
            is_system_role=True,
        )
        operator_role.add_permission("read", ResourceType.ALERT)
        operator_role.add_permission("write", ResourceType.ALERT)
        self.roles["operator"] = operator_role
    
    def create_role(
        self,
        role_id: str,
        name: str,
        description: str,
        created_by: str,
    ) -> Role:
        """Create new custom role."""
        role = Role(
            role_id=role_id,
            name=name,
            description=description,
            created_by=created_by,
        )
        self.roles[role_id] = role
        
        self._audit_log(
            actor=created_by,
            action="create_role",
            target_role_id=role_id,
            result="success"
        )
        
        return role
    
    def create_user(
        self,
        user_id: str,
        name: str,
        email: str,
        roles: Optional[List[str]] = None,
    ) -> User:
        """Create new user."""
        user = User(
            user_id=user_id,
            name=name,
            email=email,
        )
        
        if roles:
            for role_id in roles:
                if role_id in self.roles:
                    user.add_role(role_id)
        
        self.users[user_id] = user
        return user
    
    def grant_role(
        self,
        user_id: str,
        role_id: str,
        actor: str,
    ) -> bool:
        """Grant role to user."""
        if user_id not in self.users or role_id not in self.roles:
            self._audit_log(
                actor=actor,
                action="grant_role",
                target_user_id=user_id,
                target_role_id=role_id,
                result="denied"
            )
            return False
        
        self.users[user_id].add_role(role_id)
        
        self._audit_log(
            actor=actor,
            action="grant_role",
            target_user_id=user_id,
            target_role_id=role_id,
            result="success"
        )
        
        return True
    
    def revoke_role(
        self,
        user_id: str,
        role_id: str,
        actor: str,
    ) -> bool:
        """Revoke role from user."""
        if user_id not in self.users:
            return False
        
        self.users[user_id].remove_role(role_id)
        
        self._audit_log(
            actor=actor,
            action="revoke_role",
            target_user_id=user_id,
            target_role_id=role_id,
            result="success"
        )
        
        return True
    
    def check_access(
        self,
        user_id: str,
        permission: str,
        resource_type: Optional[ResourceType] = None,
        resource_id: Optional[str] = None,
        actor: str = "system",
    ) -> bool:
        """Check if user has access."""
        if user_id not in self.users:
            self._audit_log(
                actor=actor,
                action="access_check",
                target_user_id=user_id,
                resource_type=resource_type,
                resource_id=resource_id,
                result="denied"
            )
            return False
        
        user = self.users[user_id]
        
        # Check permanent roles
        for role_id in user.roles:
            if role_id in self.roles:
                role = self.roles[role_id]
                if role.has_permission(permission, resource_type):
                    self._audit_log(
                        actor=actor,
                        action="access_check",
                        target_user_id=user_id,
                        resource_type=resource_type,
                        result="success"
                    )
                    return True
        
        # Check time-based temporary roles
        for policy in user.temporary_roles.values():
            if policy.is_active and policy.role_id in self.roles:
                role = self.roles[policy.role_id]
                if role.has_permission(permission, resource_type):
                    self._audit_log(
                        actor=actor,
                        action="access_check_temporary",
                        target_user_id=user_id,
                        resource_type=resource_type,
                        result="success"
                    )
                    return True
        
        self._audit_log(
            actor=actor,
            action="access_check",
            target_user_id=user_id,
            resource_type=resource_type,
            result="denied"
        )
        return False
    
    def request_access(
        self,
        user_id: str,
        role_id: str,
        duration_hours: int = 2,
        reason: str = "",
    ) -> AccessRequest:
        """Create access request."""
        request_id = self._generate_id()
        request = AccessRequest(
            request_id=request_id,
            user_id=user_id,
            requested_role_id=role_id,
            requested_duration_hours=duration_hours,
            reason=reason,
            expires_at=datetime.utcnow() + timedelta(hours=24),
        )
        self.access_requests[request_id] = request
        
        self._audit_log(
            actor=user_id,
            action="request_access",
            target_user_id=user_id,
            target_role_id=role_id,
            details={"reason": reason, "duration_hours": duration_hours}
        )
        
        return request
    
    def approve_access_request(
        self,
        request_id: str,
        approved_by: str,
    ) -> bool:
        """Approve access request."""
        if request_id not in self.access_requests:
            return False
        
        request = self.access_requests[request_id]
        if request.status != AccessRequestStatus.PENDING:
            return False
        
        request.status = AccessRequestStatus.APPROVED
        request.approved_by = approved_by
        request.approved_at = datetime.utcnow()
        request.expires_at = datetime.utcnow() + timedelta(hours=request.requested_duration_hours)
        
        # Grant temporary role
        policy = TimeBasedPolicy(
            policy_id=self._generate_id(),
            role_id=request.requested_role_id,
            start_time=datetime.utcnow(),
            end_time=request.expires_at,
            reason=f"Approved access request {request_id}",
        )
        
        user = self.users[request.user_id]
        user.temporary_roles[policy.policy_id] = policy
        
        self._audit_log(
            actor=approved_by,
            action="approve_access",
            target_user_id=request.user_id,
            target_role_id=request.requested_role_id,
            details={"request_id": request_id}
        )
        
        return True
    
    def revoke_access_request(
        self,
        request_id: str,
        revoked_by: str,
    ) -> bool:
        """Revoke access request."""
        if request_id not in self.access_requests:
            return False
        
        request = self.access_requests[request_id]
        request.status = AccessRequestStatus.REVOKED
        
        # Remove temporary roles
        user = self.users[request.user_id]
        user.temporary_roles = {
            pid: p for pid, p in user.temporary_roles.items()
            if p.role_id != request.requested_role_id
        }
        
        self._audit_log(
            actor=revoked_by,
            action="revoke_access",
            target_user_id=request.user_id,
            target_role_id=request.requested_role_id,
            details={"request_id": request_id}
        )
        
        return True
    
    def get_audit_log(
        self,
        user_id: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 100,
    ) -> List[AuditLogEntry]:
        """Get audit log entries."""
        entries = self.audit_log
        
        if user_id:
            entries = [e for e in entries if e.target_user_id == user_id]
        
        if start_time:
            entries = [e for e in entries if e.timestamp >= start_time]
        
        if end_time:
            entries = [e for e in entries if e.timestamp <= end_time]
        
        return entries[-limit:]
    
    def _audit_log(
        self,
        actor: str,
        action: str,
        target_user_id: Optional[str] = None,
        target_role_id: Optional[str] = None,
        resource_type: Optional[ResourceType] = None,
        resource_id: Optional[str] = None,
        result: str = "success",
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        """Add entry to audit log."""
        entry = AuditLogEntry(
            entry_id=self._generate_id(),
            actor_user_id=actor,
            action=action,
            target_user_id=target_user_id,
            target_role_id=target_role_id,
            resource_type=resource_type,
            resource_id=resource_id,
            result=result,
            details=details or {},
        )
        self.audit_log.append(entry)
    
    def _generate_id(self) -> str:
        """Generate unique ID."""
        import time
        import random
        key = f"{time.time()}{random.random()}"
        return hashlib.md5(key.encode()).hexdigest()[:16]


__all__ = [
    "Permission",
    "ResourceType",
    "AccessRequestStatus",
    "TimeBasedPolicy",
    "Role",
    "AccessRequest",
    "User",
    "AuditLogEntry",
    "RBACEngine",
]
