#!/usr/bin/env python3
# @file        apps/prompt-gateway/model_health.py
# @module      ai/health
# @description Model health check and monitoring - detects and removes unhealthy models
# @owner       ai/health
# @status      production-ready
#
# Periodically health checks all models and removes unhealthy ones from rotation

import asyncio
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, Set, Optional
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class ModelHealth:
    """Health status of a model"""
    model_id: str
    is_healthy: bool
    last_check: datetime = field(default_factory=datetime.utcnow)
    consecutive_failures: int = 0
    consecutive_successes: int = 0
    latency_ms: Optional[float] = None
    error_message: Optional[str] = None


class ModelHealthChecker:
    """Monitors model health and manages rotation"""
    
    def __init__(
        self,
        check_interval_seconds: int = 30,
        failure_threshold: int = 3,
        recovery_threshold: int = 2,
        unhealthy_timeout_seconds: int = 60,
    ):
        """
        Initialize health checker
        
        Args:
            check_interval_seconds: How often to check each model (default 30s)
            failure_threshold: Mark unhealthy after N consecutive failures
            recovery_threshold: Mark healthy after N consecutive successes
            unhealthy_timeout_seconds: How long before attempting recovery
        """
        self.check_interval_seconds = check_interval_seconds
        self.failure_threshold = failure_threshold
        self.recovery_threshold = recovery_threshold
        self.unhealthy_timeout_seconds = unhealthy_timeout_seconds
        
        self.health_status: Dict[str, ModelHealth] = {}
        self.is_checking = False
    
    async def start_health_checks(
        self,
        models: list,
        health_check_func,  # async function(model_id) -> bool
    ):
        """
        Start periodic health checks for all models
        
        Args:
            models: List of model IDs to monitor
            health_check_func: Async function that returns True if model is healthy
        """
        # Initialize health status for all models
        for model in models:
            self.health_status[model] = ModelHealth(model_id=model, is_healthy=True)
        
        self.is_checking = True
        logger.info(f"Starting health checks for {len(models)} models every {self.check_interval_seconds}s")
        
        # Run health check loop
        while self.is_checking:
            try:
                await self._perform_health_checks(models, health_check_func)
                await asyncio.sleep(self.check_interval_seconds)
            except Exception as e:
                logger.error(f"Health check loop error: {e}")
                await asyncio.sleep(self.check_interval_seconds)
    
    async def _perform_health_checks(
        self,
        models: list,
        health_check_func,
    ):
        """Perform health checks on all models"""
        tasks = [
            self._check_single_model(model, health_check_func)
            for model in models
        ]
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _check_single_model(
        self,
        model_id: str,
        health_check_func,
    ):
        """Check health of a single model"""
        current_status = self.health_status.get(model_id)
        if not current_status:
            current_status = ModelHealth(model_id=model_id, is_healthy=True)
            self.health_status[model_id] = current_status
        
        # Skip checks if model is unhealthy and within timeout
        if not current_status.is_healthy:
            elapsed = (datetime.utcnow() - current_status.last_check).total_seconds()
            if elapsed < self.unhealthy_timeout_seconds:
                logger.debug(f"Skipping {model_id} (unhealthy, {elapsed:.0f}s elapsed)")
                return
        
        try:
            start_time = time.time()
            is_healthy = await asyncio.wait_for(
                health_check_func(model_id),
                timeout=5.0,
            )
            latency = (time.time() - start_time) * 1000
            
            if is_healthy:
                current_status.consecutive_failures = 0
                current_status.consecutive_successes += 1
                current_status.latency_ms = latency
                current_status.error_message = None
                
                # Mark as recovered if threshold reached
                if current_status.consecutive_successes >= self.recovery_threshold:
                    if not current_status.is_healthy:
                        logger.warning(f"Model {model_id} RECOVERED (latency: {latency:.0f}ms)")
                        current_status.is_healthy = True
                        current_status.consecutive_successes = 0
            else:
                current_status.consecutive_successes = 0
                current_status.consecutive_failures += 1
                current_status.error_message = "Health check returned False"
                
                # Mark as unhealthy if threshold reached
                if current_status.consecutive_failures >= self.failure_threshold:
                    if current_status.is_healthy:
                        logger.error(f"Model {model_id} UNHEALTHY (failed {current_status.consecutive_failures} checks)")
                        current_status.is_healthy = False
                        current_status.consecutive_failures = 0
        
        except asyncio.TimeoutError:
            current_status.consecutive_successes = 0
            current_status.consecutive_failures += 1
            current_status.error_message = "Health check timeout"
            current_status.latency_ms = None
            
            if current_status.consecutive_failures >= self.failure_threshold:
                if current_status.is_healthy:
                    logger.error(f"Model {model_id} UNHEALTHY (timeout threshold reached)")
                    current_status.is_healthy = False
                    current_status.consecutive_failures = 0
        
        except Exception as e:
            current_status.consecutive_successes = 0
            current_status.consecutive_failures += 1
            current_status.error_message = str(e)
            current_status.latency_ms = None
            
            if current_status.consecutive_failures >= self.failure_threshold:
                if current_status.is_healthy:
                    logger.error(f"Model {model_id} UNHEALTHY (error: {e})")
                    current_status.is_healthy = False
                    current_status.consecutive_failures = 0
        
        current_status.last_check = datetime.utcnow()
    
    def get_healthy_models(self) -> Set[str]:
        """Get set of currently healthy models"""
        return {
            model_id
            for model_id, status in self.health_status.items()
            if status.is_healthy
        }
    
    def get_unhealthy_models(self) -> Set[str]:
        """Get set of currently unhealthy models"""
        return {
            model_id
            for model_id, status in self.health_status.items()
            if not status.is_healthy
        }
    
    def is_model_healthy(self, model_id: str) -> bool:
        """Check if a specific model is healthy"""
        return self.health_status.get(model_id, ModelHealth(model_id=model_id, is_healthy=False)).is_healthy
    
    def get_health_status(self) -> Dict[str, dict]:
        """Get full health status for all models"""
        return {
            model_id: {
                "is_healthy": status.is_healthy,
                "last_check": status.last_check.isoformat(),
                "consecutive_failures": status.consecutive_failures,
                "consecutive_successes": status.consecutive_successes,
                "latency_ms": status.latency_ms,
                "error": status.error_message,
            }
            for model_id, status in self.health_status.items()
        }
    
    def stop_checks(self):
        """Stop health check loop"""
        self.is_checking = False
        logger.info("Health checks stopped")
