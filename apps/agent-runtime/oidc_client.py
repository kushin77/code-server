"""
@file apps/agent-runtime/oidc_client.py
@description OIDC client for federated identity and scoped permissions
@governance GOV-002: Deterministic OIDC flow with audit logging and scope enforcement
"""

import logging
import asyncio
from typing import Optional, Dict, Any, Set
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum

logger = logging.getLogger(__name__)


class AgentScope(str, Enum):
    """Agent-type-specific scopes for federated identity"""
    CODE_REVIEWER = "agent:code-reviewer:execute"
    INCIDENT_RESPONDER = "agent:incident-responder:execute"
    DOC_WRITER = "agent:doc-writer:execute"
    TEST_GENERATOR = "agent:test-generator:execute"


@dataclass
class OIDCToken:
    """OIDC token with metadata and scope tracking"""
    access_token: str
    token_type: str
    expires_in: int
    scope: str
    issued_at: datetime
    scope_set: Set[str] = field(default_factory=set)
    
    def is_expired(self) -> bool:
        """Check if token is expired (with 30s refresh buffer)"""
        expiration = self.issued_at + timedelta(seconds=self.expires_in - 30)
        return datetime.utcnow() >= expiration
    
    def has_scope(self, required_scope: str) -> bool:
        """Check if token has required scope"""
        return required_scope in self.scope_set or required_scope in self.scope.split()


