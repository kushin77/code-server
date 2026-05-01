#!/usr/bin/env python3
# @file apps/paperclip/main.py
# @module paperclip
# @description Minimal Paperclip human control plane service
# @governance GOV-002: Approval gating, OPA policy enforcement, tier-based access

from typing import Optional

from fastapi import FastAPI, HTTPException

from approval_queue import ApprovalQueue
from heartbeat import HeartbeatMonitor
from killswitch import KillswitchManager
from event_publisher import PaperclipEventPublisher
from models import ApprovalCreate, ApprovalDecision, HeartbeatCreate, KillswitchRequest
from opa_integration import OPAPolicyManager
from reputation_integration import ReputationTierManager
import config

config.validate_config()

app = FastAPI(title="Paperclip Human Control Plane", version="1.0")

approval_queue = ApprovalQueue()
heartbeat_monitor = HeartbeatMonitor()
killswitch_manager = KillswitchManager()
event_publisher = PaperclipEventPublisher()
opa_manager = OPAPolicyManager()
reputation_manager = ReputationTierManager()


@app.get("/health")
async def health():
    opa_healthy = opa_manager.health_check()
    reputation_healthy = reputation_manager.health_check()
    return {
        "status": "healthy",
        "approval_queue": len(approval_queue.list_pending()),
        "killswitch_active": killswitch_manager.active,
        "opa_service": "healthy" if opa_healthy else "unhealthy",
        "reputation_engine": "healthy" if reputation_healthy else "unhealthy",
    }


@app.post("/approvals")
async def submit_approval(request: ApprovalCreate):
    approval = approval_queue.submit(request)
    event_publisher.publish_pending_approval(approval)
    return approval.model_dump()


@app.get("/approvals")
async def list_approvals():
    return {"items": [approval.model_dump() for approval in approval_queue.list_pending()]}


@app.get("/approvals/escalated")
async def list_escalated_approvals():
    return {"items": [approval.model_dump() for approval in approval_queue.list_escalated()]}


@app.get("/approvals/{approval_id}")
async def get_approval(approval_id: str):
    approval = approval_queue.get(approval_id)
    if approval is None:
        raise HTTPException(status_code=404, detail="Approval not found")
    return approval.model_dump()


@app.post("/approvals/{approval_id}/approve")
async def approve(approval_id: str, decision: ApprovalDecision):
    # Fetch the approval to check details
    approval = approval_queue.get(approval_id)
    if approval is None:
        raise HTTPException(status_code=404, detail="Approval not found")
    
    # Check OPA policy for approval eligibility
    opa_result = opa_manager.check_approval_policy(
        user_id=decision.approved_by,
        approval_type=approval.approval_type if hasattr(approval, "approval_type") else "standard",
        risk_level=approval.risk_level if hasattr(approval, "risk_level") else "medium",
    )
    
    if not opa_result.get("allowed", False):
        raise HTTPException(
            status_code=403,
            detail=f"Approval denied by policy: {opa_result.get('reason', 'Unknown reason')}",
        )
    
    # Check reputation tier for authority level
    authority = reputation_manager.get_approval_authority_level(decision.approved_by)
    risk_level = getattr(approval, "risk_level", "medium")
    
    if risk_level == "critical" and not authority.get("can_approve_critical", False):
        raise HTTPException(
            status_code=403,
            detail=f"User tier {authority.get('tier')} cannot approve critical actions",
        )
    elif risk_level == "high" and not authority.get("can_approve_high", False):
        raise HTTPException(
            status_code=403,
            detail=f"User tier {authority.get('tier')} cannot approve high-risk actions",
        )
    
    # Proceed with approval
    try:
        approval_obj = approval_queue.approve(approval_id, decision)
    except KeyError:
        raise HTTPException(status_code=404, detail="Approval not found")
    
    event_publisher.publish_approved_approval(approval_obj)
    return approval_obj.model_dump()


@app.post("/approvals/{approval_id}/deny")
async def deny(approval_id: str, decision: ApprovalDecision):
    try:
        approval = approval_queue.deny(approval_id, decision)
    except KeyError:
        raise HTTPException(status_code=404, detail="Approval not found")
    return approval.model_dump()


@app.post("/approvals/{approval_id}/delegate")
async def delegate(approval_id: str, decision: ApprovalDecision):
    try:
        approval = approval_queue.delegate(approval_id, decision)
    except KeyError:
        raise HTTPException(status_code=404, detail="Approval not found")
    return approval.model_dump()


@app.post("/approvals/escalate-overdue")
async def escalate_overdue_approvals():
    previous_escalated_ids = {approval.approval_id for approval in approval_queue.list_escalated()}
    result = approval_queue.escalate_overdue()
    for approval in approval_queue.list_escalated():
        if approval.approval_id not in previous_escalated_ids:
            event_publisher.publish_escalated_approval(approval)
    return result


@app.post("/heartbeats")
async def record_heartbeat(request: HeartbeatCreate):
    heartbeat = heartbeat_monitor.record(request)
    return heartbeat.model_dump()


@app.get("/heartbeats")
async def list_heartbeats():
    return {
        "active": [record.model_dump() for record in heartbeat_monitor.list_active()],
        "unresponsive": [record.model_dump() for record in heartbeat_monitor.list_unresponsive()],
    }


@app.post("/killswitch")
async def trigger_killswitch(request: KillswitchRequest):
    denied_count = approval_queue.deny_all_pending(request.reason, request.triggered_by)
    event_publisher.publish_killswitch(request.triggered_by, request.reason, denied_count)
    return killswitch_manager.trigger(request.triggered_by, request.reason, denied_count)


@app.get("/events")
async def list_events(event_type: Optional[str] = None):
    return {"items": event_publisher.list_events(event_type)}


@app.get("/killswitch")
async def killswitch_status():
    return {
        "active": killswitch_manager.active,
        "triggered_by": killswitch_manager.last_triggered_by,
        "reason": killswitch_manager.last_reason,
        "timestamp": killswitch_manager.last_triggered_at.isoformat() if killswitch_manager.last_triggered_at else None,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)
