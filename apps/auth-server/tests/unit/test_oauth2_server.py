"""
Unit Tests - OAuth2 Authorization Server
Issue #1545 Week 1 + Issue #1537 Integration
"""
import pytest
import json
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, MagicMock
import secrets
import base64
import hashlib

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Import the OAuth2 server
from src.oauth2_server import (
    app, OAuth2Server, KeyManager, OAuthConfig, TokenRequest,
    AuthorizationRequest, TokenResponse
)
from src.models import Base, OAuthProvider, OAuthConnection, AuthorizationCode, OAuthToken
from src.config import AuthServerConfig


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def test_config():
    """Test configuration"""
    return AuthServerConfig(
        SERVICE_PORT=8001,
        DEBUG=True,
        ENVIRONMENT="development",
        GITHUB_CLIENT_ID="test-github-id",
        GITHUB_CLIENT_SECRET="test-github-secret",
    )


@pytest.fixture
def oauth2_server():
    """OAuth2 Server instance"""
    server = OAuth2Server()
    
    # Register test providers
    server.register_provider(OAuthConfig(
        provider="github",
        client_id="test-github-id",
        client_secret="test-github-secret",
        auth_url="https://github.com/login/oauth/authorize",
        token_url="https://github.com/login/oauth/access_token",
        user_info_url="https://api.github.com/user",
        redirect_uri="http://localhost:3000/callback",
        scopes=["user:email", "read:user"],
    ))
    
    return server


@pytest.fixture
def client():
    """Test client"""
    return TestClient(app)


@pytest.fixture
def key_manager():
    """Key manager for JWT signing"""
    return KeyManager()


# ============================================================================
# OAuth2 Server Tests
# ============================================================================

class TestOAuth2Server:
    """Test OAuth2 Server functionality"""
    
    def test_server_initialization(self, oauth2_server):
        """Test OAuth2 server initialization"""
        assert oauth2_server is not None
        assert oauth2_server.key_manager is not None
        assert isinstance(oauth2_server.auth_codes, dict)
        assert isinstance(oauth2_server.sessions, dict)
    
    def test_register_provider(self, oauth2_server):
        """Test registering OAuth provider"""
        assert "github" in oauth2_server.providers
        assert oauth2_server.providers["github"].provider == "github"
        assert oauth2_server.providers["github"].client_id == "test-github-id"
    
    def test_authorization_code_generation(self, oauth2_server):
        """Test generating authorization code"""
        code = oauth2_server.generate_authorization_code(
            client_id="test-client",
            user_id="user-123",
            scope="openid profile email",
        )
        
        assert code is not None
        assert len(code) > 20
        assert code in oauth2_server.auth_codes
        
        # Verify stored code data
        stored = oauth2_server.auth_codes[code]
        assert stored["client_id"] == "test-client"
        assert stored["user_id"] == "user-123"
        assert stored["scope"] == "openid profile email"
        assert stored["is_used"] is False
    
    def test_authorization_code_expiry(self, oauth2_server):
        """Test authorization code expiry"""
        code = oauth2_server.generate_authorization_code(
            client_id="test-client",
            user_id="user-123",
            scope="openid profile email",
        )
        
        # Check expiry is set to 10 minutes
        stored = oauth2_server.auth_codes[code]
        expires_at = stored["expires_at"]
        now = datetime.utcnow()
        
        assert expires_at > now
        assert (expires_at - now).total_seconds() <= 600  # 10 minutes


