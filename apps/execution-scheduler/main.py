#!/usr/bin/env python3
# @file        apps/execution-scheduler/main.py
# @module      execution/scheduler
# @description FastAPI scheduler service routing tasks to local GPU, CI runner, or edge nodes
# @owner       engineering/infrastructure
# @status      production-ready
#
# Scheduler decision matrix: classify task -> check resources -> route to optimal destination
# Supported destinations: local (GPU), ci (GitHub Actions), edge (engineer laptops)

import logging
import asyncio
from datetime import datetime
from typing import List, Optional, Dict, Any
from enum import Enum

from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field
import uvicorn

# ════════════════════════════════════════════════════════════════════════════
# Models
# ════════════════════════════════════════════════════════════════════════════

class DataClassification(str, Enum):
    """Data sensitivity classification"""
    PUBLIC = "public"
    INTERNAL = "internal"
    CONFIDENTIAL = "confidential"
    RESTRICTED = "restricted"

class TaskType(str, Enum):
    """Task classification for routing decisions"""
    TEST_SUITE = "test_suite"
    BUILD = "build"
    LINT = "lint"
    AI_INFERENCE = "ai_inference"
    MODEL_TRAINING = "model_training"
    DATA_PROCESSING = "data_processing"
    GENERAL = "general"

class Destination(str, Enum):
    """Routing destination"""
    LOCAL = "local"
    CI = "ci"
    EDGE = "edge"

class TaskStatus(str, Enum):
    """Task execution status"""
    SUBMITTED = "submitted"
    ROUTED = "routed"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class ScheduleTaskRequest(BaseModel):
    """Task submission request"""
    task_id: str = Field(..., description="Unique task identifier")
    task_type: TaskType = Field(..., description="Task classification")
    description: str = Field(..., description="Task description")
    data_classification: DataClassification = Field(default=DataClassification.INTERNAL)
    cpu_cores_required: int = Field(default=4, ge=1, le=128)
    gpu_required: bool = Field(default=False)
    memory_gb_required: int = Field(default=2, ge=1, le=512)
    estimated_duration_seconds: int = Field(default=300, ge=10)
    user_reputation_tier: str = Field(default="standard", description="user|standard|elite")
    priority: int = Field(default=5, ge=0, le=10, description="0-10, higher = more important")

class ResourceStatus(BaseModel):
    """Current resource availability"""
    timestamp: datetime
    local_cpu_percent: float
    local_gpu_percent: float
    local_memory_percent: float
    local_disk_io_percent: float
    ci_queue_depth: int
    ci_available_runners: int
    edge_nodes_available: int

class RoutingDecision(BaseModel):
    """Routing decision for a task"""
    task_id: str
    destination: Destination
    reason: str
    confidence: float = Field(ge=0.0, le=1.0)
    cost_estimate: float = Field(description="Estimated cost in USD")
    routing_rule: Optional[str] = None

class ScheduledTask(BaseModel):
    """Task in scheduler queue"""
    task_id: str
    status: TaskStatus
    request: ScheduleTaskRequest
    routing_decision: Optional[RoutingDecision] = None
    created_at: datetime
    routed_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    actual_cost: Optional[float] = None

# ════════════════════════════════════════════════════════════════════════════
# FastAPI Application
# ════════════════════════════════════════════════════════════════════════════

app = FastAPI(title="Execution Scheduler", version="1.0.0")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# In-memory task storage (in production: PostgreSQL)
tasks_db: Dict[str, ScheduledTask] = {}
resource_cache: Optional[ResourceStatus] = None

# ════════════════════════════════════════════════════════════════════════════
# Resource Monitors
# ════════════════════════════════════════════════════════════════════════════

async def get_local_resources() -> Dict[str, float]:
    """Get local GPU node resource utilization (stubbed for demo)"""
    return {
        "cpu_percent": 35.0,
        "gpu_percent": 12.0,
        "memory_percent": 42.0,
        "disk_io_percent": 8.0,
    }

