"""
Phase 25B: Alerting & Notification System

Comprehensive alerting with multi-channel delivery:
- Alert rule engine with templating
- Multi-channel notification delivery
- Alert grouping and deduplication
- Escalation policies and workflows

Author: Observability Platform Team
Version: 1.0.0
License: Apache 2.0
"""

import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Callable, Set
from datetime import datetime, timedelta
from enum import Enum
import hashlib

logger = logging.getLogger(__name__)


class NotificationChannel(Enum):
    """Notification delivery channels."""
    EMAIL = "email"
    SLACK = "slack"
    PAGERDUTY = "pagerduty"
    SMS = "sms"
    WEBHOOK = "webhook"
    LOG = "log"


class AlertSeverity(Enum):
    """Alert severity levels."""
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"
    EMERGENCY = "emergency"


class AlertState(Enum):
    """Alert lifecycle states."""
    FIRING = "firing"
    PENDING = "pending"
    RESOLVED = "resolved"
    ACKNOWLEDGED = "acknowledged"


@dataclass
class AlertRule:
    """Rule for generating alerts."""
    rule_id: str
    name: str
    description: str
    condition: Callable
    severity: AlertSeverity
    enabled: bool = True
    cooldown_minutes: int = 5
    group_by: List[str] = field(default_factory=list)
    channels: List[NotificationChannel] = field(default_factory=list)
    escalation_minutes: int = 30


@dataclass
class Alert:
    """Individual alert instance."""
    alert_id: str
    rule_id: str
    severity: AlertSeverity
    state: AlertState
    title: str
    description: str
    fired_at: datetime
    resolved_at: Optional[datetime] = None
    acknowledged_at: Optional[datetime] = None
    acknowledged_by: Optional[str] = None
    labels: Dict[str, str] = field(default_factory=dict)
    annotations: Dict[str, str] = field(default_factory=dict)
    
    @property
    def duration_seconds(self) -> int:
        """Get alert duration in seconds."""
        end_time = self.resolved_at or datetime.utcnow()
        return int((end_time - self.fired_at).total_seconds())
    
    @property
    def is_active(self) -> bool:
        """Check if alert is active."""
        return self.state == AlertState.FIRING
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "alert_id": self.alert_id,
            "rule_id": self.rule_id,
            "severity": self.severity.value,
            "state": self.state.value,
            "title": self.title,
            "fired_at": self.fired_at.isoformat(),
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
            "duration_seconds": self.duration_seconds,
        }


@dataclass
class AlertGroup:
    """Grouped alerts for batch notification."""
    group_id: str
    alerts: List[Alert] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)
    notified_at: Optional[datetime] = None
    severity: AlertSeverity = AlertSeverity.INFO
    
    @property
    def critical_alerts(self) -> List[Alert]:
        """Get critical alerts in group."""
        return [a for a in self.alerts if a.severity in [AlertSeverity.CRITICAL, AlertSeverity.EMERGENCY]]
    
    def update_severity(self) -> None:
        """Update group severity based on alerts."""
        if self.critical_alerts:
            self.severity = AlertSeverity.CRITICAL
        elif any(a.severity == AlertSeverity.WARNING for a in self.alerts):
            self.severity = AlertSeverity.WARNING
        else:
            self.severity = AlertSeverity.INFO


class NotificationHandler:
    """Handles notification delivery."""
    
    def __init__(self, channel: NotificationChannel):
        """Initialize handler."""
        self.channel = channel
        self.handlers: Dict[NotificationChannel, Callable] = {}
    
    def register_handler(self, channel: NotificationChannel, handler: Callable) -> None:
        """Register channel handler."""
        self.handlers[channel] = handler
    
    async def send(
        self,
        alert: Alert,
        recipients: List[str],
        template: Optional[str] = None,
    ) -> bool:
        """Send notification."""
        handler = self.handlers.get(self.channel)
        if not handler:
            logger.warning(f"No handler for channel: {self.channel.value}")
            return False
        
        try:
            if asyncio.iscoroutinefunction(handler):
                await handler(alert, recipients, template)
            else:
                handler(alert, recipients, template)
            return True
        except Exception as e:
            logger.error(f"Error sending notification: {e}")
            return False


