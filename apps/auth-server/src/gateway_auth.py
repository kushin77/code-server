"""
API Gateway - OAuth Token Validation Middleware
Issue #1345 Week 5: API Gateway Integration
"""
import jwt
from datetime import datetime
from typing import Optional, Dict, Any
from log import get_logger

from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer

logger = get_logger(__name__)


# ============================================================================
# JWT Token Validation
# ============================================================================

class OAuth2TokenValidator:
    """Validate OAuth2 JWT tokens"""
    
    def __init__(self, config, cache=None):
        self.config = config
        self.cache = cache
    
    def validate_token(self, token: str) -> Dict[str, Any]:
        """Validate JWT token and return claims"""
        
        try:
            # Check if token is in blacklist (revoked)
            if self.cache:
                if self.cache.exists(f"blacklist:{token}"):
                    raise HTTPException(
                        status_code=401,
                        detail="Token has been revoked"
                    )
            
            # Get public key from JWKS cache
            public_key = self._get_public_key()
            
            # Verify and decode token
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=self.config.JWT_AUDIENCE,
                issuer=self.config.JWT_ISSUER,
            )
            
            # Check token expiry
            if payload.get("exp") and payload["exp"] < datetime.utcnow().timestamp():
                raise HTTPException(
                    status_code=401,
                    detail="Token has expired"
                )
            
            logger.info(f"Token validated for user {payload.get('sub')}")
            
            return payload
        
        except jwt.ExpiredSignatureError:
            raise HTTPException(
                status_code=401,
                detail="Token has expired"
            )
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {str(e)}")
            raise HTTPException(
                status_code=401,
                detail="Invalid token"
            )
    
    def get_current_user(self, token: str) -> Dict[str, Any]:
        """Get current user from token"""
        payload = self.validate_token(token)
        return {
            "user_id": payload.get("sub"),
            "email": payload.get("email"),
            "org_id": payload.get("org_id"),
            "teams": payload.get("teams", []),
            "permissions": payload.get("permissions", []),
            "roles": payload.get("roles", []),
        }
    
    def _get_public_key(self) -> str:
        """Get public key from JWKS endpoint"""
        # In production: fetch from /.well-known/jwks.json
        # Use cache to avoid repeated fetches
        # Rotate keys periodically
        return self.config.PUBLIC_KEY
    
    def verify_token_version(self, user_id: str, token_version: int) -> bool:
        """Verify token version hasn't been invalidated"""
        # In production: compare with stored token_version in User table
        # If user resets password or revokes all tokens, version increments
        return True


# ============================================================================
# FastAPI Dependency
# ============================================================================

async def get_current_user(
    request: Request,
    validator: OAuth2TokenValidator = Depends(lambda: None),  # Injected
) -> Dict[str, Any]:
    """FastAPI dependency to get current authenticated user"""
    
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid authorization header"
        )
    
    token = auth_header.split(" ")[1]
    return validator.get_current_user(token)


# ============================================================================
# Service-to-Service Authentication
# ============================================================================

class ServiceAuthenticator:
    """Authenticate service-to-service requests"""
    
    def __init__(self, config):
        self.config = config
    
    def generate_service_token(
        self,
        service_id: str,
        service_name: str,
        scopes: list,
    ) -> str:
        """Generate JWT token for service-to-service auth"""
        
        payload = {
            "iss": self.config.JWT_ISSUER,
            "sub": service_id,
            "service_name": service_name,
            "type": "service",
            "scopes": scopes,
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(hours=24),  # 24-hour expiry
        }
        
        token = jwt.encode(
            payload,
            self.config.PRIVATE_KEY,
            algorithm="RS256",
        )
        
        logger.info(f"Generated service token for {service_name}")
        
        return token
    
    def validate_service_token(self, token: str) -> Dict[str, Any]:
        """Validate service-to-service token"""
        
        try:
            payload = jwt.decode(
                token,
                self.config.PUBLIC_KEY,
                algorithms=["RS256"],
                issuer=self.config.JWT_ISSUER,
            )
            
            if payload.get("type") != "service":
                raise HTTPException(
                    status_code=403,
                    detail="Not a service token"
                )
            
            return payload
        
        except jwt.InvalidTokenError:
            raise HTTPException(
                status_code=403,
                detail="Invalid service token"
            )


# ============================================================================
# API Key Authentication
# ============================================================================

