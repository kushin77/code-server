"""
OAuth2 Authorization Server Configuration
Issue #1545: Enterprise SSO Portal
"""
import os
from typing import List, Optional
from pydantic_settings import BaseSettings
from pydantic import Field

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)


class AuthServerConfig(BaseSettings):
    """Auth Server Configuration (from environment)"""
    
    # Service Configuration
    SERVICE_NAME: str = "oauth2-auth-server"
    SERVICE_PORT: int = Field(default=8001, alias="AUTH_SERVER_PORT")
    SERVICE_HOST: str = Field(default="0.0.0.0", alias="AUTH_SERVER_HOST")
    DEBUG: bool = Field(default=False, alias="DEBUG")
    
    # Database Configuration
    DATABASE_URL: str = Field(
        default="postgresql://postgres:postgres@postgres:5432/elevatediq",
        alias="DATABASE_URL"
    )
    DATABASE_POOL_SIZE: int = 20
    DATABASE_ECHO: bool = Field(default=False, alias="DATABASE_ECHO")
    DATABASE_SSL_MODE: str = "disable"
    
    # Redis Configuration
    REDIS_URL: str = Field(
        default="redis://redis:6379/1",
        alias="REDIS_URL"
    )
    REDIS_TIMEOUT: int = 5
    
    # JWT Configuration
    JWT_ALGORITHM: str = "RS256"
    JWT_EXPIRY_SECONDS: int = 900  # 15 minutes
    JWT_REFRESH_EXPIRY_DAYS: int = 30
    JWT_ISSUER: str = "https://auth.kushnir.cloud"
    JWT_AUDIENCE: str = "https://api.kushnir.cloud"
    
    # OAuth Provider Secrets (loaded from environment)
    GITHUB_CLIENT_ID: Optional[str] = None
    GITHUB_CLIENT_SECRET: Optional[str] = None
    GOOGLE_CLIENT_ID: Optional[str] = None
    GOOGLE_CLIENT_SECRET: Optional[str] = None
    MICROSOFT_CLIENT_ID: Optional[str] = None
    MICROSOFT_CLIENT_SECRET: Optional[str] = None
    
    # CORS Configuration
    CORS_ORIGINS: List[str] = Field(
        default=[
            "https://kushnir.cloud",
            "https://app.kushnir.cloud",
            "http://localhost:3000",
            "http://localhost:8080",
        ],
        alias="CORS_ORIGINS"
    )
    
    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_REQUESTS: int = 100
    RATE_LIMIT_WINDOW_SECONDS: int = 60
    
    # Session Configuration
    SESSION_TIMEOUT_MINUTES: int = 1440  # 24 hours
    SESSION_SECURE: bool = True
    SESSION_SAME_SITE: str = "lax"
    SESSION_DOMAIN: str = ".kushnir.cloud"
    
    # Email Configuration (for user verification)
    EMAIL_ENABLED: bool = True
    EMAIL_PROVIDER: str = Field(default="sendgrid", alias="EMAIL_PROVIDER")
    SENDGRID_API_KEY: Optional[str] = None
    EMAIL_FROM_ADDRESS: str = "noreply@kushnir.cloud"
    EMAIL_FROM_NAME: str = "ElevatedIQ Auth"
    
    # Logging Configuration
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: str = "json"  # json or text
    
    # Feature Flags
    FEATURE_PKCE_REQUIRED: bool = True
    FEATURE_AUTO_PROVISION: bool = True
    FEATURE_MULTI_TENANT: bool = True
    
    # Environment
    ENVIRONMENT: str = Field(default="development", alias="ENVIRONMENT")
    DEPLOYMENT_ID: str = Field(default="local", alias="DEPLOYMENT_ID")
    
    class Config:
        env_file = ".env"
        case_sensitive = True
    
    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT in ["production", "prod"]
    
    @property
    def is_development(self) -> bool:
        return self.ENVIRONMENT in ["development", "dev", "local"]


# Singleton instance
_config: Optional[AuthServerConfig] = None


def get_config() -> AuthServerConfig:
    """Get configuration singleton"""
    global _config
    if _config is None:
        _config = AuthServerConfig()
    return _config


def validate_config() -> bool:
    """Validate configuration on startup"""
    config = get_config()
    
    errors = []
    
    # Required in production
    if config.is_production:
        if not config.JWT_ISSUER.startswith("https://"):
            errors.append("JWT_ISSUER must use HTTPS in production")
        
        if not config.SESSION_SECURE:
            errors.append("SESSION_SECURE must be True in production")
    
    # At least one provider configured
    providers_configured = sum([
        bool(config.GITHUB_CLIENT_ID),
        bool(config.GOOGLE_CLIENT_ID),
        bool(config.MICROSOFT_CLIENT_ID),
    ])
    
    if providers_configured == 0:
        errors.append("At least one OAuth provider must be configured")
    
    if errors:
        logger.info("Configuration Validation Errors:")
        for error in errors:
            logger.info(f"  ❌ {error}")
        return False
    
    logger.info("✅ Configuration validation passed")
    return True
