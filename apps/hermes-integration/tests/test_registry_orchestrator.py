"""
@file apps/hermes-integration/tests/test_registry_orchestrator.py
@description Unit tests for AgentRegistry and AgentOrchestrator
@coverage agent_registry.py, agent_orchestrator.py
"""

import asyncio
import sys
import uuid
from datetime import datetime, timedelta
from typing import Any, Dict
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Ensure the hermes-integration module is importable
sys.path.insert(0, '.')


# ============================================================================
# 1. AgentRecord
# ============================================================================

class TestAgentRecord:
    """Tests for the AgentRecord data class."""

    def _make_record(self, agent_type="code-reviewer", host="localhost", port=9000):
        from agent_registry import AgentRecord, AgentStatus
        r = AgentRecord("test-id", agent_type, host, port)
        return r, AgentStatus

    def test_base_url_construction(self):
        record, _ = self._make_record(host="myhost", port=1234)
        assert record.base_url == "http://myhost:1234"

    def test_health_url(self):
        record, _ = self._make_record()
        assert record.health_url.endswith("/health")

    def test_readiness_url(self):
        record, _ = self._make_record()
        assert record.readiness_url.endswith("/health/ready")

    def test_initial_status_is_registering(self):
        record, AgentStatus = self._make_record()
        assert record.status == AgentStatus.REGISTERING

    def test_to_dict_contains_required_keys(self):
        record, _ = self._make_record()
        d = record.to_dict()
        for key in ("agent_id", "agent_type", "host", "port", "status", "registered_at"):
            assert key in d


# ============================================================================
# 2. AgentRegistry
# ============================================================================

class TestAgentRegistry:
    """Tests for the in-memory AgentRegistry."""

    def setup_method(self):
        from agent_registry import AgentRegistry
        self.registry = AgentRegistry()

    def test_register_creates_record(self):
        record = self.registry.register("code-reviewer", "host1", 9000)
        assert record.agent_type == "code-reviewer"
        assert record.host == "host1"
        assert record.port == 9000

    def test_register_auto_generates_agent_id(self):
        r1 = self.registry.register("code-reviewer", "h1", 9000)
        r2 = self.registry.register("code-reviewer", "h2", 9001)
        assert r1.agent_id != r2.agent_id

    def test_register_accepts_explicit_agent_id(self):
        record = self.registry.register("doc-writer", "h", 9000, agent_id="my-id")
        assert record.agent_id == "my-id"

    def test_deregister_removes_agent(self):
        record = self.registry.register("doc-writer", "h", 9000)
        result = self.registry.deregister(record.agent_id)
        assert result is True
        assert self.registry.get(record.agent_id) is None

    def test_deregister_returns_false_for_unknown_id(self):
        assert self.registry.deregister("no-such-agent") is False

    def test_get_returns_none_for_missing_agent(self):
        assert self.registry.get("not-here") is None

    def test_get_by_type_returns_matching_agents(self):
        self.registry.register("code-reviewer", "h1", 9001)
        self.registry.register("code-reviewer", "h2", 9002)
        self.registry.register("doc-writer", "h3", 9003)
        reviewers = self.registry.get_by_type("code-reviewer")
        assert len(reviewers) == 2
        assert all(r.agent_type == "code-reviewer" for r in reviewers)

    def test_update_status_changes_agent_status(self):
        from agent_registry import AgentStatus
        record = self.registry.register("incident-responder", "h", 9000)
        self.registry.update_status(record.agent_id, AgentStatus.HEALTHY)
        updated = self.registry.get(record.agent_id)
        assert updated.status == AgentStatus.HEALTHY

    def test_update_status_noop_for_unknown_id(self):
        from agent_registry import AgentStatus
        # Should not raise
        self.registry.update_status("nonexistent", AgentStatus.HEALTHY)

    def test_mark_stale_agents_sets_unreachable(self):
        from agent_registry import AgentStatus
        record = self.registry.register("test-generator", "h", 9000)
        # Simulate last_seen_at long ago
        record.last_seen_at = datetime.utcnow() - timedelta(seconds=120)
        record.status = AgentStatus.HEALTHY
        self.registry.mark_stale_agents()
        assert record.status == AgentStatus.UNREACHABLE

    def test_all_agents_returns_all_records(self):
        self.registry.register("code-reviewer", "h1", 9001)
        self.registry.register("doc-writer", "h2", 9002)
        all_agents = self.registry.all_agents()
        assert len(all_agents) == 2

    def test_healthy_agents_returns_only_healthy(self):
        from agent_registry import AgentStatus
        r1 = self.registry.register("code-reviewer", "h1", 9001)
        r2 = self.registry.register("code-reviewer", "h2", 9002)
        self.registry.update_status(r1.agent_id, AgentStatus.HEALTHY)
        # r2 stays REGISTERING
        healthy = self.registry.healthy_agents()
        assert len(healthy) == 1
        assert healthy[0].agent_id == r1.agent_id


