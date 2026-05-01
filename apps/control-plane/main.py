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
from apps.shared.tracing import TracingConfig, instrument_app, setup_tracing, trace_operation
from apps.shared.gcp_integration import get_gcp_integration, GCPService
from apps.shared.trace_enhancement import (
    initialize_trace_enhancement,
    setup_request_sampling,
    get_outbound_trace_headers,
    end_request_trace,
)
from apps.shared.trace_patterns import TraceSamplingConfig, SamplingStrategy

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

control_plane_tracing = setup_tracing(
    TracingConfig(
        service_name="control-plane",
        app_version="1.0",
        environment=getattr(_svc_config, "ENVIRONMENT", "production"),
        enabled=os.getenv("OTEL_ENABLED", "true").lower() != "false",
        otlp_endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", ""),
    )
)

app = FastAPI(
    title="Control Plane",
    description="Service orchestration and control",
    version="1.0"
)

# Initialize advanced tracing with sampling
sampling_config = TraceSamplingConfig(
    strategy=SamplingStrategy.UNIFORM,
    sample_rate=float(os.environ.get("TRACE_SAMPLE_RATE", "0.1")),
    exclude_paths=["/health", "/metrics"],
    always_sample_paths=["/gcp/", "/services/"],
)
initialize_trace_enhancement(sampling_config)

instrument_app(app, control_plane_tracing)

# ── Advanced Tracing Middleware ───────────────────────────────────────────────
# Middleware for request-level trace sampling and context management
@app.middleware("http")
async def advanced_tracing_middleware(request, call_next):
    """Middleware for advanced tracing with sampling and context propagation."""
    # Setup sampling for request
    should_trace = setup_request_sampling(
        path=request.url.path,
        headers=dict(request.headers),
    )
    
    try:
        # Call endpoint
        response = await call_next(request)
        
        # Add trace headers to response if traced
        if should_trace:
            trace_headers = get_outbound_trace_headers()
            for key, value in trace_headers.items():
                response.headers[key] = value
        
        return response
    finally:
        # End trace
        end_request_trace()

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
@trace_operation(control_plane_tracing, "control-plane.health_check")
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        service="control-plane",
        version="1.0"
    )

@app.get("/services", response_model=Dict[str, Any])
@track_metrics(control_plane_metrics, method="GET", endpoint="/services")
@trace_operation(control_plane_tracing, "control-plane.get_services")
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
@trace_operation(control_plane_tracing, "control-plane.restart_service")
async def restart_service(service: str):
    """Request service restart (orchestrated by docker-compose)"""
    logger.info(f"Restart request for service: {service}")
    return {"service": service, "action": "restart_requested"}