class OIDCClient:
    """OIDC client for agent identity and authorization with scoped permissions"""
    
    # Retry configuration (exponential backoff)
    readonly_MAX_RETRIES = 3
    readonly_INITIAL_BACKOFF = 1.0  # seconds
    
    def __init__(
        self,
        client_id: str,
        client_secret: str,
        token_endpoint: str = "http://oauth2-proxy:4180/oauth2/token",
        scopes: Optional[Set[str]] = None,
        agent_type: Optional[str] = None
    ):
        self.client_id = client_id
        self.client_secret = client_secret
        self.token_endpoint = token_endpoint
        self.agent_type = agent_type
        
        # Set scopes: if agent_type provided, use specific scope; else use all scopes
        if scopes:
            self.scopes = scopes
        elif agent_type:
            agent_scope_map = {
                "code-reviewer": AgentScope.CODE_REVIEWER.value,
                "incident-responder": AgentScope.INCIDENT_RESPONDER.value,
                "doc-writer": AgentScope.DOC_WRITER.value,
                "test-generator": AgentScope.TEST_GENERATOR.value,
            }
            self.scopes = {agent_scope_map.get(agent_type, f"agent:{agent_type}:execute")}
        else:
            self.scopes = {scope.value for scope in AgentScope}
        
        self.current_token: Optional[OIDCToken] = None
        self.authentication_attempts = 0
        self.last_auth_error: Optional[str] = None
    
    async def authenticate(self, force_refresh: bool = False) -> Optional[OIDCToken]:
        """Authenticate using client credentials flow with exponential backoff retry"""
        if not force_refresh and self.current_token and not self.current_token.is_expired():
            return self.current_token
        
        retry_count = 0
        backoff = self.readonly_INITIAL_BACKOFF
        
        while retry_count < self.readonly_MAX_RETRIES:
            try:
                import httpx
                
                scope_str = " ".join(sorted(self.scopes))
                
                async with httpx.AsyncClient(timeout=10) as client:
                    response = await client.post(
                        self.token_endpoint,
                        data={
                            "grant_type": "client_credentials",
                            "client_id": self.client_id,
                            "client_secret": self.client_secret,
                            "scope": scope_str
                        }
                    )
                    
                    if response.status_code == 200:
                        data = response.json()
                        
                        # Parse scopes from response
                        response_scopes = set(data.get("scope", scope_str).split())
                        
                        token = OIDCToken(
                            access_token=data["access_token"],
                            token_type=data.get("token_type", "Bearer"),
                            expires_in=data.get("expires_in", 3600),
                            scope=data.get("scope", scope_str),
                            issued_at=datetime.utcnow(),
                            scope_set=response_scopes
                        )
                        self.current_token = token
                        self.authentication_attempts += 1
                        self.last_auth_error = None
                        logger.info(
                            f"OIDC authentication successful: client={self.client_id} "
                            f"agent_type={self.agent_type} scopes={response_scopes}"
                        )
                        return token
                    elif response.status_code in (429, 502, 503):
                        # Retry on rate limit or server errors
                        retry_count += 1
                        if retry_count < self.readonly_MAX_RETRIES:
                            logger.warning(
                                f"OIDC authentication temporary failure ({response.status_code}), "
                                f"retrying in {backoff}s (attempt {retry_count}/{self.readonly_MAX_RETRIES})"
                            )
                            await asyncio.sleep(backoff)
                            backoff *= 2  # Exponential backoff
                            continue
                        else:
                            error_msg = f"OIDC auth failed after {retry_count} retries: {response.status_code}"
                            self.last_auth_error = error_msg
                            logger.error(error_msg)
                            return None
                    else:
                        error_msg = f"OIDC authentication failed: {response.status_code} {response.text[:200]}"
                        self.last_auth_error = error_msg
                        logger.error(error_msg)
                        return None
            except asyncio.TimeoutError:
                retry_count += 1
                if retry_count < self.readonly_MAX_RETRIES:
                    logger.warning(f"OIDC authentication timeout, retrying in {backoff}s")
                    await asyncio.sleep(backoff)
                    backoff *= 2
                    continue
                else:
                    error_msg = "OIDC authentication: timeout after max retries"
                    self.last_auth_error = error_msg
                    logger.error(error_msg)
                    return None
            except Exception as e:
                error_msg = f"OIDC authentication error: {str(e)}"
                self.last_auth_error = error_msg
                logger.error(error_msg)
                return None
        
        return None
    
    async def get_valid_token(self, require_scope: Optional[str] = None) -> Optional[str]:
        """Get a valid access token, refreshing if needed, with optional scope validation"""
        token = await self.authenticate()  # Will refresh if expired
        
        if token is None:
            return None
        
        # Validate required scope if specified
        if require_scope and not token.has_scope(require_scope):
            logger.error(
                f"Token missing required scope: {require_scope}. "
                f"Available scopes: {token.scope_set}"
            )
            return None
        
        return token.access_token
    
    async def verify_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify token with introspection endpoint"""
        try:
            import httpx
            
            introspect_endpoint = self.token_endpoint.replace("/token", "/introspect")
            
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.post(
                    introspect_endpoint,
                    data={
                        "token": token,
                        "client_id": self.client_id,
                        "client_secret": self.client_secret
                    }
                )
                
                if response.status_code == 200:
                    data = response.json()
                    logger.debug(f"Token verification: active={data.get('active')}")
                    return data
                else:
                    logger.warning(f"Token verification failed: {response.status_code}")
                    return None
        except Exception as e:
            logger.error(f"Token verification error: {e}")
            return None
    
    def get_authorization_header(self) -> str:
        """Get Authorization header value for API calls"""
        if self.current_token:
            return f"{self.current_token.token_type} {self.current_token.access_token}"
        return ""
    
    def get_token_info(self) -> Dict[str, Any]:
        """Get current token information (for diagnostics)"""
        if not self.current_token:
            return {"status": "not_authenticated"}
        
        return {
            "status": "authenticated",
            "is_expired": self.current_token.is_expired(),
            "issued_at": self.current_token.issued_at.isoformat(),
            "expires_in": self.current_token.expires_in,
            "scopes": list(self.current_token.scope_set),
            "authentication_attempts": self.authentication_attempts,
            "last_error": self.last_auth_error
        }
    
    async def has_scope(self, required_scope: str) -> bool:
        """Check if token has required scope"""
        if not self.current_token:
            await self.authenticate()
        
        if self.current_token:
            scopes = self.current_token.scope.split()
            return required_scope in scopes
        
        return False
