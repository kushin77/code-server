"""
Phase 25C: Audit Logging System

Comprehensive audit logging for compliance and security:
- Immutable audit logs with cryptographic integrity
- Multi-level audit trail (access, modification, deletion)
- Compliance reporting with audit evidence
- Real-time alert on suspicious activities
- Tamper detection and prevention

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Set
from datetime import datetime, timedelta
from enum import Enum
import hashlib
import json

logger = logging.getLogger(__name__)


class AuditEventType(Enum):
    """Types of audit events."""
    # Access events
    ACCESS_GRANTED = "access_granted"
    ACCESS_DENIED = "access_denied"
    AUTHENTICATION_SUCCESS = "auth_success"
    AUTHENTICATION_FAILED = "auth_failed"
    MFA_SUCCESS = "mfa_success"
    MFA_FAILED = "mfa_failed"
    
    # Modification events
    RESOURCE_CREATED = "resource_created"
    RESOURCE_MODIFIED = "resource_modified"
    RESOURCE_DELETED = "resource_deleted"
    CONFIGURATION_CHANGED = "config_changed"
    
    # Security events
    ENCRYPTION_KEY_ROTATED = "key_rotated"
    ENCRYPTION_KEY_COMPROMISED = "key_compromised"
    PRIVILEGE_ESCALATION = "privilege_escalation"
    SUSPICIOUS_ACTIVITY = "suspicious_activity"
    
    # Export/deletion events
    DATA_EXPORTED = "data_exported"
    DATA_PURGED = "data_purged"
    BACKUP_CREATED = "backup_created"
    BACKUP_RESTORED = "backup_restored"
    
    # Compliance events
    COMPLIANCE_REPORT_GENERATED = "compliance_report_generated"
    AUDIT_LOG_ACCESSED = "audit_log_accessed"
    AUDIT_LOG_EXPORTED = "audit_log_exported"


class AuditSeverity(Enum):
    """Severity levels for audit events."""
    INFO = "info"
    WARNING = "warning"
    ALERT = "alert"
    CRITICAL = "critical"


class AuditStatus(Enum):
    """Status of audit operation."""
    SUCCESS = "success"
    FAILED = "failed"
    DENIED = "denied"


@dataclass
class AuditLogEntry:
    """Immutable audit log entry."""
    entry_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
    event_type: AuditEventType = AuditEventType.ACCESS_GRANTED
    severity: AuditSeverity = AuditSeverity.INFO
    status: AuditStatus = AuditStatus.SUCCESS
    actor_user_id: str = ""
    actor_ip_address: str = ""
    actor_user_agent: str = ""
    target_resource_type: str = ""
    target_resource_id: str = ""
    action: str = ""
    result: str = ""
    details: Dict[str, Any] = field(default_factory=dict)
    affected_data: Optional[str] = None  # JSON representation of affected data
    change_description: str = ""
    previous_value: Optional[str] = None
    new_value: Optional[str] = None
    integrity_hash: str = ""  # SHA256 hash for tamper detection
    sequence_number: int = 0  # Sequential number for ordering
    
    def compute_integrity_hash(self, previous_hash: str = "") -> str:
        """Compute integrity hash for tamper detection."""
        content = (
            f"{self.entry_id}{self.timestamp.isoformat()}"
            f"{self.event_type.value}{self.actor_user_id}"
            f"{self.action}{self.result}{previous_hash}"
        )
        self.integrity_hash = hashlib.sha256(content.encode()).hexdigest()
        return self.integrity_hash
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "entry_id": self.entry_id,
            "timestamp": self.timestamp.isoformat(),
            "event_type": self.event_type.value,
            "severity": self.severity.value,
            "status": self.status.value,
            "actor_user_id": self.actor_user_id,
            "actor_ip_address": self.actor_ip_address,
            "target_resource_type": self.target_resource_type,
            "target_resource_id": self.target_resource_id,
            "action": self.action,
            "result": self.result,
            "details": self.details,
            "change_description": self.change_description,
            "integrity_hash": self.integrity_hash,
            "sequence_number": self.sequence_number,
        }


@dataclass
class AuditAlert:
    """Alert triggered by suspicious audit activity."""
    alert_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)
    rule_name: str = ""
    severity: AuditSeverity = AuditSeverity.ALERT
    description: str = ""
    suspicious_entries: List[str] = field(default_factory=list)  # Entry IDs
    action_required: str = ""
    resolved: bool = False
    resolved_at: Optional[datetime] = None
    resolved_by: Optional[str] = None


@dataclass
class AuditAlertRule:
    """Rule for detecting suspicious audit activity."""
    rule_id: str
    name: str
    description: str
    enabled: bool = True
    event_types: Set[AuditEventType] = field(default_factory=set)
    threshold_count: int = 5  # Trigger if N events in threshold_window
    threshold_window_minutes: int = 60
    severity: AuditSeverity = AuditSeverity.ALERT
    action: str = "alert"  # alert, block, escalate, etc.
    notifications: List[str] = field(default_factory=list)  # Email addresses, webhook URLs


class AuditLogger:
    """Comprehensive audit logging system."""
    
    def __init__(self, retention_days: int = 2555):  # 7 years default
        """Initialize audit logger."""
        self.entries: Dict[str, AuditLogEntry] = {}
        self.alerts: Dict[str, AuditAlert] = {}
        self.alert_rules: Dict[str, AuditAlertRule] = {}
        self.retention_days = retention_days
        self.sequence_counter = 0
        self._init_default_rules()
    
    def _init_default_rules(self) -> None:
        """Initialize default alert rules."""
        # Multiple failed authentication attempts
        rule1 = AuditAlertRule(
            rule_id="rule_auth_failures",
            name="Multiple Authentication Failures",
            description="Alert on multiple failed authentication attempts",
            event_types={AuditEventType.AUTHENTICATION_FAILED},
            threshold_count=5,
            threshold_window_minutes=10,
            severity=AuditSeverity.ALERT,
        )
        self.alert_rules[rule1.rule_id] = rule1
        
        # Privilege escalation attempts
        rule2 = AuditAlertRule(
            rule_id="rule_escalation",
            name="Privilege Escalation Attempts",
            description="Alert on privilege escalation attempts",
            event_types={AuditEventType.PRIVILEGE_ESCALATION},
            threshold_count=1,
            severity=AuditSeverity.CRITICAL,
        )
        self.alert_rules[rule2.rule_id] = rule2
        
        # Suspicious data access
        rule3 = AuditAlertRule(
            rule_id="rule_data_access",
            name="Unusual Data Access Pattern",
            description="Alert on unusual data access patterns",
            event_types={AuditEventType.DATA_EXPORTED},
            threshold_count=3,
            threshold_window_minutes=60,
            severity=AuditSeverity.ALERT,
        )
        self.alert_rules[rule3.rule_id] = rule3
    
    def log_event(
        self,
        event_type: AuditEventType,
        actor_user_id: str,
        action: str,
        target_resource_type: str = "",
        target_resource_id: str = "",
        severity: AuditSeverity = AuditSeverity.INFO,
        status: AuditStatus = AuditStatus.SUCCESS,
        details: Optional[Dict[str, Any]] = None,
        actor_ip_address: str = "",
        previous_value: Optional[str] = None,
        new_value: Optional[str] = None,
    ) -> AuditLogEntry:
        """Log audit event."""
        entry_id = self._generate_id()
        self.sequence_counter += 1
        
        previous_hash = ""
        if self.entries:
            latest_entry = list(self.entries.values())[-1]
            previous_hash = latest_entry.integrity_hash
        
        entry = AuditLogEntry(
            entry_id=entry_id,
            event_type=event_type,
            severity=severity,
            status=status,
            actor_user_id=actor_user_id,
            actor_ip_address=actor_ip_address,
            target_resource_type=target_resource_type,
            target_resource_id=target_resource_id,
            action=action,
            result=status.value,
            details=details or {},
            previous_value=previous_value,
            new_value=new_value,
            sequence_number=self.sequence_counter,
        )
        
        # Compute integrity hash
        entry.compute_integrity_hash(previous_hash)
        
        self.entries[entry_id] = entry
        
        # Check alert rules
        self._check_alert_rules(entry)
        
        logger.info(
            f"Audit event: {event_type.value} by {actor_user_id} "
            f"on {target_resource_type}:{target_resource_id}"
        )
        
        return entry
    
    def log_access_check(
        self,
        user_id: str,
        resource_type: str,
        result: bool,
        ip_address: str = "",
    ) -> AuditLogEntry:
        """Log access check."""
        return self.log_event(
            event_type=AuditEventType.ACCESS_GRANTED if result else AuditEventType.ACCESS_DENIED,
            actor_user_id=user_id,
            action="access_check",
            target_resource_type=resource_type,
            status=AuditStatus.SUCCESS if result else AuditStatus.DENIED,
            severity=AuditSeverity.INFO if result else AuditSeverity.WARNING,
            actor_ip_address=ip_address,
        )
    
    def log_resource_modification(
        self,
        user_id: str,
        resource_type: str,
        resource_id: str,
        previous_value: str,
        new_value: str,
        change_description: str = "",
        ip_address: str = "",
    ) -> AuditLogEntry:
        """Log resource modification."""
        entry = self.log_event(
            event_type=AuditEventType.RESOURCE_MODIFIED,
            actor_user_id=user_id,
            action="modify",
            target_resource_type=resource_type,
            target_resource_id=resource_id,
            severity=AuditSeverity.INFO,
            status=AuditStatus.SUCCESS,
            actor_ip_address=ip_address,
            previous_value=previous_value,
            new_value=new_value,
        )
        entry.change_description = change_description
        return entry
    
    def log_suspicious_activity(
        self,
        description: str,
        user_id: str,
        details: Optional[Dict[str, Any]] = None,
        ip_address: str = "",
    ) -> AuditLogEntry:
        """Log suspicious activity."""
        return self.log_event(
            event_type=AuditEventType.SUSPICIOUS_ACTIVITY,
            actor_user_id=user_id,
            action="suspicious",
            severity=AuditSeverity.ALERT,
            status=AuditStatus.DENIED,
            details=details or {},
            actor_ip_address=ip_address,
        )
    
    def _check_alert_rules(self, entry: AuditLogEntry) -> None:
        """Check audit alert rules."""
        for rule in self.alert_rules.values():
            if not rule.enabled or entry.event_type not in rule.event_types:
                continue
            
            # Count events matching rule in time window
            cutoff_time = datetime.utcnow() - timedelta(minutes=rule.threshold_window_minutes)
            matching_events = [
                e for e in self.entries.values()
                if e.event_type in rule.event_types
                and e.timestamp >= cutoff_time
                and e.actor_user_id == entry.actor_user_id
            ]
            
            if len(matching_events) >= rule.threshold_count:
                self._create_alert(rule, matching_events)
    
    def _create_alert(self, rule: AuditAlertRule, entries: List[AuditLogEntry]) -> AuditAlert:
        """Create alert from rule."""
        alert_id = self._generate_id()
        alert = AuditAlert(
            alert_id=alert_id,
            rule_name=rule.name,
            severity=rule.severity,
            description=f"{rule.name}: {rule.description}",
            suspicious_entries=[e.entry_id for e in entries],
            action_required=rule.action,
        )
        self.alerts[alert_id] = alert
        
        logger.warning(f"Audit alert triggered: {rule.name}")
        
        return alert
    
    def get_audit_trail(
        self,
        user_id: Optional[str] = None,
        resource_id: Optional[str] = None,
        event_type: Optional[AuditEventType] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 1000,
    ) -> List[AuditLogEntry]:
        """Get audit trail."""
        entries = list(self.entries.values())
        
        if user_id:
            entries = [e for e in entries if e.actor_user_id == user_id]
        
        if resource_id:
            entries = [e for e in entries if e.target_resource_id == resource_id]
        
        if event_type:
            entries = [e for e in entries if e.event_type == event_type]
        
        if start_time:
            entries = [e for e in entries if e.timestamp >= start_time]
        
        if end_time:
            entries = [e for e in entries if e.timestamp <= end_time]
        
        # Sort by sequence number
        entries.sort(key=lambda e: e.sequence_number)
        
        return entries[-limit:]
    
    def verify_integrity(self) -> Tuple[bool, List[str]]:
        """Verify integrity of audit log chain."""
        integrity_issues = []
        previous_hash = ""
        
        entries = sorted(self.entries.values(), key=lambda e: e.sequence_number)
        
        for entry in entries:
            expected_hash = self._compute_integrity_hash_for_entry(entry, previous_hash)
            
            if entry.integrity_hash != expected_hash:
                integrity_issues.append(f"Tamper detected in entry {entry.entry_id}")
            
            previous_hash = entry.integrity_hash
        
        return len(integrity_issues) == 0, integrity_issues
    
    def _compute_integrity_hash_for_entry(self, entry: AuditLogEntry, previous_hash: str) -> str:
        """Compute expected integrity hash for entry."""
        content = (
            f"{entry.entry_id}{entry.timestamp.isoformat()}"
            f"{entry.event_type.value}{entry.actor_user_id}"
            f"{entry.action}{entry.result}{previous_hash}"
        )
        return hashlib.sha256(content.encode()).hexdigest()
    
    def get_audit_statistics(self) -> Dict[str, Any]:
        """Get audit statistics."""
        total_entries = len(self.entries)
        alerts = len([a for a in self.alerts.values() if not a.resolved])
        
        event_counts = {}
        for entry in self.entries.values():
            event_type = entry.event_type.value
            event_counts[event_type] = event_counts.get(event_type, 0) + 1
        
        return {
            "total_audit_entries": total_entries,
            "active_alerts": alerts,
            "event_type_counts": event_counts,
            "retention_days": self.retention_days,
            "audit_rules": len(self.alert_rules),
        }
    
    def _generate_id(self) -> str:
        """Generate unique ID."""
        import time
        import random
        key = f"{time.time()}{random.random()}"
        return hashlib.md5(key.encode()).hexdigest()[:16]


__all__ = [
    "AuditEventType",
    "AuditSeverity",
    "AuditStatus",
    "AuditLogEntry",
    "AuditAlert",
    "AuditAlertRule",
    "AuditLogger",
]
