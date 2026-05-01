"""
Single Sign-Out (SLO) and Session Management
Issue #1345 Week 4: Advanced Authentication Features
"""
import uuid
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from log import get_logger

from sqlalchemy.orm import Session

logger = get_logger(__name__)


# ============================================================================
# Single Sign-Out Service
# ============================================================================

class SingleSignOutService:
    """Service for handling single sign-out and session management"""
    
    def __init__(self, db_session: Session, redis_client, config):
        self.db = db_session
        self.redis = redis_client
        self.config = config
    
    def sign_out_user(self, user_id: str, revoke_all_sessions: bool = False) -> Dict[str, Any]:
        """Sign out user, optionally from all devices"""
        
        try:
            # Get all refresh tokens for user
            refresh_tokens = self._get_user_refresh_tokens(user_id)
            
            if revoke_all_sessions:
                # Revoke all refresh tokens
                for token in refresh_tokens:
                    self._revoke_token(token.id)
                logger.info(f"Revoked all sessions for user {user_id}")
                count = len(refresh_tokens)
            else:
                # Revoke only current session (first/most recent)
                if refresh_tokens:
                    self._revoke_token(refresh_tokens[0].id)
                    count = 1
                logger.info(f"Revoked current session for user {user_id}")
            
            return {
                "status": "signed_out",
                "user_id": user_id,
                "revoked_sessions": count,
            }
        
        except Exception as e:
            logger.error(f"Failed to sign out user: {str(e)}")
            raise
    
    def revoke_device_session(self, user_id: str, device_id: str) -> Dict[str, Any]:
        """Revoke all sessions for specific device"""
        
        try:
            # Get sessions for device
            sessions = self._get_device_sessions(user_id, device_id)
            
            for session in sessions:
                self._revoke_token(session.token_id)
            
            logger.info(f"Revoked {len(sessions)} sessions for device {device_id}")
            
            return {
                "status": "revoked",
                "device_id": device_id,
                "revoked_sessions": len(sessions),
            }
        
        except Exception as e:
            logger.error(f"Failed to revoke device session: {str(e)}")
            raise
    
    def invalidate_all_tokens(self, user_id: str) -> Dict[str, Any]:
        """Invalidate all tokens (nuclear option)"""
        
        try:
            # Get all tokens for user
            tokens = self._get_all_user_tokens(user_id)
            
            for token in tokens:
                self._revoke_token(token.id)
            
            # Increment token version to invalidate JWTs
            self._increment_token_version(user_id)
            
            logger.warning(f"Invalidated all tokens for user {user_id}")
            
            return {
                "status": "invalidated",
                "user_id": user_id,
                "invalidated_count": len(tokens),
            }
        
        except Exception as e:
            logger.error(f"Failed to invalidate tokens: {str(e)}")
            raise
    
    def get_active_sessions(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all active sessions for user"""
        
        sessions = self._get_user_sessions(user_id)
        
        return [
            {
                "session_id": str(session.id),
                "device_id": session.device_id,
                "device_name": session.device_name,
                "ip_address": session.ip_address,
                "user_agent": session.user_agent,
                "last_activity": session.last_activity.isoformat() if session.last_activity else None,
                "created_at": session.created_at.isoformat(),
            }
            for session in sessions
        ]
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _get_user_refresh_tokens(self, user_id: str) -> List[Any]:
        """Get all refresh tokens for user"""
        # In production: query RefreshToken where user_id=? and revoked_at IS NULL
        return []
    
    def _get_user_sessions(self, user_id: str) -> List[Any]:
        """Get all active sessions"""
        # In production: query UserSession where user_id=? and revoked_at IS NULL
        return []
    
    def _get_device_sessions(self, user_id: str, device_id: str) -> List[Any]:
        """Get sessions for specific device"""
        # In production: query UserSession where user_id=? and device_id=? and revoked_at IS NULL
        return []
    
    def _get_all_user_tokens(self, user_id: str) -> List[Any]:
        """Get all tokens (including revoked)"""
        # In production: query RefreshToken where user_id=?
        return []
    
    def _revoke_token(self, token_id: str) -> None:
        """Revoke a refresh token"""
        # In production: update RefreshToken set revoked_at=now() where id=?
        # Also set in Redis blacklist for JWT validation
        self.redis.setex(f"blacklist:{token_id}", 86400 * 30, "revoked")
    
    def _increment_token_version(self, user_id: str) -> None:
        """Increment token version to invalidate all JWTs"""
        # In production: update User set token_version = token_version + 1 where id=?
        pass


# ============================================================================
# Session Management
# ============================================================================

class SessionManagementService:
    """Service for session and device tracking"""
    
    def __init__(self, db_session: Session, config):
        self.db = db_session
        self.config = config
    
    def create_session(
        self,
        user_id: str,
        device_id: str,
        device_name: str,
        ip_address: str,
        user_agent: str,
        refresh_token: str,
    ) -> Dict[str, Any]:
        """Create new session"""
        
        try:
            session = self._create_user_session(
                user_id=user_id,
                device_id=device_id,
                device_name=device_name,
                ip_address=ip_address,
                user_agent=user_agent,
                refresh_token=refresh_token,
            )
            
            logger.info(f"Created session for user {user_id} on device {device_id}")
            
            return {
                "session_id": str(session.id),
                "device_id": device_id,
                "status": "created",
            }
        
        except Exception as e:
            logger.error(f"Failed to create session: {str(e)}")
            raise
    
    def update_session_activity(self, session_id: str) -> None:
        """Update last activity timestamp"""
        self._update_session_activity(session_id)
    
    def list_user_devices(self, user_id: str) -> List[Dict[str, Any]]:
        """List all devices for user"""
        
        devices = self._get_user_devices(user_id)
        
        return [
            {
                "device_id": device.device_id,
                "device_name": device.device_name,
                "device_type": device.device_type,
                "os": device.os,
                "browser": device.browser,
                "ip_address": device.ip_address,
                "last_seen": device.last_seen.isoformat() if device.last_seen else None,
                "created_at": device.created_at.isoformat(),
                "is_current": device.is_current,
            }
            for device in devices
        ]
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _create_user_session(self, **kwargs) -> Any:
        """Create user session record"""
        return type('UserSession', (), kwargs)()
    
    def _update_session_activity(self, session_id: str) -> None:
        """Update last activity time"""
        # In production: update UserSession set last_activity=now() where id=?
        pass
    
    def _get_user_devices(self, user_id: str) -> List[Any]:
        """Get all devices for user"""
        # In production: query UserDevice where user_id=?
        return []
