#!/usr/bin/env python3
# @file apps/edge_agent/service.py
# @module infrastructure/edge-agent
# @description Edge agent registry, heartbeat tracking, routing, and replication planning
# @governance GOV-002: Deterministic edge routing and state replication logic

from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
from enum import Enum
from typing import Dict, List, Optional, Any

from prometheus_client import Counter, Gauge
from pydantic import BaseModel, Field
from kafka import KafkaProducer
from kafka.errors import KafkaError

# METRICS DEFINITION
AGENT_REGISTRATIONS = Counter("edge_agent_registrations_total", "Total registered edge agents", ["region"])
AGENT_HEARTBEATS = Counter("edge_agent_heartbeats_total", "Total edge agent heartbeats", ["agent_id"])
ACTIVE_AGENTS = Gauge("edge_agent_active_count", "Current number of active edge agents")
ROUTING_REQUESTS = Counter("edge_agent_routing_requests_total", "Total routing requests", ["region", "status"])
REPLICATION_JOBS = Counter("edge_agent_replication_jobs_total", "Total replication jobs", ["status"])
AGENT_CPU_USAGE = Gauge("edge_agent_cpu_utilization", "CPU utilization", ["agent_id"])
AGENT_MEM_USAGE = Gauge("edge_agent_memory_utilization", "Memory utilization", ["agent_id"])
AGENT_SESSIONS = Gauge("edge_agent_sessions_count", "Active session count", ["agent_id"])

class ServiceConfig(BaseModel):
    redis_url: str = "redis://redis:6379/0"
    kafka_bootstrap_servers: str = "kafka:9092"
    replication_topic: str = "edge.replication.events"


logger = logging.getLogger(__name__)


class ReplicationEvent(BaseModel):
    event_id: str
    timestamp: datetime
    type: str  # e.g., "replication_started", "replication_completed"
    data: Dict[str, Any]


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


class ReplicationJobStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"


class ReplicationJob(BaseModel):
    job_id: str
    workspace_id: str
    source_agent_id: str
    target_agent_id: str
    assets: List[str]
    status: ReplicationJobStatus = ReplicationJobStatus.PENDING
    started_at: datetime
    updated_at: datetime
    error_message: Optional[str] = None


class ReplicationPlanResponse(BaseModel):
    workspace_id: str
    strategy: str
    actions: List[ReplicationAction] = Field(default_factory=list)
    missing_regions: List[str] = Field(default_factory=list)


