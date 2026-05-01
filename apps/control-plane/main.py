#!/usr/bin/env python3
"""
Control Plane Service
Orchestrates and manages code-server infrastructure services
"""

import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, Any

from apps._shared.python.config import get_config
import config as _svc_config

import os

try:
    from .risk_engine import RiskEngine
    from .policy_propagator import PolicyPropagator
    from .compliance_reporter import ComplianceReporter
except ImportError:
    from risk_engine import RiskEngine
    from policy_propagator import PolicyPropagator
    from compliance_reporter import ComplianceReporter

# SLOG: structured JSON logging (GOV-002 compliant)
class _JsonFmt(logging.Formatter):
    def format(self, r):
        import json, sys
        return json.dumps({"ts": self.formatTime(r, "%Y-%m-%dT%H:%M:%S"), "level": r.levelname, "svc": r.name, "msg": r.getMessage()})
_h = logging.StreamHandler()
_h.setFormatter(_JsonFmt())
logging.basicConfig(level=logging.INFO, handlers=[_h], force=True)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Control Plane",
    description="Service orchestration and control",
    version="1.0"
)

class ServiceStatus(BaseModel):
    service: str
    status: str
    healthy: bool

class HealthResponse(BaseModel):
    status: str
    service: str
    version: str

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        service="control-plane",
        version="1.0"
    )

@app.get("/services", response_model=Dict[str, Any])
async def get_services():
    """Get all managed services status"""
    config = get_config()
    return {
        "services": [
            "code-server-ide",
            "gitlab",
            "gitlab-runner",
            "testing-service",
            "minio",
            "vault",
            "artifact-repository"
        ],
        "cluster_id": config.get("DEPLOYMENT_ID", "primary"),
        "timestamp": os.getcwd()
    }

@app.post("/services/{service}/restart")
async def restart_service(service: str):
    """Request service restart (orchestrated by docker-compose)"""
    logger.info(f"Restart request for service: {service}")
    return {"service": service, "action": "restart_requested"}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return {
        "status": "operational",
        "services_managed": 7,
        "cluster_nodes": 2
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=_svc_config.HOST,
        port=_svc_config.PORT,
        log_level=_svc_config.LOG_LEVEL.lower(),
    )
