"""Tests for alert receiver module."""

import importlib.util
import sys
import types
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

apps_pkg = types.ModuleType("apps")
apps_pkg.__path__ = [str(ROOT.parent)]
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
shared_pkg.__path__ = [str(ROOT)]
sys.modules["apps.shared"] = shared_pkg


def _load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / file_name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


AI_OPERATIONS = _load_module("apps.shared.ai_operations", "ai_operations.py")
shared_pkg.ai_operations = AI_OPERATIONS
ALERT_RECEIVER = _load_module("apps.shared.alert_receiver", "alert_receiver.py")

Alert = ALERT_RECEIVER.Alert
AlertGroup = ALERT_RECEIVER.AlertGroup
AlertReceiver = ALERT_RECEIVER.AlertReceiver
AlertSeverity = ALERT_RECEIVER.AlertSeverity


def test_alert_parsing() -> None:
    """Test Alert parsing from raw webhook data."""
    alert = Alert(
        labels={"alertname": "TestAlert", "severity": "critical", "component": "database"},
        annotations={"description": "Database is down", "runbook": "docs/db-runbook.md"},
        startsAt="2026-05-01T10:00:00Z",
    )

    assert alert.name == "TestAlert"
    assert alert.severity == AlertSeverity.CRITICAL
    assert alert.component == "database"


def test_alert_severity_parsing() -> None:
    """Test severity parsing with various inputs."""
    # Test all severity levels
    for severity_str in ["critical", "warning", "info"]:
        alert = Alert(
            labels={"severity": severity_str},
            annotations={},
            startsAt="2026-05-01T10:00:00Z",
        )
        assert alert.severity == AlertSeverity(severity_str)

    # Test default (invalid severity)
    alert = Alert(
        labels={"severity": "invalid"},
        annotations={},
        startsAt="2026-05-01T10:00:00Z",
    )
    assert alert.severity == AlertSeverity.INFO


def test_alert_group_from_webhook() -> None:
    """Test AlertGroup parsing from webhook payload."""
    webhook_data = {
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {"alertname": "HighLoad", "severity": "warning", "component": "cpu"},
                "annotations": {"description": "CPU usage is high", "runbook": "docs/cpu-runbook.md"},
                "startsAt": "2026-05-01T10:00:00Z",
                "endsAt": None,
            }
        ],
        "groupLabels": {"alertname": "HighLoad"},
        "commonLabels": {"component": "cpu"},
        "commonAnnotations": {"runbook": "docs/cpu-runbook.md"},
        "receiver": "platform",
        "groupKey": "{}:{HighLoad}",
    }

    alert_group = AlertGroup.from_webhook(webhook_data)

    assert alert_group.status == "firing"
    assert len(alert_group.alerts) == 1
    assert alert_group.alerts[0].name == "HighLoad"
    assert alert_group.receiver == "platform"


def test_alert_receiver_webhook_processing() -> None:
    """Test alert receiver processing webhook payloads."""
    receiver = AlertReceiver(slack_enabled=False, pagerduty_enabled=False)

    webhook_data = {
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {"alertname": "TestAlert", "severity": "critical", "component": "monitoring"},
                "annotations": {"description": "Test alert", "runbook": "docs/test.md"},
                "startsAt": "2026-05-01T10:00:00Z",
            }
        ],
        "groupLabels": {},
        "commonLabels": {},
        "commonAnnotations": {},
        "receiver": "default",
        "groupKey": "test",
    }

    result = receiver.receive_webhook(webhook_data)

    assert result["status"] == "success"
    assert result["alerts_received"] == 1
    assert "routing" in result


def test_alert_receiver_routing_result() -> None:
    """Test that alert receiver includes routing results."""
    receiver = AlertReceiver(slack_enabled=True, pagerduty_enabled=True)

    webhook_data = {
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": {"alertname": "CriticalAlert", "severity": "critical"},
                "annotations": {"description": "Critical issue"},
                "startsAt": "2026-05-01T10:00:00Z",
            }
        ],
        "groupLabels": {},
        "commonLabels": {},
        "commonAnnotations": {},
        "receiver": "default",
        "groupKey": "test",
    }

    result = receiver.receive_webhook(webhook_data)

    assert "routing" in result
    assert "logging" in result["routing"]
    assert "slack" in result["routing"]
    assert "pagerduty" in result["routing"]


def test_alert_receiver_summary() -> None:
    """Test alert receiver summary statistics."""
    receiver = AlertReceiver()

    # Send multiple alerts
    for i in range(3):
        webhook_data = {
            "status": "firing",
            "alerts": [
                {
                    "status": "firing",
                    "labels": {"alertname": f"Alert{i}", "severity": ["critical", "warning", "info"][i % 3]},
                    "annotations": {"description": f"Alert {i}"},
                    "startsAt": "2026-05-01T10:00:00Z",
                }
            ],
            "groupLabels": {},
            "commonLabels": {},
            "commonAnnotations": {},
            "receiver": "default",
            "groupKey": f"test{i}",
        }
        receiver.receive_webhook(webhook_data)

    summary = receiver.get_alert_summary()

    assert summary["total_received"] == 3
    assert summary["total_alerts"] == 3
    assert summary["critical_count"] == 1
    assert summary["warning_count"] == 1
    assert summary["info_count"] == 1


def test_alert_receiver_invalid_payload() -> None:
    """Test handling of invalid webhook payload."""
    receiver = AlertReceiver()

    result = receiver.receive_webhook({"invalid": "data"})

    assert result["status"] == "success"  # Gracefully handles empty alerts
    assert result["alerts_received"] == 0


def test_slack_message_formatting() -> None:
    """Test Slack message formatting."""
    receiver = AlertReceiver()

    alert_group = AlertGroup(
        status="firing",
        alerts=[
            Alert(
                labels={"alertname": "DatabaseDown", "severity": "critical", "component": "database"},
                annotations={"description": "Database is unavailable", "runbook": "docs/db-recovery.md"},
                startsAt="2026-05-01T10:00:00Z",
            )
        ],
        groupLabels={},
        commonLabels={},
        commonAnnotations={},
        receiver="default",
        groupKey="test",
    )

    messages = receiver._format_slack_messages(alert_group)

    assert len(messages) == 1
    assert "attachments" in messages[0]
    assert messages[0]["attachments"][0]["color"] == "danger"  # Critical severity


def test_pagerduty_incident_formatting() -> None:
    """Test PagerDuty incident formatting."""
    receiver = AlertReceiver()

    alert_group = AlertGroup(
        status="firing",
        alerts=[
            Alert(
                labels={"alertname": "ServiceDown", "severity": "critical", "component": "api"},
                annotations={"description": "API is down", "runbook": "docs/api-recovery.md"},
                startsAt="2026-05-01T10:00:00Z",
            ),
            Alert(
                labels={"alertname": "HighMemory", "severity": "info"},
                annotations={"description": "Memory usage is increasing"},
                startsAt="2026-05-01T10:00:00Z",
            ),
        ],
        groupLabels={},
        commonLabels={},
        commonAnnotations={},
        receiver="default",
        groupKey="test",
    )

    incidents = receiver._format_pagerduty_incidents(alert_group)

    # Only critical and warning alerts create incidents
    assert len(incidents) == 1
    assert incidents[0]["event_action"] == "trigger"
    assert incidents[0]["payload"]["severity"] == "critical"
