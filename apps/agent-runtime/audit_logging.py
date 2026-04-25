"""
@governance: Audit trail logging — comprehensive logging with correlation tracking
@Purpose: Track all agent actions with correlation IDs for incident investigation
@Author: Autonomous Infrastructure
@Date: 2026-04-25
@Related issues: #1534 (IaC Governance), #1557 (Agent Runtime)

Structured audit logging system for agent execution with correlation tracking
and compliance-ready event records.
"""

import logging
import json
import uuid
from enum import Enum
from typing import Optional, Dict, Any, List
from datetime import datetime
from dataclasses import dataclass, asdict
from contextlib import contextmanager


class AuditEventType(str, Enum):
    """Types of audit events to log"""
    AGENT_STARTUP = "agent.startup"
    AGENT_SHUTDOWN = "agent.shutdown"
    AGENT_HEARTBEAT = "agent.heartbeat"
    
    ACTION_REQUESTED = "action.requested"
    ACTION_CAPABILITY_CHECK = "action.capability_check"
    ACTION_APPROVAL_SUBMITTED = "action.approval_submitted"
    ACTION_APPROVAL_GRANTED = "action.approval_granted"
    ACTION_APPROVAL_DENIED = "action.approval_denied"
    ACTION_APPROVAL_TIMEOUT = "action.approval_timeout"
    ACTION_EXECUTION_STARTED = "action.execution_started"
    ACTION_EXECUTION_COMPLETED = "action.execution_completed"
    ACTION_EXECUTION_FAILED = "action.execution_failed"
    ACTION_EXECUTION_TIMEOUT = "action.execution_timeout"
    
    AUTHENTICATION_SUCCESS = "auth.success"
    AUTHENTICATION_FAILURE = "auth.failure"
    TOKEN_REFRESH = "token.refresh"
    TOKEN_EXPIRATION = "token.expiration"
    
    SANDBOX_VIOLATION = "sandbox.violation"
    RESOURCE_LIMIT_EXCEEDED = "resource.limit_exceeded"
    
    ERROR_CRITICAL = "error.critical"
    ERROR_HIGH = "error.high"
    ERROR_MEDIUM = "error.medium"


@dataclass
class AuditEvent:
    """Structured audit event"""
    event_type: AuditEventType
    timestamp: datetime
    correlation_id: str
    agent_id: Optional[str] = None
    execution_id: Optional[str] = None
    action: Optional[str] = None
    status: str = "success"  # success, failure, pending
    risk_level: Optional[str] = None
    approval_required: Optional[str] = None
    approval_id: Optional[str] = None
    user_id: Optional[str] = None
    details: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    duration_ms: Optional[int] = None
    resource_usage: Optional[Dict[str, Any]] = None
    
    def to_json(self) -> str:
        """Convert to JSON for logging"""
        event_dict = asdict(self)
        event_dict["event_type"] = self.event_type.value
        event_dict["timestamp"] = self.timestamp.isoformat()
        return json.dumps(event_dict, default=str)


class CorrelationContext:
    """Thread-local correlation context for tracking requests"""
    
    def __init__(self):
        self.correlation_id = str(uuid.uuid4())
        self.trace_id = str(uuid.uuid4())
        self.execution_id: Optional[str] = None
        self.agent_id: Optional[str] = None
        self.user_id: Optional[str] = None
        self.parent_correlation_id: Optional[str] = None