# ============================================================================
# 3. DispatchResult
# ============================================================================

class TestDispatchResult:
    """Tests for DispatchResult value object."""

    def test_success_dispatch_result(self):
        from agent_orchestrator import DispatchResult
        r = DispatchResult("d1", "a1", "code-reviewer", success=True, status_code=200,
                           response_body={"result": "ok"}, duration_ms=42.0)
        assert r.success is True
        assert r.status_code == 200
        assert r.duration_ms == 42.0

    def test_failed_dispatch_result(self):
        from agent_orchestrator import DispatchResult
        r = DispatchResult("d2", "a1", "code-reviewer", success=False,
                           error="connection refused", duration_ms=5000.0)
        assert r.success is False
        assert r.error == "connection refused"

    def test_to_dict_contains_all_fields(self):
        from agent_orchestrator import DispatchResult
        r = DispatchResult("d3", "a2", "doc-writer", success=True, status_code=201,
                           response_body={}, duration_ms=10.0)
        d = r.to_dict()
        for key in ("dispatch_id", "agent_id", "agent_type", "success",
                    "status_code", "duration_ms", "dispatched_at"):
            assert key in d


# ============================================================================
# 4. AgentOrchestrator
# ============================================================================

class TestAgentOrchestrator:
    """Tests for AgentOrchestrator dispatch logic."""

    def setup_method(self):
        from agent_registry import AgentRegistry, AgentStatus
        from agent_orchestrator import AgentOrchestrator
        self.AgentStatus = AgentStatus
        self.registry = AgentRegistry()
        self.orchestrator = AgentOrchestrator(registry=self.registry)

    @pytest.mark.asyncio
    async def test_dispatch_returns_error_when_no_agents(self):
        result = await self.orchestrator.dispatch(
            agent_type="code-reviewer",
            endpoint="/execute",
            payload={"action": "review"},
        )
        assert result.success is False
        assert "no healthy" in (result.error or "").lower()

    @pytest.mark.asyncio
    async def test_dispatch_calls_healthy_agent(self):
        # Register a healthy agent
        record = self.registry.register("code-reviewer", "localhost", 9001)
        self.registry.update_status(record.agent_id, self.AgentStatus.HEALTHY)

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json = MagicMock(return_value={"result": "ok"})
        mock_response.raise_for_status = MagicMock()

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.post = AsyncMock(return_value=mock_response)

        with patch("agent_orchestrator.httpx.AsyncClient", return_value=mock_client):
            result = await self.orchestrator.dispatch(
                agent_type="code-reviewer",
                endpoint="/execute",
                payload={"action": "review"},
            )

        assert result.success is True
        assert result.status_code == 200

    @pytest.mark.asyncio
    async def test_dispatch_marks_agent_unhealthy_on_http_error(self):
        import httpx
        record = self.registry.register("incident-responder", "localhost", 9002)
        self.registry.update_status(record.agent_id, self.AgentStatus.HEALTHY)

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.post = AsyncMock(side_effect=httpx.ConnectError("refused"))

        with patch("agent_orchestrator.httpx.AsyncClient", return_value=mock_client):
            result = await self.orchestrator.dispatch(
                agent_type="incident-responder",
                endpoint="/execute",
                payload={},
            )

        assert result.success is False
        updated = self.registry.get(record.agent_id)
        assert updated.status == self.AgentStatus.UNREACHABLE

    @pytest.mark.asyncio
    async def test_health_sweep_updates_status(self):
        record = self.registry.register("doc-writer", "localhost", 9003)
        self.registry.update_status(record.agent_id, self.AgentStatus.REGISTERING)

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.raise_for_status = MagicMock()

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = AsyncMock(return_value=mock_response)

        with patch("agent_orchestrator.httpx.AsyncClient", return_value=mock_client):
            await self.orchestrator.health_sweep()

        updated = self.registry.get(record.agent_id)
        assert updated.status == self.AgentStatus.HEALTHY
