"""
Edge Agent Models - Registration, Heartbeat, Status
@governance GOV-002: IaC, immutable, version-controlled
@author GitHub Copilot
@created 2026-04-24
"""

from datetime import datetime
from enum import Enum
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field


class EdgeAgentStatus(str, Enum):
    """Edge Agent lifecycle states (idempotent)"""
    REGISTERED = "registered"
    ACTIVE = "active"
    UNHEALTHY = "unhealthy"
    OFFLINE = "offline"
    DEREGISTERED = "deregistered"


class EdgeAgentLocation(str, Enum):
    """Supported edge agent locations (for geo-distribution)"""
    US_WEST = "us-west"
    US_EAST = "us-east"
    EU_CENTRAL = "eu-central"
    ASIA_PACIFIC = "asia-pacific"
    CUSTOM = "custom"


class EdgeAgentRegistration(BaseModel):
    """Edge Agent registration request (idempotent)"""
    agent_id: str = Field(..., description="Unique agent identifier")
    location: str = Field(..., description="Geographic location")
    capacity: int = Field(..., ge=1, description="Task capacity (cores or tasks)")
    status: str = Field(default="active", description="Agent status")
    registered_at: datetime = Field(default_factory=datetime.utcnow)
    last_heartbeat: datetime = Field(default_factory=datetime.utcnow)
    
    class Config:
        use_enum_values = True


class EdgeAgentHeartbeat(BaseModel):
    """Heartbeat from edge agent to control plane"""
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    status: str = Field(..., description="Current agent status")
    cpu_usage: float = Field(default=0.0, ge=0, le=100, description="CPU % utilization")
    memory_usage: float = Field(default=0.0, ge=0, le=100, description="Memory % utilization")
    active_tasks: int = Field(default=0, ge=0, description="Currently executing tasks")
    available_capacity: int = Field(default=0, ge=0, description="Available task slots")


class EdgeAgentStatusResponse(BaseModel):
    """Edge Agent status at any point in time (idempotent query)"""
    agent_id: str
    location: str
    capacity: int
    status: EdgeAgentStatus
    registered_at: datetime
    last_heartbeat: datetime
    unhealthy_reason: Optional[str] = None
    failed_at: Optional[datetime] = None
    failure_count: int = Field(default=0, ge=0)
    
    class Config:
        use_enum_values = True


class EdgeAgentRegistry(BaseModel):
    """Registry of all edge agents (for control plane)"""
    agents: Dict[str, EdgeAgentStatusResponse] = Field(default_factory=dict)
    total_capacity: int = Field(default=0)
    healthy_agents: int = Field(default=0)
    unhealthy_agents: int = Field(default=0)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    
    class Config:
        use_enum_values = True


class EdgeAgentHealthMetrics(BaseModel):
    """Health metrics for monitoring and alerting"""
    agent_id: str
    heartbeat_latency_ms: float  # Milliseconds since last heartbeat
    cpu_threshold_exceeded: bool  # CPU > 80%
    memory_threshold_exceeded: bool  # Memory > 85%
    capacity_utilization_pct: float  # (active_tasks / capacity) * 100
    is_healthy: bool
    last_check_at: datetime = Field(default_factory=datetime.utcnow)
    
    class Config:
        use_enum_values = True
