import yaml
import logging
from typing import Dict, Any, List, Optional
import time

# @file        apps/prompt-gateway/fallback.py
# @module      ai/routing
# @description Health-aware model fallback handler for Prompt Gateway

class FallbackHandler:
    def __init__(self, registry_config_path: str):
        self.logger = logging.getLogger("fallback-handler")
        with open(registry_config_path, 'r') as f:
            self.registry_config = yaml.safe_load(f)
        
        # In-memory health status (should be in Redis for production)
        self.unhealthy_models = {} # model_id -> expiry_timestamp

    def get_alternative(self, model_id: str) -> Optional[str]:
        """
        Get the next available model in the fallback chain for a failed model.
        """
        model_meta = self.registry_config.get('models', {}).get(model_id)
        if not model_meta:
            return None

        chain = model_meta.get('fallback_chain', [])
        for alternative in chain:
            if self._is_healthy(alternative):
                self.logger.info(f"Fallback selected for {model_id}: {alternative}")
                return alternative
        
        return None

    def report_failure(self, model_id: str, duration_seconds: int = 300):
        """
        Mark a model as unhealthy for a duration.
        """
        self.logger.warning(f"Model failure reported: {model_id}. Cooling down for {duration_seconds}s")
        self.unhealthy_models[model_id] = time.time() + duration_seconds

    def _is_healthy(self, model_id: str) -> bool:
        """
        Check if model is currently healthy based on failure reports.
        """
        expiry = self.unhealthy_models.get(model_id)
        if expiry and time.time() < expiry:
            return False
        return True

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    handler = FallbackHandler('config/model-registry.yaml')
    
    # Test fallback chain for llama3:8b
    # According to model-registry.yaml, llama3:8b falls back to llama3:70b
    alt = handler.get_alternative('llama3:8b')
    print(f"Initial alternative for llama3:8b: {alt}")
    
    # Report failure and test again
    handler.report_failure('llama3:8b')
    alt = handler.get_alternative('llama3:8b')
    print(f"Alternative after failure: {alt}")
