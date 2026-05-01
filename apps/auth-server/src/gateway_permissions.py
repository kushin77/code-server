"""
API Gateway - Permission Enforcement Middleware
Issue #1345 Week 5: API Gateway Integration
"""
from typing import Optional, List, Dict, Any, Callable
from functools import wraps
from log import get_logger

from fastapi import Request, HTTPException

logger = get_logger(__name__)


# ============================================================================
# Permission Enforcement
# ============================================================================

class PermissionEnforcer:
    """Enforce permissions at API boundary"""
    
    def __init__(self, db_session, config):
        self.db = db_session
        self.config = config
    
    def require_permission(
        self,
        required_permission: str,
        resource_type: Optional[str] = None,
    ):
        """Decorator to require specific permission"""
        
        def decorator(func: Callable):
            @wraps(func)
            async def wrapper(*args, **kwargs):
                # Get current user from request
                request: Request = args[0] if args else None
                if not request:
                    raise HTTPException(status_code=401, detail="Not authenticated")
                
                # Extract user info
                user = request.state.user
                if not user:
                    raise HTTPException(status_code=401, detail="Not authenticated")
                
                # Get resource ID if applicable
                resource_id = kwargs.get("resource_id") or kwargs.get("id")
                
                # Check permission
                has_permission = self.check_permission(
                    user_id=user.get("user_id"),
                    permission=required_permission,
                    resource_type=resource_type,
                    resource_id=resource_id,
                )
                
                if not has_permission:
                    raise HTTPException(
                        status_code=403,
                        detail=f"Insufficient permissions for {required_permission}"
                    )
                
                return await func(*args, **kwargs)
            
            return wrapper
        return decorator
    
    def check_permission(
        self,
        user_id: str,
        permission: str,
        resource_type: Optional[str] = None,
        resource_id: Optional[str] = None,
    ) -> bool:
        """Check if user has permission"""
        
        try:
            # Get user roles
            user_roles = self._get_user_roles(user_id)
            
            # Get permissions for all roles
            all_permissions = set()
            for role in user_roles:
                permissions = self._get_role_permissions(role)
                all_permissions.update(permissions)
            
            # Check for wildcard permission (e.g., admin)
            if "*" in all_permissions:
                return True
            
            # Check specific resource permission
            if resource_type and resource_id:
                # Check resource-specific permission
                has_resource_access = self._check_resource_access(
                    user_id=user_id,
                    resource_type=resource_type,
                    resource_id=resource_id,
                    permission=permission,
                )
                if not has_resource_access:
                    return False
            
            # Check permission
            return permission in all_permissions or f"{resource_type}:{permission}" in all_permissions
        
        except Exception as e:
            logger.error(f"Permission check failed: {str(e)}")
            return False
    
    def check_team_access(
        self,
        user_id: str,
        team_id: str,
    ) -> bool:
        """Check if user has access to team"""
        
        # Check if user is member of team
        return self._is_team_member(user_id, team_id)
    
    def check_org_access(
        self,
        user_id: str,
        org_id: str,
    ) -> bool:
        """Check if user has access to organization"""
        
        return self._is_org_member(user_id, org_id)
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _get_user_roles(self, user_id: str) -> List[str]:
        """Get user roles"""
        # In production: query roles from User/Role junction table
        return []
    
    def _get_role_permissions(self, role: str) -> List[str]:
        """Get permissions for role"""
        
        # Define permission matrix
        permission_matrix = {
            "admin": ["*"],  # Admin has all permissions
            "owner": ["read", "write", "admin", "delete"],
            "maintainer": ["read", "write", "approve"],
            "developer": ["read", "write"],
            "viewer": ["read"],
        }
        
        return permission_matrix.get(role, [])
    
    def _check_resource_access(
        self,
        user_id: str,
        resource_type: str,
        resource_id: str,
        permission: str,
    ) -> bool:
        """Check resource-specific access"""
        # In production: query ResourceAccess table
        return True
    
    def _is_team_member(self, user_id: str, team_id: str) -> bool:
        """Check if user is team member"""
        # In production: query TeamMember where user_id=? and team_id=?
        return False
    
    def _is_org_member(self, user_id: str, org_id: str) -> bool:
        """Check if user is org member"""
        # In production: query OrganizationMember where user_id=? and org_id=?
        return False


# ============================================================================
# RBAC (Role-Based Access Control) Middleware
# ============================================================================

class RBACMiddleware:
    """Role-Based Access Control middleware"""
    
    def __init__(self, app, permission_enforcer: PermissionEnforcer):
        self.app = app
        self.enforcer = permission_enforcer
    
    async def __call__(self, request: Request, call_next):
        """Check RBAC before processing request"""
        
        # Get current user
        user = getattr(request.state, "user", None)
        if not user:
            return await call_next(request)
        
        # Check endpoint permissions
        # This would be configured per route
        permission_required = self._get_endpoint_permission(request.url.path, request.method)
        
        if permission_required:
            if not self.enforcer.check_permission(
                user_id=user.get("user_id"),
                permission=permission_required,
            ):
                return HTTPException(
                    status_code=403,
                    detail="Insufficient permissions"
                )
        
        response = await call_next(request)
        return response
    
    def _get_endpoint_permission(self, path: str, method: str) -> Optional[str]:
        """Get required permission for endpoint"""
        
        # Define permission mappings
        permissions_map = {
            ("GET", "/api/users"): "read:users",
            ("POST", "/api/users"): "write:users",
            ("PUT", "/api/users/*"): "write:users",
            ("DELETE", "/api/users/*"): "delete:users",
            ("GET", "/api/teams"): "read:teams",
            ("POST", "/api/teams"): "write:teams",
            ("GET", "/api/organizations"): "read:orgs",
            ("POST", "/api/organizations"): "write:orgs",
        }
        
        for (method_pattern, path_pattern), permission in permissions_map.items():
            if self._matches_pattern(path, path_pattern) and method == method_pattern:
                return permission
        
        return None
    
    def _matches_pattern(self, path: str, pattern: str) -> bool:
        """Check if path matches pattern"""
        # Handle wildcard patterns
        if "*" in pattern:
            base = pattern.replace("/*", "")
            return path.startswith(base)
        return path == pattern
