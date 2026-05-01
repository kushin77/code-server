#!/usr/bin/env python3
"""
@file apps/agent-runtime/main.py
@module infrastructure/agent-runtime
@description P3-1557: Agent Runtime - Sandboxed agent execution with approval gating
@governance GOV-002: Deterministic, audited, capability-scoped execution
"""

import asyncio
import os
import uuid
from datetime import datetime
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, Query, HTTPException, BackgroundTasks, Body
from contextlib import asynccontextmanager

from agent import (
    CodeReviewerAgent, IncidentResponderAgent, 
    DocWriterAgent, TestGeneratorAgent
)
from models import (
    AgentType, AgentExecutionRequest, AgentExecutionResult,
    AgentHeartbeat, AgentConfiguration, ApprovalStatus
)
from paperclip_client import PaperclipClient
from oidc_client import OIDCClient
from execution_router import ExecutionRouter, ExecutionDestination
from config import PORT, HOST, validate_config
from log import get_logger, log_event
from health import router as health_router
from hermes_registration import hermes_client
from hermes_tracing import setup_tracing, instrument_app
from apps.shared.github_integration import get_github_integration, GitHubUser, GitHubRepository
from apps.shared.trace_enhancement import (
    initialize_trace_enhancement,
    setup_request_sampling,
    get_outbound_trace_headers,
    end_request_trace,
)
from apps.shared.trace_patterns import TraceSamplingConfig, SamplingStrategy

# Validate configuration on startup (raises if production secrets missing)
validate_config()

# Centralized structured logging
logger = get_logger(__name__)

# Global state
agents = {}
paperclip_client = PaperclipClient()
oidc_client: Optional[OIDCClient] = None
execution_router = ExecutionRouter()
start_time = datetime.utcnow()
execution_count = 0
execution_failures: List[Dict[str, Any]] = []


