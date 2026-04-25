#!/usr/bin/env python3
"""
@file apps/agent-runtime/main.py
@module infrastructure/agent-runtime
@description P3-1557: Agent Runtime - Sandboxed agent execution with approval gating
@governance GOV-002: Deterministic, audited, capability-scoped execution
"""

import logging
import asyncio
from datetime import datetime
from apps._common.logging import setup_logging
from apps._common.tracing import setup_tracing
from prometheus_fastapi_instrumentator import Instrumentator
from typing import Optional, List, Dict
from fastapi import FastAPI, Query, HTTPException, BackgroundTasks, Body, Request
from contextlib import asynccontextmanager

from agent import (
    CodeReviewerAgent, IncidentResponderAgent, 
    DocWriterAgent, TestGeneratorAgent
)
from models import (
    AgentType, AgentExecutionRequest, AgentExecutionResult,
    AgentHeartbeat, AgentConfiguration
)
from paperclip_client import PaperclipClient
from oidc_client import OIDCClient
from execution_router import ExecutionRouter, ExecutionDestination
from access_control import CapabilityValidator, CapabilityScope, RiskLevel
from audit_logging import get_audit_logger, AuditLogger
from sandbox_enforcement import SandboxOrchestrator, SandboxConstraint
from config import get_config, get_agent_constraints

setup_logging("agent-runtime")
logger = logging.getLogger(__name__)

# Initialize configuration (readonly, from environment)
readonly_CONFIG = get_config()

