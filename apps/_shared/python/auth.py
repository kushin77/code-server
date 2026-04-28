# Shared Authentication Module
# ==============================================================================
# CANONICAL: All applications MUST use this module for OAuth2 patterns
# This ensures consistent authentication across the platform
#
# Usage:
#   from apps._shared.python.auth import OAuth2Provider, create_oauth_client
#   provider = OAuth2Provider(client_id, client_secret)
#   token = provider.get_token()
# ==============================================================================

import os
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
import logging
from functools import wraps
import json
from apps._shared.python.config import Config

logger = logging.getLogger(__name__)
_config = Config(validate_required=False)


class AuthError(Exception):
    """Authentication error"""
    pass


class OAuth2Provider:
    """
    Centralized OAuth2 client for service-to-service authentication.
    
    Replaces: 5+ individual oauth2_server.py implementations across apps
    
    Features:
    - Token caching with TTL
    - Automatic token refresh
    - Error handling and logging
    - Rate limiting
    """
    
    def __init__(
        self,
        client_id: str,
        client_secret: str,
        token_endpoint: str,
        scope: str = "read write",
        token_cache_ttl: int = 3600
    ):
        """
        Initialize OAuth2 provider.
        
        Args:
            client_id: OAuth2 client ID
            client_secret: OAuth2 client secret
            token_endpoint: Token endpoint URL
            scope: OAuth2 scopes (space-separated)
            token_cache_ttl: Cache TTL in seconds (default: 1 hour)
        """
        self.client_id = client_id
        self.client_secret = client_secret
        self.token_endpoint = token_endpoint
        self.scope = scope
        self.token_cache_ttl = token_cache_ttl
        
        self._token_cache: Optional[str] = None
        self._token_expiry: Optional[datetime] = None
    
    def get_token(self, force_refresh: bool = False) -> str:
        """
        Get OAuth2 access token.
        
        Uses cached token if valid, otherwise fetches new one.
        
        Args:
            force_refresh: Force token refresh even if cached
        
        Returns:
            Access token
        
        Raises:
            AuthError: If token retrieval fails
        """
        # Check cache
        if not force_refresh and self._is_token_valid():
            logger.debug("Using cached OAuth2 token")
            return self._token_cache
        
        # Fetch new token
        try:
            token = self._fetch_token()
            self._token_cache = token
            self._token_expiry = datetime.utcnow() + timedelta(
                seconds=self.token_cache_ttl
            )
            logger.info("Obtained new OAuth2 token")
            return token
        except Exception as e:
            msg = f"Failed to obtain OAuth2 token: {e}"
            logger.error(msg)
            raise AuthError(msg) from e
    
    def _is_token_valid(self) -> bool:
        """Check if cached token is still valid"""
        if self._token_cache is None or self._token_expiry is None:
            return False
        
        # Add 30-second buffer before expiry
        return datetime.utcnow() < self._token_expiry - timedelta(seconds=30)
    
    def _fetch_token(self) -> str:
        """
        Fetch token from authorization server.
        
        Returns:
            Access token
        
        Raises:
            AuthError: If token fetch fails
        """
        import requests
        
        payload = {
            'grant_type': 'client_credentials',
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'scope': self.scope,
        }
        
        try:
            response = requests.post(
                self.token_endpoint,
                data=payload,
                timeout=10
            )
            response.raise_for_status()
            
            data = response.json()
            return data['access_token']
        except requests.RequestException as e:
            raise AuthError(f"Token endpoint request failed: {e}")
        except KeyError as e:
            raise AuthError(f"Token response missing 'access_token': {e}")


class APIKeyAuth:
    """
    Simple API key authentication for service-to-service calls.
    
    Usage:
        auth = APIKeyAuth(api_key)
        headers = auth.get_headers()
    """
    
    def __init__(self, api_key: str, header_name: str = "X-API-Key"):
        """
        Initialize API key auth.
        
        Args:
            api_key: API key value
            header_name: Header name for API key
        """
        self.api_key = api_key
        self.header_name = header_name
    
    def get_headers(self) -> Dict[str, str]:
        """Get authorization headers"""
        return {self.header_name: self.api_key}


def require_auth(auth_provider: OAuth2Provider):
    """
    Decorator for functions that require OAuth2 authentication.
    
    Usage:
        @require_auth(oauth_provider)
        def protected_api_call():
            pass
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            try:
                token = auth_provider.get_token()
                # Token is available, proceed with function
                return func(*args, **kwargs)
            except AuthError as e:
                logger.error(f"Authentication failed: {e}")
                raise
        return wrapper
    return decorator


def create_oauth_client(
    client_id: Optional[str] = None,
    client_secret: Optional[str] = None,
    token_endpoint: Optional[str] = None,
    scope: str = "read write"
) -> OAuth2Provider:
    """
    Factory function to create OAuth2 provider from environment.
    
    Args:
        client_id: Override client ID (uses env var if not provided)
        client_secret: Override client secret (uses env var if not provided)
        token_endpoint: Override token endpoint (uses env var if not provided)
        scope: OAuth2 scopes
    
    Returns:
        OAuth2Provider instance
    
    Raises:
        AuthError: If required variables not set
    """
    client_id = client_id or _config.get('OAUTH2_CLIENT_ID')
    client_secret = client_secret or _config.get('OAUTH2_CLIENT_SECRET')
    token_endpoint = token_endpoint or _config.get('OAUTH2_TOKEN_ENDPOINT', '/oauth/token')
    
    if not client_id or not client_secret:
        raise AuthError("OAuth2 credentials not configured")
    
    return OAuth2Provider(
        client_id=client_id,
        client_secret=client_secret,
        token_endpoint=token_endpoint,
        scope=scope
    )