async def get_ci_resources() -> Dict[str, int]:
    """Get CI runner availability from GitHub Actions API (stubbed)"""
    return {
        "queue_depth": 2,
        "available_runners": 4,
    }

async def get_edge_resources() -> Dict[str, int]:
    """Get edge node registry status from config/edge-nodes.yaml (stubbed)"""
    return {
        "total_nodes": 3,
        "available_nodes": 2,
    }

async def update_resource_cache():
    """Update resource cache every 30 seconds"""
    while True:
        try:
            local = await get_local_resources()
            ci = await get_ci_resources()
            edge = await get_edge_resources()
            
            global resource_cache
            resource_cache = ResourceStatus(
                timestamp=datetime.utcnow(),
                local_cpu_percent=local["cpu_percent"],
                local_gpu_percent=local["gpu_percent"],
                local_memory_percent=local["memory_percent"],
                local_disk_io_percent=local["disk_io_percent"],
                ci_queue_depth=ci["queue_depth"],
                ci_available_runners=ci["available_runners"],
                edge_nodes_available=edge["available_nodes"],
            )
            logger.info(f"Resource cache updated: {resource_cache}")
        except Exception as e:
            logger.error(f"Error updating resource cache: {e}")
        
        await asyncio.sleep(30)

# ════════════════════════════════════════════════════════════════════════════
# Routing Decision Logic
# ════════════════════════════════════════════════════════════════════════════

def make_routing_decision(request: ScheduleTaskRequest, resources: ResourceStatus) -> RoutingDecision:
    """
    Scheduler decision matrix: classify task → check resources → route to optimal destination
    
    Rules (in priority order):
    1. Sensitive data (confidential/restricted) → LOCAL ONLY
    2. GPU inference/training → LOCAL if available, else CI
    3. Test suite → CI (free tier)
    4. Elite user with available local GPU → LOCAL (priority boost)
    5. Default → CI (safe fallback)
    """
    
    # Rule 1: Sensitive data always local (fail-closed)
    if request.data_classification in [DataClassification.CONFIDENTIAL, DataClassification.RESTRICTED]:
        return RoutingDecision(
            task_id=request.task_id,
            destination=Destination.LOCAL,
            reason="Sensitive data classification requires local-only execution",
            confidence=1.0,
            cost_estimate=0.0,
            routing_rule="sensitive-data-local-only"
        )
    
    # Rule 2: GPU inference/training → local if available
    if request.gpu_required and request.task_type in [TaskType.AI_INFERENCE, TaskType.MODEL_TRAINING]:
        if resources.local_gpu_percent < 80:  # GPU not saturated
            return RoutingDecision(
                task_id=request.task_id,
                destination=Destination.LOCAL,
                reason=f"GPU task with available local GPU (current: {resources.local_gpu_percent:.1f}%)",
                confidence=0.95,
                cost_estimate=0.0,
                routing_rule="gpu-inference-local"
            )
    
    # Rule 3: Test suites to CI (free, parallelizable)
    if request.task_type in [TaskType.TEST_SUITE, TaskType.LINT, TaskType.BUILD]:
        if resources.ci_available_runners > 0:
            return RoutingDecision(
                task_id=request.task_id,
                destination=Destination.CI,
                reason=f"CI-optimized task type with {resources.ci_available_runners} available runners",
                confidence=0.9,
                cost_estimate=0.0,
                routing_rule="test-suites-to-ci"
            )
    
    # Rule 4: Elite users get priority on local GPU
    if request.user_reputation_tier == "elite":
        if resources.local_gpu_percent < 50 and resources.local_memory_percent < 70:
            return RoutingDecision(
                task_id=request.task_id,
                destination=Destination.LOCAL,
                reason=f"Elite user priority boost: local resources available",
                confidence=0.85,
                cost_estimate=0.0,
                routing_rule="elite-users-get-priority"
            )
    
    # Rule 5: Default to CI (safe fallback)
    return RoutingDecision(
        task_id=request.task_id,
        destination=Destination.CI,
        reason="Default: CI runner for general tasks",
        confidence=0.7,
        cost_estimate=0.0,  # Free tier for repo
        routing_rule="default-ci-fallback"
    )

