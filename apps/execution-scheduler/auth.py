"""
@file apps/execution-scheduler/auth.py
@description API key and OAuth2 authentication for scheduler endpoints
@governance GOV-002: Immutable, deterministic token validation
"""

import os
import secrets
from typing import Optional
from fastapi import HTTPException, Depends, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

# Simple in-memory API key store (in production, use secrets manager)
VALID_API_KEYS = {
    os.getenv("SCHEDULER_API_KEY", "scheduler-default-key-dev-only"): "scheduler-service",
}


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

    async def verify_bearer_token(self, credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())) -> str:
        """
        Verify Bearer token (placeholder for OAuth2).
        
        In production, validate against authorization server.
        """
        token = credentials.credentials

        # Placeholder validation - in production, call OAuth2 provider
        if not token.startswith("bearer_"):
            raise HTTPException(
                status_code=401,
                detail="Invalid bearer token format",
            )

        # In production: validate token against OAuth2 provider
        return "user-from-token"


def get_auth() -> SchedulerAuth:
    """Dependency injection for auth."""
    return SchedulerAuth()
