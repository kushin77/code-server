"""
OAuth2 Authorization Server - Week 1 Implementation
Issue #1545: Enterprise SSO Portal Architecture
"""
import os
from datetime import datetime, timedelta
from config import get_config
from log import get_logger
from exceptions import (
    InvalidToken, TokenExpired, AuthenticationFailure, MissingConfig
)
from typing import Optional, Dict, Any
import json
import secrets
import hashlib
import base64

from fastapi import FastAPI, HTTPException, Depends, Query, Request, Response
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel, Field, EmailStr

from src.request_logging import setup_request_logging
from src.audit_logging import setup_audit_logging
from src.email_service import setup_email_service
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend
import jwt


logger = get_logger(__name__)

# ============================================================================
# Data Models
# ============================================================================

class OAuthConfig(BaseModel):
    """OAuth2 Provider Configuration"""
    provider: str  # github, google, microsoft
    client_id: str
    client_secret: str
    auth_url: str
    token_url: str
    user_info_url: str
    redirect_uri: str
    scopes: list[str]


class AuthorizationRequest(BaseModel):
    """OAuth2 Authorization Request"""
    client_id: str
    redirect_uri: str
    response_type: str = "code"
    scope: str
    state: str
    code_challenge: Optional[str] = None  # PKCE
    code_challenge_method: Optional[str] = None


class TokenRequest(BaseModel):
    """OAuth2 Token Request"""
    grant_type: str  # authorization_code, refresh_token
    code: Optional[str] = None
    client_id: str
    client_secret: str
    redirect_uri: Optional[str] = None
    code_verifier: Optional[str] = None  # PKCE
    refresh_token: Optional[str] = None


class TokenResponse(BaseModel):
    """OAuth2 Token Response"""
    access_token: str
    token_type: str = "Bearer"
    expires_in: int = 900  # 15 minutes
    refresh_token: Optional[str] = None
    id_token: Optional[str] = None
    scope: str = ""


class UserInfo(BaseModel):
    """User Information from OAuth Provider"""
    id: str
    email: EmailStr
    name: str
    picture: Optional[str] = None
    locale: Optional[str] = None


# ============================================================================
# JWT Key Management
# ============================================================================

class KeyManager:
    """Manage RSA key pair for JWT signing"""
    
    def __init__(self):
        # In production, load from secure key store
        self.private_key = None
        self.public_key = None
        self._generate_keys()
    
    def _generate_keys(self):
        """Generate RSA key pair for JWT signing"""
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
        self.private_key = private_key
        self.public_key = private_key.public_key()
    
    def get_public_key_jwks(self) -> Dict[str, Any]:
        """Get public key in JWKS format for /.well-known/jwks.json"""
        public_numbers = self.public_key.public_numbers()
        
        return {
            "keys": [
                {
                    "kty": "RSA",
                    "use": "sig",
                    "kid": hashlib.sha256(str(public_numbers.n).encode()).hexdigest()[:8],
                    "n": base64.urlsafe_b64encode(
                        public_numbers.n.to_bytes(
                            (public_numbers.n.bit_length() + 7) // 8,
                            byteorder='big'
                        )
                    ).decode().rstrip('='),
                    "e": base64.urlsafe_b64encode(
                        public_numbers.e.to_bytes(
                            (public_numbers.e.bit_length() + 7) // 8,
                            byteorder='big'
                        )
                    ).decode().rstrip('='),
                    "alg": "RS256",
                }
            ]
        }


# ============================================================================
# OAuth2 Authorization Server
# ============================================================================

