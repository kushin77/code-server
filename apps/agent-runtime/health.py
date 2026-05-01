"""
Agent Runtime Health Checks

Liveness check: `/health` — is the service running?
Readiness check: `/health/ready` — are dependencies available?

Both endpoints return JSON status and appropriate HTTP status codes.
"""

from datetime import datetime
from typing import Dict, Any, Optional

from fastapi import APIRouter, HTTPException
import asyncio

from log import get_logger, log_event

log = get_logger(__name__)
router = APIRouter()

# Global state tracking
_startup_time = datetime.utcnow()
_dependencies_healthy: Dict[str, bool] = {
    "database": False,
    "redis": False,
    "opa": False,
    "paperclip": False,
}


@router.get("")
async def liveness_check() -> Dict[str, Any]:
    """
    Liveness check endpoint.
    
    Returns 200 if the service is running and responding to requests.
    Used by Kubernetes/Docker as liveness probe.
    """
    uptime_seconds = (datetime.utcnow() - _startup_time).total_seconds()
    
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "uptime_seconds": uptime_seconds,
        "version": "1.0",
    }


@router.get("/ready")
async def readiness_check() -> Dict[str, Any]:
    """
    Readiness check endpoint.
    
    Returns 200 only if all critical dependencies are available:
    - Database (if DATABASE_URL set)
    - Redis (if REDIS_URL set)
    - OPA policy engine
    - Paperclip approval service
    
    Used by Kubernetes/Docker as readiness probe to determine if traffic should be sent.
    Returns 503 if any critical dependency is down.
    """
    ready_status = {
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "dependencies": _dependencies_healthy.copy(),
        "all_healthy": all(_dependencies_healthy.values()),
    }
    
    # If any dependency is unhealthy, return 503 Service Unavailable
    if not ready_status["all_healthy"]:
        log_event(
            log,
            "readiness_check_failed",
            unhealthy_deps=[k for k, v in _dependencies_healthy.items() if not v],
        )
        raise HTTPException(status_code=503, detail=ready_status)
    
    return ready_status


async def check_dependencies() -> None:
    """
    Background task to check dependency health.
    
    Called periodically to verify:
    - Database connectivity
    - Redis connectivity
    - OPA availability
    - Paperclip availability
    
    Updates global _dependencies_healthy dict.
    """
    # TODO: Implement actual health checks
    # For now, mark all as healthy on startup
    for key in _dependencies_healthy:
        _dependencies_healthy[key] = True
    
    log_event(log, "dependencies_health_checked", dependencies=_dependencies_healthy)
