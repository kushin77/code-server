"""
@file apps/agent-runtime/oidc_client.py
@description OIDC client for federated identity and scoped permissions
@governance GOV-002: Deterministic OIDC flow with audit logging
"""

from log import get_logger
from typing import Optional, Dict, Any
from dataclasses import dataclass
from datetime import datetime, timedelta

logger = get_logger(__name__)


@dataclass
class OIDCToken:
    """OIDC token with metadata"""
    access_token: str
    token_type: str
    expires_in: int
    scope: str
    issued_at: datetime
    
    def is_expired(self) -> bool:
        """Check if token is expired"""
        expiration = self.issued_at + timedelta(seconds=self.expires_in - 30)  # 30s buffer
        return datetime.utcnow() >= expiration


class OIDCClient:
    """OIDC client for agent identity and authorization"""
    
    def __init__(
        self,
        client_id: str,
        client_secret: str,
        token_endpoint: str = "http://oauth2-proxy:4180/oauth2/token",
        scope: str = "agent.execute"
    ):
        self.client_id = client_id
        self.client_secret = client_secret
        self.token_endpoint = token_endpoint
        self.scope = scope
        self.current_token: Optional[OIDCToken] = None
    
    async def authenticate(self) -> Optional[OIDCToken]:
        """Authenticate using client credentials flow"""
        try:
            import httpx
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    self.token_endpoint,
                    data={
                        "grant_type": "client_credentials",
                        "client_id": self.client_id,
                        "client_secret": self.client_secret,
                        "scope": self.scope
                    },
                    timeout=10
                )
                
                if response.status_code == 200:
                    data = response.json()
                    token = OIDCToken(
                        access_token=data["access_token"],
                        token_type=data.get("token_type", "Bearer"),
                        expires_in=data.get("expires_in", 3600),
                        scope=data.get("scope", self.scope),
                        issued_at=datetime.utcnow()
                    )
                    self.current_token = token
                    logger.info(f"OIDC authentication successful: {self.client_id}")
                    return token
                else:
                    logger.error(f"OIDC authentication failed: {response.status_code}")
                    return None
        except Exception as e:
            logger.error(f"OIDC authentication error: {e}")
            return None
    
    async def get_valid_token(self) -> Optional[str]:
        """Get a valid access token, refreshing if needed"""
        if self.current_token is None or self.current_token.is_expired():
            token = await self.authenticate()
            if token is None:
                return None
        
        return self.current_token.access_token if self.current_token else None
    
    async def verify_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify token with introspection endpoint"""
        try:
            import httpx
            
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.token_endpoint.replace('/token', '/introspect')}",
                    data={
                        "token": token,
                        "client_id": self.client_id,
                        "client_secret": self.client_secret
                    },
                    timeout=10
                )
                
                if response.status_code == 200:
                    return response.json()
                else:
                    logger.warning(f"Token verification failed: {response.status_code}")
                    return None
        except Exception as e:
            logger.error(f"Token verification error: {e}")
            return None
    
    def get_authorization_header(self) -> str:
        """Get Authorization header value"""
        if self.current_token:
            return f"{self.current_token.token_type} {self.current_token.access_token}"
        return ""
    
    async def has_scope(self, required_scope: str) -> bool:
        """Check if token has required scope"""
        if not self.current_token:
            await self.authenticate()
        
        if self.current_token:
            scopes = self.current_token.scope.split()
            return required_scope in scopes
        
        return False