class TestAccessTokenGeneration:
    """Test JWT access token generation"""
    
    def test_access_token_generation(self, oauth2_server):
        """Test generating access token"""
        token = oauth2_server.generate_access_token(
            user_id="user-123",
            email="user@example.com",
            org_id="org-123",
            teams=["team-1", "team-2"],
            permissions=["read", "write"],
        )
        
        assert token is not None
        assert isinstance(token, str)
        assert len(token) > 50
    
    def test_access_token_claims(self, oauth2_server):
        """Test access token contains correct claims"""
        token = oauth2_server.generate_access_token(
            user_id="user-123",
            email="user@example.com",
            org_id="org-123",
            teams=["team-1"],
            permissions=["read"],
            expires_in=900,
        )
        
        # Decode token (without verification for testing)
        import jwt
        payload = jwt.decode(token, options={"verify_signature": False})
        
        assert payload["sub"] == "user-123"
        assert payload["email"] == "user@example.com"
        assert payload["org_id"] == "org-123"
        assert payload["teams"] == ["team-1"]
        assert payload["permissions"] == ["read"]
        assert "iat" in payload
        assert "exp" in payload
        assert payload["iss"] == "https://auth.kushnir.cloud"
    
    def test_access_token_expiry(self, oauth2_server):
        """Test access token expiry"""
        expires_in = 1800  # 30 minutes
        token = oauth2_server.generate_access_token(
            user_id="user-123",
            email="user@example.com",
            org_id="org-123",
            teams=[],
            permissions=[],
            expires_in=expires_in,
        )
        
        import jwt
        payload = jwt.decode(token, options={"verify_signature": False})
        
        iat = payload["iat"]
        exp = payload["exp"]
        
        assert exp - iat == expires_in


class TestRefreshToken:
    """Test refresh token functionality"""
    
    def test_refresh_token_generation(self, oauth2_server):
        """Test generating refresh token"""
        token = oauth2_server.generate_refresh_token(
            user_id="user-123",
            client_id="client-123",
        )
        
        assert token is not None
        assert isinstance(token, str)
        assert len(token) > 50
        assert token in oauth2_server.sessions
    
    def test_refresh_token_expiry(self, oauth2_server):
        """Test refresh token expiry is set to 30 days"""
        token = oauth2_server.generate_refresh_token(
            user_id="user-123",
            client_id="client-123",
        )
        
        session = oauth2_server.sessions[token]
        expires_at = session["expires_at"]
        created_at = session["created_at"]
        
        delta = expires_at - created_at
        assert delta.days == 30


class TestAuthorizationCodeVerification:
    """Test authorization code verification"""
    
    def test_verify_valid_authorization_code(self, oauth2_server):
        """Test verifying valid authorization code"""
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
        )
        
        verified = oauth2_server.verify_authorization_code(
            code=code,
            client_id="client-123",
        )
        
        assert verified["client_id"] == "client-123"
        assert verified["user_id"] == "user-123"
        assert verified["scope"] == "openid profile"
        
        # Code should be deleted after use
        assert code not in oauth2_server.auth_codes
    
    def test_verify_invalid_authorization_code(self, oauth2_server):
        """Test verifying invalid authorization code raises error"""
        with pytest.raises(Exception):
            oauth2_server.verify_authorization_code(
                code="invalid-code",
                client_id="client-123",
            )
    
    def test_verify_code_client_id_mismatch(self, oauth2_server):
        """Test authorization code client_id mismatch raises error"""
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
        )
        
        with pytest.raises(Exception):
            oauth2_server.verify_authorization_code(
                code=code,
                client_id="different-client",
            )
    
    def test_verify_expired_authorization_code(self, oauth2_server):
        """Test verifying expired authorization code raises error"""
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
        )
        
        # Manually expire the code
        oauth2_server.auth_codes[code]["expires_at"] = datetime.utcnow() - timedelta(minutes=1)
        
        with pytest.raises(Exception):
            oauth2_server.verify_authorization_code(
                code=code,
                client_id="client-123",
            )


class TestPKCESupport:
    """Test PKCE (Proof Key for Public Clients) support"""
    
    def test_pkce_code_challenge_storage(self, oauth2_server):
        """Test storing code challenge for PKCE"""
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
            code_challenge="test-challenge",
        )
        
        stored = oauth2_server.auth_codes[code]
        assert stored["code_challenge"] == "test-challenge"
    
    def test_pkce_code_verifier_validation(self, oauth2_server):
        """Test validating PKCE code verifier"""
        # Generate code verifier and challenge
        code_verifier = secrets.token_urlsafe(32)
        code_challenge = base64.urlsafe_b64encode(
            hashlib.sha256(code_verifier.encode()).digest()
        ).decode().rstrip('=')
        
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
            code_challenge=code_challenge,
        )
        
        # Verify with correct verifier
        verified = oauth2_server.verify_authorization_code(
            code=code,
            client_id="client-123",
            code_verifier=code_verifier,
        )
        
        assert verified is not None
    
    def test_pkce_invalid_code_verifier(self, oauth2_server):
        """Test invalid PKCE code verifier raises error"""
        code_challenge = base64.urlsafe_b64encode(
            hashlib.sha256(b"original-verifier").digest()
        ).decode().rstrip('=')
        
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile",
            code_challenge=code_challenge,
        )
        
        # Try to verify with wrong verifier
        with pytest.raises(Exception):
            oauth2_server.verify_authorization_code(
                code=code,
                client_id="client-123",
                code_verifier="wrong-verifier",
            )


