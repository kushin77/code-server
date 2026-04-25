"""
@governance: Agent Runtime configuration — environment-driven, immutable, no hardcoding
@Purpose: Centralized config with readonly env-var pattern and sensible defaults
@Author: Autonomous Infrastructure
@Date: 2026-04-25
@Related issues: #1534 (IaC Governance), #1557 (Agent Runtime)

Configuration module for Agent Runtime following GOV-002 immutable infrastructure
principles. All configuration via environment variables with sensible defaults.
"""

import os
import logging
from typing import List, Optional, Dict, Any
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class AgentRuntimeConfig:
    """Immutable Agent Runtime configuration - all readonly fields"""
    
    # Service configuration (readonly, env-var driven)
    readonly_SERVICE_HOST: str
    readonly_SERVICE_PORT: int
    readonly_LOG_LEVEL: str
    
    # OIDC configuration
    readonly_OIDC_CLIENT_ID: str
    readonly_OIDC_CLIENT_SECRET: str
    readonly_OIDC_TOKEN_ENDPOINT: str
    readonly_OIDC_MAX_RETRIES: int
    
    # Paperclip approval gating
    readonly_PAPERCLIP_URL: str
    readonly_APPROVAL_TIMEOUT_SECONDS: int
    readonly_AUTO_APPROVE_LOW_RISK: bool
    
    # Resource constraints (per agent type)
    readonly_CODE_REVIEWER_TIMEOUT_SECONDS: int
    readonly_CODE_REVIEWER_MEMORY_MB: int
    readonly_CODE_REVIEWER_CPU_CORES: float
    
    readonly_INCIDENT_RESPONDER_TIMEOUT_SECONDS: int
    readonly_INCIDENT_RESPONDER_MEMORY_MB: int
    readonly_INCIDENT_RESPONDER_CPU_CORES: float
    
    readonly_DOC_WRITER_TIMEOUT_SECONDS: int
    readonly_DOC_WRITER_MEMORY_MB: int
    readonly_DOC_WRITER_CPU_CORES: float
    
    readonly_TEST_GENERATOR_TIMEOUT_SECONDS: int
    readonly_TEST_GENERATOR_MEMORY_MB: int
    readonly_TEST_GENERATOR_CPU_CORES: float
    
    # Audit logging
    readonly_AUDIT_LOG_ENABLED: bool
    readonly_AUDIT_LOG_DIR: str
    readonly_AUDIT_BUFFER_SIZE: int
    
    # Sandbox enforcement
    readonly_SANDBOX_ENFORCEMENT_ENABLED: bool
    readonly_NETWORK_EGRESS_ALLOWED: List[str]
    readonly_ALLOW_INTERNET_ACCESS: bool
    readonly_ALLOWED_FILESYSTEM_PATHS: List[str]
    
    # Deployment info (readonly)
    readonly_DEPLOYMENT_ENVIRONMENT: str
    readonly_DEPLOYMENT_REGION: str
    readonly_VERSION: str


