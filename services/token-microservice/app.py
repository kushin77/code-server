#!/usr/bin/env python3
# services/token-microservice/app.py
# P1 #388 Phase 2: JWT Token Microservice
# Issues and validates JWT tokens for service-to-service authentication

from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime, timedelta, timezone
import jwt
import json
import logging
import sys
from typing import Dict, Tuple, Optional, Literal
import os
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import hashlib
from pydantic import BaseModel, ConfigDict, Field, ValidationError

class RuntimeConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    FLASK_DEBUG: bool = False
    TOKEN_TTL_MINUTES: int = Field(default=15, ge=1)
    REFRESH_WINDOW_MINUTES: int = Field(default=5, ge=0)
    OIDC_ISSUER: str = Field(default="https://oidc.kushnir.cloud", min_length=1)
    PLATFORM_NAME: str = Field(default="kushnir-platform", min_length=1)
    CODE_SERVER_SECRET: str = Field(min_length=1)
    POSTGRESQL_SECRET: str | None = None
    REDIS_SECRET: str | None = None
    GRAFANA_SECRET: str | None = None
    PROMETHEUS_SECRET: str | None = None
    OLLAMA_SECRET: str | None = None


class TokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    grant_type: Literal["client_credentials"]
    client_id: str = Field(min_length=1)
    client_secret: str = Field(min_length=1)
    scope: str = ""


class ValidateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=1)
    audience: str | None = None


class RevokeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=1)


