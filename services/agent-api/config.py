from __future__ import annotations
from functools import lru_cache
from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")
    ollama_base_url: str = "http://ollama:11434"
    ollama_default_model: str = "qwen2.5-coder:14b-instruct-q6_K"
    ollama_fast_model: str = "qwen2.5-coder:7b-instruct-q8_0"
    keycloak_base_url: str = "http://keycloak:8080"
    keycloak_realm: str = "enterprise"
    introspection_client_id: str = "agent-api"
    introspection_client_secret: str = ""
    jwt_audience: str = "agent-api"
    chroma_host: str = "chroma"
    chroma_port: int = 8000
    backstage_mcp_url: str = "http://backstage:7007"
    computer_use_mcp_url: str = "http://computer-use-mcp:8008"
    agent_max_iterations: int = 10
    hitl_strict: bool = False
    cors_origins: List[str] = ["*"]
    dev_mode: bool = False

    @property
    def keycloak_realm_url(self) -> str:
        return f"{self.keycloak_base_url}/realms/{self.keycloak_realm}"

    @property
    def jwks_url(self) -> str:
        return f"{self.keycloak_realm_url}/protocol/openid-connect/certs"

    @property
    def introspection_url(self) -> str:
        return f"{self.keycloak_realm_url}/protocol/openid-connect/token/introspect"

@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