# Global state - initialized at startup
agents = {}
paperclip_client: Optional[PaperclipClient] = None
oidc_client: Optional[OIDCClient] = None
execution_router: Optional[ExecutionRouter] = None
audit_logger: Optional[AuditLogger] = None
capability_validators: Dict[str, CapabilityValidator] = {}
sandbox_orchestrators: Dict[str, SandboxOrchestrator] = {}
start_time = datetime.utcnow()
execution_count = 0


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle - initialize all components at startup"""
    global paperclip_client, oidc_client, execution_router, audit_logger
    
    logger.info("Agent Runtime starting (version 1.0)...")
    
    try:
        # Initialize audit logger first (needed for all components)
        audit_logger = get_audit_logger()
        logger.info(f"✓ Audit logger initialized (buffer: {readonly_CONFIG.readonly_AUDIT_BUFFER_SIZE})")
        
        # Initialize Paperclip client
        paperclip_client = PaperclipClient(
            paperclip_url=readonly_CONFIG.readonly_PAPERCLIP_URL
        )
        logger.info(f"✓ Paperclip client initialized ({readonly_CONFIG.readonly_PAPERCLIP_URL})")
        
        # Initialize OIDC client for each agent type
        oidc_client = OIDCClient(
            client_id=readonly_CONFIG.readonly_OIDC_CLIENT_ID,
            client_secret=readonly_CONFIG.readonly_OIDC_CLIENT_SECRET,
            token_endpoint=readonly_CONFIG.readonly_OIDC_TOKEN_ENDPOINT
        )
        logger.info(f"✓ OIDC client initialized ({readonly_CONFIG.readonly_OIDC_CLIENT_ID})")
        
        # Initialize execution router
        execution_router = ExecutionRouter()
        logger.info("✓ Execution router initialized")
        
        # Initialize agents with capability validators and sandbox orchestrators
        agents["code-reviewer"] = CodeReviewerAgent()
        capability_validators["code-reviewer"] = CapabilityValidator(
            agent_type="code-reviewer",
            declared_capabilities=agents["code-reviewer"].capabilities.capabilities_set
        )
        constraints = get_agent_constraints("code-reviewer")
        sandbox_orchestrators["code-reviewer"] = SandboxOrchestrator(
            agent_id="agent-code-reviewer",
            constraint=SandboxConstraint(
                max_execution_time_seconds=constraints["timeout_seconds"],
                max_memory_mb=constraints["memory_mb"],
                max_cpu_cores=constraints["cpu_cores"],
                allowed_network_egress=readonly_CONFIG.readonly_NETWORK_EGRESS_ALLOWED,
                allowed_filesystem_paths=readonly_CONFIG.readonly_ALLOWED_FILESYSTEM_PATHS,
                allow_internet_access=readonly_CONFIG.readonly_ALLOW_INTERNET_ACCESS
            )
        )
        logger.info("✓ Code Reviewer agent initialized with access control and sandbox")
        
        agents["incident-responder"] = IncidentResponderAgent()
        capability_validators["incident-responder"] = CapabilityValidator(
            agent_type="incident-responder",
            declared_capabilities=agents["incident-responder"].capabilities.capabilities_set
        )
        constraints = get_agent_constraints("incident-responder")
        sandbox_orchestrators["incident-responder"] = SandboxOrchestrator(
            agent_id="agent-incident-responder",
            constraint=SandboxConstraint(
                max_execution_time_seconds=constraints["timeout_seconds"],
                max_memory_mb=constraints["memory_mb"],
                max_cpu_cores=constraints["cpu_cores"],
                allowed_network_egress=readonly_CONFIG.readonly_NETWORK_EGRESS_ALLOWED,
                allowed_filesystem_paths=readonly_CONFIG.readonly_ALLOWED_FILESYSTEM_PATHS,
                allow_internet_access=readonly_CONFIG.readonly_ALLOW_INTERNET_ACCESS
            )
        )
        logger.info("✓ Incident Responder agent initialized with access control and sandbox")
        
        agents["doc-writer"] = DocWriterAgent()
        capability_validators["doc-writer"] = CapabilityValidator(
            agent_type="doc-writer",
            declared_capabilities=agents["doc-writer"].capabilities.capabilities_set
        )
        constraints = get_agent_constraints("doc-writer")
        sandbox_orchestrators["doc-writer"] = SandboxOrchestrator(
            agent_id="agent-doc-writer",
            constraint=SandboxConstraint(
                max_execution_time_seconds=constraints["timeout_seconds"],
                max_memory_mb=constraints["memory_mb"],
                max_cpu_cores=constraints["cpu_cores"],
                allowed_network_egress=readonly_CONFIG.readonly_NETWORK_EGRESS_ALLOWED,
                allowed_filesystem_paths=readonly_CONFIG.readonly_ALLOWED_FILESYSTEM_PATHS,
                allow_internet_access=readonly_CONFIG.readonly_ALLOW_INTERNET_ACCESS
            )
        )
        logger.info("✓ Doc Writer agent initialized with access control and sandbox")
        
        agents["test-generator"] = TestGeneratorAgent()
        capability_validators["test-generator"] = CapabilityValidator(
            agent_type="test-generator",
            declared_capabilities=agents["test-generator"].capabilities.capabilities_set
        )
        constraints = get_agent_constraints("test-generator")
        sandbox_orchestrators["test-generator"] = SandboxOrchestrator(
            agent_id="agent-test-generator",
            constraint=SandboxConstraint(
                max_execution_time_seconds=constraints["timeout_seconds"],
                max_memory_mb=constraints["memory_mb"],
                max_cpu_cores=constraints["cpu_cores"],
                allowed_network_egress=readonly_CONFIG.readonly_NETWORK_EGRESS_ALLOWED,
                allowed_filesystem_paths=readonly_CONFIG.readonly_ALLOWED_FILESYSTEM_PATHS,
                allow_internet_access=readonly_CONFIG.readonly_ALLOW_INTERNET_ACCESS
            )
        )
        logger.info("✓ Test Generator agent initialized with access control and sandbox")
        
        audit_logger.log_event(audit_logger._create_event(
            event_type="agent.startup",
            details={"agents_initialized": len(agents)}
        ))
        
        logger.info(f"Agent Runtime fully initialized: {len(agents)} agents ready")
        
    except Exception as e:
        logger.error(f"Failed to initialize Agent Runtime: {e}", exc_info=True)
        raise
    
    yield
    
    logger.info("Agent Runtime shutting down...")


app = FastAPI(
    title="Agent Runtime",
    description="Sandboxed agent execution with approval gating and OIDC",
    version="1.0",
    lifespan=lifespan
)

# Setup Tracing
setup_tracing("agent-runtime", app)

# Instrument with Prometheus metrics
Instrumentator().instrument(app).expose(app)


# ============================================================================
# HEALTH & DIAGNOSTICS
# ============================================================================

@app.get("/health")
async def health_check():
    """Service health check - includes agent and dependency status"""
    uptime = (datetime.utcnow() - start_time).total_seconds()
    
    return {
        "status": "healthy",
        "version": readonly_CONFIG.readonly_VERSION,
        "uptime_seconds": uptime,
        "agents_available": len(agents),
        "agents_running": sum(1 for a in agents.values() if a.is_running),
        "execution_count": execution_count,
        "audit_enabled": readonly_CONFIG.readonly_AUDIT_LOG_ENABLED,
        "sandbox_enabled": readonly_CONFIG.readonly_SANDBOX_ENFORCEMENT_ENABLED,
        "environment": readonly_CONFIG.readonly_DEPLOYMENT_ENVIRONMENT,
        "region": readonly_CONFIG.readonly_DEPLOYMENT_REGION
    }


@app.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics"""
    return {
        "uptime_seconds": (datetime.utcnow() - start_time).total_seconds(),
        "execution_count": execution_count,
        "agents_active": sum(1 for a in agents.values() if a.is_running),
        "agents_total": len(agents),
        "audit_log_buffer_size": len(audit_logger.event_buffer) if audit_logger else 0
    }


