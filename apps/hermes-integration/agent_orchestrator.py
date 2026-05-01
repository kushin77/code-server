"""
@file apps/hermes-integration/agent_orchestrator.py
@description Hermes Agent Orchestrator — coordinates execution across registered agents.
             Routes requests to the optimal healthy agent, handles retries,
             and emits structured audit events for every dispatch.
@governance GOV-002: Deterministic, audited, capability-scoped execution
"""

import asyncio
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

import httpx

from agent_registry import AgentRegistry, AgentRecord, AgentStatus, registry
from apps._shared.python.logging import get_logger

logger = get_logger(__name__)


class DispatchResult:
    """Outcome of a single agent dispatch attempt."""

    __slots__ = (
        "dispatch_id", "agent_id", "agent_type",
        "success", "status_code", "response_body",
        "error", "duration_ms", "dispatched_at",
    )

    def __init__(
        self,
        dispatch_id: str,
        agent_id: str,
        agent_type: str,
        success: bool,
        status_code: Optional[int] = None,
        response_body: Optional[Dict[str, Any]] = None,
        error: Optional[str] = None,
        duration_ms: float = 0.0,
    ) -> None:
        self.dispatch_id   = dispatch_id
        self.agent_id      = agent_id
        self.agent_type    = agent_type
        self.success       = success
        self.status_code   = status_code
        self.response_body = response_body or {}
        self.error         = error
        self.duration_ms   = duration_ms
        self.dispatched_at = datetime.utcnow()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "dispatch_id":   self.dispatch_id,
            "agent_id":      self.agent_id,
            "agent_type":    self.agent_type,
            "success":       self.success,
            "status_code":   self.status_code,
            "response_body": self.response_body,
            "error":         self.error,
            "duration_ms":   round(self.duration_ms, 2),
            "dispatched_at": self.dispatched_at.isoformat(),
        }


