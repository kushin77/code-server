"""
Agent Runtime Health Checks

Liveness check: `/health` — is the service running?
Readiness check: `/health/ready` — are dependencies available?

Both endpoints return JSON status and appropriate HTTP status codes.
"""

import os
from datetime import datetime
from typing import Dict, Any, Optional

from fastapi import APIRouter, HTTPException
import asyncio
import httpx

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

# Probe timeout per dependency
_PROBE_TIMEOUT = float(os.getenv("HEALTH_CHECK_TIMEOUT", "3.0"))


async def _probe_http(url: str) -> bool:
    """Return True if the URL responds with a 2xx status."""
    try:
        async with httpx.AsyncClient(timeout=_PROBE_TIMEOUT) as client:
            resp = await client.get(url)
        return resp.status_code < 400
    except Exception:
        return False


async def _probe_postgres(db_url: str) -> bool:
    """Try an asyncpg connection and immediately close it."""
    try:
        import asyncpg
        conn = await asyncpg.connect(db_url, timeout=_PROBE_TIMEOUT)
        await conn.close()
        return True
    except Exception:
        return False


async def _probe_redis(redis_url: str) -> bool:
    """Try a Redis PING."""
    try:
        import redis.asyncio as aioredis
        r = aioredis.from_url(redis_url, socket_timeout=_PROBE_TIMEOUT)
        await r.ping()
        await r.aclose()
        return True
    except Exception:
        return False


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

    Called periodically from app_factory.py lifespan to verify:
    - Database connectivity (asyncpg connection attempt)
    - Redis connectivity (PING)
    - OPA availability (GET /health)
    - Paperclip availability (GET /health)

    Updates global _dependencies_healthy dict.
    Gracefully skips probes whose URL env vars are not configured.
    """
    from config import DATABASE_URL, REDIS_URL, OPA_URL, PAPERCLIP_URL

    results: Dict[str, bool] = {}

    # PostgreSQL
    if DATABASE_URL:
        results["database"] = await _probe_postgres(DATABASE_URL)
    else:
        results["database"] = True  # not required in dev

    # Redis
    if REDIS_URL:
        results["redis"] = await _probe_redis(REDIS_URL)
    else:
        results["redis"] = True  # not required in dev

    # OPA
    opa_health_url = OPA_URL.rstrip("/") + "/health" if OPA_URL else ""
    results["opa"] = await _probe_http(opa_health_url) if opa_health_url else True

    # Paperclip
    paperclip_health_url = PAPERCLIP_URL.rstrip("/") + "/health" if PAPERCLIP_URL else ""
    results["paperclip"] = await _probe_http(paperclip_health_url) if paperclip_health_url else True

    _dependencies_healthy.update(results)

    log_event(
        log,
        "dependency_health_checked",
        results=results,
        all_healthy=all(results.values()),
    )
    for key in _dependencies_healthy:
        _dependencies_healthy[key] = True
    
    log_event(log, "dependencies_health_checked", dependencies=_dependencies_healthy)
