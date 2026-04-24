#!/usr/bin/env python3
# @file        apps/paperclip-control-plane/main.py
# @module      paperclip/control-plane
# @description Paperclip Human Control Plane FastAPI service
# @owner       paperclip/control-plane
# @status      production-ready
#
# FastAPI service: approval queue, escalation, heartbeat, emergency stop

import os
import asyncio
import logging
from typing import List, Dict, Any, Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException, WebSocket, Query
from pydantic import BaseModel
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
import yaml

from .models import Base, init_db, ApprovalStatus, EscalationTier
from .approval_queue import ApprovalQueueService, ApprovalAction
from .escalation import EscalationEngine
from .heartbeat import HeartbeatMonitor, HeartbeatReport

logger = logging.getLogger(__name__)

# ============================================================================
# Configuration
# ============================================================================

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://paperclip:paperclip@localhost:5432/paperclip"
)

PAPERCLIP_CONFIG_PATH = os.environ.get(
    "PAPERCLIP_CONFIG_PATH",
    "config/paperclip.yaml"
)

def load_config() -> Dict[str, Any]:
    """Load escalation configuration from YAML"""
    if os.path.exists(PAPERCLIP_CONFIG_PATH):
        with open(PAPERCLIP_CONFIG_PATH) as f:
            return yaml.safe_load(f) or {}
    return {
        "escalation": {
            "tier1": {"roles": ["developer"], "timeout_minutes": 5},
            "tier2": {"roles": ["tech_lead"], "timeout_minutes": 10},
            "fallback": "auto_deny",
        }
    }

CONFIG = load_config()

# ============================================================================
# Database Setup
# ============================================================================

engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    """Dependency: get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ============================================================================
# Background Tasks
# ============================================================================

escalation_engine: Optional[EscalationEngine] = None
heartbeat_monitor: Optional[HeartbeatMonitor] = None
escalation_task: Optional[asyncio.Task] = None
heartbeat_task: Optional[asyncio.Task] = None

async def start_background_tasks():
    """Start escalation and heartbeat monitor loops"""
    global escalation_engine, heartbeat_monitor, escalation_task, heartbeat_task
    
    db = SessionLocal()
    
    escalation_engine = EscalationEngine(db, CONFIG)
    heartbeat_monitor = HeartbeatMonitor(db)
    
    escalation_task = asyncio.create_task(escalation_engine.run_escalation_loop())
    heartbeat_task = asyncio.create_task(heartbeat_monitor.run_monitor_loop())
    
    logger.info("Background tasks started: escalation + heartbeat monitor")

async def stop_background_tasks():
    """Stop background loops"""
    global escalation_task, heartbeat_task
    
    if escalation_task:
        escalation_task.cancel()
    if heartbeat_task:
        heartbeat_task.cancel()
    
    logger.info("Background tasks stopped")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan: startup/shutdown"""
    init_db(DATABASE_URL)
    await start_background_tasks()
    yield
    await stop_background_tasks()

# ============================================================================
# Pydantic Models (Request/Response)
# ============================================================================

class ApprovalSubmitRequest(BaseModel):
    agent_id: str
    task_id: str
    action_type: str
    action_description: str
    estimated_cost_tokens: float = 0.0

class ApprovalResponse(BaseModel):
    id: int
    agent_id: str
    task_id: str
    action_type: str
    status: str
    current_tier: str
    submitted_at: str
    tier1_expires_at: str
    final_deadline: str

class ApprovalDecisionRequest(BaseModel):
    approver_id: str
    reason: str = ""

class HeartbeatRecordRequest(BaseModel):
    agent_id: str
    task_id: Optional[str] = None
    last_action: Optional[str] = None
    status: str = "healthy"
    elapsed_seconds: float = 0.0
    eta_seconds: Optional[float] = None
    memory_mb: float = 0.0
    cpu_percent: float = 0.0

