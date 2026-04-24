#!/usr/bin/env python3
# @file        apps/prompt-gateway/fallback.py
# @module      ai/fallback
# @description Fallback chain handler - routes through multiple models on timeout/error
# @owner       ai/fallback
# @status      production-ready
#
# Implements automatic fallback to secondary models on timeout, error, or degradation

import asyncio
import logging
import time
from typing import List, Optional, Dict, Any, Tuple
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class FallbackConfig:
    """Configuration for a fallback chain"""
    primary_model: str
    chain: List[str]  # Ordered list of fallback models
    timeout_ms: int = 30000  # Timeout per model attempt
    max_retries: int = 3
    backoff_ms: int = 500


class FallbackHandler:
    """Handles fallback routing when primary model fails"""
    
    def __init__(self):
        self.fallback_configs: Dict[str, FallbackConfig] = {}
        self.metrics = {
            "fallback_total": 0,
            "fallback_by_reason": {},
        }
    
    def register_fallback_chain(self, config: FallbackConfig):
        """Register a fallback chain for a model"""
        self.fallback_configs[config.primary_model] = config
        logger.info(f"Registered fallback chain for {config.primary_model}: {config.chain}")
    
    async def forward_with_fallback(
        self,
        prompt: str,
        primary_model: str,
        forward_func,  # async function(model, prompt) -> response
        fallback_chain: Optional[List[str]] = None,
        timeout_ms: int = 30000,
    ) -> Tuple[str, str, bool]:  # (model_used, response, is_fallback)
        """
        Forward request through primary + fallback chain on failures
        
        Args:
            prompt: Request text
            primary_model: Primary model to try first
            forward_func: Async function to call Ollama
            fallback_chain: Models to try if primary fails
            timeout_ms: Timeout per attempt
        
        Returns: (model_used, response, is_fallback)
        """
        if fallback_chain is None:
            fallback_chain = self.fallback_configs.get(primary_model, FallbackConfig(
                primary_model=primary_model,
                chain=[]
            )).chain
        
        models_to_try = [primary_model] + fallback_chain
        last_error = None
        
        for attempt, model in enumerate(models_to_try):
            try:
                logger.info(f"Attempting {model} (attempt {attempt + 1}/{len(models_to_try)})")
                
                response = await asyncio.wait_for(
                    forward_func(model, prompt),
                    timeout=timeout_ms / 1000.0,
                )
                
                if attempt > 0:
                    # Fallback was used
                    self._record_fallback(primary_model, model, "success")
                    logger.info(f"Fallback succeeded on {model}")
                    return model, response, True
                else:
                    # Primary model worked
                    logger.info(f"Primary model {model} succeeded")
                    return model, response, False
            
            except asyncio.TimeoutError:
                last_error = f"Timeout after {timeout_ms}ms"
                logger.warning(f"Model {model} timeout: {last_error}")
                self._record_fallback(primary_model, model, "timeout")
                
                if attempt < len(models_to_try) - 1:
                    await asyncio.sleep(0.5)  # Brief delay before next attempt
                    continue
            
            except Exception as e:
                last_error = str(e)
                logger.warning(f"Model {model} error: {e}")
                self._record_fallback(primary_model, model, "error")
                
                if attempt < len(models_to_try) - 1:
                    await asyncio.sleep(0.5)
                    continue
        
        # All models failed
        error_msg = f"All models failed. Last error: {last_error}"
        logger.error(error_msg)
        raise Exception(error_msg)
    
    def _record_fallback(self, from_model: str, to_model: str, reason: str):
        """Record fallback event for metrics"""
        self.metrics["fallback_total"] += 1
        
        key = f"{from_model}→{to_model}:{reason}"
        self.metrics["fallback_by_reason"][key] = self.metrics["fallback_by_reason"].get(key, 0) + 1
        
        logger.info(f"Fallback recorded: {from_model} → {to_model} ({reason})")
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get fallback metrics for monitoring"""
        return {
            "total_fallbacks": self.metrics["fallback_total"],
            "by_reason": self.metrics["fallback_by_reason"],
        }
    
    async def health_check_fallback_chain(
        self,
        models: List[str],
        health_check_func,  # async function(model) -> bool
    ) -> Dict[str, bool]:
        """
        Health check all models in a chain
        
        Returns: {model: is_healthy}
        """
        health_status = {}
        
        for model in models:
            try:
                is_healthy = await asyncio.wait_for(
                    health_check_func(model),
                    timeout=5.0,
                )
                health_status[model] = is_healthy
                logger.info(f"Health check {model}: {'healthy' if is_healthy else 'unhealthy'}")
            except Exception as e:
                logger.warning(f"Health check failed for {model}: {e}")
                health_status[model] = False
        
        return health_status
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