class OAuth2Server:
    """OAuth2 Authorization Server Implementation"""
    
    def __init__(self):
        self.key_manager = KeyManager()
        self.providers: Dict[str, OAuthConfig] = {}
        self.auth_codes: Dict[str, Dict[str, Any]] = {}  # In-memory store (use Redis in production)
        self.sessions: Dict[str, Dict[str, Any]] = {}
        
        # PKCE state tracking
        self.pkce_challenges: Dict[str, str] = {}
    
    def register_provider(self, config: OAuthConfig):
        """Register OAuth2 provider (GitHub, Google, Microsoft)"""
        self.providers[config.provider] = config
    
    def generate_authorization_code(
        self,
        client_id: str,
        user_id: str,
        scope: str,
        code_challenge: Optional[str] = None
    ) -> str:
        """Generate authorization code"""
        code = secrets.token_urlsafe(32)
        
        self.auth_codes[code] = {
            "client_id": client_id,
            "user_id": user_id,
            "scope": scope,
            "issued_at": datetime.utcnow(),
            "expires_at": datetime.utcnow() + timedelta(minutes=10),
            "code_challenge": code_challenge,
            "is_used": False,
        }
        
        return code
    
    def generate_access_token(
        self,
        user_id: str,
        email: str,
        org_id: str,
        teams: list[str],
        permissions: list[str],
        expires_in: int = 900  # 15 minutes
    ) -> str:
        """Generate JWT access token"""
        now = datetime.utcnow()
        
        payload = {
            "sub": user_id,
            "email": email,
            "org_id": org_id,
            "teams": teams,
            "permissions": permissions,
            "iat": now,
            "exp": now + timedelta(seconds=expires_in),
            "iss": "https://auth.kushnir.cloud",
            "aud": "https://api.kushnir.cloud",
        }
        
        token = jwt.encode(
            payload,
            self.key_manager.private_key,
            algorithm="RS256"
        )
        
        return token
    
    def generate_refresh_token(self, user_id: str, client_id: str) -> str:
        """Generate refresh token for long-term session"""
        token = secrets.token_urlsafe(64)
        
        # Store refresh token (in production, use Redis/database with expiry)
        self.sessions[token] = {
            "user_id": user_id,
            "client_id": client_id,
            "created_at": datetime.utcnow(),
            "expires_at": datetime.utcnow() + timedelta(days=30),
        }
        
        return token
    
    def verify_authorization_code(
        self,
        code: str,
        client_id: str,
        code_verifier: Optional[str] = None
    ) -> Dict[str, Any]:
        """Verify authorization code and return user info"""
        
        # Check code exists
        if code not in self.auth_codes:
            raise HTTPException(status_code=400, detail="Invalid authorization code")
        
        auth_code_data = self.auth_codes[code]

        if auth_code_data.get("is_used"):
            raise HTTPException(status_code=400, detail="Authorization code already used")
        
        # Check client_id matches
        if auth_code_data["client_id"] != client_id:
            raise HTTPException(status_code=400, detail="Client ID mismatch")
        
        # Check code not expired
        if datetime.utcnow() > auth_code_data["expires_at"]:
            del self.auth_codes[code]
            raise HTTPException(status_code=400, detail="Authorization code expired")
        
        # Verify PKCE code_verifier if code_challenge was used
        if auth_code_data["code_challenge"] and code_verifier:
            challenge = base64.urlsafe_b64encode(
                hashlib.sha256(code_verifier.encode()).digest()
            ).decode().rstrip('=')
            
            if challenge != auth_code_data["code_challenge"]:
                raise HTTPException(status_code=400, detail="Invalid code verifier")
        
        # Code verified, delete it (single-use)
                auth_code_data["is_used"] = True
        del self.auth_codes[code]
        
        return auth_code_data


        def register_default_oauth_providers(server: OAuth2Server, config) -> None:
            """Register OAuth providers from shared configuration values."""
            provider_specs = [
                {
                    "provider": "github",
                    "client_id_key": "GITHUB_CLIENT_ID",
                    "client_secret_key": "GITHUB_CLIENT_SECRET",
                    "auth_url": "https://github.com/login/oauth/authorize",
                    "token_url": "https://github.com/login/oauth/access_token",
                    "user_info_url": "https://api.github.com/user",
                    "redirect_uri": "https://auth.kushnir.cloud/oauth/github/callback",
                    "scopes": ["user:email", "read:user"],
                },
                {
                    "provider": "google",
                    "client_id_key": "GOOGLE_CLIENT_ID",
                    "client_secret_key": "GOOGLE_CLIENT_SECRET",
                    "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
                    "token_url": "https://oauth2.googleapis.com/token",
                    "user_info_url": "https://openidconnect.googleapis.com/v1/userinfo",
                    "redirect_uri": "https://auth.kushnir.cloud/oauth/google/callback",
                    "scopes": ["openid", "email", "profile"],
                },
                {
                    "provider": "microsoft",
                    "client_id_key": "MICROSOFT_CLIENT_ID",
                    "client_secret_key": "MICROSOFT_CLIENT_SECRET",
                    "auth_url": "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                    "token_url": "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                    "user_info_url": "https://graph.microsoft.com/v1.0/me",
                    "redirect_uri": "https://auth.kushnir.cloud/oauth/microsoft/callback",
                    "scopes": ["openid", "email", "profile", "User.Read"],
                },
            ]

            for spec in provider_specs:
                client_id = config.get(spec["client_id_key"], "")
                client_secret = config.get(spec["client_secret_key"], "")

                if not client_id or not client_secret:
                    logger.warning(
                        "Skipping OAuth provider %s because credentials are not configured",
                        spec["provider"],
                    )
                    continue

                server.register_provider(OAuthConfig(
                    provider=spec["provider"],
                    client_id=client_id,
                    client_secret=client_secret,
                    auth_url=spec["auth_url"],
                    token_url=spec["token_url"],
                    user_info_url=spec["user_info_url"],
                    redirect_uri=spec["redirect_uri"],
                    scopes=spec["scopes"],
                ))


# ============================================================================
# FastAPI Application
# ============================================================================

app = FastAPI(
    title="OAuth2 Authorization Server",
    description="Issue #1545 Week 1: Enterprise SSO Portal",
    version="0.1.0"
)

oauth2_server = OAuth2Server()

# Initialize config (SSOT from scripts/_common/config.env)
config = get_config(validate_required=False)

# Register providers from canonical shared config values.
register_default_oauth_providers(oauth2_server, config)

