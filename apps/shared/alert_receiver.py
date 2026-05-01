"""Alert webhook receiver for Prometheus alerts.

Receives and routes alerts from Prometheus AlertManager to:
- Slack channels
- PagerDuty incidents
- Local logging/storage

Implements AlertManager webhook format.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from .ai_operations import AIOperationsAdvisor

logger = logging.getLogger(__name__)


class AlertSeverity(str, Enum):
    """Alert severity levels."""

    CRITICAL = "critical"
    WARNING = "warning"
    INFO = "info"


@dataclass
class Alert:
    """Parsed Prometheus alert."""

    labels: Dict[str, str]
    annotations: Dict[str, str]
    startsAt: str
    endsAt: Optional[str] = None
    status: str = "firing"

    @property
    def severity(self) -> AlertSeverity:
        """Get alert severity from labels."""
        severity_str = self.labels.get("severity", "info").lower()
        try:
            return AlertSeverity(severity_str)
        except ValueError:
            return AlertSeverity.INFO

    @property
    def name(self) -> str:
        """Get alert name (alertname label)."""
        return self.labels.get("alertname", "Unknown")

    @property
    def component(self) -> str:
        """Get component from labels."""
        return self.labels.get("component", "unknown")


@dataclass
class AlertGroup:
    """Group of related alerts from AlertManager webhook."""

    status: str
    alerts: List[Alert]
    groupLabels: Dict[str, str]
    commonLabels: Dict[str, str]
    commonAnnotations: Dict[str, str]
    receiver: str
    groupKey: str

    @classmethod
    def from_webhook(cls, webhook_data: Dict[str, Any]) -> AlertGroup:
        """Parse AlertManager webhook payload."""
        alerts = [
            Alert(
                labels=alert.get("labels", {}),
                annotations=alert.get("annotations", {}),
                startsAt=alert.get("startsAt", datetime.utcnow().isoformat()),
                endsAt=alert.get("endsAt"),
                status=alert.get("status", "firing"),
            )
            for alert in webhook_data.get("alerts", [])
        ]

        return cls(
            status=webhook_data.get("status", "unknown"),
            alerts=alerts,
            groupLabels=webhook_data.get("groupLabels", {}),
            commonLabels=webhook_data.get("commonLabels", {}),
            commonAnnotations=webhook_data.get("commonAnnotations", {}),
            receiver=webhook_data.get("receiver", "unknown"),
            groupKey=webhook_data.get("groupKey", "unknown"),
        )


class AlertReceiver:
    """Receives and processes Prometheus AlertManager webhooks."""

    def __init__(
        self,
        slack_enabled: bool = False,
        pagerduty_enabled: bool = False,
        ai_enabled: bool = True,
    ):
        """Initialize alert receiver.

        Args:
            slack_enabled: Whether to send alerts to Slack
            pagerduty_enabled: Whether to send alerts to PagerDuty
            ai_enabled: Whether to include AI operations guidance
        """
        self.slack_enabled = slack_enabled
        self.pagerduty_enabled = pagerduty_enabled
        self.ai_enabled = ai_enabled
        self.ai_advisor = AIOperationsAdvisor()
        self._received_alerts: List[AlertGroup] = []

    def receive_webhook(self, webhook_data: Dict[str, Any]) -> Dict[str, Any]:
        """Receive and process an AlertManager webhook payload.

        Args:
            webhook_data: AlertManager webhook JSON payload

        Returns:
            Processing status and routing information
        """
        try:
            alert_group = AlertGroup.from_webhook(webhook_data)
            self._received_alerts.append(alert_group)

            logger.info(
                f"Received alert group: {len(alert_group.alerts)} alert(s), "
                f"status={alert_group.status}, receiver={alert_group.receiver}"
            )

            routing_result = self._route_alerts(alert_group)

            ai_result = None
            if self.ai_enabled and alert_group.alerts:
                ai_result = self.ai_advisor.analyze_alert_group(alert_group).to_dict()

            return {
                "status": "success",
                "alerts_received": len(alert_group.alerts),
                "ai": ai_result,
                "routing": routing_result,
            }
        except Exception as e:
            logger.error(f"Error processing webhook: {e}", exc_info=True)
            return {
                "status": "error",
                "error": str(e),
            }

    def _route_alerts(self, alert_group: AlertGroup) -> Dict[str, Any]:
        """Route alerts to appropriate destinations.

        Args:
            alert_group: Group of alerts to route

        Returns:
            Routing status by destination
        """
        routing_result: Dict[str, Any] = {}

        # Route to Slack if enabled
        if self.slack_enabled:
            slack_result = self._route_to_slack(alert_group)
            routing_result["slack"] = slack_result

        # Route to PagerDuty if enabled
        if self.pagerduty_enabled:
            pagerduty_result = self._route_to_pagerduty(alert_group)
            routing_result["pagerduty"] = pagerduty_result

        # Always log locally
        logging_result = self._log_alerts(alert_group)
        routing_result["logging"] = logging_result

        return routing_result

    def _route_to_slack(self, alert_group: AlertGroup) -> Dict[str, Any]:
        """Route alerts to Slack channel.

        Args:
            alert_group: Group of alerts to route

        Returns:
            Routing status (stub for now)
        """
        # Stub implementation - would integrate with slack_sdk
        messages = self._format_slack_messages(alert_group)
        logger.info(f"Would send {len(messages)} Slack message(s) for alert group")

        return {
            "status": "routed",
            "messages_count": len(messages),
            "note": "Slack integration requires SLACK_WEBHOOK_URL configuration",
        }

    def _route_to_pagerduty(self, alert_group: AlertGroup) -> Dict[str, Any]:
        """Route alerts to PagerDuty.

        Args:
            alert_group: Group of alerts to route

        Returns:
            Routing status (stub for now)
        """
        # Stub implementation - would integrate with pdpyras
        incidents = self._format_pagerduty_incidents(alert_group)
        logger.info(f"Would create {len(incidents)} PagerDuty incident(s)")

        return {
            "status": "routed",
            "incidents_count": len(incidents),
            "note": "PagerDuty integration requires PAGERDUTY_INTEGRATION_KEY configuration",
        }

    def _log_alerts(self, alert_group: AlertGroup) -> Dict[str, Any]:
        """Log alerts to application logger.

        Args:
            alert_group: Group of alerts to log

        Returns:
            Logging status
        """
        for alert in alert_group.alerts:
            log_entry = {
                "alert_name": alert.name,
                "severity": alert.severity.value,
                "component": alert.component,
                "status": alert.status,
                "labels": alert.labels,
                "annotations": alert.annotations,
                "started_at": alert.startsAt,
            }

            if alert.severity == AlertSeverity.CRITICAL:
                logger.critical(json.dumps(log_entry))
            elif alert.severity == AlertSeverity.WARNING:
                logger.warning(json.dumps(log_entry))
            else:
                logger.info(json.dumps(log_entry))

        return {
            "status": "logged",
            "alerts_logged": len(alert_group.alerts),
        }

    def _format_slack_messages(self, alert_group: AlertGroup) -> List[Dict[str, Any]]:
        """Format alerts for Slack delivery.

        Args:
            alert_group: Group of alerts to format

        Returns:
            List of Slack message payloads
        """
        messages = []

        for alert in alert_group.alerts:
            color = {
                AlertSeverity.CRITICAL: "danger",
                AlertSeverity.WARNING: "warning",
                AlertSeverity.INFO: "good",
            }.get(alert.severity, "good")

            message = {
                "attachments": [
                    {
                        "color": color,
                        "title": alert.name,
                        "text": alert.annotations.get("description", "No description"),
                        "fields": [
                            {"title": "Severity", "value": alert.severity.value, "short": True},
                            {"title": "Component", "value": alert.component, "short": True},
                            {"title": "Status", "value": alert.status, "short": True},
                            {
                                "title": "Runbook",
                                "value": alert.annotations.get("runbook", "N/A"),
                                "short": False,
                            },
                        ],
                        "ts": int(datetime.fromisoformat(alert.startsAt).timestamp()),
                    }
                ]
            }
            messages.append(message)

        return messages

    def _format_pagerduty_incidents(self, alert_group: AlertGroup) -> List[Dict[str, Any]]:
        """Format alerts for PagerDuty delivery.

        Args:
            alert_group: Group of alerts to format

        Returns:
            List of PagerDuty incident payloads
        """
        incidents = []

        for alert in alert_group.alerts:
            # Only create incidents for critical/warning alerts
            if alert.severity in {AlertSeverity.CRITICAL, AlertSeverity.WARNING}:
                incident = {
                    "routing_key": "REQUIRES_PAGERDUTY_INTEGRATION_KEY",
                    "event_action": "trigger" if alert.status == "firing" else "resolve",
                    "payload": {
                        "summary": alert.name,
                        "severity": alert.severity.value,
                        "source": alert.component,
                        "custom_details": {
                            "description": alert.annotations.get("description", ""),
                            "runbook": alert.annotations.get("runbook", ""),
                            "labels": alert.labels,
                        },
                    },
                }
                incidents.append(incident)

        return incidents

    def get_alert_summary(self) -> Dict[str, Any]:
        """Get summary of received alerts.

        Returns:
            Summary statistics
        """
        total_alerts = sum(len(group.alerts) for group in self._received_alerts)
        critical_count = sum(
            1
            for group in self._received_alerts
            for alert in group.alerts
            if alert.severity == AlertSeverity.CRITICAL
        )
        warning_count = sum(
            1
            for group in self._received_alerts
            for alert in group.alerts
            if alert.severity == AlertSeverity.WARNING
        )

        return {
            "total_received": len(self._received_alerts),
            "total_alerts": total_alerts,
            "critical_count": critical_count,
            "warning_count": warning_count,
            "info_count": total_alerts - critical_count - warning_count,
        }


__all__ = [
    "AlertSeverity",
    "Alert",
    "AlertGroup",
    "AlertReceiver",
]