@app.get("/diagnostics/config")
async def diagnostics_config():
    """Configuration diagnostics (for operators)"""
    return {
        "oidc": {
            "client_id": readonly_CONFIG.readonly_OIDC_CLIENT_ID,
            "token_endpoint": readonly_CONFIG.readonly_OIDC_TOKEN_ENDPOINT,
            "max_retries": readonly_CONFIG.readonly_OIDC_MAX_RETRIES
        },
        "paperclip": {
            "url": readonly_CONFIG.readonly_PAPERCLIP_URL,
            "approval_timeout_seconds": readonly_CONFIG.readonly_APPROVAL_TIMEOUT_SECONDS,
            "auto_approve_low_risk": readonly_CONFIG.readonly_AUTO_APPROVE_LOW_RISK
        },
        "sandbox": {
            "enforcement_enabled": readonly_CONFIG.readonly_SANDBOX_ENFORCEMENT_ENABLED,
            "allow_internet_access": readonly_CONFIG.readonly_ALLOW_INTERNET_ACCESS,
            "network_egress_allowed": readonly_CONFIG.readonly_NETWORK_EGRESS_ALLOWED
        },
        "agents": {
            agent_key: {
                "timeout_seconds": get_agent_constraints(agent_key)["timeout_seconds"],
                "memory_mb": get_agent_constraints(agent_key)["memory_mb"],
                "cpu_cores": get_agent_constraints(agent_key)["cpu_cores"]
            }
            for agent_key in agents.keys()
        }
    }


@app.get("/diagnostics/oidc")
async def diagnostics_oidc():
    """OIDC token diagnostics"""
    if not oidc_client:
        return {"status": "not_initialized"}
    return oidc_client.get_token_info()


# ============================================================================
# EXECUTION ENDPOINTS
# ============================================================================