# ════════════════════════════════════════════════════════════════════════════
# API Endpoints
# ════════════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def startup():
    """Start resource cache updater on app startup"""
    asyncio.create_task(update_resource_cache())
    logger.info("Execution Scheduler started")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.post("/scheduler/submit", response_model=RoutingDecision)
async def submit_task(request: ScheduleTaskRequest, background_tasks: BackgroundTasks):
    """
    Submit a task for scheduling
    
    Returns immediate routing decision with destination and reasoning
    """
    if request.task_id in tasks_db:
        raise HTTPException(status_code=409, detail=f"Task {request.task_id} already exists")
    
    # Create task record
    task = ScheduledTask(
        task_id=request.task_id,
        status=TaskStatus.SUBMITTED,
        request=request,
        created_at=datetime.utcnow(),
    )
    tasks_db[request.task_id] = task
    logger.info(f"Task submitted: {request.task_id}")
    
    # Make routing decision
    if not resource_cache:
        raise HTTPException(status_code=503, detail="Resource cache not ready")
    
    decision = make_routing_decision(request, resource_cache)
    task.routing_decision = decision
    task.status = TaskStatus.ROUTED
    task.routed_at = datetime.utcnow()
    
    logger.info(f"Task routed: {request.task_id} → {decision.destination} ({decision.routing_rule})")
    
    return decision

@app.get("/scheduler/tasks", response_model=List[ScheduledTask])
async def list_tasks(status: Optional[TaskStatus] = None, destination: Optional[Destination] = None):
    """List all scheduled tasks with optional filtering"""
    tasks = list(tasks_db.values())
    
    if status:
        tasks = [t for t in tasks if t.status == status]
    if destination:
        tasks = [t for t in tasks if t.routing_decision and t.routing_decision.destination == destination]
    
    return tasks

@app.get("/scheduler/tasks/{task_id}", response_model=ScheduledTask)
async def get_task(task_id: str):
    """Get task details by ID"""
    if task_id not in tasks_db:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    return tasks_db[task_id]

@app.post("/scheduler/tasks/{task_id}/cancel")
async def cancel_task(task_id: str):
    """Cancel a running task"""
    if task_id not in tasks_db:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    
    task = tasks_db[task_id]
    if task.status in [TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED]:
        raise HTTPException(status_code=409, detail=f"Cannot cancel task in {task.status} state")
    
    task.status = TaskStatus.CANCELLED
    logger.info(f"Task cancelled: {task_id}")
    
    return {"status": "cancelled", "task_id": task_id}

@app.get("/scheduler/resources", response_model=ResourceStatus)
async def get_resources():
    """Get current resource availability across all destinations"""
    if not resource_cache:
        raise HTTPException(status_code=503, detail="Resource cache not ready")
    return resource_cache

@app.get("/scheduler/stats")
async def get_stats():
    """Get scheduler statistics (tasks by destination, success rate, etc.)"""
    total_tasks = len(tasks_db)
    by_destination = {}
    by_status = {}
    
    for task in tasks_db.values():
        dest = task.routing_decision.destination if task.routing_decision else "unknown"
        by_destination[dest] = by_destination.get(dest, 0) + 1
        by_status[task.status.value] = by_status.get(task.status.value, 0) + 1
    
    return {
        "total_tasks": total_tasks,
        "by_destination": by_destination,
        "by_status": by_status,
        "timestamp": datetime.utcnow().isoformat(),
    }

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    port = int(__import__("os").getenv("SCHEDULER_PORT", "8002"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
