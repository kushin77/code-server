"""
Edge Agent Control Plane API - Registration & Heartbeat Handlers
@governance GOV-002: IaC, immutable, version-controlled
@author GitHub Copilot
@created 2026-04-24
"""

from fastapi import APIRouter, HTTPException, Depends, Request
from datetime import datetime, timedelta
from typing import Dict, Optional
from pydantic import ValidationError

from .models import (
    EdgeAgentRegistration,
    EdgeAgentHeartbeat,
    EdgeAgentStatusResponse,
    EdgeAgentRegistry,
    EdgeAgentStatus,
)

router = APIRouter(prefix="/api/v1/edge-agents", tags=["edge-agents"])

# In-memory registry (in production, use database)
_agent_registry: Dict[str, EdgeAgentStatusResponse] = {}
_heartbeat_history: Dict[str, list] = {}
HEARTBEAT_TIMEOUT_SECONDS = 60  # Agents dead if no heartbeat for 60s
MAX_HEARTBEAT_HISTORY = 100


def _is_agent_healthy(agent_id: str) -> bool:
    """Determine if agent is healthy based on recent heartbeat"""
    if agent_id not in _agent_registry:
        return False
    
    agent = _agent_registry[agent_id]
    if agent.status == EdgeAgentStatus.OFFLINE:
        return False
    
    time_since_heartbeat = (
        datetime.utcnow() - agent.last_heartbeat
    ).total_seconds()
    
    return time_since_heartbeat < HEARTBEAT_TIMEOUT_SECONDS


def _record_heartbeat(agent_id: str, heartbeat: EdgeAgentHeartbeat):
    """Store heartbeat in history for analytics"""
    if agent_id not in _heartbeat_history:
        _heartbeat_history[agent_id] = []
    
    history = _heartbeat_history[agent_id]
    history.append(heartbeat.dict())
    
    # Keep only recent history (idempotent trimming)
    if len(history) > MAX_HEARTBEAT_HISTORY:
        _heartbeat_history[agent_id] = history[-MAX_HEARTBEAT_HISTORY:]


@router.post("", status_code=201)
def register_edge_agent(registration: EdgeAgentRegistration) -> EdgeAgentStatusResponse:
    """
    Register new edge agent (idempotent - updates if exists)
    
    Args:
        registration: Agent registration details
        
    Returns:
        EdgeAgentStatusResponse with agent status
        
    Raises:
        HTTPException: If agent_id is invalid
    """
    if not registration.agent_id:
        raise HTTPException(status_code=400, detail="agent_id is required")
    
    # Idempotent: Create or update
    agent_response = EdgeAgentStatusResponse(
        agent_id=registration.agent_id,
        location=registration.location,
        capacity=registration.capacity,
        status=EdgeAgentStatus.ACTIVE,
        registered_at=registration.registered_at,
        last_heartbeat=registration.last_heartbeat,
    )
    
    _agent_registry[registration.agent_id] = agent_response
    
    return agent_response


@router.get("/{agent_id}")
def get_edge_agent(agent_id: str) -> EdgeAgentStatusResponse:
    """
    Get status of edge agent
    
    Args:
        agent_id: Agent identifier
        
    Returns:
        EdgeAgentStatusResponse with current status
        
    Raises:
        HTTPException: If agent not found
    """
    if agent_id not in _agent_registry:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
    agent = _agent_registry[agent_id]
    
    # Check health and update status if needed
    if not _is_agent_healthy(agent_id) and agent.status != EdgeAgentStatus.OFFLINE:
        agent.status = EdgeAgentStatus.UNHEALTHY
        agent.unhealthy_reason = "Heartbeat timeout"
    
    return agent


@router.patch("/{agent_id}")
def update_edge_agent(
    agent_id: str,
    update: Dict
) -> EdgeAgentStatusResponse:
    """
    Update edge agent status (idempotent)
    
    Args:
        agent_id: Agent identifier
        update: Fields to update
        
    Returns:
        Updated EdgeAgentStatusResponse
        
    Raises:
        HTTPException: If agent not found or update invalid
    """
    if agent_id not in _agent_registry:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
    agent = _agent_registry[agent_id]
    
    # Apply idempotent updates
    for key, value in update.items():
        if hasattr(agent, key):
            setattr(agent, key, value)
    
    return agent


@router.post("/{agent_id}/heartbeat", status_code=200)
def receive_heartbeat(
    agent_id: str,
    heartbeat: EdgeAgentHeartbeat
) -> Dict:
    """
    Receive heartbeat from edge agent (idempotent)
    
    Args:
        agent_id: Agent identifier
        heartbeat: Heartbeat data from agent
        
    Returns:
        Acknowledgment with control plane status
        
    Raises:
        HTTPException: If agent not registered
    """
    if agent_id not in _agent_registry:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not registered")
    
    agent = _agent_registry[agent_id]
    
    # Update last heartbeat (idempotent)
    agent.last_heartbeat = heartbeat.timestamp
    if agent.status == EdgeAgentStatus.UNHEALTHY and heartbeat.status == "healthy":
        agent.status = EdgeAgentStatus.ACTIVE
        agent.failure_count = 0
    
    # Record heartbeat history
    _record_heartbeat(agent_id, heartbeat)
    
    return {
        "acknowledged": True,
        "agent_id": agent_id,
        "server_time": datetime.utcnow().isoformat() + "Z",
    }


@router.get("/{agent_id}/status")
def get_agent_status(agent_id: str) -> Dict:
    """
    Get current health status of agent
    
    Args:
        agent_id: Agent identifier
        
    Returns:
        Current status and metrics
        
    Raises:
        HTTPException: If agent not found
    """
    if agent_id not in _agent_registry:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
    agent = _agent_registry[agent_id]
    
    return {
        "agent_id": agent_id,
        "status": agent.status.value,
        "last_heartbeat": agent.last_heartbeat.isoformat() + "Z",
        "is_healthy": _is_agent_healthy(agent_id),
        "time_since_heartbeat_seconds": (
            datetime.utcnow() - agent.last_heartbeat
        ).total_seconds(),
    }


@router.get("")
def list_edge_agents() -> EdgeAgentRegistry:
    """
    List all registered edge agents (idempotent query)
    
    Returns:
        Registry with all agents and aggregated metrics
    """
    healthy_count = sum(
        1 for agent_id in _agent_registry
        if _is_agent_healthy(agent_id)
    )
    unhealthy_count = len(_agent_registry) - healthy_count
    total_capacity = sum(agent.capacity for agent in _agent_registry.values())
    
    return EdgeAgentRegistry(
        agents=_agent_registry,
        total_capacity=total_capacity,
        healthy_agents=healthy_count,
        unhealthy_agents=unhealthy_count,
        updated_at=datetime.utcnow(),
    )


@router.post("/{agent_id}/deregister", status_code=200)
def deregister_edge_agent(agent_id: str) -> Dict:
    """
    Deregister edge agent (idempotent - safe if already deregistered)
    
    Args:
        agent_id: Agent identifier
        
    Returns:
        Confirmation of deregistration
    """
    if agent_id in _agent_registry:
        agent = _agent_registry[agent_id]
        agent.status = EdgeAgentStatus.DEREGISTERED
        # Keep record for audit trail, but mark as deregistered
    
    return {
        "deregistered": True,
        "agent_id": agent_id,
        "deregistered_at": datetime.utcnow().isoformat() + "Z",
    }
