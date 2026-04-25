#!/usr/bin/env python3
# @file apps/edge_agent/main.py
# @module infrastructure/edge-agent
# @description FastAPI control plane for edge agent registration, routing, and replication
# @governance GOV-002: Edge control-plane APIs must remain auditable and deterministic

from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, HTTPException

from service import (
    EdgeAgentHeartbeatRequest,
    EdgeAgentRecord,
    EdgeAgentRegistrationRequest,
    EdgeAgentRegistryService,
    ReplicationEvent,
    ReplicationJob,
    ReplicationJobStatus,
    ReplicationPlanRequest,
    ReplicationPlanResponse,
    RoutingDecision,
    RoutingRequest,
)


app = FastAPI(
    title="Edge Agent Control Plane",
    description="Registration, heartbeat, routing, and replication planning for edge agents",
    version="1.0.0",
)
registry_service = EdgeAgentRegistryService()


@app.get("/health")
async def health() -> dict:
    return {
        "status": "healthy",
        "service": "edge-agent",
        "registered_agents": len(registry_service.list_agents(include_stale=True)),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/edge-agents/register", response_model=EdgeAgentRecord)
async def register_edge_agent(request: EdgeAgentRegistrationRequest) -> EdgeAgentRecord:
    return registry_service.register_agent(request)


@app.post("/edge-agents/heartbeat", response_model=EdgeAgentRecord)
async def edge_agent_heartbeat(request: EdgeAgentHeartbeatRequest) -> EdgeAgentRecord:
    try:
        return registry_service.record_heartbeat(request)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get("/edge-agents", response_model=list[EdgeAgentRecord])
async def list_edge_agents(include_stale: bool = False) -> list[EdgeAgentRecord]:
    return registry_service.list_agents(include_stale=include_stale)


@app.get("/edge-agents/{agent_id}", response_model=EdgeAgentRecord)
async def get_edge_agent(agent_id: str) -> EdgeAgentRecord:
    try:
        return registry_service.get_agent(agent_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.post("/routing/resolve", response_model=RoutingDecision)
async def resolve_routing(request: RoutingRequest) -> RoutingDecision:
    try:
        return registry_service.resolve_routing(request)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/replication/plan", response_model=ReplicationPlanResponse)
async def plan_replication(request: ReplicationPlanRequest) -> ReplicationPlanResponse:
    try:
        return registry_service.build_replication_plan(request)
    except ValueError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/replication/jobs", response_model=list[ReplicationJob])
async def list_replication_jobs(
    workspace_id: Optional[str] = None, agent_id: Optional[str] = None
) -> list[ReplicationJob]:
    return registry_service.list_replication_jobs(
        workspace_id=workspace_id, target_agent_id=agent_id
    )


@app.get("/replication/jobs/{job_id}", response_model=ReplicationJob)
async def get_replication_job(job_id: str) -> ReplicationJob:
    try:
        return registry_service.get_replication_job(job_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.patch("/replication/jobs/{job_id}", response_model=ReplicationJob)
async def update_replication_job(
    job_id: str, status: ReplicationJobStatus, error_message: Optional[str] = None
) -> ReplicationJob:
    try:
        return await registry_service.update_replication_status(
            job_id, status, error_message=error_message
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get("/events", response_model=list[ReplicationEvent])
async def list_events() -> list[ReplicationEvent]:
    return registry_service._event_log


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8060)
