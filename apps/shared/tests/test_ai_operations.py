"""Tests for AI-assisted operations helpers."""

import importlib.util
import sys
import types
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


ALERT_RECEIVER = _load_module("apps.shared.alert_receiver", "alert_receiver.py")
shared_pkg.alert_receiver = ALERT_RECEIVER
AI_OPS = _load_module("apps.shared.ai_operations", "ai_operations.py")


def test_ai_advisor_deduplicates_and_recommends() -> None:
    alert_group = ALERT_RECEIVER.AlertGroup(
        status="firing",
        alerts=[
            ALERT_RECEIVER.Alert(
                labels={"alertname": "HighLoad", "severity": "warning", "component": "cpu"},
                annotations={"description": "CPU usage is high", "runbook": "docs/cpu-runbook.md"},
                startsAt="2026-05-01T10:00:00Z",
            ),
            ALERT_RECEIVER.Alert(
                labels={"alertname": "HighLoad", "severity": "warning", "component": "cpu"},
                annotations={"description": "CPU usage is high", "runbook": "docs/cpu-runbook.md"},
                startsAt="2026-05-01T10:01:00Z",
            ),
        ],
        groupLabels={},
        commonLabels={},
        commonAnnotations={},
        receiver="default",
        groupKey="test",
    )

    advisor = AI_OPS.AIOperationsAdvisor()
    result = advisor.analyze_alert_group(alert_group)

    assert result.deduplication.duplicate_count == 1
    assert len(result.deduplication.unique_alerts) == 1
    assert result.runbooks[0].runbook == "docs/cpu-runbook.md"
    assert result.scaling[0].action == "scale_up_with_review"


def test_ai_advisor_fallback_runbook_and_execution_plan() -> None:
    alert_group = ALERT_RECEIVER.AlertGroup(
        status="firing",
        alerts=[
            ALERT_RECEIVER.Alert(
                labels={"alertname": "MysteryAlert", "severity": "critical", "component": "unknown"},
                annotations={},
                startsAt="2026-05-01T10:00:00Z",
            )
        ],
        groupLabels={},
        commonLabels={},
        commonAnnotations={},
        receiver="default",
        groupKey="test",
    )

    advisor = AI_OPS.AIOperationsAdvisor()
    plan = advisor.execute_recommended_runbooks(alert_group)

    assert plan[0]["action"] == "execute_runbook"
    assert plan[0]["runbook"].endswith("general-alert-triage.md")


def test_alert_receiver_includes_ai_analysis() -> None:
    receiver = ALERT_RECEIVER.AlertReceiver(slack_enabled=False, pagerduty_enabled=False)

    result = receiver.receive_webhook(
        {
            "status": "firing",
            "alerts": [
                {
                    "status": "firing",
                    "labels": {"alertname": "HighMemory", "severity": "warning", "component": "memory"},
                    "annotations": {"description": "Memory usage is high"},
                    "startsAt": "2026-05-01T10:00:00Z",
                },
                {
                    "status": "firing",
                    "labels": {"alertname": "HighMemory", "severity": "warning", "component": "memory"},
                    "annotations": {"description": "Memory usage is high"},
                    "startsAt": "2026-05-01T10:05:00Z",
                },
            ],
            "groupLabels": {},
            "commonLabels": {},
            "commonAnnotations": {},
            "receiver": "default",
            "groupKey": "test",
        }
    )

    assert result["status"] == "success"
    assert result["ai"]["deduplication"]["duplicate_count"] == 1
    assert result["ai"]["scaling"][0]["action"] == "scale_up_with_review"
