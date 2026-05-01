"""
@file apps/execution-scheduler/models.py
@description Pydantic models for execution scheduler
@governance GOV-002
"""

from typing import List, Dict, Optional, Literal
from datetime import datetime
from pydantic import BaseModel, Field
from enum import Enum
import os


class TaskType(str, Enum):
    """Task classification for routing decisions."""
    TEST_SUITE = "test_suite"
    LINT = "lint"
    BUILD = "build"
    AI_INFERENCE = "ai_inference"
    MODEL_TRAINING = "model_training"
    DEPLOYMENT = "deployment"
    ANALYSIS = "analysis"
    OTHER = "other"


class DataClassification(str, Enum):
    """Data sensitivity classification."""
    PUBLIC = "public"
    INTERNAL = "internal"
    CONFIDENTIAL = "confidential"
    RESTRICTED = "restricted"


class Destination(str, Enum):
    """Task execution destination."""
    LOCAL = "local"
    CI = "ci"
    EDGE = "edge"
    CLOUD = "cloud"


class RoutingReason(str, Enum):
    """Why a task was routed to a destination."""
    DATA_SOVEREIGNTY = "data_sovereignty"  # Sensitive data must stay local
    LOCAL_AVAILABLE = "local_available"  # Local GPU available
    CI_OPTIMAL = "ci_optimal"  # Task type optimized for CI
    LOCAL_SATURATED = "local_saturated"  # Local GPU at capacity
    CI_OVERLOADED = "ci_overloaded"  # CI queue full
    EDGE_BURST = "edge_burst"  # Engineer laptop available
    COST_OPTIMAL = "cost_optimal"  # Minimizes cost
    REPUTATION_PRIORITY = "reputation_priority"  # Elite user gets priority
    EXPLICIT_RULE = "explicit_rule"  # Matched scheduler rule
    DEFAULT = "default"  # Default fallback


class TaskSubmissionRequest(BaseModel):
    """Task submission to scheduler."""
    task_id: str = Field(..., description="Unique task identifier")
    task_type: TaskType = Field(..., description="Task classification")
    data_classification: DataClassification = Field(default=DataClassification.INTERNAL)
    cpu_cores_required: float = Field(default=1, ge=0.5, le=256)
    gpu_required: bool = Field(default=False)
    estimated_duration_sec: int = Field(default=300, ge=1)
    submitter_user: str = Field(..., description="User submitting the task")
    submitter_tier: str = Field(default="standard", description="User reputation tier")
    memory_required_mb: int = Field(default=512, ge=256)


class SchedulingDecision(BaseModel):
    """Routing decision from scheduler."""
    task_id: str
    assigned_destination: Destination
    reasoning: RoutingReason
    estimated_cost_usd: float
    expected_latency_ms: int
    priority: int = Field(default=0, description="Queue priority (higher = earlier)")
    matched_rule: Optional[str] = None


class ResourceSnapshot(BaseModel):
    """Current resource utilization snapshot."""
    cpu_percent: float = Field(ge=0, le=100)
    gpu_percent: float = Field(ge=0, le=100)
    memory_percent: float = Field(ge=0, le=100)
    disk_io_pending: int = Field(ge=0)
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class LocalResources(BaseModel):
    """Local GPU resource availability."""
    host: str
    available: bool
    gpu_type: str
    snapshot: ResourceSnapshot
    saturated: bool  # CPU>85% OR GPU>90% OR Memory>80%


class CICapacity(BaseModel):
    """CI runner capacity snapshot."""
    provider: str
    max_runners: int
    active_runners: int
    queue_depth: int
    overloaded: bool  # queue_depth > threshold


class EdgeNode(BaseModel):
    """Edge device node for burst compute."""
    name: str
    hostname: str
    available: bool
    cpu_percent: float
    memory_percent: float
    last_heartbeat: datetime


class SystemResources(BaseModel):
    """Global system resource state."""
    local: LocalResources
    ci: CICapacity
    edge_nodes: List[EdgeNode]
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class TaskExecution(BaseModel):
    """Task execution record."""
    task_id: str
    destination: Destination
    status: Literal["submitted", "queued", "running", "completed", "failed"]
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    duration_sec: Optional[float] = None
    actual_cost_usd: float = Field(default=0.0)
    resource_usage: Dict[str, float] = Field(default_factory=dict)
    error_message: Optional[str] = None
    retry_count: int = Field(default=0)
    routing_reason: RoutingReason


class SchedulerConfig(BaseModel):
    """Scheduler configuration from env.yaml."""
    mode: Literal["local_only", "ci_only", "hybrid", "edge_burst"] = "hybrid"
    local_gpu_host: str = Field(default_factory=lambda: os.getenv("LOCAL_GPU_HOST", ""))
    local_gpu_available: bool = True
    local_gpu_type: str = "A100"
    ci_provider: str = "github"
    ci_max_runners: int = 4
    ci_timeout_sec: int = 3600
    edge_enabled: bool = True
    edge_heartbeat_timeout_sec: int = 60
    monthly_ci_budget_usd: float = 500.0
    alert_threshold: float = 0.8  # Alert at 80% of budget
    enable_sensitivity_check: bool = True