# Setup request logging and monitoring
setup_request_logging(app, config)

# Setup audit logging with retention policy
audit_service = setup_audit_logging(config)

# Setup email service with SendGrid
email_service = setup_email_service(config)


# ============================================================================
# OAuth2 Endpoints
# ============================================================================

@app.get("/oauth/authorize")
async def authorize(
    client_id: str = Query(...),
    redirect_uri: str = Query(...),
    response_type: str = Query("code"),
    scope: str = Query(""),
    state: str = Query(""),
    code_challenge: Optional[str] = Query(None),  # PKCE
    code_challenge_method: Optional[str] = Query(None),  # PKCE
):
    """
    OAuth2 Authorization Endpoint
    Redirects user to login page with authorization request
    """
    
    # Validate request
    if response_type != "code":
        raise HTTPException(
            status_code=400,
            detail="Only authorization_code flow supported"
        )
    
    # In production, validate redirect_uri against registered URIs
    
    # Redirect to login page with authorization request
    auth_request = AuthorizationRequest(
        client_id=client_id,
        redirect_uri=redirect_uri,
        response_type=response_type,
        scope=scope,
        state=state,
        code_challenge=code_challenge,
        code_challenge_method=code_challenge_method,
    )
    
    # Encode auth request in session (would use encrypted session cookie)
    auth_session_id = secrets.token_urlsafe(32)
    
    return {
        "status": "authorization_required",
        "auth_session_id": auth_session_id,
        "provider_options": list(oauth2_server.providers.keys()),
    }


@app.post("/oauth/token")
async def token(request: TokenRequest):
    """
    OAuth2 Token Endpoint
    Exchanges authorization code for access token
    """
    
    if request.grant_type == "authorization_code":
        if not request.code:
            raise HTTPException(
                status_code=400,
                detail="Authorization code required"
            )
        
        # Verify authorization code
        auth_code_data = oauth2_server.verify_authorization_code(
            code=request.code,
            client_id=request.client_id,
            code_verifier=request.code_verifier,
        )
        
        # Generate tokens
        access_token = oauth2_server.generate_access_token(
            user_id=auth_code_data["user_id"],
            email="user@example.com",  # Would come from user lookup
            org_id="org-123",  # Would come from user lookup
            teams=["team-1"],
            permissions=["read", "write"],
        )
        
        refresh_token = oauth2_server.generate_refresh_token(
            user_id=auth_code_data["user_id"],
            client_id=request.client_id,
        )
        
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=900,
            scope=auth_code_data["scope"],
        )
    
    elif request.grant_type == "refresh_token":
        if not request.refresh_token:
            raise HTTPException(
                status_code=400,
                detail="Refresh token required"
            )
        
        # Validate refresh token
        if request.refresh_token not in oauth2_server.sessions:
            raise HTTPException(
                status_code=400,
                detail="Invalid refresh token"
            )
        
        session_data = oauth2_server.sessions[request.refresh_token]
        
        # Generate new access token
        access_token = oauth2_server.generate_access_token(
            user_id=session_data["user_id"],
            email="user@example.com",
            org_id="org-123",
            teams=["team-1"],
            permissions=["read", "write"],
        )
        
        return TokenResponse(
            access_token=access_token,
            expires_in=900,
        )
    
    else:
        raise HTTPException(
            status_code=400,
            detail="Unsupported grant type"
        )


@app.get("/.well-known/jwks.json")
async def jwks():
    """
    JWKS Endpoint
    Returns public keys for JWT validation
    """
    return oauth2_server.key_manager.get_public_key_jwks()


@app.get("/oauth/{provider}/callback")
async def oauth_callback(
    provider: str,
    code: str,
    state: str,
):
    """
    OAuth2 Callback Endpoint
    Handles callback from external OAuth provider (GitHub, Google, etc.)
    """
    
    # Validate provider
    if provider not in oauth2_server.providers:
        raise HTTPException(
            status_code=400,
            detail="Invalid OAuth provider"
        )
    
    provider_config = oauth2_server.providers[provider]
    
    # Exchange provider's authorization code for access token
    # (In production, make actual HTTP request to provider's token endpoint)
    
    # Get user info from provider
    # (In production, make actual HTTP request to provider's userinfo endpoint)
    
    user_info = UserInfo(
        id=f"{provider}-user-123",
        email="user@example.com",
        name="Test User",
    )
    
    # Create or get user in database
    # (In production, perform database lookup/creation)
    
    # Generate authorization code for our app
    auth_code = oauth2_server.generate_authorization_code(
        client_id="elevatediq-app",
        user_id=user_info.id,
        scope="openid profile email",
    )
    
    # Redirect back to frontend with authorization code
    redirect_url = f"https://kushnir.cloud/auth/callback?code={auth_code}&state={state}"
    
    return RedirectResponse(url=redirect_url)


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "oauth2-authorization-server",
        "timestamp": datetime.utcnow().isoformat(),
    }


# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=config.get_int("API_PORT", 8001),
        log_level="info",
    )
