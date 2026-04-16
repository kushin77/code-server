#!/usr/bin/env python3
"""
Google Secret Manager (GSM) Client
Purpose: Application-level secret retrieval with caching
Status: Production-ready for on-prem and cloud deployments
"""

import os
import json
import logging
from typing import Dict, Optional
from datetime import datetime, timedelta
from functools import lru_cache

try:
    from google.cloud import secretmanager
    HAS_GSM = True
except ImportError:
    HAS_GSM = False

logger = logging.getLogger(__name__)


class GSMClient:
    """Google Secret Manager client with caching"""
    
    def __init__(self, project_id: str = None, cache_ttl: int = 3600):
        """
        Initialize GSM client
        
        Args:
            project_id: GCP project ID (defaults to GCP_PROJECT_ID env var)
            cache_ttl: Cache time-to-live in seconds (default: 1 hour)
        """
        self.project_id = project_id or os.getenv("GCP_PROJECT_ID", "code-server-prod")
        self.cache_ttl = cache_ttl
        self.cache = {}
        self.cache_times = {}
        
        if not HAS_GSM:
            logger.warning("google-cloud-secret-manager not installed. "
                          "Falling back to environment variables.")
        else:
            try:
                self.client = secretmanager.SecretManagerServiceClient()
                logger.info(f"GSM Client initialized for project: {self.project_id}")
            except Exception as e:
                logger.error(f"Failed to initialize GSM client: {e}")
                self.client = None
    
    def get_secret(self, secret_name: str, fallback_env_var: str = None) -> str:
        """
        Get secret from GSM with fallback to environment variable
        
        Args:
            secret_name: Name of secret in GSM (e.g., "postgres-password")
            fallback_env_var: Environment variable name to check if GSM fails
        
        Returns:
            Secret value
        
        Raises:
            RuntimeError: If secret not found in GSM and no fallback provided
        """
        
        # Check cache first
        if self._is_cached(secret_name):
            logger.debug(f"Cache hit for secret: {secret_name}")
            return self.cache[secret_name]
        
        # Try GSM
        if self.client:
            try:
                secret_value = self._get_from_gsm(secret_name)
                self._cache_secret(secret_name, secret_value)
                return secret_value
            except Exception as e:
                logger.warning(f"Failed to get secret '{secret_name}' from GSM: {e}")
        
        # Fallback to environment variable
        if fallback_env_var:
            env_value = os.getenv(fallback_env_var)
            if env_value:
                logger.info(f"Using fallback environment variable: {fallback_env_var}")
                return env_value
        
        raise RuntimeError(
            f"Secret '{secret_name}' not found in GSM and no fallback provided"
        )
    
    def _get_from_gsm(self, secret_name: str) -> str:
        """Retrieve secret from GSM"""
        try:
            name = f"projects/{self.project_id}/secrets/{secret_name}/versions/latest"
            response = self.client.access_secret_version(request={"name": name})
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            raise RuntimeError(f"GSM access failed for '{secret_name}': {e}")
    
    def _is_cached(self, secret_name: str) -> bool:
        """Check if secret is in cache and not expired"""
        if secret_name not in self.cache:
            return False
        
        if secret_name not in self.cache_times:
            return False
        
        cache_time = self.cache_times[secret_name]
        if datetime.now() - cache_time > timedelta(seconds=self.cache_ttl):
            del self.cache[secret_name]
            del self.cache_times[secret_name]
            return False
        
        return True
    
    def _cache_secret(self, secret_name: str, value: str):
        """Cache a secret"""
        self.cache[secret_name] = value
        self.cache_times[secret_name] = datetime.now()
        logger.debug(f"Cached secret: {secret_name}")
    
    def clear_cache(self):
        """Clear the cache"""
        self.cache.clear()
        self.cache_times.clear()
        logger.info("Secret cache cleared")


# Global GSM client instance
_gsm_client = None


def get_gsm_client(project_id: str = None, cache_ttl: int = 3600) -> GSMClient:
    """Get or create global GSM client"""
    global _gsm_client
    
    if _gsm_client is None:
        _gsm_client = GSMClient(project_id=project_id, cache_ttl=cache_ttl)
    
    return _gsm_client


def get_secret(secret_name: str, fallback_env_var: str = None) -> str:
    """Convenience function to get secret"""
    client = get_gsm_client()
    return client.get_secret(secret_name, fallback_env_var)


# Example usage
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    
    # Example: Get database password
    try:
        db_password = get_secret(
            secret_name="postgres-password",
            fallback_env_var="POSTGRES_PASSWORD"
        )
        print(f"✓ Successfully retrieved database password")
    except RuntimeError as e:
        print(f"✗ Error: {e}")
