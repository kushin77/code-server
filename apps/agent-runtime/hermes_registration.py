"""
@file apps/agent-runtime/hermes_registration.py
@description Hermes Orchestrator Registration — registers this Agent Runtime instance
             with the central Hermes orchestrator on startup, sends heartbeats, and
             gracefully deregisters on shutdown.

Resilience contract:
  - If Hermes is unavailable, agent-runtime starts normally (non-blocking).
  - Heartbeat failures are logged but do not stop execution.
  - Registration is retried with exponential backoff (max 3 attempts).
"""

import asyncio
import os
import socket
import uuid
from datetime import datetime
from typing import Optional

import httpx

from log import get_logger, log_event

logger = get_logger(__name__)

# ── Configuration (read from env — do not hard-code) ─────────────────────────
HERMES_URL: str = os.getenv("HERMES_URL", "")           # e.g. http://hermes:8050
HERMES_HEARTBEAT_INTERVAL: int = int(os.getenv("HERMES_HEARTBEAT_INTERVAL", "30"))  # seconds
HERMES_REGISTRATION_RETRIES: int = 3
HERMES_TIMEOUT: float = 5.0  # seconds per request

# ── Instance identity ─────────────────────────────────────────────────────────
AGENT_ID: str = os.getenv("AGENT_RUNTIME_ID", f"agent-runtime-{socket.gethostname()}")
AGENT_VERSION: str = os.getenv("AGENT_RUNTIME_VERSION", "1.0.0")
AGENT_PORT: int = int(os.getenv("AGENT_RUNTIME_PORT", "8020"))


class HermesRegistrationClient:
    """
    Manages Agent Runtime lifecycle with the Hermes orchestrator.

    Usage (in app_factory.py lifespan):
        hermes = HermesRegistrationClient()
        await hermes.register()
        # ... app runs ...
        await hermes.deregister()
    """

    def __init__(self) -> None:
        self._registered = False
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._agent_id = AGENT_ID

    @property
    def enabled(self) -> bool:
        """True when Hermes URL is configured."""
        return bool(HERMES_URL)

    async def register(self) -> bool:
        """
        Register this agent-runtime instance with Hermes.

        Returns True on success, False if Hermes is unreachable (non-fatal).
        """
        if not self.enabled:
            log_event(logger, "hermes_registration_skipped", reason="HERMES_URL not set")
            return False

        payload = {
            "agent_id": self._agent_id,
            "agent_type": "agent-runtime",
            "version": AGENT_VERSION,
            "host": socket.gethostname(),
            "port": AGENT_PORT,
            "capabilities": ["code-review", "incident-response", "doc-generation", "test-generation"],
            "registered_at": datetime.utcnow().isoformat(),
        }

        for attempt in range(1, HERMES_REGISTRATION_RETRIES + 1):
            try:
                async with httpx.AsyncClient(timeout=HERMES_TIMEOUT) as client:
                    resp = await client.post(
                        f"{HERMES_URL}/agents/register",
                        json=payload,
                    )
                    resp.raise_for_status()

                self._registered = True
                log_event(
                    logger,
                    "hermes_registration_success",
                    agent_id=self._agent_id,
                    hermes_url=HERMES_URL,
                )
                self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())
                return True

            except (httpx.HTTPError, Exception) as exc:
                backoff = 2 ** attempt
                log_event(
                    logger,
                    "hermes_registration_attempt_failed",
                    attempt=attempt,
                    max_attempts=HERMES_REGISTRATION_RETRIES,
                    error=str(exc),
                    retry_in_seconds=backoff if attempt < HERMES_REGISTRATION_RETRIES else None,
                )
                if attempt < HERMES_REGISTRATION_RETRIES:
                    await asyncio.sleep(backoff)

        log_event(
            logger,
            "hermes_registration_failed",
            agent_id=self._agent_id,
            reason="All retry attempts exhausted — running without Hermes",
        )
        return False

    async def deregister(self) -> None:
        """Gracefully deregister from Hermes on shutdown."""
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass

        if not (self.enabled and self._registered):
            return

        try:
            async with httpx.AsyncClient(timeout=HERMES_TIMEOUT) as client:
                await client.delete(f"{HERMES_URL}/agents/{self._agent_id}")
            log_event(logger, "hermes_deregistration_success", agent_id=self._agent_id)
        except Exception as exc:
            log_event(logger, "hermes_deregistration_failed", error=str(exc))

        self._registered = False

    async def _heartbeat_loop(self) -> None:
        """Send periodic heartbeats to Hermes."""
        while True:
            await asyncio.sleep(HERMES_HEARTBEAT_INTERVAL)
            await self._send_heartbeat()

    async def _send_heartbeat(self) -> None:
        """POST a single heartbeat to Hermes."""
        if not (self.enabled and self._registered):
            return
        try:
            async with httpx.AsyncClient(timeout=HERMES_TIMEOUT) as client:
                await client.post(
                    f"{HERMES_URL}/agents/{self._agent_id}/heartbeat",
                    json={"timestamp": datetime.utcnow().isoformat()},
                )
            log_event(logger, "hermes_heartbeat_sent", agent_id=self._agent_id)
        except Exception as exc:
            log_event(logger, "hermes_heartbeat_failed", error=str(exc))


# Module-level singleton — import and reuse in app_factory.py
hermes_client = HermesRegistrationClient()
