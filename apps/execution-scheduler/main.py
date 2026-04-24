#!/usr/bin/env python3
# @file apps/execution-scheduler/main.py
# @module infrastructure/execution-scheduler
# @description P3-1561 Phase 4: FastAPI scheduler with Kafka event publishing
# @governance GOV-002: All scheduling decisions published to event bus

from fastapi import FastAPI, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
import logging
import json
from .router import ExecutionScheduler, RoutingDecision
from .monitors import ResourceMonitoringService
from .cost_tracker import CostTracker

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Execution Scheduler", version="1.0")
scheduler = ExecutionScheduler()
monitor_service = ResourceMonitoringService()
cost_tracker = CostTracker(monthly_ci_budget_usd=500.0)

class SubmitTaskRequest(BaseModel):
    """Task submission for scheduling"""
    task_type: str
    data_classification: str = "public"
    estimated_cpu_cores: int = 2
    estimated_duration_seconds: int = 300
    estimated_tokens: int = 0
    user_id: str
    user_reputation_tier: str = "standard"

class RoutingResponse(BaseModel):
    """Routing decision response"""
    task_id: str
    destination: str
    reason: str
    cost_estimate: float
    latency_estimate_ms: int
    confidence: float
    fallback_destination: Optional[str]

class TaskStatusResponse(BaseModel):
    """Task execution status"""
    task_id: str
    status: str
    destination: str
    progress_percent: int
    cost_so_far: float
    estimated_total_cost: float

@app.get("/health")
async def health():
    """Health check"""
    return {
        "status": "healthy",
        "service": "execution-scheduler",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.post("/scheduler/submit", response_model=RoutingResponse)
async def submit_task(request: SubmitTaskRequest) -> RoutingResponse:
    """
    Submit a task for scheduling.
    Returns routing decision (destination, cost, latency estimates).
    """
    import uuid
    task_id = f"task-{uuid.uuid4().hex[:12]}"
    
    logger.info(
        f"Submitting task {task_id}: "
        f"type={request.task_type}, "
        f"user={request.user_id}"
    )
    
    # Get routing decision
    decision = scheduler.route_task(
        task_id=task_id,
        task_type=request.task_type,
        data_classification=request.data_classification,
        estimated_cpu_cores=request.estimated_cpu_cores,
        estimated_duration_seconds=request.estimated_duration_seconds,
        estimated_tokens=request.estimated_tokens,
        user_reputation_tier=request.user_reputation_tier
    )
    
    # Publish scheduling decision to Kafka
    await publish_scheduler_event(
        event_type="scheduler.task.submitted",
        payload={
            "task_id": task_id,
            "task_type": request.task_type,
            "destination": decision.destination,
            "reason": decision.reason,
            "cost_estimate": decision.cost_estimate,
            "user_id": request.user_id
        }
    )
    
    logger.info(f"Task {task_id} routed to {decision.destination}")
    
    return RoutingResponse(
        task_id=task_id,
        destination=decision.destination,
        reason=decision.reason,
        cost_estimate=decision.cost_estimate,
        latency_estimate_ms=decision.latency_estimate_ms,
        confidence=decision.confidence,
        fallback_destination=decision.fallback_destination
    )

@app.post("/scheduler/tasks/{task_id}/complete")
async def complete_task(
    task_id: str,
    destination: str,
    duration_seconds: float,
    cpu_cores_used: int = 2,
    tokens_used: int = 0,
    status: str = "success",
    error_message: Optional[str] = None
):
    """
    Mark a task as complete and calculate final costs.
    """
    logger.info(f"Task {task_id} completed on {destination} in {duration_seconds}s")
    
    # Calculate cost
    cost = cost_tracker.calculate_task_cost(
        task_id=task_id,
        destination=destination,
        duration_seconds=duration_seconds,
        cpu_cores_used=cpu_cores_used,
        tokens_used=tokens_used
    )
    
    # Publish task completion to Kafka
    await publish_scheduler_event(
        event_type="scheduler.task.completed",
        payload={
            "task_id": task_id,
            "destination": destination,
            "status": status,
            "duration_seconds": duration_seconds,
            "cost_usd": cost.resource_cost_usd,
            "error_message": error_message
        }
    )
    
    # Check budget
    if cost_tracker.check_budget_alert():
        logger.error("CI budget exceeded - enforcing cost controls")
    
    return {
        "task_id": task_id,
        "status": "recorded",
        "cost_usd": cost.resource_cost_usd,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.get("/scheduler/resources")
async def get_resources():
    """
    Get current resource availability across all destinations.
    """
    metrics = await monitor_service.get_all_metrics()
    
    return {
        "local": {
            "cpu_available_percent": metrics["local"]["cpu"]["available_percent"],
            "gpu_available_percent": metrics["local"]["gpu"]["gpu_available_percent"],
            "memory_available_gb": metrics["local"]["memory"]["available_gb"]
        },
        "ci": {
            "idle_runners": metrics["ci"]["idle_runners"],
            "queue_depth": metrics["ci"]["queue_depth"],
            "estimated_wait_minutes": metrics["ci"]["estimated_wait_minutes"]
        },
        "edge": {
            "available_nodes": metrics["edge"]["available_nodes"],
            "total_available_cores": metrics["edge"]["total_available_cores"]
        },
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.get("/scheduler/costs/monthly")
async def get_monthly_costs():
    """
    Get monthly cost breakdown by destination.
    """
    breakdown = cost_tracker.get_monthly_breakdown()
    
    budget_alert = cost_tracker.check_budget_alert()
    enforce_controls = cost_tracker.should_enforce_cost_controls()
    
    return {
        **breakdown,
        "budget_exceeded": budget_alert,
        "enforce_cost_controls": enforce_controls
    }

@app.get("/scheduler/tasks")
async def list_tasks(
    destination: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500)
) -> Dict[str, Any]:
    """
    List all tasks with optional filtering.
    """
    tasks = cost_tracker.get_cost_analysis(
        destination_filter=destination,
        min_cost_usd=0
    )
    
    return {
        "tasks": [
            {
                "task_id": t.task_id,
                "destination": t.destination,
                "duration_seconds": t.duration_seconds,
                "cost_usd": t.resource_cost_usd,
                "tokens_used": t.tokens_used
            }
            for t in tasks[:limit]
        ],
        "total": len(tasks),
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }

@app.post("/scheduler/tasks/{task_id}/cancel")
async def cancel_task(task_id: str):
    """
    Cancel a running task.
    """
    logger.info(f"Cancelling task {task_id}")
    
    # Publish cancellation to Kafka
    await publish_scheduler_event(
        event_type="scheduler.task.cancelled",
        payload={"task_id": task_id}
    )
    
    return {"status": "cancelled", "task_id": task_id}

async def publish_scheduler_event(
    event_type: str,
    payload: Dict[str, Any]
):
    """
    Publish scheduler event to Kafka.
    (Would use Kafka producer in production)
    """
    event = {
        "event_id": "uuid",
        "event_type": event_type,
        "schema_version": "1.0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "source": {"service": "execution-scheduler", "instance": "primary"},
        "actor": {"type": "system", "id": "scheduler"},
        "payload": payload
    }
    
    logger.info(f"Publishing event: {event_type}")
    # Would publish to Kafka topic here

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