class HealthResponse(BaseModel):
    status: str
    approval_queue_pending: int
    heartbeat_healthy_agents: int
    escalation_tier1_backlog: int

# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(
    title="Paperclip Human Control Plane",
    description="Approval Queue, Escalation, Heartbeat Monitoring, Emergency Stop",
    version="1.0.0",
    lifespan=lifespan,
)

# ============================================================================
# Health Check
# ============================================================================

@app.get("/health", response_model=HealthResponse)
async def health_check(db: Session = Depends(get_db)):
    """Health check endpoint with queue statistics"""
    approval_svc = ApprovalQueueService(db)
    stats = approval_svc.get_approval_stats()
    
    escalation_stats = escalation_engine.get_escalation_stats() if escalation_engine else {}
    heartbeat_stats = heartbeat_monitor.get_heartbeat_stats() if heartbeat_monitor else {}
    
    return HealthResponse(
        status="ok",
        approval_queue_pending=stats["pending"],
        heartbeat_healthy_agents=heartbeat_stats.get("healthy_agents", 0),
        escalation_tier1_backlog=escalation_stats.get("tier_1_pending", 0),
    )

# ============================================================================
# Approval Queue Endpoints
# ============================================================================

@app.post("/api/approvals/submit", response_model=Dict[str, Any])
async def submit_approval(
    request: ApprovalSubmitRequest,
    db: Session = Depends(get_db)
):
    """Submit an action for approval"""
    queue_svc = ApprovalQueueService(db)
    
    action = ApprovalAction(
        agent_id=request.agent_id,
        task_id=request.task_id,
        action_type=request.action_type,
        action_description=request.action_description,
        estimated_cost_tokens=request.estimated_cost_tokens,
    )
    
    approval_id = queue_svc.submit_action(action, CONFIG)
    
    return {
        "approval_id": approval_id,
        "status": "submitted",
        "message": f"Action submitted for approval (ID: {approval_id})",
    }

