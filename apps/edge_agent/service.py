#!/usr/bin/env python3
# @file apps/edge_agent/service.py
# @module infrastructure/edge-agent
# @description Edge agent registry, heartbeat tracking, routing, and replication planning
# @governance GOV-002: Deterministic edge routing and state replication logic

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Dict, List, Optional

from pydantic import BaseModel, Field


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class AgentHealth(str, Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"


class EdgeAgentCapabilities(BaseModel):
    supported_services: List[str] = Field(default_factory=list)
    cache_capacity_gb: float = Field(default=0.0, ge=0.0)
    max_sessions: int = Field(default=1, ge=1)
    replication_roles: List[str] = Field(default_factory=lambda: ["workspace-hot-state"])


class EdgeAgentCacheState(BaseModel):
    warm_workspaces: List[str] = Field(default_factory=list)
    asset_keys: List[str] = Field(default_factory=list)
    cache_hit_rate: float = Field(default=0.0, ge=0.0, le=1.0)


class EdgeAgentRuntimeState(BaseModel):
    cpu_utilization: float = Field(default=0.0, ge=0.0, le=1.0)
    memory_utilization: float = Field(default=0.0, ge=0.0, le=1.0)
    active_sessions: int = Field(default=0, ge=0)
    available_disk_gb: float = Field(default=0.0, ge=0.0)
    median_latency_ms: int = Field(default=25, ge=0)
    health: AgentHealth = AgentHealth.HEALTHY


class EdgeAgentRegistrationRequest(BaseModel):
    agent_id: str
    region: str
    country_code: str
    city: Optional[str] = None
    endpoint_url: str
    capabilities: EdgeAgentCapabilities
    cache_state: EdgeAgentCacheState = Field(default_factory=EdgeAgentCacheState)
    metadata: Dict[str, str] = Field(default_factory=dict)


class EdgeAgentHeartbeatRequest(BaseModel):
    agent_id: str
    runtime: EdgeAgentRuntimeState
    cache_state: EdgeAgentCacheState = Field(default_factory=EdgeAgentCacheState)
    observed_regions: List[str] = Field(default_factory=list)


class EdgeAgentRecord(BaseModel):
    agent_id: str
    region: str
    country_code: str
    city: Optional[str] = None
    endpoint_url: str
    capabilities: EdgeAgentCapabilities
    runtime: EdgeAgentRuntimeState = Field(default_factory=EdgeAgentRuntimeState)
    cache_state: EdgeAgentCacheState = Field(default_factory=EdgeAgentCacheState)
    metadata: Dict[str, str] = Field(default_factory=dict)
    first_seen_at: datetime
    last_heartbeat_at: datetime


class RoutingRequest(BaseModel):
    user_region: str
    workspace_id: Optional[str] = None
    asset_keys: List[str] = Field(default_factory=list)
    required_service: Optional[str] = None


class RoutingDecision(BaseModel):
    agent_id: str
    region: str
    endpoint_url: str
    score: float
    cache_warm: bool
    fallback_agents: List[str] = Field(default_factory=list)
    reason: str


class ReplicationPlanRequest(BaseModel):
    workspace_id: str
    preferred_regions: List[str] = Field(default_factory=list)
    asset_keys: List[str] = Field(default_factory=list)
    desired_replica_count: int = Field(default=2, ge=1, le=5)


class ReplicationAction(BaseModel):
    source_agent_id: str
    target_agent_id: str
    target_region: str
    assets_to_sync: List[str] = Field(default_factory=list)
    reason: str


class ReplicationPlanResponse(BaseModel):
    workspace_id: str
    strategy: str
    actions: List[ReplicationAction] = Field(default_factory=list)
    missing_regions: List[str] = Field(default_factory=list)


class EdgeAgentRegistryService:
    def __init__(self, heartbeat_ttl_seconds: int = 90):
        self.heartbeat_ttl_seconds = heartbeat_ttl_seconds
        self._agents: Dict[str, EdgeAgentRecord] = {}

    def reset(self) -> None:
        self._agents.clear()

    def register_agent(
        self,
        request: EdgeAgentRegistrationRequest,
        now: Optional[datetime] = None,
    ) -> EdgeAgentRecord:
        now = now or utcnow()
        existing = self._agents.get(request.agent_id)
        record = EdgeAgentRecord(
            agent_id=request.agent_id,
            region=request.region,
            country_code=request.country_code,
            city=request.city,
            endpoint_url=request.endpoint_url,
            capabilities=request.capabilities,
            runtime=existing.runtime if existing else EdgeAgentRuntimeState(),
            cache_state=request.cache_state,
            metadata=request.metadata,
            first_seen_at=existing.first_seen_at if existing else now,
            last_heartbeat_at=now,
        )
        self._agents[request.agent_id] = record
        return record

    def record_heartbeat(
        self,
        request: EdgeAgentHeartbeatRequest,
        now: Optional[datetime] = None,
    ) -> EdgeAgentRecord:
        now = now or utcnow()
        record = self._agents.get(request.agent_id)
        if record is None:
            raise KeyError(f"edge agent '{request.agent_id}' is not registered")

        updated = record.model_copy(
            update={
                "runtime": request.runtime,
                "cache_state": request.cache_state,
                "last_heartbeat_at": now,
                "metadata": {
                    **record.metadata,
                    "observed_regions": ",".join(request.observed_regions),
                },
            }
        )
        self._agents[request.agent_id] = updated
        return updated

    def list_agents(
        self,
        include_stale: bool = False,
        now: Optional[datetime] = None,
    ) -> List[EdgeAgentRecord]:
        now = now or utcnow()
        agents = list(self._agents.values())
        if include_stale:
            return sorted(agents, key=lambda agent: agent.agent_id)
        return sorted(
            [agent for agent in agents if not self.is_stale(agent, now)],
            key=lambda agent: agent.agent_id,
        )

    def get_agent(self, agent_id: str) -> EdgeAgentRecord:
        record = self._agents.get(agent_id)
        if record is None:
            raise KeyError(f"edge agent '{agent_id}' is not registered")
        return record

    def is_stale(self, agent: EdgeAgentRecord, now: Optional[datetime] = None) -> bool:
        now = now or utcnow()
        return (now - agent.last_heartbeat_at).total_seconds() > self.heartbeat_ttl_seconds

    def resolve_routing(
        self,
        request: RoutingRequest,
        now: Optional[datetime] = None,
    ) -> RoutingDecision:
        now = now or utcnow()
        ranked = self._rank_agents(request, now)
        if not ranked:
            raise ValueError("no healthy edge agents available for routing")

        selected_score, selected = ranked[0]
        fallback_agents = [agent.agent_id for _, agent in ranked[1:4]]
        cache_warm = self._has_warm_cache(selected, request)
        reason_parts = []
        if selected.region == request.user_region:
            reason_parts.append("exact region match")
        elif self._region_group(selected.region) == self._region_group(request.user_region):
            reason_parts.append("same geographic affinity group")
        if cache_warm:
            reason_parts.append("warm workspace cache")
        if not reason_parts:
            reason_parts.append("best available capacity")

        return RoutingDecision(
            agent_id=selected.agent_id,
            region=selected.region,
            endpoint_url=selected.endpoint_url,
            score=selected_score,
            cache_warm=cache_warm,
            fallback_agents=fallback_agents,
            reason=", ".join(reason_parts),
        )

    def build_replication_plan(
        self,
        request: ReplicationPlanRequest,
        now: Optional[datetime] = None,
    ) -> ReplicationPlanResponse:
        now = now or utcnow()
        healthy_agents = self._eligible_agents(now)
        if not healthy_agents:
            raise ValueError("no healthy edge agents available for replication planning")

        sources = [
            agent
            for agent in healthy_agents
            if request.workspace_id in agent.cache_state.warm_workspaces
        ]
        if sources:
            source = sorted(sources, key=self._source_rank, reverse=True)[0]
            strategy = "fanout-from-edge-cache"
        else:
            source = sorted(healthy_agents, key=self._source_rank, reverse=True)[0]
            strategy = "seed-from-primary-state"

        candidates = [agent for agent in healthy_agents if agent.agent_id != source.agent_id]
        ranked_targets = sorted(
            candidates,
            key=lambda agent: self._target_rank(agent, request.preferred_regions),
            reverse=True,
        )

        actions: List[ReplicationAction] = []
        missing_regions = list(request.preferred_regions)
        for agent in ranked_targets:
            if len(actions) >= request.desired_replica_count:
                break
            if request.workspace_id in agent.cache_state.warm_workspaces:
                if agent.region in missing_regions:
                    missing_regions.remove(agent.region)
                continue
            actions.append(
                ReplicationAction(
                    source_agent_id=source.agent_id,
                    target_agent_id=agent.agent_id,
                    target_region=agent.region,
                    assets_to_sync=request.asset_keys,
                    reason=self._replication_reason(agent, request.preferred_regions),
                )
            )
            if agent.region in missing_regions:
                missing_regions.remove(agent.region)

        return ReplicationPlanResponse(
            workspace_id=request.workspace_id,
            strategy=strategy,
            actions=actions,
            missing_regions=missing_regions,
        )

    def _eligible_agents(self, now: datetime) -> List[EdgeAgentRecord]:
        return [
            agent
            for agent in self._agents.values()
            if not self.is_stale(agent, now) and agent.runtime.health != AgentHealth.UNHEALTHY
        ]

    def _rank_agents(
        self,
        request: RoutingRequest,
        now: datetime,
    ) -> List[tuple[float, EdgeAgentRecord]]:
        ranked: List[tuple[float, EdgeAgentRecord]] = []
        for agent in self._eligible_agents(now):
            if request.required_service and agent.capabilities.supported_services:
                if request.required_service not in agent.capabilities.supported_services:
                    continue
            score = self._score_agent(agent, request)
            ranked.append((score, agent))
        ranked.sort(key=lambda item: item[0], reverse=True)
        return ranked

    def _score_agent(self, agent: EdgeAgentRecord, request: RoutingRequest) -> float:
        score = 0.0
        if agent.region == request.user_region:
            score += 60.0
        elif self._region_group(agent.region) == self._region_group(request.user_region):
            score += 25.0

        if request.workspace_id and request.workspace_id in agent.cache_state.warm_workspaces:
            score += 25.0

        asset_matches = len(set(request.asset_keys).intersection(agent.cache_state.asset_keys))
        score += min(asset_matches, 5) * 4.0

        score += (1.0 - agent.runtime.cpu_utilization) * 15.0
        score += (1.0 - agent.runtime.memory_utilization) * 10.0
        score += self._session_headroom(agent) * 15.0
        score += max(0.0, 20.0 - (agent.runtime.median_latency_ms / 10.0))

        if agent.runtime.health == AgentHealth.DEGRADED:
            score -= 15.0
        return round(score, 2)

    def _source_rank(self, agent: EdgeAgentRecord) -> tuple[float, float, float]:
        return (
            agent.cache_state.cache_hit_rate,
            self._session_headroom(agent),
            1.0 - agent.runtime.cpu_utilization,
        )

    def _target_rank(self, agent: EdgeAgentRecord, preferred_regions: List[str]) -> tuple[int, float, float]:
        preferred_score = 1 if agent.region in preferred_regions else 0
        return (
            preferred_score,
            self._session_headroom(agent),
            1.0 - agent.runtime.memory_utilization,
        )

    def _replication_reason(self, agent: EdgeAgentRecord, preferred_regions: List[str]) -> str:
        if agent.region in preferred_regions:
            return "preferred region requested for hot workspace replication"
        return "healthy fallback region with available capacity"

    def _has_warm_cache(self, agent: EdgeAgentRecord, request: RoutingRequest) -> bool:
        if request.workspace_id and request.workspace_id in agent.cache_state.warm_workspaces:
            return True
        return any(asset_key in agent.cache_state.asset_keys for asset_key in request.asset_keys)

    def _session_headroom(self, agent: EdgeAgentRecord) -> float:
        max_sessions = max(agent.capabilities.max_sessions, 1)
        return max(0.0, 1.0 - (agent.runtime.active_sessions / max_sessions))

    def _region_group(self, region: str) -> str:
        return region.split("-", 1)[0]
