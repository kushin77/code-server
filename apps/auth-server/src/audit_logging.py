"""
Audit Log Retention & Cleanup Service
Issue #1545: Enterprise SSO Portal - Audit Log Retention Policy
"""
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

from log import get_logger
from apps._shared.python.exceptions import (
    DatabaseException, ServiceException
)

logger = get_logger(__name__)


class AuditLogRetentionPolicy:
    """
    Manages audit log retention and automatic cleanup.
    
    Policy:
    - Retain audit logs for 1+ year (365 days)
    - Automatically delete logs older than retention period
    - Support configurable retention duration
    - Log cleanup operations for compliance auditing
    """
    
    # Default retention period in days
    DEFAULT_RETENTION_DAYS = 365
    
    def __init__(self, retention_days: Optional[int] = None):
        """
        Initialize audit log retention policy.
        
        Args:
            retention_days: Number of days to retain logs (default: 365)
        """
        self.retention_days = retention_days or self.DEFAULT_RETENTION_DAYS
        self.retention_seconds = self.retention_days * 24 * 3600
        logger.info(
            f"Audit log retention policy initialized: {self.retention_days} days retention"
        )
    
    def get_cutoff_date(self) -> datetime:
        """Get the date before which logs should be deleted."""
        return datetime.utcnow() - timedelta(days=self.retention_days)
    
    def should_delete(self, created_at: datetime) -> bool:
        """
        Check if an audit log should be deleted based on retention policy.
        
        Args:
            created_at: Timestamp when log was created
        
        Returns:
            True if log is older than retention period
        """
        cutoff_date = self.get_cutoff_date()
        return created_at < cutoff_date
    
    async def cleanup_expired_logs(self, db_session) -> Dict[str, Any]:
        """
        Delete audit logs older than retention period.
        
        This should be called periodically (e.g., daily via background job).
        
        Args:
            db_session: SQLAlchemy async database session
        
        Returns:
            Dictionary with cleanup statistics
        """
        try:
            from src.models import OAuthAuditLog
            
            cutoff_date = self.get_cutoff_date()
            
            # Query logs older than cutoff
            from sqlalchemy import delete
            
            stmt = delete(OAuthAuditLog).where(OAuthAuditLog.created_at < cutoff_date)
            result = await db_session.execute(stmt)
            deleted_count = result.rowcount
            
            # Commit the deletion
            await db_session.commit()
            
            cleanup_stats = {
                "success": True,
                "deleted_count": deleted_count,
                "cutoff_date": cutoff_date.isoformat(),
                "retention_days": self.retention_days,
                "timestamp": datetime.utcnow().isoformat(),
            }
            
            logger.info(
                f"Audit log cleanup completed: deleted {deleted_count} logs older than "
                f"{self.retention_days} days (cutoff: {cutoff_date})"
            )
            
            return cleanup_stats
        
        except Exception as e:
            logger.error(f"Audit log cleanup failed: {str(e)}")
            return {
                "success": False,
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat(),
            }
    
    def get_policy_info(self) -> Dict[str, Any]:
        """Get information about the current retention policy."""
        return {
            "retention_days": self.retention_days,
            "retention_seconds": self.retention_seconds,
            "current_cutoff_date": self.get_cutoff_date().isoformat(),
            "policy_name": "Audit Log Retention Policy (1+ Year)",
        }


class AuditLogService:
    """
    Service for creating and managing audit logs.
    
    Features:
    - Log authorization, token, and security events
    - Automatic retention policy enforcement
    - Structured logging format
    """
    
    # Event types
    EVENT_AUTHORIZE = "authorize"
    EVENT_TOKEN_EXCHANGE = "token_exchange"
    EVENT_TOKEN_REFRESH = "refresh"
    EVENT_TOKEN_REVOKE = "revoke"
    EVENT_MFA_SETUP = "mfa_setup"
    EVENT_MFA_VERIFY = "mfa_verify"
    EVENT_LOGIN = "login"
    EVENT_LOGIN_FAILED = "login_failed"
    EVENT_ACCOUNT_UPDATE = "account_update"
    
    # Event statuses
    STATUS_SUCCESS = "success"
    STATUS_FAILURE = "failure"
    STATUS_DENIED = "denied"
    
    def __init__(self, retention_policy: Optional[AuditLogRetentionPolicy] = None):
        """
        Initialize audit log service.
        
        Args:
            retention_policy: Custom retention policy (uses default if None)
        """
        self.retention_policy = retention_policy or AuditLogRetentionPolicy()
    
    def create_audit_log(
        self,
        event_type: str,
        status: str,
        user_id: Optional[str] = None,
        client_id: Optional[str] = None,
        provider: Optional[str] = None,
        scope: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Create an audit log entry.
        
        Args:
            event_type: Type of event (authorize, token_exchange, etc.)
            status: Event status (success, failure, denied)
            user_id: User ID (if applicable)
            client_id: Client ID (if applicable)
            provider: OAuth provider (github, google, etc.)
            scope: Authorization scope requested
            ip_address: Client IP address
            user_agent: Client user agent
            error_message: Error message if status is failure
            metadata: Additional metadata as dict
        
        Returns:
            Dictionary representation of the audit log entry
        """
        return {
            "event_type": event_type,
            "status": status,
            "user_id": user_id,
            "client_id": client_id,
            "provider": provider,
            "scope": scope,
            "ip_address": ip_address,
            "user_agent": user_agent,
            "error_message": error_message,
            "metadata": metadata or {},
            "created_at": datetime.utcnow().isoformat(),
        }
    
    def get_retention_policy_info(self) -> Dict[str, Any]:
        """Get information about the audit log retention policy."""
        return self.retention_policy.get_policy_info()


def setup_audit_logging(config) -> AuditLogService:
    """
    Setup audit logging service with retention policy.
    
    Args:
        config: Configuration object
    
    Returns:
        Configured AuditLogService instance
    """
    # Get retention days from config if available
    retention_days = getattr(config, "AUDIT_LOG_RETENTION_DAYS", 365)
    
    # Create retention policy
    retention_policy = AuditLogRetentionPolicy(retention_days=retention_days)
    
    # Create audit log service
    audit_service = AuditLogService(retention_policy=retention_policy)
    
    logger.info(
        f"Audit logging service initialized with {retention_days}-day retention policy"
    )
    
    return audit_service
