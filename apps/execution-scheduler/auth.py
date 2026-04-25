"""
@file apps/execution-scheduler/auth.py
@description API key and OAuth2 authentication for scheduler endpoints
@governance GOV-002: Immutable, deterministic token validation
"""

import os
import logging
from typing import Optional
from fastapi import HTTPException, Depends, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

# Simple in-memory API key store (in production, use secrets manager)
VALID_API_KEYS = {
    os.getenv("SCHEDULER_API_KEY", "scheduler-default-key-dev-only"): "scheduler-service",
}

# OAuth2 introspection endpoint (set via env for production)
_OAUTH2_INTROSPECT_URL = os.getenv("OAUTH2_INTROSPECT_URL", "")
_OAUTH2_CLIENT_ID = os.getenv("OAUTH2_CLIENT_ID", "")
_OAUTH2_CLIENT_SECRET = os.getenv("OAUTH2_CLIENT_SECRET", "")


class SchedulerAuth:
    """Authentication and authorization for scheduler API."""

    def __init__(self):
        self.security = HTTPBearer()

    async def verify_api_key(self, x_api_key: str = Header(None)) -> str:
        """
        Verify API key from request headers.

        Args:
            x_api_key: API key from X-API-Key header

        Returns:
            Service identifier if valid

        Raises:
            HTTPException(401) if invalid or missing
        """
        if not x_api_key:
            raise HTTPException(
                status_code=401,
                detail="Missing X-API-Key header",
            )

        if x_api_key not in VALID_API_KEYS:
            raise HTTPException(
                status_code=401,
                detail="Invalid API key",
            )

        return VALID_API_KEYS[x_api_key]

    async def verify_bearer_token(
        self, credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())
    ) -> str:
        """
        Verify Bearer token via OAuth2 introspection endpoint.

        Falls back to prefix-based validation when OAUTH2_INTROSPECT_URL is not set
        (development only).
        """
        token = credentials.credentials

        if _OAUTH2_INTROSPECT_URL:
            return await self._introspect_token(token)

        # Dev-only fallback: accept any non-empty token
        if not token:
            raise HTTPException(status_code=401, detail="Empty bearer token")
        logger.debug("OAuth2 introspection not configured — dev token accepted")
        return "dev-user"

    async def _introspect_token(self, token: str) -> str:
        """Call OAuth2 introspection endpoint to validate token."""
        import httpx

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    _OAUTH2_INTROSPECT_URL,
                    data={"token": token},
                    auth=(_OAUTH2_CLIENT_ID, _OAUTH2_CLIENT_SECRET),
                )
            if resp.status_code != 200:
                raise HTTPException(status_code=401, detail="Token introspection failed")
            data = resp.json()
            if not data.get("active", False):
                raise HTTPException(status_code=401, detail="Token is not active")
            return data.get("sub") or data.get("username") or "authenticated-user"
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Token introspection error: {e}")
            raise HTTPException(status_code=401, detail="Unable to validate token")


def get_auth() -> SchedulerAuth:
    """Dependency injection for auth."""
    return SchedulerAuth()