@app.post("/execute")
async def execute_agent_task(
    request: AgentExecutionRequest,
    background_tasks: BackgroundTasks
):
    """
    Submit agent task for execution with approval gating and sandbox enforcement.
    
    Execution flow:
    1. Validate capability via access control
    2. Check risk level and submit approval if required
    3. Route execution to appropriate destination
    4. Execute in sandbox with resource limits
    5. Return result with audit trail
    """
    global execution_count
    execution_count += 1
    
    # Get agent key
    agent_key = request.agent_type.value.lower().replace("_", "-")
    if agent_key not in agents:
        raise HTTPException(status_code=400, detail=f"Unknown agent type: {request.agent_type}")
    
    agent = agents[agent_key]
    execution_id = f"exec-{request.agent_id[:8]}-{execution_count:06d}"
    
    try:
        # Log action request (audit trail)
        if audit_logger:
            audit_logger.log_action_request(
                agent_id=request.agent_id,
                execution_id=execution_id,
                action=request.action,
                risk_level=request.risk_level.value,
                approval_required=str(request.requires_approval),
                details={"destination": request.execution_destination}
            )
        
        # Step 1: Validate capability
        validator = capability_validators.get(agent_key)
        if validator:
            is_allowed, reason, approval_required = validator.validate_action(
                action_scope=CapabilityScope.GITHUB_REPO,  # Simplified mapping
                action_name=request.action,
                risk_level_override=request.risk_level
            )
            
            if audit_logger:
                audit_logger.log_capability_check(
                    agent_id=request.agent_id,
                    execution_id=execution_id,
                    action=request.action,
                    allowed=is_allowed,
                    reason=reason
                )
            
            if not is_allowed:
                raise HTTPException(status_code=403, detail=f"Capability denied: {reason}")
        
        # Step 2: Check killswitch
        if paperclip_client:
            is_killed = await paperclip_client.check_killswitch(request.agent_id)
            if is_killed:
                raise HTTPException(status_code=403, detail="Agent is under killswitch")
        
        # Step 3: Submit approval if required
        approval_id = None
        if request.requires_approval:
            if paperclip_client:
                approval = await paperclip_client.submit_approval_request(
                    agent_id=request.agent_id,
                    user_id=request.submitted_by,
                    action=request.action,
                    resource=f"{request.agent_type.value}",
                    risk_level=request.risk_level.value,
                    metadata={
                        "execution_id": execution_id,
                        "destination": request.execution_destination
                    }
                )
                
                if not approval:
                    raise HTTPException(status_code=503, detail="Approval system unavailable")
                
                approval_id = approval.get("request_id")
                
                if audit_logger:
                    audit_logger.log_approval_submitted(
                        agent_id=request.agent_id,
                        execution_id=execution_id,
                        action=request.action,
                        approval_id=approval_id,
                        risk_level=request.risk_level.value
                    )
                
                # Wait for approval
                approval_status = await paperclip_client.wait_for_approval(
                    approval_id,
                    timeout_seconds=readonly_CONFIG.readonly_APPROVAL_TIMEOUT_SECONDS
                )
                
                if audit_logger:
                    audit_logger.log_approval_decision(
                        agent_id=request.agent_id,
                        execution_id=execution_id,
                        approval_id=approval_id,
                        decision=approval_status,
                        risk_level=request.risk_level.value
                    )
                
                if approval_status != "approved":
                    return {
                        "execution_id": execution_id,
                        "status": "denied",
                        "approval_status": approval_status
                    }
        
        # Step 4: Route execution
        if execution_router:
            destination = execution_router.route(request)
            request.execution_destination = destination.value
        
        # Step 5: Execute asynchronously
        async def _execute():
            try:
                exec_start = datetime.utcnow()
                
                if audit_logger:
                    audit_logger.log_execution_started(
                        agent_id=request.agent_id,
                        execution_id=execution_id,
                        action=request.action
                    )
                
                # Execute agent action
                result = await agent.execute(request)
                
                exec_duration_ms = int((datetime.utcnow() - exec_start).total_seconds() * 1000)
                
                if audit_logger:
                    audit_logger.log_execution_completed(
                        agent_id=request.agent_id,
                        execution_id=execution_id,
                        action=request.action,
                        duration_ms=exec_duration_ms,
                        details={"status": result.status}
                    )
                
                # Store result (for demonstration)
                agent.execution_history[execution_id] = result
                
            except Exception as e:
                exec_duration_ms = int((datetime.utcnow() - exec_start).total_seconds() * 1000)
                
                if audit_logger:
                    audit_logger.log_execution_failed(
                        agent_id=request.agent_id,
                        execution_id=execution_id,
                        action=request.action,
                        error=str(e),
                        duration_ms=exec_duration_ms
                    )
                
                logger.error(f"Execution failed [{execution_id}]: {e}", exc_info=True)
        
        background_tasks.add_task(_execute)
        
        return {
            "execution_id": execution_id,
            "status": "submitted",
            "agent_type": request.agent_type.value,
            "action": request.action,
            "approval_id": approval_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Request processing failed [{execution_id}]: {e}", exc_info=True)
        if audit_logger:
            audit_logger.log_event(audit_logger._create_event(
                event_type="error.high",
                agent_id=request.agent_id,
                execution_id=execution_id,
                error=str(e)
            ))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/heartbeat")
async def report_heartbeat(heartbeat: AgentHeartbeat):
    """Report agent heartbeat and current status"""
    if audit_logger:
        audit_logger.log_event(audit_logger._create_event(
            event_type="agent.heartbeat",
            agent_id=heartbeat.agent_id,
            details={"status": heartbeat.status, "last_action": heartbeat.last_action}
        ))
    
    result = await paperclip_client.report_heartbeat(
        agent_id=heartbeat.agent_id,
        agent_type=heartbeat.agent_type.value,
        status=heartbeat.status,
        current_task=heartbeat.last_action
    ) if paperclip_client else True
    
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
    """List all available agents with status"""
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
    """Get detailed agent status"""
    agent_key = agent_type.lower().replace("_", "-")
    
    if agent_key not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_type}")
    
    agent = agents[agent_key]
    
    # Get capability summary
    validator = capability_validators.get(agent_key)
    capabilities_summary = validator.get_capabilities_summary() if validator else {}
    
    # Get sandbox enforcement report
    sandbox = sandbox_orchestrators.get(agent_key)
    sandbox_report = sandbox.get_enforcement_report() if sandbox else {}
    
    return {
        "agent_type": agent_type,
        "running": agent.is_running,
        "current_execution": agent.current_execution_id,
        "total_executions": len(agent.execution_history),
        "capabilities": capabilities_summary,
        "sandbox": sandbox_report
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
                "started_at": result.start_time.isoformat() if hasattr(result, 'start_time') else None,
                "duration_seconds": result.duration_seconds if hasattr(result, 'duration_seconds') else None
            }
            for exec_id, result in history
        ]
    }