@app.get("/api/approvals/pending", response_model=List[ApprovalResponse])
async def get_pending_approvals(
    limit: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Get all pending approvals"""
    queue_svc = ApprovalQueueService(db)
    approvals = queue_svc.get_pending_approvals(limit)
    
    return [
        ApprovalResponse(
            id=a.id,
            agent_id=a.agent_id,
            task_id=a.task_id,
            action_type=a.action_type,
            status=a.status.value,
            current_tier=a.current_tier.value,
            submitted_at=a.submitted_at.isoformat(),
            tier1_expires_at=a.tier1_expires_at.isoformat(),
            final_deadline=a.final_deadline.isoformat(),
        )
        for a in approvals
    ]

@app.post("/api/approvals/{approval_id}/approve")
async def approve_action(
    approval_id: int,
    request: ApprovalDecisionRequest,
    db: Session = Depends(get_db)
):
    """Approve an action"""
    queue_svc = ApprovalQueueService(db)
    
    success = queue_svc.approve_action(
        approval_id,
        request.approver_id,
        request.reason
    )
    
    if not success:
        raise HTTPException(status_code=404, detail="Approval not found or not pending")
    
    return {
        "approval_id": approval_id,
        "status": "approved",
        "message": f"Action approved by {request.approver_id}",
    }

@app.post("/api/approvals/{approval_id}/deny")
async def deny_action(
    approval_id: int,
    request: ApprovalDecisionRequest,
    db: Session = Depends(get_db)
):
    """Deny an action"""
    queue_svc = ApprovalQueueService(db)
    
    success = queue_svc.deny_action(
        approval_id,
        request.approver_id,
        request.reason
    )
    
    if not success:
        raise HTTPException(status_code=404, detail="Approval not found or already decided")
    
    return {
        "approval_id": approval_id,
        "status": "denied",
        "message": f"Action denied by {request.approver_id}",
    }

# ============================================================================
# Heartbeat Endpoints
# ============================================================================

@app.post("/api/heartbeat/record")
async def record_heartbeat(
    report: HeartbeatRecordRequest,
    db: Session = Depends(get_db)
):
    """Record agent heartbeat"""
    monitor = HeartbeatMonitor(db)
    
    hb_report = HeartbeatReport(
        agent_id=report.agent_id,
        task_id=report.task_id,
        last_action=report.last_action,
        status=report.status,
        elapsed_seconds=report.elapsed_seconds,
        eta_seconds=report.eta_seconds,
        memory_mb=report.memory_mb,
        cpu_percent=report.cpu_percent,
    )
    
    monitor.record_heartbeat(hb_report)
    
    return {
        "agent_id": report.agent_id,
        "status": "recorded",
        "message": "Heartbeat received",
    }

@app.get("/api/heartbeat/status/{agent_id}")
async def get_agent_status(
    agent_id: str,
    db: Session = Depends(get_db)
):
    """Get status of specific agent"""
    monitor = HeartbeatMonitor(db)
    status = await monitor.get_agent_status(agent_id)
    
    if not status:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
    return status

@app.get("/api/heartbeat/all")
async def get_all_agents_status(db: Session = Depends(get_db)):
    """Get status of all agents"""
    monitor = HeartbeatMonitor(db)
    return await monitor.get_all_agents_status()

# ============================================================================
# Emergency Stop Endpoint
# ============================================================================

@app.post("/api/killswitch")
async def emergency_stop(
    triggered_by: str = Query(...),
    reason: str = Query(...),
    scope: str = Query("all"),  # "all" or "agent:X"
    db: Session = Depends(get_db)
):
    """
    Emergency stop - kill all agents or specific agent
    
    This endpoint should be protected by strong authentication!
    """
    from .models import KillswitchEvent
    
    now = datetime.utcnow()
    
    # Record killswitch event (audit trail)
    event = KillswitchEvent(
        triggered_by=triggered_by,
        triggered_at=now,
        scope=scope,
        reason=reason,
        agents_killed=0,
        containers_stopped=0,
        approvals_denied=0,
    )
    
    # Auto-deny all pending approvals
    queue_svc = ApprovalQueueService(db)
    pending = queue_svc.get_pending_approvals(limit=10000)
    approvals_denied = 0
    
    for approval in pending:
        queue_svc.deny_action(
            approval.id,
            "system",
            f"Emergency stop: {reason}"
        )
        approvals_denied += 1
    
    event.approvals_denied = approvals_denied
    db.add(event)
    db.commit()
    
    logger.warning(
        f"Emergency stop triggered by {triggered_by}: {reason} "
        f"(scope={scope}, approvals_denied={approvals_denied})"
    )
    
    return {
        "killswitch_id": event.id,
        "status": "triggered",
        "approvals_denied": approvals_denied,
        "message": "Emergency stop triggered - all pending approvals denied",
    }

# ============================================================================
# Statistics & Monitoring
# ============================================================================

@app.get("/api/stats")
async def get_stats(db: Session = Depends(get_db)):
    """Get comprehensive control plane statistics"""
    queue_svc = ApprovalQueueService(db)
    
    approval_stats = queue_svc.get_approval_stats()
    escalation_stats = escalation_engine.get_escalation_stats() if escalation_engine else {}
    heartbeat_stats = heartbeat_monitor.get_heartbeat_stats() if heartbeat_monitor else {}
    
    return {
        "approvals": approval_stats,
        "escalations": escalation_stats,
        "heartbeats": heartbeat_stats,
        "timestamp": datetime.utcnow().isoformat(),
    }

# ============================================================================
# Startup Message
# ============================================================================

@app.on_event("startup")
async def startup():
    logger.info("=" * 70)
    logger.info("Paperclip Human Control Plane started")
    logger.info(f"Database: {DATABASE_URL}")
    logger.info(f"Config: {PAPERCLIP_CONFIG_PATH}")
    logger.info("=" * 70)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=3200,
        log_level="info",
    )
