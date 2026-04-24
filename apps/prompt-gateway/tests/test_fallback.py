#!/usr/bin/env python3
# @file        apps/prompt-gateway/tests/test_fallback.py
# @module      ai/tests
# @description Unit tests for FallbackHandler and fallback routing
# @owner       ai/fallback
# @status      production-ready

import asyncio
import pytest

from fallback import FallbackHandler, FallbackConfig


@pytest.fixture
def fallback_handler():
    """Fixture: FallbackHandler instance"""
    return FallbackHandler()


@pytest.fixture
def sample_config():
    """Fixture: Sample fallback config"""
    return FallbackConfig(
        primary_model="llama3:70b",
        chain=["llama3:8b", "mistral:7b"],
        timeout_ms=30000,
        max_retries=3,
    )


class TestFallbackHandler:
    """Test FallbackHandler"""
    
    def test_register_fallback_chain(self, fallback_handler, sample_config):
        """Test registering fallback chain"""
        fallback_handler.register_fallback_chain(sample_config)
        
        assert "llama3:70b" in fallback_handler.fallback_configs
        registered = fallback_handler.fallback_configs["llama3:70b"]
        assert registered.chain == ["llama3:8b", "mistral:7b"]
    
    def test_get_fallback_metrics(self, fallback_handler):
        """Test getting fallback metrics"""
        metrics = fallback_handler.get_metrics()
        
        assert "total_fallbacks" in metrics
        assert "by_reason" in metrics
        assert metrics["total_fallbacks"] == 0
    
    @pytest.mark.asyncio
    async def test_forward_with_primary_success(self, fallback_handler):
        """Test forward succeeds on primary model"""
        async def mock_forward(model, prompt):
            if model == "llama3:70b":
                return "Success response"
            raise Exception(f"Model {model} failed")
        
        model, response, is_fallback = await fallback_handler.forward_with_fallback(
            prompt="Test prompt",
            primary_model="llama3:70b",
            forward_func=mock_forward,
            fallback_chain=["llama3:8b"],
            timeout_ms=1000,
        )
        
        assert model == "llama3:70b"
        assert response == "Success response"
        assert not is_fallback
    
    @pytest.mark.asyncio
    async def test_forward_with_fallback_success(self, fallback_handler):
        """Test fallback succeeds when primary fails"""
        async def mock_forward(model, prompt):
            if model == "llama3:70b":
                raise Exception("Primary failed")
            elif model == "llama3:8b":
                return "Fallback response"
            raise Exception(f"Model {model} failed")
        
        model, response, is_fallback = await fallback_handler.forward_with_fallback(
            prompt="Test prompt",
            primary_model="llama3:70b",
            forward_func=mock_forward,
            fallback_chain=["llama3:8b", "mistral:7b"],
            timeout_ms=1000,
        )
        
        assert model == "llama3:8b"
        assert response == "Fallback response"
        assert is_fallback
    
    @pytest.mark.asyncio
    async def test_forward_with_timeout_fallback(self, fallback_handler):
        """Test fallback on timeout"""
        async def mock_forward(model, prompt):
            if model == "llama3:70b":
                await asyncio.sleep(10)  # Simulate timeout
            elif model == "llama3:8b":
                return "Fallback after timeout"
            raise Exception(f"Model {model} failed")
        
        model, response, is_fallback = await fallback_handler.forward_with_fallback(
            prompt="Test prompt",
            primary_model="llama3:70b",
            forward_func=mock_forward,
            fallback_chain=["llama3:8b"],
            timeout_ms=100,  # Low timeout to trigger timeout
        )
        
        assert model == "llama3:8b"
        assert is_fallback
    
    @pytest.mark.asyncio
    async def test_forward_all_models_fail(self, fallback_handler):
        """Test exception when all models fail"""
        async def mock_forward(model, prompt):
            raise Exception(f"Model {model} failed")
        
        with pytest.raises(Exception, match="All models failed"):
            await fallback_handler.forward_with_fallback(
                prompt="Test prompt",
                primary_model="llama3:70b",
                forward_func=mock_forward,
                fallback_chain=["llama3:8b"],
                timeout_ms=1000,
            )
    
    @pytest.mark.asyncio
    async def test_record_fallback_metrics(self, fallback_handler):
        """Test fallback metrics recording"""
        fallback_handler._record_fallback("llama3:70b", "llama3:8b", "timeout")
        fallback_handler._record_fallback("llama3:70b", "llama3:8b", "timeout")
        fallback_handler._record_fallback("llama3:70b", "mistral:7b", "error")
        
        metrics = fallback_handler.get_metrics()
        
        assert metrics["total_fallbacks"] == 3
        assert metrics["by_reason"]["llama3:70b→llama3:8b:timeout"] == 2
        assert metrics["by_reason"]["llama3:70b→mistral:7b:error"] == 1
    
    @pytest.mark.asyncio
    async def test_health_check_chain(self, fallback_handler):
        """Test health checking fallback chain"""
        async def mock_health_check(model):
            return model in ["llama3:8b", "mistral:7b"]
        
        health_status = await fallback_handler.health_check_fallback_chain(
            models=["llama3:70b", "llama3:8b", "mistral:7b"],
            health_check_func=mock_health_check,
        )
        
        assert not health_status["llama3:70b"]
        assert health_status["llama3:8b"]
        assert health_status["mistral:7b"]
    
    @pytest.mark.asyncio
    async def test_empty_fallback_chain(self, fallback_handler):
        """Test handling empty fallback chain"""
        async def mock_forward(model, prompt):
            if model == "llama3:70b":
                return "Primary response"
            raise Exception(f"No fallback for {model}")
        
        # Should succeed with primary if chain is empty
        model, response, is_fallback = await fallback_handler.forward_with_fallback(
            prompt="Test",
            primary_model="llama3:70b",
            forward_func=mock_forward,
            fallback_chain=[],
            timeout_ms=1000,
        )
        
        assert model == "llama3:70b"
        assert not is_fallback


class TestFallbackConfig:
    """Test FallbackConfig dataclass"""
    
    def test_config_creation(self):
        """Test creating fallback config"""
        config = FallbackConfig(
            primary_model="llama3:70b",
            chain=["llama3:8b", "mistral:7b"],
            timeout_ms=60000,
            max_retries=5,
            backoff_ms=1000,
        )
        
        assert config.primary_model == "llama3:70b"
        assert config.chain == ["llama3:8b", "mistral:7b"]
        assert config.timeout_ms == 60000
        assert config.max_retries == 5
        assert config.backoff_ms == 1000
    
    def test_config_defaults(self):
        """Test fallback config defaults"""
        config = FallbackConfig(
            primary_model="llama3:8b",
            chain=["mistral:7b"],
        )
        
        assert config.timeout_ms == 30000
        assert config.max_retries == 3
        assert config.backoff_ms == 500


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