def record_execution_failure(
    request: AgentExecutionRequest,
    destination: ExecutionDestination,
    error: Exception,
    execution_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Store structured execution failure evidence for diagnostics."""
    failure_record = {
        "execution_id": execution_id or f"exec-failed-{uuid.uuid4().hex[:12]}",
        "agent_id": request.agent_id,
        "agent_type": request.agent_type.value,
        "task_type": request.task_type,
        "action": request.action,
        "destination": destination.value,
        "error_message": str(error),
        "timestamp": datetime.utcnow().isoformat(),
    }

    execution_failures.append(failure_record)
    del execution_failures[:-100]
    return failure_record


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle"""
    setup_tracing(service_name=os.environ.get("OTEL_SERVICE_NAME", "agent-runtime"))
    
    # Initialize advanced tracing with sampling
    sampling_config = TraceSamplingConfig(
        strategy=SamplingStrategy.UNIFORM,
        sample_rate=float(os.environ.get("TRACE_SAMPLE_RATE", "0.1")),
        exclude_paths=["/health", "/metrics"],
        always_sample_paths=["/agents/execute", "/approval/request"],
    )
    initialize_trace_enhancement(sampling_config)
    
    log_event(logger, "agent_runtime_startup")
    # Initialize agents based on AGENT_TYPE (each container runs one type)
    agent_type_env = os.environ.get("AGENT_TYPE", "all")
    if agent_type_env in ("code-reviewer", "all"):
        agents["code-reviewer"] = CodeReviewerAgent()
    if agent_type_env in ("incident-responder", "all"):
        agents["incident-responder"] = IncidentResponderAgent()
    if agent_type_env in ("doc-writer", "all"):
        agents["doc-writer"] = DocWriterAgent()
    if agent_type_env in ("test-generator", "all"):
        agents["test-generator"] = TestGeneratorAgent()
    await hermes_client.register()
    yield
    await hermes_client.deregister()
    log_event(logger, "agent_runtime_shutdown")


app = FastAPI(
    title="Agent Runtime",
    description="Sandboxed agent execution with approval gating and OIDC",
    version="1.0",
    lifespan=lifespan
)

# Register health check router
app.include_router(health_router, prefix="/health", tags=["health"])

# Apply OTEL FastAPI auto-instrumentation (no-op if tracing not initialised)
instrument_app(app)


# ── Advanced Tracing Middleware ───────────────────────────────────────────────
# Middleware for request-level trace sampling and context management
@app.middleware("http")
async def advanced_tracing_middleware(request, call_next):
    """Middleware for advanced tracing with sampling and context propagation."""
    # Setup sampling for request
    should_trace = setup_request_sampling(
        path=request.url.path,
        headers=dict(request.headers),
    )
    
    try:
        # Call endpoint
        response = await call_next(request)
        
        # Add trace headers to response if traced
        if should_trace:
            trace_headers = get_outbound_trace_headers()
            for key, value in trace_headers.items():
                response.headers[key] = value
        
        return response
    finally:
        # End trace
        end_request_trace()


# ============================================================================
# HEALTH & DIAGNOSTICS
# ============================================================================

# ============================================================================
# (Health checks moved to health.py and registered via router)
# ============================================================================

@app.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics"""
    uptime = (datetime.utcnow() - start_time).total_seconds()
    
    return {
        "status": "healthy",
        "version": "1.0",
        "uptime_seconds": uptime,
        "agents_available": len(agents),
        "execution_count": execution_count,
        "routing_stats": execution_router.get_routing_stats()
    }


# ============================================================================
# EXECUTION ENDPOINTS
# ============================================================================

@app.post("/execute")
async def execute_agent_task(
    request: AgentExecutionRequest,
    background_tasks: BackgroundTasks
):
    """Submit agent task for execution"""
    global execution_count
    execution_count += 1
    
    # Check killswitch
    is_killed = await paperclip_client.check_killswitch(request.agent_id)
    if is_killed:
        raise HTTPException(status_code=403, detail="Agent is under killswitch")
    
    # Get agent
    agent_key = request.agent_type.value.lower().replace("_", "-")
    if agent_key not in agents:
        raise HTTPException(status_code=400, detail=f"Unknown agent type: {request.agent_type}")
    
    agent = agents[agent_key]
    
    # Route execution
    destination = execution_router.route(request)
    request.execution_destination = destination.value
    
    # Submit approval if required
    if request.requires_approval:
        approval = await paperclip_client.submit_approval_request(
            agent_id=request.agent_id,
            user_id=request.submitted_by,
            action=request.action,
            resource=f"{request.agent_type}/{request.task_type}",
            risk_level=request.risk_level.value,
            metadata={"destination": destination.value}
        )
        
        if not approval:
            raise HTTPException(status_code=503, detail="Approval system unavailable")
        
        approval_request_id = approval.get("request_id")
        
        # Wait for approval
        approval_status = await paperclip_client.wait_for_approval(
            approval_request_id,
            timeout_seconds=request.timeout_seconds
        )
        
        if approval_status != "approved":
            return {
                "execution_id": None,
                "status": "denied",
                "reason": f"Approval {approval_status}"
            }
    
    # Execute asynchronously
    async def _execute():
        try:
            result = await agent.execute(request)
            log_event(logger, "agent_execution_complete", execution_id=result.execution_id, status=result.status)
            if result.status != "success":
                execution_failures.append({
                    "execution_id": result.execution_id,
                    "agent_id": result.agent_id,
                    "agent_type": result.agent_type.value,
                    "task_type": request.task_type,
                    "action": request.action,
                    "destination": result.execution_destination,
                    "error_message": result.error_message or f"Execution finished with status {result.status}",
                    "timestamp": datetime.utcnow().isoformat(),
                })
                del execution_failures[:-100]
        except Exception as e:
            failure_record = record_execution_failure(request, destination, e, getattr(agent, "current_execution_id", None))
            if failure_record["execution_id"] not in agent.execution_history:
                agent.execution_history[failure_record["execution_id"]] = AgentExecutionResult(
                    execution_id=failure_record["execution_id"],
                    agent_id=request.agent_id,
                    agent_type=request.agent_type,
                    status="failure",
                    approval_status=ApprovalStatus.APPROVED,
                    start_time=datetime.utcnow(),
                    end_time=datetime.utcnow(),
                    duration_seconds=0.0,
                    error_message=str(e),
                    execution_destination=destination.value,
                )
            logger.exception(f"Execution error: {e}")
    
    background_tasks.add_task(_execute)
    
    return {
        "execution_id": agent.current_execution_id,
        "agent_id": request.agent_id,
        "agent_type": request.agent_type.value,
        "status": "queued",
        "destination": destination.value,
        "submitted_at": datetime.utcnow().isoformat()
    }


@app.post("/heartbeat")
async def report_heartbeat(heartbeat: AgentHeartbeat):
    """Report agent heartbeat"""
    result = await paperclip_client.report_heartbeat(
        agent_id=heartbeat.agent_id,
        agent_type=heartbeat.agent_type.value,
        status=heartbeat.status,
        current_task=heartbeat.last_action
    )
    
    return {
        "agent_id": heartbeat.agent_id,
        "status": "recorded" if result else "failed",
        "timestamp": datetime.utcnow().isoformat()
    }


# ============================================================================
# AGENT MANAGEMENT ENDPOINTS
# ============================================================================

@app.get("/agents")
async def list_agents():
    """List all available agents"""
    return {
        "agents": [
            {
                "agent_type": agent_key,
                "running": agent.is_running,
                "execution_id": agent.current_execution_id,
                "execution_count": len(agent.execution_history)
            }
            for agent_key, agent in agents.items()
        ]
    }


@app.get("/agents/{agent_type}/status")
async def get_agent_status(agent_type: str):
    """Get agent status"""
    agent_key = agent_type.lower().replace("_", "-")
    
    if agent_key not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_type}")
    
    agent = agents[agent_key]
    
    return {
        "agent_type": agent_type,
        "running": agent.is_running,
        "current_execution": agent.current_execution_id,
        "total_executions": len(agent.execution_history),
        "capabilities": agent.capabilities.dict()
    }


@app.get("/agents/{agent_type}/history")
async def get_agent_history(
    agent_type: str,
    limit: int = Query(10, ge=1, le=100)
):
    """Get agent execution history"""
    agent_key = agent_type.lower().replace("_", "-")
    
    if agent_key not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_type}")
    
    agent = agents[agent_key]
    history = list(agent.execution_history.items())[-limit:]
    
    return {
        "agent_type": agent_type,
        "history_count": len(history),
        "executions": [
            {
                "execution_id": exec_id,
                "status": result.status,
                "started_at": result.start_time.isoformat(),
                "duration_seconds": result.duration_seconds
            }
            for exec_id, result in history
        ]
    }


# ============================================================================
# ROUTING & INFRASTRUCTURE
# ============================================================================

@app.get("/routing/stats")
async def get_routing_stats():
    """Get execution routing statistics"""
    return {
        "stats": execution_router.get_routing_stats()
    }


@app.get("/diagnostics/executions")
async def get_execution_diagnostics(limit: int = Query(20, ge=1, le=100)):
    """Get recent execution failure evidence."""
    return {
        "failure_count": len(execution_failures),
        "recent_failures": execution_failures[-limit:],
        "agents_tracked": len(agents),
    }


@app.post("/routing/mark-local-unavailable")
async def mark_local_unavailable():
    """Mark local execution as unavailable"""
    execution_router.mark_local_unavailable()
    return {"status": "local marked unavailable"}


@app.post("/routing/mark-local-available")
async def mark_local_available():
    """Mark local execution as available"""
    execution_router.mark_local_available()
    return {"status": "local marked available"}


# ============================================================================
# STATISTICS
# ============================================================================

@app.get("/statistics")
async def get_statistics():
    """Get system statistics"""
    return {
        "total_executions": execution_count,
        "agents_active": sum(1 for a in agents.values() if a.is_running),
        "agents_total": len(agents),
        "uptime_hours": (datetime.utcnow() - start_time).total_seconds() / 3600
    }


# ============================================================================
# GITHUB INTEGRATION (WITH DISTRIBUTED TRACING)
# ============================================================================

@app.get("/github/user/{username}")
async def get_github_user(username: str):
    """Get GitHub user information with distributed tracing.
    
    All calls are automatically traced to Jaeger for visibility
    into external service dependencies.
    """
    github = get_github_integration()
    user = await github.get_user(username)
    
    if user:
        return {
            "status": "success",
            "user": user.to_dict(),
            "traces": github.get_traces()
        }
    else:
        raise HTTPException(status_code=404, detail=f"User not found: {username}")


@app.get("/github/repositories/{username}")
async def get_user_repositories(username: str):
    """Get user's repositories with distributed tracing."""
    github = get_github_integration()
    repositories = await github.get_user_repositories(username)
    
    return {
        "status": "success",
        "username": username,
        "repository_count": len(repositories),
        "repositories": [repo.to_dict() for repo in repositories],
        "traces": github.get_traces()
    }


@app.post("/github/pull-request/{owner}/{repo}")
async def create_pull_request(
    owner: str,
    repo: str,
    title: str = Body(...),
    body: str = Body(...),
    head: str = Body(...),
    base: str = Body("main"),
):
    """Create pull request with distributed tracing."""
    github = get_github_integration()
    pr = await github.create_pull_request(
        owner=owner,
        repo=repo,
        title=title,
        body=body,
        head=head,
        base=base,
    )
    
    if pr:
        return {
            "status": "success",
            "pull_request": pr.to_dict(),
            "traces": github.get_traces()
        }
    else:
        raise HTTPException(status_code=500, detail="Failed to create pull request")


@app.get("/github/traces")
async def get_github_traces():
    """Get all recorded GitHub API traces for observability."""
    github = get_github_integration()
    traces = github.get_traces()
    
    return {
        "trace_count": len(traces),
        "traces": traces
    }


if __name__ == "__main__":
    import config as _cfg
    import uvicorn
    uvicorn.run(app, host=_cfg.HOST, port=_cfg.PORT)
