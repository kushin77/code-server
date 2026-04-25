"""
OAuth2 Authorization Server Package
Issue #1545: Enterprise SSO Portal - Week 1
"""

__version__ = "0.1.0"
__author__ = "ElevatedIQ Team"
__description__ = "OAuth2 Authorization Server with JWT, PKCE, and multi-tenant support"

from src.oauth2_server import OAuth2Server, app
from src.config import AuthServerConfig, get_config, validate_config
from src.models import Base, OAuthProvider, OAuthConnection, AuthorizationCode, OAuthToken, OAuthClient

__all__ = [
    "OAuth2Server",
    "app",
    "AuthServerConfig",
    "get_config",
    "validate_config",
    "Base",
    "OAuthProvider",
    "OAuthConnection",
    "AuthorizationCode",
    "OAuthToken",
    "OAuthClient",
]
