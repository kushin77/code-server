"""
@file apps/hermes-integration/tests/test_agent_orchestration.py
@description Integration tests for the Hermes agent registry and orchestrator.
             Validates registration, heartbeat, liveness, dispatch routing,
             broadcast, audit log, and the REST API endpoints.
"""

import asyncio
import sys
import os
import pytest
from datetime import datetime, timedelta
from typing import Dict, Any
from unittest.mock import AsyncMock, MagicMock, patch

# ── Path setup ────────────────────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


# ===========================================================================
# TestAgentRegistry
# ===========================================================================

class TestAgentRegistry:
    """Unit tests for AgentRegistry core operations."""

    def _make_registry(self):
        from agent_registry import AgentRegistry
        return AgentRegistry()

    def test_register_returns_record(self):
        reg = self._make_registry()
        rec = reg.register("code-reviewer", "localhost", 9001)
        assert rec.agent_type == "code-reviewer"
        assert rec.host == "localhost"
        assert rec.port == 9001
        assert rec.agent_id is not None

    def test_register_with_explicit_id(self):
        reg = self._make_registry()
        rec = reg.register("doc-writer", "host1", 9003, agent_id="fixed-id-123")
        assert rec.agent_id == "fixed-id-123"

    def test_deregister_known_agent(self):
        reg = self._make_registry()
        rec = reg.register("test-generator", "host1", 9004)
        removed = reg.deregister(rec.agent_id)
        assert removed is True
        assert reg.get(rec.agent_id) is None

    def test_deregister_unknown_agent(self):
        reg = self._make_registry()
        removed = reg.deregister("nonexistent-id")
        assert removed is False

    def test_heartbeat_updates_last_seen(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        rec = reg.register("incident-responder", "host1", 9002)
        before = datetime.utcnow()
        found = reg.record_heartbeat(rec.agent_id)
        assert found is True
        assert rec.last_seen_at is not None
        assert rec.last_seen_at >= before

    def test_heartbeat_sets_healthy_from_registering(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        rec = reg.register("code-reviewer", "host1", 9001)
        assert rec.status == AgentStatus.REGISTERING
        reg.record_heartbeat(rec.agent_id)
        assert rec.status == AgentStatus.HEALTHY

    def test_heartbeat_unknown_returns_false(self):
        reg = self._make_registry()
        assert reg.record_heartbeat("ghost-id") is False

    def test_list_all_returns_all_agents(self):
        reg = self._make_registry()
        reg.register("code-reviewer", "host1", 9001)
        reg.register("doc-writer", "host1", 9003)
        assert len(reg.list_all()) == 2

    def test_list_by_type(self):
        reg = self._make_registry()
        reg.register("code-reviewer", "host1", 9001)
        reg.register("code-reviewer", "host2", 9001)
        reg.register("doc-writer", "host1", 9003)
        reviewers = reg.list_by_type("code-reviewer")
        assert len(reviewers) == 2

    def test_list_healthy_filters_correctly(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        r1 = reg.register("code-reviewer", "host1", 9001)
        r1.status = AgentStatus.HEALTHY
        r2 = reg.register("doc-writer", "host1", 9003)
        r2.status = AgentStatus.UNREACHABLE
        healthy = reg.list_healthy()
        assert len(healthy) == 1
        assert healthy[0].agent_id == r1.agent_id

    def test_count_by_status(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        r1 = reg.register("code-reviewer", "host1", 9001)
        r1.status = AgentStatus.HEALTHY
        r2 = reg.register("doc-writer", "host1", 9003)
        r2.status = AgentStatus.HEALTHY
        r3 = reg.register("test-generator", "host1", 9004)
        r3.status = AgentStatus.UNREACHABLE
        counts = reg.count_by_status()
        assert counts["healthy"] == 2
        assert counts["unreachable"] == 1

    def test_mark_stale_agents(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        r1 = reg.register("code-reviewer", "host1", 9001)
        r1.status = AgentStatus.HEALTHY
        # Simulate old last_seen
        r1.last_seen_at = datetime.utcnow() - timedelta(seconds=90)
        stale = reg.mark_stale_agents()
        assert r1.agent_id in stale
        assert r1.status == AgentStatus.UNREACHABLE

    def test_mark_stale_skips_no_heartbeat(self):
        """Agents that never sent a heartbeat are not marked stale."""
        from agent_registry import AgentStatus
        reg = self._make_registry()
        r1 = reg.register("code-reviewer", "host1", 9001)
        # last_seen_at is None — never heartbeated
        stale = reg.mark_stale_agents()
        assert r1.agent_id not in stale

    def test_agent_record_to_dict(self):
        reg = self._make_registry()
        rec = reg.register("incident-responder", "10.0.0.1", 9002, metadata={"region": "us-east-1"})
        d = rec.to_dict()
        assert d["agent_type"] == "incident-responder"
        assert d["host"] == "10.0.0.1"
        assert d["port"] == 9002
        assert d["metadata"]["region"] == "us-east-1"
        assert "registered_at" in d

    def test_agent_record_base_url(self):
        reg = self._make_registry()
        rec = reg.register("test-generator", "10.0.0.5", 9004)
        assert rec.base_url == "http://10.0.0.5:9004"
        assert rec.health_url == "http://10.0.0.5:9004/health"
        assert rec.readiness_url == "http://10.0.0.5:9004/health/ready"


# ===========================================================================
# TestAgentRegistryHttpProbes
# ===========================================================================

class TestAgentRegistryHttpProbes:
    """Tests for the async HTTP probe methods."""

    def _make_registry(self):
        from agent_registry import AgentRegistry
        return AgentRegistry()

    @pytest.mark.asyncio
    async def test_probe_health_healthy(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        rec = reg.register("code-reviewer", "host1", 9001)
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        with patch("agent_registry.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.get = AsyncMock(return_value=mock_resp)
            mock_cls.return_value = mock_client
            status = await reg.probe_health(rec.agent_id)
        assert status == AgentStatus.HEALTHY

    @pytest.mark.asyncio
    async def test_probe_health_degraded_on_non_200(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        rec = reg.register("code-reviewer", "host1", 9001)
        mock_resp = MagicMock()
        mock_resp.status_code = 503
        with patch("agent_registry.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.get = AsyncMock(return_value=mock_resp)
            mock_cls.return_value = mock_client
            status = await reg.probe_health(rec.agent_id)
        assert status == AgentStatus.DEGRADED

    @pytest.mark.asyncio
    async def test_probe_health_unreachable_on_exception(self):
        from agent_registry import AgentStatus
        import httpx
        reg = self._make_registry()
        rec = reg.register("doc-writer", "host1", 9003)
        with patch("agent_registry.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.get = AsyncMock(side_effect=httpx.ConnectError("refused"))
            mock_cls.return_value = mock_client
            status = await reg.probe_health(rec.agent_id)
        assert status == AgentStatus.UNREACHABLE

    @pytest.mark.asyncio
    async def test_probe_health_offline_for_unknown_id(self):
        from agent_registry import AgentStatus
        reg = self._make_registry()
        status = await reg.probe_health("nonexistent-id")
        assert status == AgentStatus.OFFLINE

    @pytest.mark.asyncio
    async def test_probe_readiness_true_on_200(self):
        reg = self._make_registry()
        rec = reg.register("test-generator", "host1", 9004)
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        with patch("agent_registry.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.get = AsyncMock(return_value=mock_resp)
            mock_cls.return_value = mock_client
            ready = await reg.probe_readiness(rec.agent_id)
        assert ready is True


# ===========================================================================
# TestAgentOrchestrator
# ===========================================================================

class TestAgentOrchestrator:
    """Unit tests for AgentOrchestrator dispatch and routing."""

    def _make_orchestrator(self):
        from agent_registry import AgentRegistry
        from agent_orchestrator import AgentOrchestrator
        reg = AgentRegistry()
        return AgentOrchestrator(reg), reg

    @pytest.mark.asyncio
    async def test_dispatch_no_agents_returns_failure(self):
        orch, _ = self._make_orchestrator()
        result = await orch.dispatch("code-reviewer", "/execute", {"input": "test"})
        assert result.success is False
        assert "No healthy agents" in (result.error or "")

    @pytest.mark.asyncio
    async def test_dispatch_success(self):
        from agent_registry import AgentStatus
        orch, reg = self._make_orchestrator()
        rec = reg.register("code-reviewer", "localhost", 9001)
        rec.status = AgentStatus.HEALTHY
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.headers = {"content-type": "application/json"}
        mock_resp.json = MagicMock(return_value={"result": "ok"})
        with patch("agent_orchestrator.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.post = AsyncMock(return_value=mock_resp)
            mock_cls.return_value = mock_client
            result = await orch.dispatch("code-reviewer", "/execute", {"input": "x"})
        assert result.success is True
        assert result.status_code == 200
        assert result.response_body == {"result": "ok"}

    @pytest.mark.asyncio
    async def test_dispatch_prefers_healthy_over_degraded(self):
        from agent_registry import AgentStatus
        orch, reg = self._make_orchestrator()
        degraded = reg.register("code-reviewer", "host-degraded", 9001)
        degraded.status = AgentStatus.DEGRADED
        healthy = reg.register("code-reviewer", "host-healthy", 9001)
        healthy.status = AgentStatus.HEALTHY

        dispatched_hosts = []
        async def mock_dispatch(agent_type, path, payload, method="POST", retries=0):
            from agent_orchestrator import DispatchResult
            selected = orch._select_agent(agent_type)
            dispatched_hosts.append(selected.host if selected else None)
            return DispatchResult(
                dispatch_id="test", agent_id=selected.agent_id if selected else "none",
                agent_type=agent_type, success=True, status_code=200,
            )

        selected = orch._select_agent("code-reviewer")
        assert selected is not None
        assert selected.status == AgentStatus.HEALTHY

    @pytest.mark.asyncio
    async def test_dispatch_round_robin(self):
        from agent_registry import AgentStatus
        orch, reg = self._make_orchestrator()
        h1 = reg.register("test-generator", "host1", 9004)
        h1.status = AgentStatus.HEALTHY
        h2 = reg.register("test-generator", "host2", 9004)
        h2.status = AgentStatus.HEALTHY
        # First pick
        s1 = orch._select_agent("test-generator")
        # Second pick — should be different
        s2 = orch._select_agent("test-generator")
        assert s1 is not None and s2 is not None
        assert s1.agent_id != s2.agent_id

    @pytest.mark.asyncio
    async def test_dispatch_adds_to_audit_log(self):
        from agent_registry import AgentStatus
        orch, reg = self._make_orchestrator()
        rec = reg.register("doc-writer", "localhost", 9003)
        rec.status = AgentStatus.HEALTHY
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.headers = {}
        mock_resp.json = MagicMock(return_value={})
        with patch("agent_orchestrator.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.post = AsyncMock(return_value=mock_resp)
            mock_cls.return_value = mock_client
            await orch.dispatch("doc-writer", "/generate", {"spec": "api.yml"})
        assert len(orch.get_audit_log()) == 1
        entry = orch.get_audit_log()[0]
        assert entry["agent_type"] == "doc-writer"

    @pytest.mark.asyncio
    async def test_dispatch_retries_on_network_error(self):
        from agent_registry import AgentStatus
        import httpx
        orch, reg = self._make_orchestrator()
        rec = reg.register("incident-responder", "localhost", 9002)
        rec.status = AgentStatus.HEALTHY

        call_count = 0
        async def flaky_post(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            raise httpx.ConnectError("timeout")

        with patch("agent_orchestrator.httpx.AsyncClient") as mock_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=None)
            mock_client.post = flaky_post
            mock_cls.return_value = mock_client
            result = await orch.dispatch("incident-responder", "/respond", {})

        # MAX_RETRIES=2, so up to 3 total attempts
        assert call_count == 3
        assert result.success is False

    def test_audit_log_capped_at_500(self):
        from agent_orchestrator import AgentOrchestrator, DispatchResult
        from agent_registry import AgentRegistry
        reg = AgentRegistry()
        orch = AgentOrchestrator(reg)
        for i in range(600):
            result = DispatchResult(
                dispatch_id=f"d{i}", agent_id="a1", agent_type="test",
                success=True, status_code=200,
            )
            orch._record_audit(result, {})
        assert len(orch._audit_log) == 500

    @pytest.mark.asyncio
    async def test_broadcast_dispatches_to_all_types(self):
        from agent_registry import AgentStatus
        orch, reg = self._make_orchestrator()
        for t in ["code-reviewer", "doc-writer", "test-generator"]:
            rec = reg.register(t, "localhost", 9001)
            rec.status = AgentStatus.HEALTHY

        dispatched_types = []
        original = orch.dispatch

        async def recording_dispatch(agent_type, path, payload, method="POST", retries=0):
            dispatched_types.append(agent_type)
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.headers = {}
            mock_resp.json = MagicMock(return_value={})
            from agent_orchestrator import DispatchResult
            return DispatchResult("d1", "aid", agent_type, True, 200)

        orch.dispatch = recording_dispatch
        results = await orch.broadcast("/health", {})
        assert len(results) == 3
        assert set(dispatched_types) == {"code-reviewer", "doc-writer", "test-generator"}


# ===========================================================================
# TestHermesRegistrationClient
# ===========================================================================

class TestHermesRegistrationClient:
    """Tests for the agent-runtime Hermes registration client."""

    def test_enabled_false_when_no_url(self):
        with patch.dict(os.environ, {"HERMES_URL": ""}):
            from importlib import reload
            import agent_registry  # confirm our module loads
            # Import hermes_registration from agent-runtime path
            rt_path = os.path.join(os.path.dirname(__file__), "..", "..", "agent-runtime")
            if rt_path not in sys.path:
                sys.path.insert(0, rt_path)
            import hermes_registration
            client = hermes_registration.HermesRegistrationClient()
            # Enabled only if HERMES_URL is set
            assert client.enabled is False

    def test_agent_type_read_from_env(self):
        rt_path = os.path.join(os.path.dirname(__file__), "..", "..", "agent-runtime")
        if rt_path not in sys.path:
            sys.path.insert(0, rt_path)
        with patch.dict(os.environ, {"AGENT_TYPE": "code-reviewer", "HERMES_URL": "http://hermes:8000"}):
            import importlib, hermes_registration
            importlib.reload(hermes_registration)
            assert hermes_registration.AGENT_TYPE == "code-reviewer"

    @pytest.mark.asyncio
    async def test_register_skipped_when_disabled(self):
        rt_path = os.path.join(os.path.dirname(__file__), "..", "..", "agent-runtime")
        if rt_path not in sys.path:
            sys.path.insert(0, rt_path)
        with patch.dict(os.environ, {"HERMES_URL": ""}):
            import importlib, hermes_registration
            importlib.reload(hermes_registration)
            client = hermes_registration.HermesRegistrationClient()
            result = await client.register()
            assert result is False

    @pytest.mark.asyncio
    async def test_register_success(self):
        rt_path = os.path.join(os.path.dirname(__file__), "..", "..", "agent-runtime")
        if rt_path not in sys.path:
            sys.path.insert(0, rt_path)
        with patch.dict(os.environ, {
            "HERMES_URL": "http://hermes:8000",
            "AGENT_TYPE": "incident-responder",
        }):
            import importlib, hermes_registration
            importlib.reload(hermes_registration)
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.raise_for_status = MagicMock()
            with patch("hermes_registration.httpx.AsyncClient") as mock_cls:
                mock_client = AsyncMock()
                mock_client.__aenter__ = AsyncMock(return_value=mock_client)
                mock_client.__aexit__ = AsyncMock(return_value=None)
                mock_client.post = AsyncMock(return_value=mock_resp)
                mock_cls.return_value = mock_client
                client = hermes_registration.HermesRegistrationClient()
                result = await client.register()
            assert result is True
            assert client._registered is True
            # Cleanup: cancel heartbeat task
            if client._heartbeat_task:
                client._heartbeat_task.cancel()


# ===========================================================================
# TestHermesRestEndpoints
# ===========================================================================

class TestHermesRestEndpoints:
    """FastAPI endpoint integration tests for /agents/* routes."""

    def _make_client(self):
        from fastapi.testclient import TestClient
        # Reset registry state for isolated tests
        from agent_registry import AgentRegistry, registry as global_reg
        from agent_orchestrator import AgentOrchestrator, orchestrator as global_orch
        # Patch the singletons with fresh instances
        fresh_reg = AgentRegistry()
        with patch("agent_registry.registry", fresh_reg), \
             patch("agent_orchestrator.registry", fresh_reg):
            import importlib
            import main as hermes_main
            importlib.reload(hermes_main)
            return TestClient(hermes_main.app), fresh_reg

    def test_list_agents_empty(self):
        client, reg = self._make_client()
        resp = client.get("/agents")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 0

    def test_register_agent_endpoint(self):
        client, reg = self._make_client()
        resp = client.post("/agents/register", json={
            "agent_type": "code-reviewer",
            "host": "localhost",
            "port": 9001,
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["registered"] is True
        assert data["agent"]["agent_type"] == "code-reviewer"

    def test_register_missing_fields_422(self):
        client, reg = self._make_client()
        resp = client.post("/agents/register", json={"agent_type": "code-reviewer"})
        assert resp.status_code == 422

    def test_heartbeat_endpoint(self):
        from agent_registry import AgentStatus
        client, reg = self._make_client()
        rec = reg.register("doc-writer", "localhost", 9003)
        rec.status = AgentStatus.HEALTHY
        resp = client.post(f"/agents/{rec.agent_id}/heartbeat")
        assert resp.status_code == 200
        assert resp.json()["status"] == "heartbeat_recorded"

    def test_heartbeat_unknown_agent_404(self):
        client, reg = self._make_client()
        resp = client.post("/agents/ghost-id/heartbeat")
        assert resp.status_code == 404

    def test_deregister_endpoint(self):
        from agent_registry import AgentStatus
        client, reg = self._make_client()
        rec = reg.register("test-generator", "localhost", 9004)
        rec.status = AgentStatus.HEALTHY
        resp = client.delete(f"/agents/{rec.agent_id}")
        assert resp.status_code == 200
        assert resp.json()["deregistered"] is True

    def test_deregister_unknown_404(self):
        client, reg = self._make_client()
        resp = client.delete("/agents/nonexistent")
        assert resp.status_code == 404

    def test_dispatch_missing_fields_422(self):
        client, reg = self._make_client()
        resp = client.post("/agents/dispatch", json={"agent_type": "code-reviewer"})
        assert resp.status_code == 422

    def test_audit_log_empty_initially(self):
        client, reg = self._make_client()
        resp = client.get("/agents/audit")
        assert resp.status_code == 200
        assert resp.json()["entries"] == []
