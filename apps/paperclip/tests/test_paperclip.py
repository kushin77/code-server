from pathlib import Path
import sys
from datetime import timedelta
from unittest.mock import patch, MagicMock

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


# ========================================================================
# INTEGRATION TESTS: OPA Policy & Reputation Tier Enforcement
# ========================================================================


def test_opa_policy_allows_elite_approval():
    """Elite users can approve all risk levels via OPA policy."""
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-opa-1",
            "task_id": "task-opa-1",
            "action_description": "Critical infrastructure change",
            "risk_score": 95,
            "risk_level": "critical",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    # Mock OPA to allow elite approval
    with patch("main.opa_manager.check_approval_policy") as mock_opa:
        mock_opa.return_value = {
            "allowed": True,
            "reason": "Elite tier can approve all actions",
            "requires_escalation": False,
        }

        # Mock Reputation to return elite tier
        with patch("main.reputation_manager.get_approval_authority_level") as mock_rep:
            mock_rep.return_value = {
                "tier": "elite",
                "can_approve_critical": True,
                "can_approve_high": True,
                "can_approve_medium": True,
                "can_approve_low": True,
                "requires_escalation": False,
            }

            response = client.post(
                f"/approvals/{approval['approval_id']}/approve",
                json={"approver": "elite-user", "approved_by": "elite-user", "reason": "Verified critical action"},
            )

            assert response.status_code == 200
            assert response.json()["status"] == "approved"


def test_reputation_tier_blocks_standard_critical_approval():
    """Standard users cannot approve critical actions per reputation tier."""
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-tier-1",
            "task_id": "task-tier-1",
            "action_description": "Critical deployment",
            "risk_score": 95,
            "risk_level": "critical",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    # Mock OPA to allow (bypassed by tier check)
    with patch("main.opa_manager.check_approval_policy") as mock_opa:
        mock_opa.return_value = {
            "allowed": True,
            "reason": "Policy allows",
            "requires_escalation": False,
        }

        # Mock Reputation to return standard tier (cannot approve critical)
        with patch("main.reputation_manager.get_approval_authority_level") as mock_rep:
            mock_rep.return_value = {
                "tier": "standard",
                "can_approve_critical": False,
                "can_approve_high": False,
                "can_approve_medium": True,
                "can_approve_low": True,
                "requires_escalation_for": ["high", "critical"],
            }

            response = client.post(
                f"/approvals/{approval['approval_id']}/approve",
                json={"approver": "standard-user", "approved_by": "standard-user", "reason": "Attempt critical"},
            )

            assert response.status_code == 403
            assert "cannot approve critical" in response.json()["detail"]


def test_opa_policy_denial_blocks_approval():
    """OPA policy denial blocks approval regardless of tier."""
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-opa-2",
            "task_id": "task-opa-2",
            "action_description": "Sensitive data export",
            "risk_score": 85,
            "risk_level": "high",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    # Mock OPA to deny (data sovereignty rule)
    with patch("main.opa_manager.check_approval_policy") as mock_opa:
        mock_opa.return_value = {
            "allowed": False,
            "reason": "Data sovereignty breach: sensitive data requires local approval only",
            "requires_escalation": True,
        }

        response = client.post(
            f"/approvals/{approval['approval_id']}/approve",
            json={"approver": "regional-user", "approved_by": "regional-user", "reason": "Attempt export"},
        )

        assert response.status_code == 403
        assert "Data sovereignty" in response.json()["detail"]


def test_health_endpoint_checks_opa_and_reputation():
    """Health endpoint verifies OPA and Reputation Engine connectivity."""
    with patch("main.opa_manager.health_check") as mock_opa_health:
        mock_opa_health.return_value = True

        with patch("main.reputation_manager.health_check") as mock_rep_health:
            mock_rep_health.return_value = True

            response = client.get("/health")

            assert response.status_code == 200
            assert response.json()["opa_service"] == "healthy"
            assert response.json()["reputation_engine"] == "healthy"


def test_health_endpoint_warns_opa_unavailable():
    """Health endpoint reports when OPA is unavailable."""
    with patch("main.opa_manager.health_check") as mock_opa_health:
        mock_opa_health.return_value = False

        with patch("main.reputation_manager.health_check") as mock_rep_health:
            mock_rep_health.return_value = True

            response = client.get("/health")

            assert response.status_code == 200
            assert response.json()["opa_service"] == "unhealthy"
            assert response.json()["reputation_engine"] == "healthy"


def test_senior_tier_blocks_critical_approval():
    """Senior users cannot approve critical actions (only elite can)."""
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-senior-1",
            "task_id": "task-senior-1",
            "action_description": "Critical security policy change",
            "risk_score": 99,
            "risk_level": "critical",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    with patch("main.opa_manager.check_approval_policy") as mock_opa:
        mock_opa.return_value = {"allowed": True, "reason": "Policy allows", "requires_escalation": False}

        with patch("main.reputation_manager.get_approval_authority_level") as mock_rep:
            mock_rep.return_value = {
                "tier": "senior",
                "can_approve_critical": False,
                "can_approve_high": True,
                "can_approve_medium": True,
                "can_approve_low": True,
                "requires_escalation_for": ["critical"],
            }

            response = client.post(
                f"/approvals/{approval['approval_id']}/approve",
                json={"approver": "senior-user", "approved_by": "senior-user", "reason": "Attempt critical"},
            )

            assert response.status_code == 403
            assert "senior" in response.json()["detail"].lower()


def test_approval_includes_audit_trail():
    """Approved actions include audit metadata for OPA/reputation checks."""
    approval = client.post(
        "/approvals",
        json={
            "agent_id": "agent-audit-1",
            "task_id": "task-audit-1",
            "action_description": "Standard deployment",
            "risk_score": 45,
            "risk_level": "medium",
            "timeout_minutes": 5,
            "requested_by": "agent-runtime",
        },
    ).json()

    with patch("main.opa_manager.check_approval_policy") as mock_opa:
        mock_opa.return_value = {"allowed": True, "reason": "OPA approved", "requires_escalation": False}

        with patch("main.reputation_manager.get_approval_authority_level") as mock_rep:
            mock_rep.return_value = {
                "tier": "standard",
                "can_approve_medium": True,
                "can_approve_low": True,
                "can_approve_high": False,
                "can_approve_critical": False,
            }

            response = client.post(
                f"/approvals/{approval['approval_id']}/approve",
                json={"approver": "standard-user", "approved_by": "standard-user", "reason": "Standard approval"},
            )

            assert response.status_code == 200
            result = response.json()
            assert result["status"] == "approved"
            assert result["approver"] == "standard-user"
            assert result["approval_id"] == approval["approval_id"]
