#!/usr/bin/env python3
"""
Control Plane Service
Orchestrates and manages code-server infrastructure services
"""

from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel
from typing import Dict, Any

import config as _svc_config
from apps.shared.monitoring import ApplicationMetrics, MonitoringConfig, track_metrics

import os

try:
    from .risk_engine import RiskEngine
    from .policy_propagator import PolicyPropagator
    from .compliance_reporter import ComplianceReporter
except ImportError:
    from risk_engine import RiskEngine
    from policy_propagator import PolicyPropagator
    from compliance_reporter import ComplianceReporter

from log import get_logger

logger = get_logger(__name__)

control_plane_metrics = ApplicationMetrics(
    MonitoringConfig(
        app_name="control_plane",
        app_version="1.0",
        environment=getattr(_svc_config, "ENVIRONMENT", "production"),
    )
)

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
@track_metrics(control_plane_metrics, method="GET", endpoint="/health")
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        service="control-plane",
        version="1.0"
    )

@app.get("/services", response_model=Dict[str, Any])
@track_metrics(control_plane_metrics, method="GET", endpoint="/services")
async def get_services():
    """Get all managed services status"""
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
        "cluster_id": _svc_config.DEPLOYMENT_ID,
        "timestamp": os.getcwd()
    }

@app.post("/services/{service}/restart")
@track_metrics(control_plane_metrics, method="POST", endpoint="/services/{service}/restart")
async def restart_service(service: str):
    """Request service restart (orchestrated by docker-compose)"""
    logger.info(f"Restart request for service: {service}")
    return {"service": service, "action": "restart_requested"}

@app.get("/metrics")
@track_metrics(control_plane_metrics, method="GET", endpoint="/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(
        content=control_plane_metrics.get_metrics(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=_svc_config.HOST,
        port=_svc_config.PORT,
        log_level=_svc_config.LOG_LEVEL.lower(),
    )