class AuditLogger:
    """Comprehensive audit logging system with correlation tracking"""
    
    def __init__(self, logger_name: str = "agent-runtime.audit"):
        self.logger = logging.getLogger(logger_name)
        self.context: Optional[CorrelationContext] = None
        self.event_buffer: List[AuditEvent] = []
        self.readonly_MAX_BUFFER_SIZE = 10000
    
    @contextmanager
    def correlation_scope(
        self,
        agent_id: str,
        execution_id: str,
        user_id: Optional[str] = None
    ):
        """Context manager for correlation tracking"""
        old_context = self.context
        self.context = CorrelationContext()
        self.context.agent_id = agent_id
        self.context.execution_id = execution_id
        self.context.user_id = user_id
        
        try:
            yield self.context
        finally:
            self.context = old_context
    
    def _get_correlation_id(self) -> str:
        """Get current correlation ID or create new one"""
        if self.context:
            return self.context.correlation_id
        return str(uuid.uuid4())
    
    def _get_execution_id(self) -> Optional[str]:
        """Get current execution ID if in scope"""
        if self.context:
            return self.context.execution_id
        return None
    
    def _create_event(
        self,
        event_type: AuditEventType,
        agent_id: Optional[str] = None,
        execution_id: Optional[str] = None,
        **kwargs
    ) -> AuditEvent:
        """Create audit event with context"""
        event = AuditEvent(
            event_type=event_type,
            timestamp=datetime.utcnow(),
            correlation_id=self._get_correlation_id(),
            agent_id=agent_id or (self.context.agent_id if self.context else None),
            execution_id=execution_id or self._get_execution_id(),
            **kwargs
        )
        return event
    
    def log_event(self, event: AuditEvent) -> None:
        """Log an audit event"""
        # Buffer event
        self.event_buffer.append(event)
        if len(self.event_buffer) > self.readonly_MAX_BUFFER_SIZE:
            self.event_buffer.pop(0)
        
        # Log structured event
        log_level = logging.INFO
        if event.status == "failure":
            log_level = logging.ERROR
        
        self.logger.log(
            log_level,
            f"[{event.correlation_id}] {event.event_type.value}: {event.status}",
            extra={
                "correlation_id": event.correlation_id,
                "execution_id": event.execution_id,
                "agent_id": event.agent_id,
                "event_type": event.event_type.value,
                "structured": event.to_json()
            }
        )
    
    def log_action_request(
        self,
        agent_id: str,
        execution_id: str,
        action: str,
        risk_level: str,
        approval_required: str,
        details: Optional[Dict] = None
    ) -> str:
        """Log action request"""
        event = self._create_event(
            AuditEventType.ACTION_REQUESTED,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action,
            risk_level=risk_level,
            approval_required=approval_required,
            details=details
        )
        self.log_event(event)
        return event.correlation_id
    
    def log_capability_check(
        self,
        agent_id: str,
        execution_id: str,
        action: str,
        allowed: bool,
        reason: Optional[str] = None
    ) -> None:
        """Log capability validation"""
        event = self._create_event(
            AuditEventType.ACTION_CAPABILITY_CHECK,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action,
            status="success" if allowed else "failure",
            details={"reason": reason}
        )
        self.log_event(event)
    
    def log_approval_submitted(
        self,
        agent_id: str,
        execution_id: str,
        action: str,
        approval_id: str,
        risk_level: str
    ) -> None:
        """Log approval submission to Paperclip"""
        event = self._create_event(
            AuditEventType.ACTION_APPROVAL_SUBMITTED,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action,
            approval_id=approval_id,
            risk_level=risk_level
        )
        self.log_event(event)
    
    def log_approval_decision(
        self,
        agent_id: str,
        execution_id: str,
        approval_id: str,
        decision: str,  # granted, denied, timeout, expired
        risk_level: str,
        details: Optional[Dict] = None
    ) -> None:
        """Log approval decision from Paperclip"""
        event_type_map = {
            "granted": AuditEventType.ACTION_APPROVAL_GRANTED,
            "denied": AuditEventType.ACTION_APPROVAL_DENIED,
            "timeout": AuditEventType.ACTION_APPROVAL_TIMEOUT,
            "expired": AuditEventType.ACTION_APPROVAL_TIMEOUT,
        }
        
        event = self._create_event(
            event_type_map.get(decision, AuditEventType.ACTION_APPROVAL_DENIED),
            agent_id=agent_id,
            execution_id=execution_id,
            approval_id=approval_id,
            status=decision,
            risk_level=risk_level,
            details=details
        )
        self.log_event(event)
    
    def log_execution_started(
        self,
        agent_id: str,
        execution_id: str,
        action: str
    ) -> None:
        """Log action execution start"""
        event = self._create_event(
            AuditEventType.ACTION_EXECUTION_STARTED,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action
        )
        self.log_event(event)
    
    def log_execution_completed(
        self,
        agent_id: str,
        execution_id: str,
        action: str,
        duration_ms: int,
        resource_usage: Optional[Dict] = None,
        details: Optional[Dict] = None
    ) -> None:
        """Log successful execution"""
        event = self._create_event(
            AuditEventType.ACTION_EXECUTION_COMPLETED,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action,
            status="success",
            duration_ms=duration_ms,
            resource_usage=resource_usage,
            details=details
        )
        self.log_event(event)
    
    def log_execution_failed(
        self,
        agent_id: str,
        execution_id: str,
        action: str,
        error: str,
        duration_ms: Optional[int] = None,
        resource_usage: Optional[Dict] = None
    ) -> None:
        """Log failed execution"""
        event = self._create_event(
            AuditEventType.ACTION_EXECUTION_FAILED,
            agent_id=agent_id,
            execution_id=execution_id,
            action=action,
            status="failure",
            error=error,
            duration_ms=duration_ms,
            resource_usage=resource_usage
        )
        self.log_event(event)
    
    def log_authentication(
        self,
        agent_id: str,
        success: bool,
        error: Optional[str] = None,
        details: Optional[Dict] = None
    ) -> None:
        """Log authentication event"""
        event = self._create_event(
            AuditEventType.AUTHENTICATION_SUCCESS if success else AuditEventType.AUTHENTICATION_FAILURE,
            agent_id=agent_id,
            status="success" if success else "failure",
            error=error,
            details=details
        )
        self.log_event(event)
    
    def log_resource_violation(
        self,
        agent_id: str,
        execution_id: str,
        resource_type: str,
        limit: float,
        used: float,
        details: Optional[Dict] = None
    ) -> None:
        """Log resource limit violation"""
        event = self._create_event(
            AuditEventType.RESOURCE_LIMIT_EXCEEDED,
            agent_id=agent_id,
            execution_id=execution_id,
            status="failure",
            details={
                "resource_type": resource_type,
                "limit": limit,
                "used": used,
                **(details or {})
            }
        )
        self.log_event(event)
    
    def get_event_history(
        self,
        correlation_id: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """Get event history (for diagnostics)"""
        events = self.event_buffer
        
        if correlation_id:
            events = [e for e in events if e.correlation_id == correlation_id]
        
        return [asdict(e) for e in events[-limit:]]
    
    def get_execution_trace(self, execution_id: str) -> List[Dict]:
        """Get all events for an execution (complete trace)"""
        return [
            asdict(e) for e in self.event_buffer 
            if e.execution_id == execution_id
        ]


# Global audit logger instance
_audit_logger = AuditLogger()


def get_audit_logger() -> AuditLogger:
    """Get global audit logger"""
    return _audit_logger