def load_config_from_env() -> AgentRuntimeConfig:
    """Load configuration from environment variables with sensible defaults"""
    
    logger.info("Loading Agent Runtime configuration from environment...")
    
    # Helper to get env var with default and type conversion
    def get_env_str(key: str, default: str = "") -> str:
        return os.environ.get(key, default).strip()
    
    def get_env_int(key: str, default: int = 0) -> int:
        try:
            return int(os.environ.get(key, str(default)).strip())
        except ValueError:
            logger.warning(f"Invalid int for {key}, using default: {default}")
            return default
    
    def get_env_float(key: str, default: float = 0.0) -> float:
        try:
            return float(os.environ.get(key, str(default)).strip())
        except ValueError:
            logger.warning(f"Invalid float for {key}, using default: {default}")
            return default
    
    def get_env_bool(key: str, default: bool = False) -> bool:
        value = os.environ.get(key, str(default)).strip().lower()
        return value in ("true", "1", "yes", "on")
    
    def get_env_list(key: str, default: Optional[List[str]] = None) -> List[str]:
        if default is None:
            default = []
        value = os.environ.get(key, "")
        if not value:
            return default
        return [item.strip() for item in value.split(",") if item.strip()]
    
    # Load configuration
    config = AgentRuntimeConfig(
        # Service configuration
        readonly_SERVICE_HOST=get_env_str("AGENT_RUNTIME_HOST", "0.0.0.0"),
        readonly_SERVICE_PORT=get_env_int("AGENT_RUNTIME_PORT", 8020),
        readonly_LOG_LEVEL=get_env_str("LOG_LEVEL", "INFO"),
        
        # OIDC configuration
        readonly_OIDC_CLIENT_ID=get_env_str("OIDC_CLIENT_ID", "agent-runtime"),
        readonly_OIDC_CLIENT_SECRET=get_env_str(
            "OIDC_CLIENT_SECRET",
            os.environ.get("OIDC_CLIENT_SECRET_DEFAULT", "changeme")
        ),
        readonly_OIDC_TOKEN_ENDPOINT=get_env_str(
            "OIDC_TOKEN_ENDPOINT",
            "http://oauth2-proxy:4180/oauth2/token"
        ),
        readonly_OIDC_MAX_RETRIES=get_env_int("OIDC_MAX_RETRIES", 3),
        
        # Paperclip approval gating
        readonly_PAPERCLIP_URL=get_env_str(
            "PAPERCLIP_URL",
            "http://paperclip-control-plane:8010"
        ),
        readonly_APPROVAL_TIMEOUT_SECONDS=get_env_int("APPROVAL_TIMEOUT_SECONDS", 900),
        readonly_AUTO_APPROVE_LOW_RISK=get_env_bool("AUTO_APPROVE_LOW_RISK", True),
        
        # Code Reviewer sandbox constraints
        readonly_CODE_REVIEWER_TIMEOUT_SECONDS=get_env_int("CODE_REVIEWER_TIMEOUT_SECONDS", 600),
        readonly_CODE_REVIEWER_MEMORY_MB=get_env_int("CODE_REVIEWER_MEMORY_MB", 1024),
        readonly_CODE_REVIEWER_CPU_CORES=get_env_float("CODE_REVIEWER_CPU_CORES", 4.0),
        
        # Incident Responder sandbox constraints
        readonly_INCIDENT_RESPONDER_TIMEOUT_SECONDS=get_env_int("INCIDENT_RESPONDER_TIMEOUT_SECONDS", 300),
        readonly_INCIDENT_RESPONDER_MEMORY_MB=get_env_int("INCIDENT_RESPONDER_MEMORY_MB", 2048),
        readonly_INCIDENT_RESPONDER_CPU_CORES=get_env_float("INCIDENT_RESPONDER_CPU_CORES", 8.0),
        
        # Doc Writer sandbox constraints
        readonly_DOC_WRITER_TIMEOUT_SECONDS=get_env_int("DOC_WRITER_TIMEOUT_SECONDS", 180),
        readonly_DOC_WRITER_MEMORY_MB=get_env_int("DOC_WRITER_MEMORY_MB", 512),
        readonly_DOC_WRITER_CPU_CORES=get_env_float("DOC_WRITER_CPU_CORES", 2.0),
        
        # Test Generator sandbox constraints
        readonly_TEST_GENERATOR_TIMEOUT_SECONDS=get_env_int("TEST_GENERATOR_TIMEOUT_SECONDS", 300),
        readonly_TEST_GENERATOR_MEMORY_MB=get_env_int("TEST_GENERATOR_MEMORY_MB", 1024),
        readonly_TEST_GENERATOR_CPU_CORES=get_env_float("TEST_GENERATOR_CPU_CORES", 4.0),
        
        # Audit logging
        readonly_AUDIT_LOG_ENABLED=get_env_bool("AUDIT_LOG_ENABLED", True),
        readonly_AUDIT_LOG_DIR=get_env_str("AUDIT_LOG_DIR", "/var/log/agent-runtime/audit"),
        readonly_AUDIT_BUFFER_SIZE=get_env_int("AUDIT_BUFFER_SIZE", 10000),
        
        # Sandbox enforcement
        readonly_SANDBOX_ENFORCEMENT_ENABLED=get_env_bool("SANDBOX_ENFORCEMENT_ENABLED", True),
        readonly_NETWORK_EGRESS_ALLOWED=get_env_list(
            "NETWORK_EGRESS_ALLOWED",
            ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        ),
        readonly_ALLOW_INTERNET_ACCESS=get_env_bool("ALLOW_INTERNET_ACCESS", False),
        readonly_ALLOWED_FILESYSTEM_PATHS=get_env_list(
            "ALLOWED_FILESYSTEM_PATHS",
            ["/app", "/tmp", "/var/run"]
        ),
        
        # Deployment info
        readonly_DEPLOYMENT_ENVIRONMENT=get_env_str("DEPLOYMENT_ENVIRONMENT", "development"),
        readonly_DEPLOYMENT_REGION=get_env_str("DEPLOYMENT_REGION", "local"),
        readonly_VERSION=get_env_str("AGENT_RUNTIME_VERSION", "1.0.0"),
    )
    
    logger.info(
        f"Configuration loaded: "
        f"host={config.readonly_SERVICE_HOST}:{config.readonly_SERVICE_PORT}, "
        f"environment={config.readonly_DEPLOYMENT_ENVIRONMENT}, "
        f"audit_enabled={config.readonly_AUDIT_LOG_ENABLED}"
    )
    
    return config


# Global configuration instance (loaded at startup)
_config: Optional[AgentRuntimeConfig] = None


def get_config() -> AgentRuntimeConfig:
    """Get global configuration instance (lazy load)"""
    global _config
    if _config is None:
        _config = load_config_from_env()
    return _config


def set_config(config: AgentRuntimeConfig) -> None:
    """Set global configuration (primarily for testing)"""
    global _config
    _config = config


def get_agent_constraints(agent_type: str) -> Dict[str, Any]:
    """Get sandbox constraints for agent type"""
    config = get_config()
    
    constraints_map = {
        "code-reviewer": {
            "timeout_seconds": config.readonly_CODE_REVIEWER_TIMEOUT_SECONDS,
            "memory_mb": config.readonly_CODE_REVIEWER_MEMORY_MB,
            "cpu_cores": config.readonly_CODE_REVIEWER_CPU_CORES,
        },
        "incident-responder": {
            "timeout_seconds": config.readonly_INCIDENT_RESPONDER_TIMEOUT_SECONDS,
            "memory_mb": config.readonly_INCIDENT_RESPONDER_MEMORY_MB,
            "cpu_cores": config.readonly_INCIDENT_RESPONDER_CPU_CORES,
        },
        "doc-writer": {
            "timeout_seconds": config.readonly_DOC_WRITER_TIMEOUT_SECONDS,
            "memory_mb": config.readonly_DOC_WRITER_MEMORY_MB,
            "cpu_cores": config.readonly_DOC_WRITER_CPU_CORES,
        },
        "test-generator": {
            "timeout_seconds": config.readonly_TEST_GENERATOR_TIMEOUT_SECONDS,
            "memory_mb": config.readonly_TEST_GENERATOR_MEMORY_MB,
            "cpu_cores": config.readonly_TEST_GENERATOR_CPU_CORES,
        },
    }
    
    return constraints_map.get(agent_type, constraints_map["code-reviewer"])
