from pathlib import Path
import sys

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
    record.created_at = record.created_at.replace(year=record.created_at.year - 1)

    response = client.post("/approvals/escalate-overdue")

    assert response.status_code == 200
    assert response.json()["escalated"] == 1
    escalated_items = client.get("/approvals/escalated").json()["items"]
    assert escalated_items[0]["approval_id"] == approval["approval_id"]
    assert escalated_items[0]["escalation_level"] == 1


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
