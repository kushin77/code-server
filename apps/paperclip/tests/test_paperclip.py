from pathlib import Path
import sys
from datetime import timedelta

from fastapi.testclient import TestClient

APP_DIR = Path(__file__).resolve().parents[1]
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

import main


client = TestClient(main.app)


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_approval_lifecycle_and_killswitch():
    approval_one = client.post(
        "/approvals",
        json={
            "agent_id": "agent-1",
            "task_id": "task-1",
            "action_description": "Write config outside workspace",
            "risk_score": 80,
            "diff_preview": "- old\n+ new",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    approval_two = client.post(
        "/approvals",
        json={
            "agent_id": "agent-2",
            "task_id": "task-2",
            "action_description": "Deploy release",
            "risk_score": 95,
            "timeout_minutes": 10,
            "requested_by": "agent-runtime",
        },
    ).json()

    assert client.get("/approvals").json()["items"]

    approved = client.post(
        f"/approvals/{approval_one['approval_id']}/approve",
        json={"approver": "tech-lead", "reason": "Safe change"},
    )
    assert approved.status_code == 200
    assert approved.json()["status"] == "approved"

    killswitch = client.post(
        "/killswitch",
        json={"triggered_by": "operator", "reason": "Emergency stop"},
    )

    assert killswitch.status_code == 200
    assert killswitch.json()["denied_pending_approvals"] == 1
    assert client.get("/approvals").json()["items"] == []
    assert client.get("/approvals/escalated").json()["items"] == []
    assert client.get("/killswitch").json()["active"] is True

    events = client.get("/events").json()["items"]
    event_types = [event["event_type"] for event in events]
    assert "agent.awaiting_approval" in event_types
    assert "agent.killswitch" in event_types


def test_escalation_marks_overdue_approvals():
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-9",
            "task_id": "task-9",
            "action_description": "Escalate overdue approval",
            "risk_score": 60,
            "timeout_minutes": 1,
            "requested_by": "agent-runtime",
        },
    ).json()

    from main import approval_queue

    record = approval_queue.get(approval["approval_id"])
    record.created_at = record.created_at - timedelta(minutes=6)

    response = client.post("/approvals/escalate-overdue")

    assert response.status_code == 200
    assert response.json()["escalated"] == 1
    assert response.json()["auto_denied"] == 0
    escalated_items = client.get("/approvals/escalated").json()["items"]
    assert any(item["approval_id"] == approval["approval_id"] for item in escalated_items)

    escalated_events = client.get("/events", params={"event_type": "approval.escalated"}).json()["items"]
    assert any(event["payload"]["approval_id"] == approval["approval_id"] for event in escalated_events)


def test_escalation_does_not_republish_existing_events():
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-11",
            "task_id": "task-11",
            "action_description": "Avoid duplicate escalation events",
            "risk_score": 55,
            "timeout_minutes": 1,
            "requested_by": "agent-runtime",
        },
    ).json()

    from main import approval_queue

    record = approval_queue.get(approval["approval_id"])
    record.created_at = record.created_at - timedelta(minutes=6)

    first = client.post("/approvals/escalate-overdue")
    second = client.post("/approvals/escalate-overdue")

    assert first.status_code == 200
    assert second.status_code == 200

    escalated_events = client.get("/events", params={"event_type": "approval.escalated"}).json()["items"]
    matching_events = [event for event in escalated_events if event["payload"]["approval_id"] == approval["approval_id"]]
    assert len(matching_events) == 1


def test_escalation_auto_denies_after_tier2_timeout():
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-10",
            "task_id": "task-10",
            "action_description": "Auto-deny overdue approval",
            "risk_score": 70,
            "timeout_minutes": 1,
            "requested_by": "agent-runtime",
        },
    ).json()

    from main import approval_queue

    record = approval_queue.get(approval["approval_id"])
    record.created_at = record.created_at - timedelta(minutes=20)

    response = client.post("/approvals/escalate-overdue")

    assert response.status_code == 200
    assert response.json()["escalated"] == 0
    assert response.json()["auto_denied"] == 1

    approval_state = client.get(f"/approvals/{approval['approval_id']}").json()
    assert approval_state["status"] == "denied"
    assert approval_state["decision_reason"] == "Escalation timeout reached; auto-denied"


def test_killswitch_emits_event():
    response = client.post(
        "/killswitch",
        json={"triggered_by": "operator-2", "reason": "Emergency stop"},
    )

    assert response.status_code == 200
    killswitch_events = client.get("/events", params={"event_type": "agent.killswitch"}).json()["items"]
    assert killswitch_events[-1]["payload"]["triggered_by"] == "operator-2"


def test_heartbeat_tracking():
    response = client.post(
        "/heartbeats",
        json={
            "agent_id": "agent-3",
            "task_id": "task-3",
            "last_action": "processing",
            "status": "running",
            "eta_seconds": 120,
        },
    )

    assert response.status_code == 200

    heartbeats = client.get("/heartbeats").json()
    assert len(heartbeats["active"]) == 1
    assert heartbeats["active"][0]["agent_id"] == "agent-3"
