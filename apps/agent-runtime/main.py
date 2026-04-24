#!/usr/bin/env python3
# @file        apps/agent-runtime/main.py
# @module      agent-runtime/service
# @description Agent runtime FastAPI service - spawn agents, manage lifecycle, handle approvals
# @owner       agent-runtime
# @status      production-ready
#
# API endpoints: spawn agent, get status, submit action, approve/deny, get results

import os
import asyncio
import logging
from typing import Dict, Any, Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from datetime import datetime, timedelta

from .models import (
    Base, init_db, AgentType, TaskState, ActionType, PolicyDecision,
    TaskAssignment, AgentAction,
)
from .sandbox import SandboxManager
from .identity import IdentityManager
from .approval_gate import ApprovalGateService
from .agents.incident_responder import IncidentResponderAgent

logger = logging.getLogger(__name__)

# ============================================================================
# Configuration
# ============================================================================

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://paperclip:paperclip@localhost:5432/paperclip"
)

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
# Global Services
# ============================================================================

identity_manager: Optional[IdentityManager] = None

async def init_services():
    """Initialize services"""
    global identity_manager
    identity_manager = IdentityManager()
    logger.info("Services initialized: identity manager")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan: startup/shutdown"""
    init_db(DATABASE_URL)
    await init_services()
    logger.info("Agent runtime startup complete")
    yield
    logger.info("Agent runtime shutdown")

# ============================================================================
# Pydantic Models
# ============================================================================

class TaskSubmitRequest(BaseModel):
    agent_type: str
    description: str
    input_data: Dict[str, Any]

class TaskResponse(BaseModel):
    task_id: str
    agent_type: str
    state: str
    created_at: str

class ActionSubmitRequest(BaseModel):
    action_type: str
    resource: str
    payload: Dict[str, Any]

class ApprovalDecisionRequest(BaseModel):
    decision: str  # "approved" or "denied"
    approver_id: str
    reason: str = ""

# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(
    title="Agent Runtime Service",
    description="Spawn agents, manage lifecycle, handle approvals, track audit trail",
    version="1.0.0",
    lifespan=lifespan,
)

# ============================================================================
# Health Check
# ============================================================================

@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """Health check"""
    try:
        # Verify database connectivity
        db.execute("SELECT 1")
        return {
            "status": "ok",
            "service": "agent-runtime",
            "database": "connected",
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database error: {e}")

# ============================================================================
# Task Submission & Lifecycle
# ============================================================================

@app.post("/api/tasks/submit", response_model=TaskResponse)
async def submit_task(
    request: TaskSubmitRequest,
    db: Session = Depends(get_db)
):
    """Submit a task for agent execution"""
    
    try:
        agent_type = AgentType[request.agent_type.upper()]
    except KeyError:
        raise HTTPException(status_code=400, detail=f"Unknown agent type: {request.agent_type}")
    
    import uuid
    task_id = f"task-{str(uuid.uuid4())[:8]}"
    
    # Create task assignment
    task = TaskAssignment(
        id=task_id,
        agent_type=agent_type,
        description=request.description,
        input_data=str(request.input_data),
        state=TaskState.QUEUED,
        created_at=datetime.utcnow(),
    )
    
    db.add(task)
    db.commit()
    
    logger.info(f"Task submitted: {task_id} (type: {agent_type.value})")
    
    return TaskResponse(
        task_id=task_id,
        agent_type=agent_type.value,
        state=TaskState.QUEUED.value,
        created_at=task.created_at.isoformat(),
    )

@app.post("/api/tasks/{task_id}/spawn-agent")
async def spawn_agent(
    task_id: str,
    db: Session = Depends(get_db)
):
    """Spawn agent container for task"""
    
    # Get task
    task = db.query(TaskAssignment).filter(
        TaskAssignment.id == task_id
    ).first()
    
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")
    
    # Issue OIDC token
    capabilities = identity_manager.get_agent_capabilities(task.agent_type.value)
    token_result = identity_manager.issue_token(
        agent_id=f"{task.agent_type.value}/{task_id}",
        agent_type=task.agent_type.value,
        parent_task_id=task_id,
        capabilities=capabilities,
    )
    
    # Spawn sandbox
    sandbox = SandboxManager(db)
    spawn_result = sandbox.spawn_agent(
        agent_type=task.agent_type,
        parent_task_id=task_id,
        oidc_token=token_result["token"],
        oidc_expires_at=datetime.fromisoformat(token_result["expires_at"]),
    )
    
    # Update task state
    task.agent_id = spawn_result["agent_id"]
    task.state = TaskState.RUNNING
    task.started_at = datetime.utcnow()
    
    # Record state transition
    states = [
        {"state": TaskState.QUEUED.value, "at": task.created_at.isoformat()},
        {"state": TaskState.RUNNING.value, "at": datetime.utcnow().isoformat()},
    ]
    task.state_transitions = str(states)
    
    db.commit()
    
    return {
        "task_id": task_id,
        "agent_id": spawn_result["agent_id"],
        "container_id": spawn_result["container_id"],
        "status": "running",
    }

@app.get("/api/tasks/{task_id}")
async def get_task(
    task_id: str,
    db: Session = Depends(get_db)
):
    """Get task status"""
    
    task = db.query(TaskAssignment).filter(
        TaskAssignment.id == task_id
    ).first()
    
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")
    
    return {
        "task_id": task.id,
        "agent_id": task.agent_id,
        "agent_type": task.agent_type.value,
        "state": task.state.value,
        "description": task.description,
        "started_at": task.started_at.isoformat() if task.started_at else None,
        "completed_at": task.completed_at.isoformat() if task.completed_at else None,
        "output": task.output_data,
    }

@app.get("/api/tasks")
async def list_tasks(
    state: Optional[str] = Query(None),
    agent_type: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """List tasks"""
    
    query = db.query(TaskAssignment)
    
    if state:
        query = query.filter(TaskAssignment.state == TaskState[state.upper()])
    
    if agent_type:
        query = query.filter(TaskAssignment.agent_type == AgentType[agent_type.upper()])
    
    tasks = query.order_by(TaskAssignment.created_at.desc()).limit(limit).all()
    
    return [
        {
            "task_id": t.id,
            "agent_type": t.agent_type.value,
            "state": t.state.value,
            "created_at": t.created_at.isoformat(),
        }
        for t in tasks
    ]

# ============================================================================
# Action Submission & Approval
# ============================================================================

@app.post("/api/agents/{agent_id}/actions/submit")
async def submit_action(
    agent_id: str,
    request: ActionSubmitRequest,
    db: Session = Depends(get_db)
):
    """Agent submits action for approval"""
    
    try:
        action_type = ActionType[request.action_type.upper()]
    except KeyError:
        raise HTTPException(status_code=400, detail=f"Unknown action type: {request.action_type}")
    
    # Get agent's task
    from .models import AgentInstance
    agent = db.query(AgentInstance).filter(
        AgentInstance.id == agent_id
    ).first()
    
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_id}")
    
    # Evaluate action against OPA policy
    approval_gate = ApprovalGateService(db)
    capabilities = identity_manager.get_agent_capabilities(agent.agent_type.value)
    
    policy_decision, policy_details = approval_gate.evaluate_action(
        agent_id=agent_id,
        task_id=agent.parent_task_id,
        action_type=action_type,
        resource=request.resource,
        payload=request.payload,
        agent_capabilities=capabilities,
    )
    
    # Record action
    result = approval_gate.record_action(
        agent_id=agent_id,
        task_id=agent.parent_task_id,
        action_type=action_type,
        resource=request.resource,
        payload=request.payload,
        policy_decision=policy_decision,
        policy_details=policy_details,
    )
    
    return {
        "action_id": result["action_id"],
        "policy_decision": result["policy_decision"],
        "requires_approval": result["requires_approval"],
        "approval_gate_id": result.get("approval_gate_id"),
    }

@app.get("/api/approvals/pending")
async def get_pending_approvals(
    db: Session = Depends(get_db)
):
    """Get actions awaiting approval"""
    
    approval_gate = ApprovalGateService(db)
    pending = approval_gate.get_pending_approvals()
    
    return {
        "count": len(pending),
        "approvals": pending,
    }

@app.post("/api/approvals/{gate_id}/decide")
async def decide_approval(
    gate_id: str,
    request: ApprovalDecisionRequest,
    db: Session = Depends(get_db)
):
    """Human approves or denies action"""
    
    approval_gate = ApprovalGateService(db)
    
    if request.decision == "approved":
        success = approval_gate.approve_action(gate_id, request.approver_id, request.reason)
    elif request.decision == "denied":
        success = approval_gate.deny_action(gate_id, request.approver_id, request.reason)
    else:
        raise HTTPException(status_code=400, detail=f"Invalid decision: {request.decision}")
    
    if not success:
        raise HTTPException(status_code=404, detail=f"Approval not found: {gate_id}")
    
    return {
        "gate_id": gate_id,
        "decision": request.decision,
        "decided_by": request.approver_id,
        "status": "recorded",
    }

# ============================================================================
# Incident Responder (Example Agent)
# ============================================================================

@app.post("/api/agents/incident-responder/execute")
async def execute_incident_responder(
    task_id: str,
    input_data: Dict[str, Any],
    db: Session = Depends(get_db)
):
    """Execute incident responder agent"""
    
    agent_id = f"incident-responder/{task_id}"
    agent = IncidentResponderAgent(
        agent_id=agent_id,
        task_id=task_id,
        oidc_token="mock-token",
    )
    
    result = await agent.execute(input_data)
    
    # Update task with result
    task = db.query(TaskAssignment).filter(
        TaskAssignment.id == task_id
    ).first()
    
    if task:
        task.state = TaskState.COMPLETED
        task.completed_at = datetime.utcnow()
        task.output_data = str(result)
        db.commit()
    
    return result

# ============================================================================
# Statistics
# ============================================================================

@app.get("/api/stats")
async def get_stats(db: Session = Depends(get_db)):
    """Get runtime statistics"""
    
    total_tasks = db.query(TaskAssignment).count()
    running_tasks = db.query(TaskAssignment).filter(
        TaskAssignment.state == TaskState.RUNNING
    ).count()
    completed_tasks = db.query(TaskAssignment).filter(
        TaskAssignment.state == TaskState.COMPLETED
    ).count()
    
    approval_gate = ApprovalGateService(db)
    approval_stats = approval_gate.get_approval_stats()
    
    return {
        "tasks": {
            "total": total_tasks,
            "running": running_tasks,
            "completed": completed_tasks,
        },
        "approvals": approval_stats,
        "timestamp": datetime.utcnow().isoformat(),
    }

# ============================================================================
# Startup
# ============================================================================

@app.on_event("startup")
async def startup():
    logger.info("=" * 70)
    logger.info("Agent Runtime Service started")
    logger.info(f"Database: {DATABASE_URL}")
    logger.info("=" * 70)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=3300,
        log_level="info",
    )
