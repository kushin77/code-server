#!/usr/bin/env python3
# @file apps/paperclip/main.py
# @module paperclip
# @description Minimal Paperclip human control plane service

from fastapi import FastAPI, HTTPException

from approval_queue import ApprovalQueue
from heartbeat import HeartbeatMonitor
from killswitch import KillswitchManager
from models import ApprovalCreate, ApprovalDecision, HeartbeatCreate, KillswitchRequest


app = FastAPI(title="Paperclip Human Control Plane", version="1.0")

approval_queue = ApprovalQueue()
heartbeat_monitor = HeartbeatMonitor()
killswitch_manager = KillswitchManager()


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "approval_queue": len(approval_queue.list_pending()),
        "killswitch_active": killswitch_manager.active,
    }


@app.post("/approvals")
async def submit_approval(request: ApprovalCreate):
    approval = approval_queue.submit(request)
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
    try:
        approval = approval_queue.approve(approval_id, decision)
    except KeyError:
        raise HTTPException(status_code=404, detail="Approval not found")
    return approval.model_dump()


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
    return {"escalated": approval_queue.escalate_overdue()}


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
    return killswitch_manager.trigger(request.triggered_by, request.reason, denied_count)


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

    uvicorn.run(app, host="0.0.0.0", port=8010)