def load_runtime_config() -> RuntimeConfig:
    raw_config = {
        field_name: os.getenv(field_name)
        for field_name in RuntimeConfig.model_fields
    }

    try:
        return RuntimeConfig.model_validate(raw_config)
    except ValidationError as error:
        print(f"Token microservice startup validation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


def parse_json_request(model_cls):
    payload = request.get_json(silent=True)

    if payload is None:
        return None, ({"error": "invalid_json"}, 400)

    try:
        return model_cls.model_validate(payload), None
    except ValidationError as error:
        logger.warning("Request validation failed for %s: %s", model_cls.__name__, error)
        return None, ({"error": "invalid_request"}, 400)


# Configuration defaults are overwritten with validated runtime values in main().
FLASK_DEBUG = False
TOKEN_TTL_MINUTES = 15
REFRESH_WINDOW_MINUTES = 5
OIDC_ISSUER = "https://oidc.kushnir.cloud"
PLATFORM_NAME = "kushnir-platform"

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Global state (would be in database for production)
_service_accounts: Dict[str, Dict] = {}
_revoked_tokens: set = set()

# ════════════════════════════════════════════════════════════════════════════
# Key Management
# ════════════════════════════════════════════════════════════════════════════

class KeyManager:
    """Manage RSA keys for JWT signing and verification"""
    
    def __init__(self):
        self.private_key = self._load_or_generate_private_key()
        self.public_key = self.private_key.public_key()
    
    def _load_or_generate_private_key(self):
        """Load existing key or generate new one"""
        key_file = "/etc/token-microservice/private.pem"
        
        if os.path.exists(key_file):
            with open(key_file, "rb") as f:
                return serialization.load_pem_private_key(
                    f.read(),
                    password=None,
                    backend=default_backend()
                )
        
        # Generate new RSA key (2048-bit)
        logger.warning("Generating new RSA key - this should only happen once!")
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
    
    def get_jwks(self) -> Dict:
        """Get JWKS (JSON Web Key Set) for public key verification"""
        public_pem = self.public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        
        # Extract key components for JWK format
        # (simplified - full implementation would use python-jose)
        return {
            "keys": [{
                "kty": "RSA",
                "use": "sig",
                "kid": hashlib.sha256(public_pem).hexdigest()[:8],
                "n": "...",  # Modulus
                "e": "AQAB"   # Exponent
            }]
        }

key_manager: KeyManager | None = None


def get_key_manager() -> KeyManager:
    if key_manager is None:
        raise RuntimeError("Token microservice key manager has not been initialized")

    return key_manager

# ════════════════════════════════════════════════════════════════════════════
# Service Account Management
# ════════════════════════════════════════════════════════════════════════════

def register_service_account(
    service_name: str,
    client_id: str,
    client_secret: str,
    scopes: list,
    allowed_targets: list
):
    """Register a service account for JWT token requests"""
    _service_accounts[client_id] = {
        "service_name": service_name,
        "client_id": client_id,
        "client_secret": hashlib.sha256(client_secret.encode()).hexdigest(),
        "scopes": scopes,
        "allowed_targets": allowed_targets,
        "created_at": datetime.now(timezone.utc).isoformat()
    }
    logger.info(f"Registered service account: {service_name}")

# ════════════════════════════════════════════════════════════════════════════
# JWT Operations
# ════════════════════════════════════════════════════════════════════════════

def create_jwt_token(client_id: str, scopes: list) -> str:
    """Create JWT token for service"""
    now = datetime.now(timezone.utc)
    exp = now + timedelta(minutes=TOKEN_TTL_MINUTES)
    
    token_data = {
        "iss": OIDC_ISSUER,
        "sub": client_id,
        "aud": PLATFORM_NAME,
        "scope": " ".join(scopes),
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "jti": hashlib.sha256(f"{client_id}{now}".encode()).hexdigest()[:16]
    }
    
    token = jwt.encode(
        token_data,
        get_key_manager().private_key,
        algorithm="RS256"
    )
    
    logger.info(f"Issued token for {client_id}: {token_data['jti']}")
    return token

def verify_jwt_token(token: str, audience: str) -> Optional[Dict]:
    """Verify and decode JWT token"""
    if token in _revoked_tokens:
        logger.warning("Token verification failed: token revoked")
        return None
    
    try:
        decoded = jwt.decode(
            token,
            get_key_manager().public_key,
            algorithms=["RS256"],
            audience=audience,
            issuer=OIDC_ISSUER
        )
        return decoded
    except jwt.ExpiredSignatureError:
        logger.warning("Token verification failed: token expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"Token verification failed: {e}")
        return None

# ════════════════════════════════════════════════════════════════════════════
# HTTP Endpoints
# ════════════════════════════════════════════════════════════════════════════

@app.route("/token", methods=["POST"])
def issue_token() -> Tuple[Dict, int]:
    """
    Issue JWT token using client credentials flow
    
    Request:
    {
        "grant_type": "client_credentials",
        "client_id": "code-server",
        "client_secret": "...",
        "scope": "read:secrets write:config"
    }
    
    Response:
    {
        "access_token": "eyJ...",
        "token_type": "Bearer",
        "expires_in": 900,
        "scope": "read:secrets write:config"
    }
    """
    data, error_response = parse_json_request(TokenRequest)
    if error_response:
        return error_response

    if data.grant_type != "client_credentials":
        return {"error": "unsupported_grant_type"}, 400

    client_id = data.client_id
    client_secret = data.client_secret
    scopes = data.scope.split()
    
    # Verify client credentials
    if client_id not in _service_accounts:
        logger.warning(f"Unknown service account: {client_id}")
        return {"error": "invalid_client"}, 401
    
    account = _service_accounts[client_id]
    secret_hash = hashlib.sha256(client_secret.encode()).hexdigest()
    
    if secret_hash != account["client_secret"]:
        logger.warning(f"Invalid credentials for {client_id}")
        return {"error": "invalid_client"}, 401
    
    # Create token
    token = create_jwt_token(client_id, scopes or account["scopes"])
    
    return {
        "access_token": token,
        "token_type": "Bearer",
        "expires_in": TOKEN_TTL_MINUTES * 60,
        "scope": " ".join(scopes or account["scopes"])
    }, 200

@app.route("/validate", methods=["POST"])
def validate_token() -> Tuple[Dict, int]:
    """
    Validate JWT token
    
    Request:
    {
        "token": "eyJ...",
        "audience": "kushnir-platform"
    }
    
    Response:
    {
        "valid": true,
        "claims": {...}
    }
    """
    data, error_response = parse_json_request(ValidateRequest)
    if error_response:
        return error_response

    token = data.token
    audience = data.audience or PLATFORM_NAME
    
    decoded = verify_jwt_token(token, audience)
    
    if decoded:
        return {
            "valid": True,
            "claims": decoded
        }, 200
    else:
        return {
            "valid": False,
            "error": "invalid_token"
        }, 401

@app.route("/jwks", methods=["GET"])
def get_jwks() -> Tuple[Dict, int]:
    """Get JWKS (JSON Web Key Set) for public key verification"""
    return get_key_manager().get_jwks(), 200

@app.route("/revoke", methods=["POST"])
def revoke_token() -> Tuple[Dict, int]:
    """
    Revoke JWT token (add to blacklist)
    
    Request:
    {
        "token": "eyJ..."
    }
    """
    data, error_response = parse_json_request(RevokeRequest)
    if error_response:
        return error_response

    token = data.token
    
    _revoked_tokens.add(token)
    logger.info(f"Revoked token: {token[:20]}...")
    
    return {"status": "revoked"}, 200

@app.route("/health", methods=["GET"])
def health_check() -> Tuple[Dict, int]:
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service_accounts": len(_service_accounts)
    }, 200

# ════════════════════════════════════════════════════════════════════════════
# Bootstrap
# ════════════════════════════════════════════════════════════════════════════

def apply_runtime_config(config: RuntimeConfig) -> None:
    global FLASK_DEBUG, TOKEN_TTL_MINUTES, REFRESH_WINDOW_MINUTES, OIDC_ISSUER, PLATFORM_NAME

    FLASK_DEBUG = config.FLASK_DEBUG
    TOKEN_TTL_MINUTES = config.TOKEN_TTL_MINUTES
    REFRESH_WINDOW_MINUTES = config.REFRESH_WINDOW_MINUTES
    OIDC_ISSUER = config.OIDC_ISSUER
    PLATFORM_NAME = config.PLATFORM_NAME


def bootstrap_service_accounts(config: RuntimeConfig):
    """Register known service accounts"""
    services = [
        ("code-server", "code-server", config.CODE_SERVER_SECRET,
         ["read:secrets", "write:config"], ["postgresql", "redis", "ollama"]),
        ("postgresql", "postgresql", config.POSTGRESQL_SECRET,
         ["read:pg_identity"], ["code-server", "grafana"]),
        ("redis", "redis", config.REDIS_SECRET,
         ["read:cache"], ["code-server"]),
        ("grafana", "grafana", config.GRAFANA_SECRET,
         ["read:metrics"], ["prometheus", "loki"]),
        ("prometheus", "prometheus", config.PROMETHEUS_SECRET,
         ["read:metrics"], ["code-server"]),
        ("ollama", "ollama", config.OLLAMA_SECRET,
         ["read:models"], ["code-server"]),
    ]
    
    for service_name, client_id, secret, scopes, targets in services:
        if secret:
            register_service_account(service_name, client_id, secret, scopes, targets)

if __name__ == "__main__":
    runtime_config = load_runtime_config()
    apply_runtime_config(runtime_config)
    key_manager = KeyManager()
    bootstrap_service_accounts(runtime_config)
    app.run(host="0.0.0.0", port=8888, debug=FLASK_DEBUG)