# ============================================================================
# AUDIT & DIAGNOSTICS
# ============================================================================

@app.get("/audit/events/{correlation_id}")
async def get_audit_events(
    correlation_id: str,
    limit: int = Query(100, ge=1, le=1000)
):
    """Get audit events for correlation ID"""
    if not audit_logger:
        raise HTTPException(status_code=503, detail="Audit logging not enabled")
    
    events = audit_logger.get_event_history(correlation_id=correlation_id, limit=limit)
    return {
        "correlation_id": correlation_id,
        "events_count": len(events),
        "events": events
    }


@app.get("/audit/execution-trace/{execution_id}")
async def get_execution_trace(
    execution_id: str
):
    """Get complete execution trace (all audit events for an execution)"""
    if not audit_logger:
        raise HTTPException(status_code=503, detail="Audit logging not enabled")
    
    trace = audit_logger.get_execution_trace(execution_id)
    return {
        "execution_id": execution_id,
        "events_count": len(trace),
        "trace": trace
    }


# ============================================================================
# ROUTING & INFRASTRUCTURE
# ============================================================================

@app.get("/routing/stats")
async def get_routing_stats():
    """Get execution routing statistics"""
    if not execution_router:
        raise HTTPException(status_code=503, detail="Routing not initialized")
    
    return {
        "stats": execution_router.get_routing_stats()
    }


@app.post("/routing/mark-local-unavailable")
async def mark_local_unavailable():
    """Mark local execution destination as unavailable"""
    if execution_router:
        execution_router.mark_local_unavailable()
    return {"status": "local marked unavailable"}


@app.post("/routing/mark-local-available")
async def mark_local_available():
    """Mark local execution destination as available"""
    if execution_router:
        execution_router.mark_local_available()
    return {"status": "local marked available"}


# ============================================================================
# SYSTEM STATISTICS
# ============================================================================

@app.get("/statistics")
async def get_statistics():
    """Get overall system statistics"""
    return {
        "total_executions": execution_count,
        "agents_active": sum(1 for a in agents.values() if a.is_running),
        "agents_total": len(agents),
        "uptime_hours": (datetime.utcnow() - start_time).total_seconds() / 3600,
        "audit_events_buffered": len(audit_logger.event_buffer) if audit_logger else 0,
        "deployment_environment": readonly_CONFIG.readonly_DEPLOYMENT_ENVIRONMENT
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=readonly_CONFIG.readonly_SERVICE_HOST,
        port=readonly_CONFIG.readonly_SERVICE_PORT,
        log_level=readonly_CONFIG.readonly_LOG_LEVEL.lower()
    )
