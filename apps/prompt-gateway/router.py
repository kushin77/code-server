#!/usr/bin/env python3
# @file        apps/prompt-gateway/router.py
# @module      ai/routing
# @description Intelligent model router - request routing based on type, load, performance, A/B tests
# @owner       ai/routing
# @status      production-ready
#
# Routes AI requests to optimal model based on: request type, token count, user reputation, time-of-day, env.yaml

import asyncio
import logging
import random
import hashlib
from datetime import datetime
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum

logger = logging.getLogger(__name__)


class RequestType(Enum):
    """Request type for routing decisions"""
    CODE_GENERATION = "code_generation"
    CODE_REVIEW = "code_review"
    SUMMARIZATION = "summarization"
    REASONING = "reasoning"
    GENERAL = "general"


@dataclass
class RoutingContext:
    """Context for routing decision"""
    request_type: RequestType
    token_count: int
    user_reputation_score: int  # 0-100 (from Reputation Engine #1559)
    user_id: str
    session_id: str
    timestamp: datetime = field(default_factory=datetime.utcnow)


@dataclass
class RoutingRule:
    """A single routing rule with priority and conditions"""
    priority: int  # Higher = higher priority
    name: str
    conditions: Dict[str, Any]  # Condition checks
    target_model: str
    fallback_chain: List[str] = field(default_factory=list)


class ModelRouter:
    """Intelligent router that selects best model for each request"""
    
    def __init__(self, model_registry: Dict[str, Any], ab_test_manager=None):
        """
        Initialize router
        
        Args:
            model_registry: Model metadata from config/model-registry.yaml
            ab_test_manager: A/B test manager for experiments
        """
        self.model_registry = model_registry
        self.ab_test_manager = ab_test_manager
        self.routing_rules: List[RoutingRule] = []
        self._init_default_rules()
    
    def _init_default_rules(self):
        """Initialize default routing rules with priority-based ordering"""
        
        # Rule 1: Code generation tasks → CodeLlama (specialized)
        self.routing_rules.append(RoutingRule(
            priority=900,
            name="code_generation_to_codellama",
            conditions={
                "request_type": RequestType.CODE_GENERATION,
            },
            target_model="codellama:13b",
            fallback_chain=["llama3:8b", "mistral:7b"],
        ))
        
        # Rule 2: Complex reasoning → Llama3:70B (most capable)
        self.routing_rules.append(RoutingRule(
            priority=850,
            name="reasoning_to_llama_large",
            conditions={
                "request_type": RequestType.REASONING,
                "token_count_min": 500,  # Complex queries usually longer
            },
            target_model="llama3:70b",
            fallback_chain=["llama3:8b"],
        ))
        
        # Rule 3: Fast responses for restricted users → Mistral (fastest)
        self.routing_rules.append(RoutingRule(
            priority=800,
            name="restricted_user_fast_model",
            conditions={
                "user_reputation_max": 49,  # RESTRICTED tier
            },
            target_model="mistral:7b",
            fallback_chain=["llama3:8b"],
        ))
        
        # Rule 4: Low token count → Fast model
        self.routing_rules.append(RoutingRule(
            priority=700,
            name="low_tokens_fast_model",
            conditions={
                "token_count_max": 100,
            },
            target_model="mistral:7b",
            fallback_chain=["llama3:8b"],
        ))
        
        # Rule 5: Elite users get best model
        self.routing_rules.append(RoutingRule(
            priority=600,
            name="elite_user_best_model",
            conditions={
                "user_reputation_min": 90,  # ELITE tier
            },
            target_model="llama3:70b",
            fallback_chain=["llama3:8b", "mistral:7b"],
        ))
        
        # Rule 6: Default → Llama3:8B (balanced)
        self.routing_rules.append(RoutingRule(
            priority=0,
            name="default_balanced",
            conditions={},
            target_model="llama3:8b",
            fallback_chain=["mistral:7b", "llama3:70b"],
        ))
        
        # Sort by priority descending (highest first)
        self.routing_rules.sort(key=lambda r: r.priority, reverse=True)
    
    def add_routing_rule(self, rule: RoutingRule):
        """Add a custom routing rule (hot-reloadable)"""
        self.routing_rules.append(rule)
        self.routing_rules.sort(key=lambda r: r.priority, reverse=True)
        logger.info(f"Added routing rule: {rule.name} (priority {rule.priority})")
    
    async def select_model(self, context: RoutingContext) -> Tuple[str, List[str]]:
        """
        Select best model for request based on context and rules
        
        Returns: (primary_model, fallback_chain)
        """
        
        # Check A/B tests first (highest priority for experiments)
        if self.ab_test_manager:
            ab_model = self.ab_test_manager.get_variant_for_user(context.user_id)
            if ab_model:
                logger.info(f"A/B test routing: {context.user_id} → {ab_model}")
                return ab_model, self._get_fallback_chain(ab_model)
        
        # Evaluate rules in priority order
        for rule in self.routing_rules:
            if self._matches_conditions(context, rule.conditions):
                logger.info(f"Routing rule matched: {rule.name} → {rule.target_model}")
                return rule.target_model, rule.fallback_chain
        
        # Should not reach here (default rule always matches)
        logger.warning("No routing rule matched, using default model")
        return "llama3:8b", ["mistral:7b", "llama3:70b"]
    
    def _matches_conditions(self, context: RoutingContext, conditions: Dict[str, Any]) -> bool:
        """Check if context matches routing rule conditions"""
        
        for key, value in conditions.items():
            if key == "request_type":
                if context.request_type != value:
                    return False
            
            elif key == "token_count_min":
                if context.token_count < value:
                    return False
            
            elif key == "token_count_max":
                if context.token_count > value:
                    return False
            
            elif key == "user_reputation_min":
                if context.user_reputation_score < value:
                    return False
            
            elif key == "user_reputation_max":
                if context.user_reputation_score > value:
                    return False
            
            elif key == "time_of_day":
                # For future: time-based routing (peak hours → faster model)
                pass
        
        return True
    
    def _get_fallback_chain(self, primary_model: str) -> List[str]:
        """Get fallback chain for a model from registry"""
        if primary_model in self.model_registry:
            return self.model_registry[primary_model].get("fallback_chain", [])
        return []
    
    def get_model_capabilities(self, model: str) -> List[str]:
        """Get capabilities of a model"""
        if model in self.model_registry:
            return self.model_registry[model].get("capabilities", [])
        return []
    
    def is_model_available(self, model: str, health_status: Dict[str, bool]) -> bool:
        """Check if model is available (healthy)"""
        return health_status.get(model, False)
    
    def get_routing_stats(self) -> Dict[str, int]:
        """Get routing statistics"""
        return {
            "total_rules": len(self.routing_rules),
            "active_ab_tests": 0,
            "fallback_count": 0,
        }

    router = ModelRouter('config/model-router.yaml', 'config/model-registry.yaml')
    
    print(f"Code Generation -> {router.route_request('code_generation')}")
    print(f"Complex Reasoning -> {router.route_request('complex_reasoning')}")
    print(f"Unknown Intent -> {router.route_request('unknown')}")