class AlertRuleEngine:
    """Engine for evaluating alert rules."""
    
    def __init__(self):
        """Initialize engine."""
        self.rules: Dict[str, AlertRule] = {}
        self.last_fired: Dict[str, datetime] = {}
        self.active_alerts: Dict[str, Alert] = {}
    
    def register_rule(self, rule: AlertRule) -> None:
        """Register alert rule."""
        self.rules[rule.rule_id] = rule
        logger.info(f"Registered alert rule: {rule.name}")
    
    def evaluate_rules(self, context: Dict[str, Any]) -> List[Alert]:
        """Evaluate all rules against context."""
        fired_alerts = []
        
        for rule_id, rule in self.rules.items():
            if not rule.enabled:
                continue
            
            # Check cooldown
            if rule_id in self.last_fired:
                elapsed = datetime.utcnow() - self.last_fired[rule_id]
                if elapsed.total_seconds() < rule.cooldown_minutes * 60:
                    continue
            
            # Evaluate condition
            try:
                if rule.condition(context):
                    alert = self._create_alert(rule, context)
                    fired_alerts.append(alert)
                    self.last_fired[rule_id] = datetime.utcnow()
            except Exception as e:
                logger.error(f"Error evaluating rule {rule_id}: {e}")
        
        return fired_alerts
    
    def _create_alert(self, rule: AlertRule, context: Dict[str, Any]) -> Alert:
        """Create alert from rule."""
        alert_id = self._generate_alert_id(rule, context)
        
        return Alert(
            alert_id=alert_id,
            rule_id=rule.rule_id,
            severity=rule.severity,
            state=AlertState.FIRING,
            title=rule.name,
            description=rule.description,
            fired_at=datetime.utcnow(),
            labels=context.get("labels", {}),
        )
    
    def _generate_alert_id(self, rule: AlertRule, context: Dict[str, Any]) -> str:
        """Generate unique alert ID."""
        key = f"{rule.rule_id}:{str(context)}"
        return hashlib.md5(key.encode()).hexdigest()[:16]
    
    def record_alert(self, alert: Alert) -> None:
        """Record active alert."""
        self.active_alerts[alert.alert_id] = alert
    
    def resolve_alert(self, alert_id: str) -> Optional[Alert]:
        """Resolve alert."""
        if alert_id in self.active_alerts:
            alert = self.active_alerts[alert_id]
            alert.state = AlertState.RESOLVED
            alert.resolved_at = datetime.utcnow()
            del self.active_alerts[alert_id]
            return alert
        return None
    
    def acknowledge_alert(self, alert_id: str, acknowledged_by: str) -> Optional[Alert]:
        """Acknowledge alert."""
        if alert_id in self.active_alerts:
            alert = self.active_alerts[alert_id]
            alert.state = AlertState.ACKNOWLEDGED
            alert.acknowledged_at = datetime.utcnow()
            alert.acknowledged_by = acknowledged_by
            return alert
        return None


class AlertGrouper:
    """Groups related alerts."""
    
    def __init__(self, group_window_minutes: int = 5):
        """Initialize grouper."""
        self.group_window_minutes = group_window_minutes
        self.groups: Dict[str, AlertGroup] = {}
    
    def group_alerts(self, alerts: List[Alert]) -> List[AlertGroup]:
        """Group alerts."""
        alert_groups = []
        
        for alert in alerts:
            group_id = self._calculate_group_id(alert)
            
            if group_id not in self.groups:
                self.groups[group_id] = AlertGroup(
                    group_id=group_id,
                    created_at=datetime.utcnow(),
                )
            
            self.groups[group_id].alerts.append(alert)
            self.groups[group_id].update_severity()
        
        return list(self.groups.values())
    
    def _calculate_group_id(self, alert: Alert) -> str:
        """Calculate group ID for alert."""
        key = alert.rule_id
        return hashlib.md5(key.encode()).hexdigest()[:16]