class AgentOrchestrator:
    """
    Routes execution requests to the best available registered agent.

    Selection strategy:
      1. Filter by agent_type.
      2. Prefer HEALTHY over DEGRADED agents.
      3. Round-robin among equally-ranked candidates (simple counter).
    """

    # Maximum retries before giving up on a dispatch
    MAX_RETRIES: int = 2
    # Per-request timeout in seconds
    REQUEST_TIMEOUT: float = 30.0

    def __init__(self, reg: AgentRegistry) -> None:
        self._registry = reg
        self._rr_counters: Dict[str, int] = {}   # per agent_type round-robin index
        self._audit_log: List[Dict[str, Any]] = []  # last 500 events

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _select_agent(self, agent_type: str) -> Optional[AgentRecord]:
        """Pick a healthy agent of the requested type (round-robin)."""
        candidates = [
            r for r in self._registry.list_by_type(agent_type)
            if r.status in (AgentStatus.HEALTHY, AgentStatus.DEGRADED)
        ]
        # Prefer HEALTHY
        healthy = [c for c in candidates if c.status == AgentStatus.HEALTHY]
        pool = healthy if healthy else candidates

        if not pool:
            return None

        idx = self._rr_counters.get(agent_type, 0) % len(pool)
        self._rr_counters[agent_type] = idx + 1
        return pool[idx]

    def _record_audit(self, result: DispatchResult, request_payload: Dict[str, Any]) -> None:
        """Store dispatch audit entry (capped ring buffer)."""
        entry = result.to_dict()
        entry["payload_summary"] = {k: str(v)[:100] for k, v in request_payload.items()}
        self._audit_log.append(entry)
        del self._audit_log[:-500]

    # ── Public API ────────────────────────────────────────────────────────────

    async def dispatch(
        self,
        agent_type: str,
        path: str,
        payload: Dict[str, Any],
        method: str = "POST",
        retries: int = 0,
    ) -> DispatchResult:
        """
        Dispatch an HTTP request to the best available agent of agent_type.

        Args:
            agent_type: Target agent class (e.g. "code-reviewer").
            path:       Endpoint path on the agent service (e.g. "/execute").
            payload:    JSON body to send.
            method:     HTTP method (default POST).
            retries:    How many times this has already been retried (internal).

        Returns:
            DispatchResult with success/failure details.
        """
        dispatch_id = f"dispatch-{uuid.uuid4().hex[:12]}"
        record = self._select_agent(agent_type)

        if record is None:
            logger.warning(
                "no_available_agent",
                extra={"agent_type": agent_type, "dispatch_id": dispatch_id},
            )
            result = DispatchResult(
                dispatch_id=dispatch_id,
                agent_id="none",
                agent_type=agent_type,
                success=False,
                error=f"No healthy agents available for type '{agent_type}'",
            )
            self._record_audit(result, payload)
            return result

        url = f"{record.base_url}{path}"
        t0 = asyncio.get_event_loop().time()

        try:
            async with httpx.AsyncClient(timeout=self.REQUEST_TIMEOUT) as client:
                if method.upper() == "POST":
                    resp = await client.post(url, json=payload)
                elif method.upper() == "GET":
                    resp = await client.get(url, params=payload)
                else:
                    resp = await client.request(method, url, json=payload)

            duration_ms = (asyncio.get_event_loop().time() - t0) * 1000
            success = resp.status_code < 400

            # Update liveness on successful contact
            self._registry.record_heartbeat(record.agent_id)

            result = DispatchResult(
                dispatch_id=dispatch_id,
                agent_id=record.agent_id,
                agent_type=agent_type,
                success=success,
                status_code=resp.status_code,
                response_body=resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {},
                duration_ms=duration_ms,
            )

            logger.info(
                "agent_dispatch_complete",
                extra={
                    "dispatch_id": dispatch_id,
                    "agent_id":    record.agent_id,
                    "status_code": resp.status_code,
                    "duration_ms": round(duration_ms, 1),
                },
            )

        except Exception as exc:
            duration_ms = (asyncio.get_event_loop().time() - t0) * 1000

            logger.error(
                "agent_dispatch_error",
                extra={
                    "dispatch_id": dispatch_id,
                    "agent_id":    record.agent_id,
                    "error":       str(exc),
                },
            )

            # Retry on network errors
            if retries < self.MAX_RETRIES:
                logger.info(
                    "agent_dispatch_retry",
                    extra={"dispatch_id": dispatch_id, "retry": retries + 1},
                )
                return await self.dispatch(agent_type, path, payload, method, retries + 1)

            result = DispatchResult(
                dispatch_id=dispatch_id,
                agent_id=record.agent_id,
                agent_type=agent_type,
                success=False,
                error=str(exc),
                duration_ms=duration_ms,
            )

        self._record_audit(result, payload)
        return result

    async def broadcast(
        self,
        path: str,
        payload: Dict[str, Any],
        agent_types: Optional[List[str]] = None,
    ) -> List[DispatchResult]:
        """
        Fan-out a request to all (or selected) agent types in parallel.

        Useful for broadcasting configuration refreshes or shutdown signals.
        """
        types = agent_types or list({r.agent_type for r in self._registry.list_all()})
        tasks = [self.dispatch(t, path, payload) for t in types]
        return list(await asyncio.gather(*tasks, return_exceptions=False))

    async def health_sweep(self) -> Dict[str, AgentStatus]:
        """Probe every registered agent and return updated statuses."""
        tasks = {aid: self._registry.probe_health(aid) for aid in
                 [r.agent_id for r in self._registry.list_all()]}
        results = await asyncio.gather(*tasks.values(), return_exceptions=True)
        return {aid: (status if isinstance(status, AgentStatus) else AgentStatus.UNREACHABLE)
                for aid, status in zip(tasks.keys(), results)}

    def get_audit_log(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Return recent dispatch audit entries."""
        return self._audit_log[-limit:]


# Singleton orchestrator (backed by singleton registry)
orchestrator = AgentOrchestrator(registry)