class APIKeyAuthenticator:
    """Manage API keys for programmatic access"""
    
    def __init__(self, db_session, config):
        self.db = db_session
        self.config = config
    
    def create_api_key(
        self,
        user_id: str,
        name: str,
        scopes: list,
        expires_in_days: int = 365,
    ) -> Dict[str, Any]:
        """Create new API key"""
        
        try:
            # Generate key (format: sk_live_xxxxx)
            key_prefix = f"sk_{'live' if not self.config.DEBUG else 'test'}"
            key_secret = secrets.token_urlsafe(32)
            key_full = f"{key_prefix}_{key_secret}"
            
            # Hash key for storage
            key_hash = self._hash_key(key_full)
            
            # Store in database
            api_key = self._create_api_key_record(
                user_id=user_id,
                name=name,
                key_hash=key_hash,
                scopes=scopes,
                expires_in_days=expires_in_days,
            )
            
            logger.info(f"Created API key '{name}' for user {user_id}")
            
            return {
                "key_id": str(api_key.id),
                "key": key_full,  # Only returned once!
                "name": name,
                "scopes": scopes,
                "message": "Save this key securely. You won't be able to see it again.",
            }
        
        except Exception as e:
            logger.error(f"Failed to create API key: {str(e)}")
            raise
    
    def authenticate_api_key(self, api_key: str) -> Dict[str, Any]:
        """Authenticate using API key"""
        
        try:
            # Extract key parts (sk_live_xxxxx)
            parts = api_key.split("_", 2)
            if len(parts) != 3 or parts[0] != "sk":
                raise ValueError("Invalid API key format")
            
            # Hash and lookup
            key_hash = self._hash_key(api_key)
            key_record = self._get_api_key_by_hash(key_hash)
            
            if not key_record:
                raise ValueError("API key not found or expired")
            
            # Check expiry
            if key_record.expires_at < datetime.utcnow():
                raise ValueError("API key has expired")
            
            # Update last used
            self._update_key_last_used(key_record.id)
            
            logger.info(f"API key authenticated for user {key_record.user_id}")
            
            return {
                "user_id": str(key_record.user_id),
                "scopes": key_record.scopes,
                "key_id": str(key_record.id),
            }
        
        except Exception as e:
            logger.error(f"API key authentication failed: {str(e)}")
            raise
    
    def list_api_keys(self, user_id: str) -> list:
        """List all API keys for user (without showing secrets)"""
        
        keys = self._get_user_api_keys(user_id)
        
        return [
            {
                "key_id": str(k.id),
                "name": k.name,
                "scopes": k.scopes,
                "created_at": k.created_at.isoformat(),
                "last_used": k.last_used.isoformat() if k.last_used else None,
                "expires_at": k.expires_at.isoformat(),
            }
            for k in keys
        ]
    
    def revoke_api_key(self, user_id: str, key_id: str) -> Dict[str, Any]:
        """Revoke API key"""
        
        key = self._get_api_key(key_id)
        if not key or str(key.user_id) != user_id:
            raise ValueError("API key not found")
        
        self._revoke_api_key(key_id)
        
        logger.info(f"Revoked API key {key_id} for user {user_id}")
        
        return {"status": "revoked", "key_id": key_id}
    
    # ====================================================================
    # Private Helpers
    # ====================================================================
    
    def _hash_key(self, key: str) -> str:
        """Hash API key for storage"""
        import hashlib
        return hashlib.sha256(key.encode()).hexdigest()
    
    def _create_api_key_record(self, **kwargs) -> Any:
        """Create API key record"""
        # In production: insert into APIKey table
        return type('APIKey', (), kwargs)()
    
    def _get_api_key_by_hash(self, key_hash: str) -> Optional[Any]:
        """Get API key by hash"""
        # In production: query APIKey where key_hash=?
        return None
    
    def _get_api_key(self, key_id: str) -> Optional[Any]:
        """Get API key by ID"""
        # In production: query APIKey where id=?
        return None
    
    def _get_user_api_keys(self, user_id: str) -> list:
        """Get all API keys for user"""
        # In production: query APIKey where user_id=? and revoked_at IS NULL
        return []
    
    def _update_key_last_used(self, key_id: str) -> None:
        """Update last used timestamp"""
        # In production: update APIKey set last_used=now() where id=?
        pass
    
    def _revoke_api_key(self, key_id: str) -> None:
        """Revoke API key"""
        # In production: update APIKey set revoked_at=now() where id=?
        pass


# ============================================================================
# Imports for time functions
# ============================================================================

from datetime import timedelta
import secrets