class EscalationPolicy:
    """Escalation policy for alerts."""
    
    def __init__(self):
        """Initialize policy."""
        self.escalation_steps: List[Dict[str, Any]] = []
    
    def add_step(
        self,
        minutes: int,
        channels: List[NotificationChannel],
        recipients: List[str],
    ) -> None:
        """Add escalation step."""
        self.escalation_steps.append({
            "minutes": minutes,
            "channels": channels,
            "recipients": recipients,
        })
    
    def get_current_escalation(self, alert_duration_minutes: int) -> Optional[Dict[str, Any]]:
        """Get current escalation step."""
        for step in self.escalation_steps:
            if alert_duration_minutes >= step["minutes"]:
                continue
            return step
        return None


class AlertNotificationManager:
    """Manages alert notifications."""
    
    def __init__(self):
        """Initialize manager."""
        self.rule_engine = AlertRuleEngine()
        self.grouper = AlertGrouper()
        self.escalation_policies: Dict[str, EscalationPolicy] = {}
        self.notification_history: List[Dict[str, Any]] = []
        self.handlers: Dict[NotificationChannel, Callable] = {}
    
    def register_rule(self, rule: AlertRule) -> None:
        """Register alert rule."""
        self.rule_engine.register_rule(rule)
    
    def register_escalation_policy(self, name: str, policy: EscalationPolicy) -> None:
        """Register escalation policy."""
        self.escalation_policies[name] = policy
    
    def register_notification_handler(
        self,
        channel: NotificationChannel,
        handler: Callable
    ) -> None:
        """Register notification handler."""
        self.handlers[channel] = handler
    
    def evaluate_and_notify(self, context: Dict[str, Any]) -> List[Alert]:
        """Evaluate rules and send notifications."""
        # Evaluate rules
        alerts = self.rule_engine.evaluate_rules(context)
        
        if not alerts:
            return []
        
        # Group alerts
        groups = self.grouper.group_alerts(alerts)
        
        # Send notifications
        for group in groups:
            for alert in group.alerts:
                self.rule_engine.record_alert(alert)
                self._send_notifications(alert)
        
        return alerts
    
    def _send_notifications(self, alert: Alert) -> None:
        """Send notifications for alert."""
        rule = self.rule_engine.rules.get(alert.rule_id)
        if not rule:
            return
        
        for channel in rule.channels:
            handler = self.handlers.get(channel)
            if handler:
                try:
                    handler(alert)
                except Exception as e:
                    logger.error(f"Error in notification handler: {e}")
        
        # Record notification
        self.notification_history.append({
            "alert_id": alert.alert_id,
            "timestamp": datetime.utcnow(),
            "channels": [c.value for c in rule.channels],
        })
    
    def get_active_alerts(self) -> List[Alert]:
        """Get all active alerts."""
        return list(self.rule_engine.active_alerts.values())
    
    def get_alert_statistics(self) -> Dict[str, Any]:
        """Get alert statistics."""
        active = self.get_active_alerts()
        
        return {
            "active_alerts": len(active),
            "critical_alerts": len([a for a in active if a.severity == AlertSeverity.CRITICAL]),
            "warning_alerts": len([a for a in active if a.severity == AlertSeverity.WARNING]),
            "total_notifications_sent": len(self.notification_history),
            "active_rules": sum(1 for r in self.rule_engine.rules.values() if r.enabled),
        }


import asyncio
__all__ = [
    "NotificationChannel",
    "AlertSeverity",
    "AlertState",
    "AlertRule",
    "Alert",
    "AlertGroup",
    "NotificationHandler",
    "AlertRuleEngine",
    "AlertGrouper",
    "EscalationPolicy",
    "AlertNotificationManager",
]
