"""
@file apps/agent-runtime/tests/test_hermes_integration.py
@description Tests for Hermes orchestrator registration and OTEL tracing modules
@coverage hermes_registration.py, hermes_tracing.py
"""

import asyncio
import os
import sys
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

sys.path.insert(0, '..')


# ============================================================================
# 1. HermesRegistrationClient — unit tests
# ============================================================================

class TestHermesRegistrationClient:
    """Tests for the Hermes lifecycle registration client."""

    def test_client_disabled_when_no_url(self):
        """Client reports disabled when HERMES_URL is not configured."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HERMES_URL", None)
            # Reimport to pick up empty HERMES_URL
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)
            client = hermes_registration.HermesRegistrationClient()
            assert client.enabled is False

    def test_client_enabled_when_url_set(self):
        """Client reports enabled when HERMES_URL is configured."""
        with patch.dict(os.environ, {"HERMES_URL": "http://hermes:8050"}):
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)
            client = hermes_registration.HermesRegistrationClient()
            assert client.enabled is True

    @pytest.mark.asyncio
    async def test_register_skipped_without_url(self):
        """register() returns False and does not make HTTP calls when disabled."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HERMES_URL", None)
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)
            client = hermes_registration.HermesRegistrationClient()
            result = await client.register()
            assert result is False
            assert client._registered is False

    @pytest.mark.asyncio
    async def test_register_success(self):
        """register() returns True and starts heartbeat on successful HTTP call."""
        with patch.dict(os.environ, {"HERMES_URL": "http://hermes:8050"}):
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)

            mock_response = MagicMock()
            mock_response.raise_for_status = MagicMock()

            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)
            mock_client.post = AsyncMock(return_value=mock_response)

            with patch("hermes_registration.httpx.AsyncClient", return_value=mock_client):
                client = hermes_registration.HermesRegistrationClient()
                result = await client.register()

            assert result is True
            assert client._registered is True
            # Cancel background heartbeat task to avoid lingering coroutines
            if client._heartbeat_task:
                client._heartbeat_task.cancel()
                try:
                    await client._heartbeat_task
                except asyncio.CancelledError:
                    pass

    @pytest.mark.asyncio
    async def test_register_retries_on_failure(self):
        """register() retries up to HERMES_REGISTRATION_RETRIES times."""
        import httpx

        with patch.dict(os.environ, {"HERMES_URL": "http://hermes:8050",
                                      "HERMES_HEARTBEAT_INTERVAL": "3600"}):
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)

            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)
            mock_client.post = AsyncMock(side_effect=httpx.ConnectError("refused"))

            with patch("hermes_registration.httpx.AsyncClient", return_value=mock_client):
                with patch("hermes_registration.asyncio.sleep", new_callable=AsyncMock):
                    client = hermes_registration.HermesRegistrationClient()
                    result = await client.register()

            assert result is False
            assert client._registered is False
            # post called 3 times (HERMES_REGISTRATION_RETRIES default)
            assert mock_client.post.call_count == 3

    @pytest.mark.asyncio
    async def test_deregister_noop_when_not_registered(self):
        """deregister() is a no-op when never registered."""
        with patch.dict(os.environ, {"HERMES_URL": "http://hermes:8050"}):
            import importlib
            import hermes_registration
            importlib.reload(hermes_registration)

            client = hermes_registration.HermesRegistrationClient()
            # Not registered, should not raise
            await client.deregister()
            assert client._registered is False


# ============================================================================
# 2. Hermes Tracing — unit tests
# ============================================================================

class TestHermesTracing:
    """Tests for the OTEL tracing module."""

    def test_setup_tracing_disabled_by_env(self):
        """setup_tracing() exits early when OTEL_ENABLED=false."""
        with patch.dict(os.environ, {"OTEL_ENABLED": "false"}):
            import importlib
            import hermes_tracing
            importlib.reload(hermes_tracing)
            hermes_tracing.setup_tracing()
            # Tracer should remain None
            assert hermes_tracing.get_tracer() is None

    def test_trace_agent_execution_noop_without_tracer(self):
        """trace_agent_execution yields None when tracer is not initialised."""
        import importlib
        import hermes_tracing
        importlib.reload(hermes_tracing)
        # Force tracer to None
        hermes_tracing._tracer = None

        with hermes_tracing.trace_agent_execution(
            agent_id="a1", agent_type="code-review", action="review", execution_id="e1"
        ) as span:
            assert span is None

    def test_trace_hermes_call_noop_without_tracer(self):
        """trace_hermes_call yields None when tracer is not initialised."""
        import importlib
        import hermes_tracing
        importlib.reload(hermes_tracing)
        hermes_tracing._tracer = None

        with hermes_tracing.trace_hermes_call("register", "agent-1") as span:
            assert span is None

    def test_instrument_app_noop_without_tracer(self):
        """instrument_app() is a no-op when tracer is None."""
        import importlib
        import hermes_tracing
        importlib.reload(hermes_tracing)
        hermes_tracing._tracer = None

        app_mock = MagicMock()
        hermes_tracing.instrument_app(app_mock)
        # FastAPIInstrumentor should not have been called
        app_mock.assert_not_called()


# ============================================================================
# 3. Config — Hermes additions
# ============================================================================

class TestHermesConfig:
    """Verify Hermes-related config entries were added to the SSOT."""

    def test_hermes_config_keys_present(self):
        """config.py exports HERMES_URL and related settings."""
        import importlib
        import config
        importlib.reload(config)

        assert hasattr(config, "HERMES_URL")
        assert hasattr(config, "HERMES_HEARTBEAT_INTERVAL")
        assert hasattr(config, "HERMES_REGISTRATION_RETRIES")

    def test_hermes_url_defaults_empty(self):
        """HERMES_URL defaults to empty string (integration disabled by default)."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HERMES_URL", None)
            import importlib
            import config
            importlib.reload(config)
            assert config.HERMES_URL == ""

    def test_hermes_heartbeat_interval_default(self):
        """HERMES_HEARTBEAT_INTERVAL defaults to 30 seconds."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("HERMES_HEARTBEAT_INTERVAL", None)
            import importlib
            import config
            importlib.reload(config)
            assert config.HERMES_HEARTBEAT_INTERVAL == 30