class EdgeAgentRegistryService:
    def __init__(self, config: Optional[ServiceConfig] = None, heartbeat_ttl_seconds: int = 90):
        self.config = config or ServiceConfig()
        self.heartbeat_ttl_seconds = heartbeat_ttl_seconds
        self._agents: Dict[str, EdgeAgentRecord] = {}
        self._replication_jobs: Dict[str, ReplicationJob] = {}
        self._event_log: List[ReplicationEvent] = []
        # Initialize Kafka producer for event replication
        try:
            self._kafka_producer = KafkaProducer(
                bootstrap_servers=self.config.kafka_bootstrap_servers.split(','),
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            logger.info(f"Kafka producer initialized: {self.config.kafka_bootstrap_servers}")
        except Exception as e:
            logger.warning(f"Failed to initialize Kafka producer: {e}. Events will be logged only.")
            self._kafka_producer = None

    def reset(self) -> None:
        self._agents.clear()
        self._replication_jobs.clear()
        self._event_log.clear()
        
        # Close Kafka producer gracefully
        if self._kafka_producer:
            try:
                self._kafka_producer.flush()
                self._kafka_producer.close()
                logger.info("Kafka producer closed")
            except Exception as e:
                logger.warning(f"Error closing Kafka producer: {e}")

    async def _broadcast_event(self, event_type: str, data: Dict[str, Any]) -> ReplicationEvent:
        event = ReplicationEvent(
            event_id=f"evt-{int(utcnow().timestamp())}-{event_type}",
            timestamp=utcnow(),
            type=event_type,
            data=data
        )
        self._event_log.append(event)
        
        # Send event to Kafka topic
        if self._kafka_producer:
            try:
                future = self._kafka_producer.send(
                    self.config.replication_topic,
                    value={
                        'event_id': event.event_id,
                        'timestamp': event.timestamp.isoformat(),
                        'type': event.type,
                        'data': event.data
                    }
                )
                # Wait for acknowledgment with timeout
                future.get(timeout=5)
                logger.info(f"Event published to Kafka: {event.event_id}")
            except KafkaError as e:
                logger.error(f"Failed to publish event to Kafka: {e}")
            except Exception as e:
                logger.error(f"Unexpected error publishing event: {e}")
        else:
            logger.info(f"Kafka producer unavailable. Event logged locally: {event.model_dump_json()}")
        
        logger.info(f"Broadcasted event: {event.model_dump_json()}")
        return event

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

        # METRICS
        AGENT_REGISTRATIONS.labels(region=request.region).inc()
        ACTIVE_AGENTS.set(len(self.list_agents(include_stale=False)))
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
          
        # METRICS
        AGENT_HEARTBEATS.labels(agent_id=request.agent_id).inc()
        AGENT_CPU_USAGE.labels(agent_id=request.agent_id).set(request.runtime.cpu_utilization)
        AGENT_MEM_USAGE.labels(agent_id=request.agent_id).set(request.runtime.memory_utilization)
        AGENT_SESSIONS.labels(agent_id=request.agent_id).set(request.runtime.active_sessions)
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
        
        # METRICS
        ROUTING_REQUESTS.labels(region=request.user_region, status="success").inc()
        
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

    async def create_replication_job(
        self,
        workspace_id: str,
        source_agent_id: str,
        target_agent_id: str,
        assets: List[str],
        now: Optional[datetime] = None,
    ) -> ReplicationJob:
        now = now or utcnow()
        job_id = f"repl-{workspace_id}-{target_agent_id}-{int(now.timestamp())}"
        job = ReplicationJob(
            job_id=job_id,
            workspace_id=workspace_id,
            source_agent_id=source_agent_id,
            target_agent_id=target_agent_id,
            assets=assets,
            started_at=now,
            updated_at=now,
        )
        self._replication_jobs[job_id] = job
        
        # METRICS
        REPLICATION_JOBS.labels(status="created").inc()

        await self._broadcast_event(
            "replication_started",
            {
                "job_id": job.job_id,
                "workspace_id": job.workspace_id,
                "source": job.source_agent_id,
                "target": job.target_agent_id,
            }
        )
        return job

    async def update_replication_status(
        self,
        job_id: str,
        status: ReplicationJobStatus,
        error_message: Optional[str] = None,
        now: Optional[datetime] = None,
    ) -> ReplicationJob:
        now = now or utcnow()
        job = self._replication_jobs.get(job_id)
        if not job:
            raise KeyError(f"replication job '{job_id}' not found")

        updated = job.model_copy(
            update={
                "status": status,
                "error_message": error_message,
                "updated_at": now,
            }
        )
        self._replication_jobs[job_id] = updated
        
        # METRICS
        if status == ReplicationJobStatus.COMPLETED:
            REPLICATION_JOBS.labels(status="completed").inc()
        elif status == ReplicationJobStatus.FAILED:
            REPLICATION_JOBS.labels(status="failed").inc()

        await self._broadcast_event(
            "replication_status_changed",
            {
                "job_id": job.job_id,
                "status": status,
                "error": error_message
            }
        )
        return updated

    def get_replication_job(self, job_id: str) -> ReplicationJob:
        job = self._replication_jobs.get(job_id)
        if not job:
            raise KeyError(f"replication job '{job_id}' not found")
        return job

    def list_replication_jobs(
        self,
        workspace_id: Optional[str] = None,
        target_agent_id: Optional[str] = None,
    ) -> List[ReplicationJob]:
        jobs = list(self._replication_jobs.values())
        if workspace_id:
            jobs = [j for j in jobs if j.workspace_id == workspace_id]
        if target_agent_id:
            jobs = [j for j in jobs if j.target_agent_id == target_agent_id]
        return sorted(jobs, key=lambda j: j.started_at, reverse=True)
