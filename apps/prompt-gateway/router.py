import yaml
import logging
from typing import Dict, Any, Optional

# @file        apps/prompt-gateway/router.py
# @module      ai/routing
# @description Intent-based model router for Prompt Gateway

class ModelRouter:
    def __init__(self, router_config_path: str, registry_config_path: str):
        self.logger = logging.getLogger("model-router")
        with open(router_config_path, 'r') as f:
            self.router_config = yaml.safe_load(f)
        with open(registry_config_path, 'r') as f:
            self.registry_config = yaml.safe_load(f)

    def route_request(self, intent: str, token_count: int = 0) -> str:
        """
        Routes an incoming request to the preferred model based on intent and constraints.
        """
        for rule in self.router_config.get('routing_rules', []):
            if rule['intent'] == intent:
                if rule.get('min_tokens', 0) <= token_count <= rule.get('max_tokens', 999999):
                    preferred = rule['preferred_model']
                    if self._is_model_healthy(preferred):
                        self.logger.info(f"Routing intent '{intent}' to preferred model: {preferred}")
                        return preferred
                    
                    fallback = rule['fallback_model']
                    if self._is_model_healthy(fallback):
                        self.logger.warning(f"Preferred model {preferred} unhealthy. Falling back to {fallback}")
                        return fallback

        default = self.router_config.get('default_model', 'llama3:8b')
        self.logger.info(f"No intent match or unhealthy models. Using default: {default}")
        return default

    def _is_model_healthy(self, model_id: str) -> bool:
        """
        Check model health from registry (mock for MVP).
        """
        model = self.registry_config.get('models', {}).get(model_id)
        if not model:
            return False
            
        # Real implementation would check dynamic health state from Redis/HealthCheck service
        return True

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    router = ModelRouter('config/model-router.yaml', 'config/model-registry.yaml')
    
    print(f"Code Generation -> {router.route_request('code_generation')}")
    print(f"Complex Reasoning -> {router.route_request('complex_reasoning')}")
    print(f"Unknown Intent -> {router.route_request('unknown')}")
