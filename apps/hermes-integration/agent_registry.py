"""
@file apps/hermes-integration/agent_registry.py
@description Hermes Agent Registry — tracks registered agents, liveness, and execution state.
             Provides the central directory for all code-server agent instances.
@governance GOV-002: Deterministic, audited agent lifecycle management
"""

import asyncio
import time
import uuid
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Any

import httpx

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)


class AgentStatus(str, Enum):
    """Agent lifecycle status."""
    REGISTERING = "registering"   # Agent starting up, not yet ready
    HEALTHY     = "healthy"       # Agent running and passing health checks
    DEGRADED    = "degraded"      # Agent reachable but deps unhealthy
    UNREACHABLE = "unreachable"   # No response from agent health check
    DRAINING    = "draining"      # Agent shutting down gracefully
    OFFLINE     = "offline"       # Agent confirmed down


class AgentRecord:
    """Tracks a single agent instance."""

    __slots__ = (
        "agent_id", "agent_type", "host", "port",
        "status", "registered_at", "last_seen_at",
        "last_health_check", "metadata",
    )

    def __init__(
        self,
        agent_id: str,
        agent_type: str,
        host: str,
        port: int,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.agent_id = agent_id
        self.agent_type = agent_type
        self.host = host
        self.port = port
        self.status = AgentStatus.REGISTERING
        self.registered_at = datetime.utcnow()
        self.last_seen_at: Optional[datetime] = None
        self.last_health_check: Optional[datetime] = None
        self.metadata: Dict[str, Any] = metadata or {}

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    @property
    def health_url(self) -> str:
        return f"{self.base_url}/health"

    @property
    def readiness_url(self) -> str:
        return f"{self.base_url}/health/ready"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "agent_type": self.agent_type,
            "host": self.host,
            "port": self.port,
            "status": self.status.value,
            "registered_at": self.registered_at.isoformat(),
            "last_seen_at": self.last_seen_at.isoformat() if self.last_seen_at else None,
            "last_health_check": self.last_health_check.isoformat() if self.last_health_check else None,
            "metadata": self.metadata,
        }


class AgentRegistry:
    """
    Central registry for all code-server agent instances.

    Thread-safe in-memory store.  For HA across replicas, replace
    ``_agents`` with a Redis-backed dict using the same interface.
    """

    # If an agent hasn't been seen in this many seconds, mark it unreachable
    STALE_THRESHOLD_SECONDS: int = 60

    def __init__(self) -> None:
        self._agents: Dict[str, AgentRecord] = {}

    # ── Registration ──────────────────────────────────────────────────────────

    def register(
        self,
        agent_type: str,
        host: str,
        port: int,
        agent_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> AgentRecord:
        """Register an agent and return its record."""
        aid = agent_id or f"{agent_type}-{uuid.uuid4().hex[:8]}"
        record = AgentRecord(aid, agent_type, host, port, metadata)
        self._agents[aid] = record
        logger.info("agent_registered", extra={"agent_id": aid, "agent_type": agent_type, "port": port})
        return record

    def deregister(self, agent_id: str) -> bool:
        """Remove agent from registry. Returns True if found."""
        record = self._agents.pop(agent_id, None)
        if record:
            logger.info("agent_deregistered", extra={"agent_id": agent_id})
        return record is not None

    # ── Liveness ──────────────────────────────────────────────────────────────

    def record_heartbeat(self, agent_id: str) -> bool:
        """Update last_seen_at for an agent. Returns True if agent found."""
        record = self._agents.get(agent_id)
        if not record:
            return False
        record.last_seen_at = datetime.utcnow()
        if record.status in (AgentStatus.UNREACHABLE, AgentStatus.REGISTERING):
            record.status = AgentStatus.HEALTHY
        return True

    async def probe_health(
        self,
        agent_id: str,
        timeout: float = 3.0,
    ) -> AgentStatus:
        """Perform an HTTP liveness probe against a registered agent."""
        record = self._agents.get(agent_id)
        if not record:
            return AgentStatus.OFFLINE

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.get(record.health_url)
            record.last_health_check = datetime.utcnow()
            record.last_seen_at = datetime.utcnow()
            if resp.status_code == 200:
                record.status = AgentStatus.HEALTHY
            else:
                record.status = AgentStatus.DEGRADED
        except Exception as exc:
            logger.warning(
                "agent_health_probe_failed",
                extra={"agent_id": agent_id, "error": str(exc)},
            )
            record.status = AgentStatus.UNREACHABLE

        return record.status

    async def probe_readiness(
        self,
        agent_id: str,
        timeout: float = 5.0,
    ) -> bool:
        """Check readiness probe (all deps healthy). Returns True if ready."""
        record = self._agents.get(agent_id)
        if not record:
            return False
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                resp = await client.get(record.readiness_url)
            return resp.status_code == 200
        except Exception:
            return False

    # ── Query ─────────────────────────────────────────────────────────────────

    def get(self, agent_id: str) -> Optional[AgentRecord]:
        return self._agents.get(agent_id)

    def list_all(self) -> List[AgentRecord]:
        return list(self._agents.values())

    def list_by_type(self, agent_type: str) -> List[AgentRecord]:
        return [r for r in self._agents.values() if r.agent_type == agent_type]

    def list_healthy(self) -> List[AgentRecord]:
        return [r for r in self._agents.values() if r.status == AgentStatus.HEALTHY]

    def count_by_status(self) -> Dict[str, int]:
        counts: Dict[str, int] = {s.value: 0 for s in AgentStatus}
        for record in self._agents.values():
            counts[record.status.value] += 1
        return counts

    def mark_stale_agents(self) -> List[str]:
        """Mark agents whose last heartbeat is older than STALE_THRESHOLD_SECONDS."""
        now = datetime.utcnow()
        stale: List[str] = []
        for record in self._agents.values():
            if record.last_seen_at is None:
                continue
            age = (now - record.last_seen_at).total_seconds()
            if age > self.STALE_THRESHOLD_SECONDS and record.status == AgentStatus.HEALTHY:
                record.status = AgentStatus.UNREACHABLE
                stale.append(record.agent_id)
                logger.warning(
                    "agent_marked_stale",
                    extra={"agent_id": record.agent_id, "stale_seconds": age},
                )
        return stale


# Singleton registry (process-scoped)
registry = AgentRegistry()
