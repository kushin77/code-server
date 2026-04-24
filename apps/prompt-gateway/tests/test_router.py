#!/usr/bin/env python3
# @file        apps/prompt-gateway/tests/test_router.py
# @module      ai/tests
# @description Unit tests for ModelRouter and routing logic
# @owner       ai/routing
# @status      production-ready

import asyncio
import pytest
from datetime import datetime

from router import ModelRouter, RoutingContext, RequestType, RoutingRule


@pytest.fixture
def model_registry():
    """Fixture: Model registry config"""
    return {
        "codellama:13b": {
            "capabilities": ["code_generation", "code_review"],
            "fallback_chain": ["llama3:8b", "mistral:7b"],
        },
        "llama3:70b": {
            "capabilities": ["reasoning", "summarization"],
            "fallback_chain": ["llama3:8b"],
        },
        "llama3:8b": {
            "capabilities": ["general", "code_review"],
            "fallback_chain": ["mistral:7b"],
        },
        "mistral:7b": {
            "capabilities": ["general", "summarization"],
            "fallback_chain": [],
        },
    }


@pytest.fixture
def router(model_registry):
    """Fixture: ModelRouter instance"""
    return ModelRouter(model_registry=model_registry)


class TestModelRouter:
    """Test ModelRouter"""
    
    def test_default_rules_initialized(self, router):
        """Test that default rules are initialized"""
        assert len(router.routing_rules) >= 6
        assert router.routing_rules[0].priority >= router.routing_rules[-1].priority
    
    def test_add_custom_rule(self, router):
        """Test adding custom routing rule"""
        initial_count = len(router.routing_rules)
        
        custom_rule = RoutingRule(
            priority=500,
            name="test_rule",
            conditions={"request_type": RequestType.SUMMARIZATION},
            target_model="llama3:8b",
        )
        router.add_routing_rule(custom_rule)
        
        assert len(router.routing_rules) == initial_count + 1
        assert custom_rule in router.routing_rules
    
    @pytest.mark.asyncio
    async def test_code_generation_routing(self, router):
        """Test code generation requests route to CodeLlama"""
        context = RoutingContext(
            request_type=RequestType.CODE_GENERATION,
            token_count=200,
            user_reputation_score=50,
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        assert model == "codellama:13b"
        assert fallback_chain == ["llama3:8b", "mistral:7b"]
    
    @pytest.mark.asyncio
    async def test_reasoning_routing_large_token(self, router):
        """Test reasoning with large token count routes to Llama3:70B"""
        context = RoutingContext(
            request_type=RequestType.REASONING,
            token_count=1000,
            user_reputation_score=60,
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        assert model == "llama3:70b"
    
    @pytest.mark.asyncio
    async def test_reasoning_routing_small_token(self, router):
        """Test reasoning with small token count routes to Llama3:8B"""
        context = RoutingContext(
            request_type=RequestType.REASONING,
            token_count=50,
            user_reputation_score=60,
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        # Should hit "low_tokens_fast_model" rule (priority 700)
        assert model == "mistral:7b"
    
    @pytest.mark.asyncio
    async def test_restricted_user_routing(self, router):
        """Test restricted users get fast model"""
        context = RoutingContext(
            request_type=RequestType.GENERAL,
            token_count=200,
            user_reputation_score=25,  # RESTRICTED tier
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        assert model == "mistral:7b"  # Fast model for restricted users
    
    @pytest.mark.asyncio
    async def test_elite_user_routing(self, router):
        """Test elite users get best model"""
        context = RoutingContext(
            request_type=RequestType.GENERAL,
            token_count=200,
            user_reputation_score=95,  # ELITE tier
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        assert model == "llama3:70b"  # Best model for elite users
    
    @pytest.mark.asyncio
    async def test_low_token_count_routing(self, router):
        """Test low token count routes to fast model"""
        context = RoutingContext(
            request_type=RequestType.GENERAL,
            token_count=50,  # Low tokens
            user_reputation_score=60,
            user_id="user123",
            session_id="session456",
        )
        
        model, fallback_chain = await router.select_model(context)
        
        assert model == "mistral:7b"  # Fast model
    
    def test_conditions_matching(self, router):
        """Test condition matching logic"""
        context = RoutingContext(
            request_type=RequestType.CODE_GENERATION,
            token_count=200,
            user_reputation_score=50,
            user_id="user123",
            session_id="session456",
        )
        
        # Exact match
        assert router._matches_conditions(context, {"request_type": RequestType.CODE_GENERATION})
        
        # No match
        assert not router._matches_conditions(context, {"request_type": RequestType.REASONING})
        
        # Token count range
        assert router._matches_conditions(context, {"token_count_min": 100, "token_count_max": 300})
        assert not router._matches_conditions(context, {"token_count_min": 300})
        
        # Reputation range
        assert router._matches_conditions(context, {"user_reputation_min": 40, "user_reputation_max": 60})
        assert not router._matches_conditions(context, {"user_reputation_min": 80})
    
    def test_model_capabilities(self, router):
        """Test getting model capabilities"""
        codellama_caps = router.get_model_capabilities("codellama:13b")
        assert "code_generation" in codellama_caps
        assert "code_review" in codellama_caps
        
        llama70b_caps = router.get_model_capabilities("llama3:70b")
        assert "reasoning" in llama70b_caps
        
        unknown_caps = router.get_model_capabilities("unknown:model")
        assert len(unknown_caps) == 0
    
    def test_model_availability(self, router):
        """Test model availability checking"""
        health_status = {
            "codellama:13b": True,
            "llama3:70b": False,
            "llama3:8b": True,
            "mistral:7b": True,
        }
        
        assert router.is_model_available("codellama:13b", health_status)
        assert not router.is_model_available("llama3:70b", health_status)
        assert router.is_model_available("llama3:8b", health_status)
    
    def test_routing_stats(self, router):
        """Test routing statistics"""
        stats = router.get_routing_stats()
        
        assert "total_rules" in stats
        assert stats["total_rules"] >= 6
        assert "active_ab_tests" in stats
        assert "fallback_count" in stats


class TestRequestTypeEnum:
    """Test RequestType enum"""
    
    def test_request_types_defined(self):
        """Test all request types are defined"""
        assert RequestType.CODE_GENERATION
        assert RequestType.CODE_REVIEW
        assert RequestType.SUMMARIZATION
        assert RequestType.REASONING
        assert RequestType.GENERAL


class TestRoutingContext:
    """Test RoutingContext dataclass"""
    
    def test_context_creation(self):
        """Test creating routing context"""
        context = RoutingContext(
            request_type=RequestType.CODE_GENERATION,
            token_count=500,
            user_reputation_score=75,
            user_id="user123",
            session_id="session456",
        )
        
        assert context.request_type == RequestType.CODE_GENERATION
        assert context.token_count == 500
        assert context.user_reputation_score == 75
        assert context.user_id == "user123"
        assert context.session_id == "session456"
        assert isinstance(context.timestamp, datetime)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