class TestKeyManagement:
    """Test JWT key management"""
    
    def test_key_generation(self, key_manager):
        """Test RSA key pair generation"""
        assert key_manager.private_key is not None
        assert key_manager.public_key is not None
    
    def test_jwks_format(self, key_manager):
        """Test JWKS (JSON Web Key Set) format"""
        jwks = key_manager.get_public_key_jwks()
        
        assert "keys" in jwks
        assert len(jwks["keys"]) > 0
        
        key = jwks["keys"][0]
        assert key["kty"] == "RSA"
        assert key["use"] == "sig"
        assert key["alg"] == "RS256"
        assert "n" in key
        assert "e" in key


# ============================================================================
# API Endpoint Tests
# ============================================================================

class TestAuthorizationEndpoint:
    """Test OAuth2 authorization endpoint"""
    
    def test_authorization_request(self, client):
        """Test authorization request"""
        response = client.get(
            "/oauth/authorize",
            params={
                "client_id": "test-client",
                "redirect_uri": "http://localhost:3000/callback",
                "response_type": "code",
                "scope": "openid profile email",
                "state": "test-state",
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "authorization_required"
        assert "auth_session_id" in data
    
    def test_authorization_unsupported_response_type(self, client):
        """Test unsupported response_type raises error"""
        response = client.get(
            "/oauth/authorize",
            params={
                "client_id": "test-client",
                "redirect_uri": "http://localhost:3000/callback",
                "response_type": "token",  # Unsupported
                "scope": "openid profile email",
                "state": "test-state",
            }
        )
        
        assert response.status_code == 400


class TestTokenEndpoint:
    """Test OAuth2 token endpoint"""
    
    def test_health_endpoint(self, client):
        """Test health check endpoint"""
        response = client.get("/health")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["service"] == "oauth2-authorization-server"
    
    def test_jwks_endpoint(self, client):
        """Test JWKS endpoint"""
        response = client.get("/.well-known/jwks.json")
        
        assert response.status_code == 200
        data = response.json()
        assert "keys" in data
        assert len(data["keys"]) > 0


# ============================================================================
# Integration Tests
# ============================================================================

class TestOAuthFlowIntegration:
    """Test complete OAuth2 flows"""
    
    def test_authorization_code_flow(self, oauth2_server):
        """Test complete authorization code flow"""
        # 1. Generate authorization code
        code = oauth2_server.generate_authorization_code(
            client_id="client-123",
            user_id="user-123",
            scope="openid profile email",
        )
        
        # 2. Exchange code for access token
        auth_code_data = oauth2_server.verify_authorization_code(
            code=code,
            client_id="client-123",
        )
        
        access_token = oauth2_server.generate_access_token(
            user_id=auth_code_data["user_id"],
            email="user@example.com",
            org_id="org-123",
            teams=["team-1"],
            permissions=["read", "write"],
        )
        
        # Verify token contains expected claims
        import jwt
        payload = jwt.decode(access_token, options={"verify_signature": False})
        
        assert payload["sub"] == "user-123"
        assert payload["email"] == "user@example.com"
    
    def test_refresh_token_flow(self, oauth2_server):
        """Test refresh token flow"""
        # 1. Generate refresh token
        refresh_token = oauth2_server.generate_refresh_token(
            user_id="user-123",
            client_id="client-123",
        )
        
        # 2. Use refresh token to get new access token
        session_data = oauth2_server.sessions[refresh_token]
        
        new_access_token = oauth2_server.generate_access_token(
            user_id=session_data["user_id"],
            email="user@example.com",
            org_id="org-123",
            teams=["team-1"],
            permissions=["read"],
        )
        
        assert new_access_token is not None
