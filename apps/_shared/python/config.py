# Shared Configuration Loading Module
# ==============================================================================
# CANONICAL: All applications MUST use this module instead of direct os.getenv()
# This ensures configuration consistency and validation across the entire platform
# 
# Usage:
#   from apps._shared.python.config import Config, ConfigError
#   config = Config()
#   db_url = config.get('DATABASE_URL')
#   db_url_required = config.get_required('DATABASE_URL')
# ==============================================================================

import os
from typing import Optional, Dict, Any
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class Environment(Enum):
    """Deployment environment"""
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"


class ConfigError(Exception):
    """Configuration error"""
    pass


class Config:
    """
    Centralized configuration loader with validation and defaults.
    
    This class:
    1. Loads configuration from environment variables
    2. Provides type checking and validation
    3. Enforces required variables
    4. Gives clear error messages on missing config
    5. Supports defaults for optional values
    
    Replaces: 50+ individual os.getenv() calls scattered across apps
    """
    
    # Canonical environment variable names (SSOT)
    _REQUIRED_VARS = [
        'PRIMARY_HOST',
        'APEX_DOMAIN',
        'ADMIN_EMAIL',
        'POSTGRES_PASSWORD',
        'REDIS_PASSWORD',
    ]
    
    _OPTIONAL_VARS = {
        'ENVIRONMENT': Environment.DEVELOPMENT.value,
        'LOG_LEVEL': 'info',
        'API_HOST': 'localhost',
        'API_PORT': '8080',
        'PORT': '8000',
        'DATABASE_URL': None,
        'KAFKA_BROKER': 'localhost:9092',
        'KAFKA_BOOTSTRAP_SERVERS': 'localhost:9092',
        'OPA_URL': 'http://localhost:8181',
        'OAUTH2_INTROSPECT_URL': '',
        'OAUTH2_CLIENT_ID': '',
        'OAUTH2_CLIENT_SECRET': '',
        'OAUTH2_TOKEN_ENDPOINT': '/oauth/token',
        'SCHEDULER_API_KEY': None,
        'SCHEDULER_PORT': '8000',
        'REPUTATION_ENGINE_PORT': '8000',
        'POSTGRES_HOST': 'localhost',
        'POSTGRES_PORT': '5432',
        'REDIS_HOST': 'localhost',
        'REDIS_PORT': '6379',
        'QDRANT_HOST': 'localhost',
        'QDRANT_PORT': '6333',
        'GIT_BRANCH': 'main',
        'GITHUB_REPO': 'kushin77/code-server',
        'GITHUB_TOKEN': '',
    }
    
    def __init__(self, validate_required: bool = True):
        """
        Initialize config loader.
        
        Args:
            validate_required: If True, raises ConfigError on missing required vars
        """
        self._config: Dict[str, Any] = {}
        self._load_config()
        
        if validate_required:
            self._validate_required()
    
    def _load_config(self) -> None:
        """Load configuration from environment variables"""
        # Load optional variables with defaults
        for var, default in self._OPTIONAL_VARS.items():
            self._config[var] = os.getenv(var, default)
        
        # Load required variables (may be None, validation happens separately)
        for var in self._REQUIRED_VARS:
            self._config[var] = os.getenv(var)
    
    def _validate_required(self) -> None:
        """Validate all required variables are set"""
        missing = []
        for var in self._REQUIRED_VARS:
            if not self._config.get(var):
                missing.append(var)
        
        if missing:
            msg = f"Missing required configuration: {', '.join(missing)}"
            logger.error(msg)
            raise ConfigError(msg)
    
    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        """
        Get configuration value.
        
        Args:
            key: Configuration key
            default: Default value if not found
        
        Returns:
            Configuration value or default
        """
        return self._config.get(key, default)
    
    def get_required(self, key: str) -> str:
        """
        Get required configuration value.
        
        Args:
            key: Configuration key
        
        Returns:
            Configuration value
        
        Raises:
            ConfigError: If value not found
        """
        value = self._config.get(key)
        if not value:
            msg = f"Required configuration missing: {key}"
            logger.error(msg)
            raise ConfigError(msg)
        return value
    
    def get_bool(self, key: str, default: bool = False) -> bool:
        """
        Get boolean configuration value.
        
        Args:
            key: Configuration key
            default: Default value if not found
        
        Returns:
            Boolean value
        """
        value = self._config.get(key, str(default)).lower()
        return value in ('true', '1', 'yes', 'on')
    
    def get_int(self, key: str, default: Optional[int] = None) -> Optional[int]:
        """
        Get integer configuration value.
        
        Args:
            key: Configuration key
            default: Default value if not found
        
        Returns:
            Integer value or None
        """
        value = self._config.get(key)
        if value is None:
            return default
        try:
            return int(value)
        except ValueError:
            msg = f"Configuration {key} is not a valid integer: {value}"
            logger.error(msg)
            raise ConfigError(msg)
    
    def get_environment(self) -> Environment:
        """
        Get deployment environment.
        
        Returns:
            Environment enum value
        """
        env_str = self.get('ENVIRONMENT', Environment.DEVELOPMENT.value)
        try:
            return Environment(env_str)
        except ValueError:
            msg = f"Invalid environment: {env_str}"
            logger.error(msg)
            raise ConfigError(msg)
    
    @property
    def is_production(self) -> bool:
        """Check if running in production"""
        return self.get_environment() == Environment.PRODUCTION
    
    @property
    def is_development(self) -> bool:
        """Check if running in development"""
        return self.get_environment() == Environment.DEVELOPMENT
    
    def to_dict(self) -> Dict[str, Any]:
        """
        Export configuration as dictionary.
        
        Warning: This exposes sensitive values. Use with caution.
        
        Returns:
            Dictionary of all configuration
        """
        return self._config.copy()
    
    def __getitem__(self, key: str) -> Optional[str]:
        """Dictionary-style access to configuration"""
        return self._config.get(key)
    
    def __contains__(self, key: str) -> bool:
        """Check if configuration key exists"""
        return key in self._config


# Singleton instance for easy access
_config_instance: Optional[Config] = None


def get_config(validate_required: bool = True) -> Config:
    """
    Get or create singleton configuration instance.
    
    Args:
        validate_required: If True, validates required variables
    
    Returns:
        Config instance
    """
    global _config_instance
    if _config_instance is None:
        _config_instance = Config(validate_required=validate_required)
    return _config_instance


# Legacy compatibility - support the 50+ os.getenv calls gradually
def getenv_required(key: str) -> str:
    """
    Get required environment variable with validation.
    
    This is a migration helper to gradually replace os.getenv calls.
    
    Args:
        key: Variable name
    
    Returns:
        Variable value
    
    Raises:
        ConfigError: If variable not set
    """
    value = os.getenv(key)
    if not value:
        raise ConfigError(f"Required environment variable not set: {key}")
    return value


# Batch load multiple variables
def load_required_vars(*keys: str) -> Dict[str, str]:
    """
    Load multiple required variables.
    
    Usage:
        db_url, api_key = load_required_vars('DATABASE_URL', 'API_KEY').values()
    
    Args:
        keys: Variable names to load
    
    Returns:
        Dictionary of loaded variables
    
    Raises:
        ConfigError: If any variable not set
    """
    result = {}
    missing = []
    
    for key in keys:
        value = os.getenv(key)
        if not value:
            missing.append(key)
        else:
            result[key] = value
    
    if missing:
        raise ConfigError(f"Missing required variables: {', '.join(missing)}")
    
    return result