@app.get("/metrics")
@track_metrics(control_plane_metrics, method="GET", endpoint="/metrics")
@trace_operation(control_plane_tracing, "control-plane.metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(
        content=control_plane_metrics.get_metrics(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )

@app.get("/slos", response_model=Dict[str, Any])
@track_metrics(control_plane_metrics, method="GET", endpoint="/slos")
async def get_slos():
    """Get current SLO status and targets"""
    return control_plane_metrics.evaluate_slos()

@app.post("/alerts/webhook", response_model=Dict[str, Any])
async def receive_alert_webhook(body: Dict[str, Any]):
    """Receive Prometheus AlertManager webhook"""
    from apps.shared.alert_receiver import AlertReceiver
    
    receiver = AlertReceiver(slack_enabled=False, pagerduty_enabled=False)
    result = receiver.receive_webhook(body)
    
    logger.info(f"Alert webhook processed: {result}")
    return result


# ============================================================================
# GCP INTEGRATION (WITH DISTRIBUTED TRACING - PHASE 11)
# ============================================================================

@app.get("/gcp/storage/buckets")
@trace_operation(control_plane_tracing, "control-plane.gcp_list_buckets")
async def list_gcp_storage_buckets():
    """List GCP Cloud Storage buckets with distributed tracing."""
    gcp = get_gcp_integration()
    buckets = await gcp.list_storage_buckets()
    
    return {
        "status": "success",
        "bucket_count": len(buckets),
        "buckets": [b.to_dict() for b in buckets],
        "traces": gcp.get_all_traces(),
    }


@app.get("/gcp/storage/bucket/{bucket_name}")
@trace_operation(control_plane_tracing, "control-plane.gcp_get_bucket")
async def get_gcp_storage_bucket(bucket_name: str):
    """Get specific GCP Cloud Storage bucket with distributed tracing."""
    gcp = get_gcp_integration()
    bucket = await gcp.get_storage_bucket(bucket_name)
    
    if bucket:
        return {
            "status": "success",
            "bucket": bucket.to_dict(),
            "traces": gcp.get_all_traces(),
        }
    else:
        raise HTTPException(status_code=404, detail=f"Bucket not found: {bucket_name}")


@app.post("/gcp/bigquery/dataset")
@trace_operation(control_plane_tracing, "control-plane.gcp_create_dataset")
async def create_gcp_bigquery_dataset(
    dataset_id: str = Body(...),
    location: str = Body("US"),
    description: Optional[str] = Body(None),
):
    """Create GCP BigQuery dataset with distributed tracing."""
    gcp = get_gcp_integration()
    dataset = await gcp.create_bigquery_dataset(
        dataset_id=dataset_id,
        location=location,
        description=description,
    )
    
    if dataset:
        return {
            "status": "success",
            "dataset": dataset.to_dict(),
            "traces": gcp.get_all_traces(),
        }
    else:
        raise HTTPException(status_code=500, detail="Failed to create dataset")


@app.get("/gcp/bigquery/dataset/{dataset_id}")
@trace_operation(control_plane_tracing, "control-plane.gcp_get_dataset")
async def get_gcp_bigquery_dataset(dataset_id: str):
    """Get GCP BigQuery dataset information with distributed tracing."""
    gcp = get_gcp_integration()
    dataset = await gcp.get_bigquery_dataset(dataset_id)
    
    if dataset:
        return {
            "status": "success",
            "dataset": dataset.to_dict(),
            "traces": gcp.get_all_traces(),
        }
    else:
        raise HTTPException(status_code=404, detail=f"Dataset not found: {dataset_id}")


@app.post("/gcp/pubsub/publish")
@trace_operation(control_plane_tracing, "control-plane.gcp_publish_message")
async def publish_gcp_pubsub_message(
    topic_name: str = Body(...),
    message: str = Body(...),
    attributes: Optional[Dict[str, str]] = Body(None),
):
    """Publish message to GCP Pub/Sub topic with distributed tracing."""
    gcp = get_gcp_integration()
    success = await gcp.publish_message(
        topic_name=topic_name,
        message=message,
        attributes=attributes,
    )
    
    return {
        "status": "success" if success else "failed",
        "topic": topic_name,
        "traces": gcp.get_all_traces(),
    }


@app.post("/gcp/functions/invoke")
@trace_operation(control_plane_tracing, "control-plane.gcp_invoke_function")
async def invoke_gcp_function(
    function_name: str = Body(...),
    data: Dict[str, Any] = Body(...),
    region: str = Body("us-central1"),
):
    """Invoke GCP Cloud Function with distributed tracing."""
    gcp = get_gcp_integration()
    result = await gcp.invoke_function(
        function_name=function_name,
        data=data,
        region=region,
    )
    
    if result:
        return {
            "status": "success",
            "function": function_name,
            "result": result,
            "traces": gcp.get_all_traces(),
        }
    else:
        raise HTTPException(status_code=500, detail="Function invocation failed")


@app.get("/gcp/traces")
async def get_gcp_traces():
    """Get all recorded GCP API traces for observability."""
    gcp = get_gcp_integration()
    traces = gcp.get_all_traces()
    
    total_traces = sum(len(t) for t in traces.values())
    return {
        "total_traces": total_traces,
        "traces_by_service": traces,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=_svc_config.HOST,
        port=_svc_config.PORT,
        log_level=_svc_config.LOG_LEVEL.lower(),
    )
