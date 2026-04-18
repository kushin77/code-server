"""
JWT Validator Library for Python Services
P1 #388 Phase 2: Service-to-Service Authentication

Usage:
  from lib.jwt_validator import JWTValidator
  validator = JWTValidator("https://token-microservice:8888")
  
  try:
    claims = validator.validate(token, audience="kushnir-platform")
    service_id = claims["sub"]
    scopes = claims["scope"].split()
  except JWTValidationError as e:
    # Handle invalid token
"""

import json
import requests
import jwt
import logging
from typing import Dict, Optional
from datetime import datetime, timedelta, timezone
import os

logger = logging.getLogger(__name__)

class JWTValidationError(Exception):
    """Raised when JWT validation fails"""
    pass

class JWTValidator:
    """Validate JWT tokens issued by token microservice"""
    
    def __init__(self, token_service_url: str = None, cache_ttl_seconds: int = 3600):
        """
        Initialize JWT validator
        
        Args:
            token_service_url: URL of token microservice (default from env)
            cache_ttl_seconds: How long to cache JWKS (default 1 hour)
        """
        self.token_service_url = token_service_url or os.getenv(
            "TOKEN_MICROSERVICE_URL", 
            "http://localhost:8888"
        )
        self.expected_issuer = os.getenv("TOKEN_EXPECTED_ISSUER", "")
        self.cache_ttl = cache_ttl_seconds
        self._jwks_cache: Optional[Dict] = None
        self._jwks_cache_time: Optional[datetime] = None
    
    def get_jwks(self, force_refresh: bool = False) -> Dict:
        """
        Get JWKS (JSON Web Key Set) from token microservice
        
        Args:
            force_refresh: Ignore cache and fetch fresh JWKS
        
        Returns:
            JWKS dictionary
        
        Raises:
            JWTValidationError: If unable to fetch JWKS
        """
        # Check cache
        if not force_refresh and self._jwks_cache:
            age = (datetime.now(timezone.utc) - self._jwks_cache_time).total_seconds()
            if age < self.cache_ttl:
                return self._jwks_cache
        
        # Fetch fresh JWKS
        try:
            response = requests.get(
                f"{self.token_service_url}/jwks",
                timeout=5
            )
            response.raise_for_status()
            jwks = response.json()
            
            # Cache it
            self._jwks_cache = jwks
            self._jwks_cache_time = datetime.now(timezone.utc)
            
            return jwks
        except Exception as e:
            logger.error(f"Failed to fetch JWKS: {e}")
            raise JWTValidationError(f"Unable to fetch JWKS: {e}")
    
    def validate(self, token: str, audience: str = "kushnir-platform") -> Dict:
        """
        Validate JWT token and return claims
        
        Args:
            token: JWT token to validate
            audience: Expected audience claim
        
        Returns:
            Dictionary of token claims
        
        Raises:
            JWTValidationError: If token is invalid
        """
        if not token:
            raise JWTValidationError("Token is empty")
        
        # Try local validation first (if we have JWKS cached)
        if self._jwks_cache:
            try:
                return self._local_validate(token, audience)
            except JWTValidationError as e:
                logger.debug(f"Local validation failed: {e}, trying remote")
        
        # Fall back to remote validation
        try:
            response = requests.post(
                f"{self.token_service_url}/validate",
                json={"token": token, "audience": audience},
                timeout=5
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get("valid"):
                    return data.get("claims", {})
            
            raise JWTValidationError(f"Remote validation failed: {response.text}")
        except Exception as e:
            logger.error(f"Remote validation error: {e}")
            raise JWTValidationError(f"Unable to validate token: {e}")
    
    def _local_validate(self, token: str, audience: str) -> Dict:
        """
        Validate JWT token locally using cached JWKS
        
        Args:
            token: JWT token
            audience: Expected audience
        
        Returns:
            Token claims
        
        Raises:
            JWTValidationError: If validation fails
        """
        try:
            # Decode without verification first to get kid
            header = jwt.get_unverified_header(token)
            kid = header.get("kid")
            
            # Get JWKS and find the key
            jwks = self.get_jwks()
            key = None
            for jwk in jwks.get("keys", []):
                if jwk.get("kid") == kid:
                    key = jwk
                    break
            
            if not key:
                raise JWTValidationError(f"Key not found: {kid}")
            
            signing_key = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key))
            decode_kwargs = {
                "key": signing_key,
                "algorithms": ["RS256"],
                "audience": audience,
                "options": {
                    "require": ["exp", "iat", "aud"]
                }
            }
            if self.expected_issuer:
                decode_kwargs["issuer"] = self.expected_issuer

            decoded = jwt.decode(token, **decode_kwargs)
            return decoded
        except JWTValidationError:
            raise
        except Exception as e:
            raise JWTValidationError(f"Local validation error: {e}")
    
    def should_refresh(self, token: str, refresh_window_minutes: int = 5) -> bool:
        """
        Check if token should be refreshed soon
        
        Args:
            token: JWT token to check
            refresh_window_minutes: Refresh if expiring within this many minutes
        
        Returns:
            True if token should be refreshed
        """
        try:
            decoded = jwt.decode(token, options={"verify_signature": False})
            exp = decoded.get("exp")
            
            if not exp:
                return False
            
            exp_time = datetime.fromtimestamp(exp, tz=timezone.utc)
            refresh_time = exp_time - timedelta(minutes=refresh_window_minutes)
            
            return datetime.now(timezone.utc) >= refresh_time
        except Exception as e:
            logger.warning(f"Error checking token refresh: {e}")
            return True

class TokenClient:
    """Client for requesting JWT tokens from token microservice"""
    
    def __init__(self, client_id: str, client_secret: str, 
                 token_service_url: str = None):
        """
        Initialize token client
        
        Args:
            client_id: Service client ID
            client_secret: Service client secret (from Vault)
            token_service_url: URL of token microservice
        """
        self.client_id = client_id
        self.client_secret = client_secret
        self.token_service_url = token_service_url or os.getenv(
            "TOKEN_MICROSERVICE_URL",
            "http://localhost:8888"
        )
        self._token: Optional[str] = None
        self._token_exp: Optional[datetime] = None
    
    def get_token(self, scopes: list = None, force_refresh: bool = False) -> str:
        """
        Get JWT token, requesting new one if expired
        
        Args:
            scopes: List of scopes to request
            force_refresh: Force new token request
        
        Returns:
            JWT token string
        
        Raises:
            JWTValidationError: If unable to get token
        """
        # Check if current token is still valid
        if not force_refresh and self._token and self._token_exp:
            if datetime.now(timezone.utc) < self._token_exp:
                return self._token
        
        # Request new token
        try:
            response = requests.post(
                f"{self.token_service_url}/token",
                json={
                    "grant_type": "client_credentials",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "scope": " ".join(scopes) if scopes else ""
                },
                timeout=5
            )
            response.raise_for_status()
            
            data = response.json()
            self._token = data["access_token"]
            
            # Calculate expiration with 1-minute buffer
            expires_in = data.get("expires_in", 900)
            self._token_exp = datetime.now(timezone.utc) + timedelta(seconds=expires_in - 60)
            
            logger.info(f"Obtained token for {self.client_id}")
            return self._token
        except Exception as e:
            logger.error(f"Failed to obtain token: {e}")
            raise JWTValidationError(f"Unable to obtain token: {e}")
    
    def get_auth_header(self) -> str:
        """Get Authorization header value with current token"""
        token = self.get_token()
        return f"Bearer {token}"
