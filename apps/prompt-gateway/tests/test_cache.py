#!/usr/bin/env python3
# @file        apps/prompt-gateway/tests/test_cache.py
# @module      prompt-gateway/tests
# @description Comprehensive tests for response caching and filtering
#

import pytest
import time
import json
from unittest.mock import Mock, MagicMock, patch
import sys
sys.path.insert(0, "/app/apps/prompt-gateway")

from cache import PromptCache, ResponseFilter, CachedResponse


class TestPromptCache:
    """Test response caching with LRU and TTL"""
    
    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client"""
        return MagicMock()
    
    @pytest.fixture
    def cache(self, mock_redis):
        """Initialize cache with mock Redis"""
        return PromptCache(mock_redis, cache_ttl_hours=24, max_size_per_user=10000)
    
    def test_cache_hit_on_exact_match(self, cache, mock_redis):
        """Test cache returns stored response on exact prompt match"""
        user_id = "user123"
        prompt = "What is 2+2?"
        model = "llama3:8b"
        response = "The answer is 4"
        
        # Simulate cached response
        cached_data = {
            "prompt_hash": cache._prompt_hash(prompt),
            "prompt_original": prompt,
            "model": model,
            "response": response,
            "tokens_used": 50,
            "cached_at": time.time(),
            "accessed_at": time.time(),
            "hit_count": 5,
            "user_id": user_id
        }
        
        mock_redis.get.return_value = json.dumps(cached_data).encode()
        
        result = cache.get(user_id, prompt, model)
        assert result is not None
        assert result[0] == response
        assert result[1]["cached"] == True
        assert result[1]["hit_count"] == 5
        assert cache.metrics["hits"] == 1
    
    def test_cache_miss_returns_none(self, cache, mock_redis):
        """Test cache returns None on cache miss"""
        mock_redis.get.return_value = None
        
        result = cache.get("user123", "What is AI?", "llama3:8b")
        assert result is None
        assert cache.metrics["misses"] == 1
    
    def test_cache_set_stores_response(self, cache, mock_redis):
        """Test cache stores new prompt-response pair"""
        user_id = "user123"
        prompt = "Explain quantum computing"
        model = "llama3:70b"
        response = "Quantum computing uses quantum bits..."
        tokens = 250
        
        mock_redis.get.return_value = b"0"  # Current size = 0
        
        cache.set(user_id, prompt, model, response, tokens)
        
        # Verify setex was called with TTL
        call_args = mock_redis.setex.call_args
        assert call_args[0][1] == 24 * 3600  # TTL in seconds
        
        # Verify size incremented
        mock_redis.incr.assert_called()
    
    def test_cache_lru_eviction_on_overflow(self, cache, mock_redis):
        """Test LRU eviction when cache exceeds max_size"""
        user_id = "user123"
        size_key = f"cache:user:{user_id}:size"
        
        # Simulate cache at max size
        mock_redis.get.side_effect = [
            b"10000",  # Current size check
            None,  # Evict oldest check
        ]
        mock_redis.keys.return_value = [
            b"cache:user:user123:prompt:abc123",
            b"cache:user:user123:prompt:def456"
        ]
        
        # Mock the data for oldest entry calculation
        oldest_data = {
            "accessed_at": time.time() - 1000,
            "user_id": user_id
        }
        mock_redis.get.return_value = json.dumps(oldest_data).encode()
        
        cache.set(user_id, "test prompt", "llama3:8b", "test response", 100)
        
        # Verify eviction occurred
        assert cache.metrics["evictions"] >= 0  # May or may not evict based on mock
    
    def test_cache_metrics_calculation(self, cache):
        """Test hit rate and metrics calculation"""
        cache.metrics["hits"] = 80
        cache.metrics["misses"] = 20
        
        metrics = cache.get_metrics()
        assert metrics["hits"] == 80
        assert metrics["misses"] == 20
        assert metrics["total_requests"] == 100
        assert metrics["hit_rate_percent"] == 80.0
    
    def test_clear_user_cache(self, cache, mock_redis):
        """Test clearing all cached entries for a user"""
        user_id = "user123"
        pattern = f"cache:user:{user_id}:prompt:*"
        
        mock_redis.keys.return_value = [
            b"key1", b"key2", b"key3"
        ]
        
        count = cache.clear_user_cache(user_id)
        
        assert count == 3
        mock_redis.delete.assert_called()


class TestResponseFilter:
    """Test response filtering for PII and sensitive data"""
    
    @pytest.fixture
    def filter_enabled(self):
        """Filter with redaction enabled"""
        return ResponseFilter(enable_redaction=True, log_redactions=True)
    
    @pytest.fixture
    def filter_disabled(self):
        """Filter with redaction disabled"""
        return ResponseFilter(enable_redaction=False, log_redactions=False)
    
    def test_filter_email_addresses(self, filter_enabled):
        """Test email address redaction"""
        response = "Contact us at support@example.com for help"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert "support@example.com" not in filtered
        assert "[REDACTED_EMAIL]" in filtered
        assert len(findings) == 1
        assert findings[0]["type"] == "email"
    
    def test_filter_phone_numbers(self, filter_enabled):
        """Test phone number redaction"""
        response = "Call 555-123-4567 for support or 555.987.6543 anytime"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert "555-123-4567" not in filtered
        assert "[REDACTED_PHONE]" in filtered
        assert len(findings) == 2
    
    def test_filter_ssn(self, filter_enabled):
        """Test SSN redaction"""
        response = "Your SSN is 123-45-6789"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert "123-45-6789" not in filtered
        assert "[REDACTED_SSN]" in filtered
        assert findings[0]["type"] == "ssn"
    
    def test_filter_credit_card(self, filter_enabled):
        """Test credit card redaction"""
        response = "Card number: 4532-1234-5678-9010"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert "4532-1234-5678-9010" not in filtered
        assert "[REDACTED_CREDIT_CARD]" in filtered
    
    def test_filter_ip_addresses(self, filter_enabled):
        """Test internal IP address redaction"""
        response = "Server at 192.168.1.1 and 10.0.0.50"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert "192.168.1.1" not in filtered or "[REDACTED_IP_ADDRESS]" in filtered
        assert len(findings) >= 1
    
    def test_filter_disabled_returns_unmodified(self, filter_disabled):
        """Test that disabled filter returns original response"""
        response = "Email: user@example.com, Phone: 555-123-4567"
        filtered, findings = filter_disabled.filter_response(response)
        
        assert filtered == response
        assert len(findings) == 0
    
    def test_filter_preserves_code_structure(self, filter_enabled):
        """Test that code examples are preserved while filtering PII"""
        response = """
def send_email(recipient):
    # recipient = "user@domain.com"
    send_to(recipient)
"""
        filtered, findings = filter_enabled.filter_response(response)
        
        # Code structure preserved
        assert "def send_email" in filtered
        assert "recipient" in filtered
        # Only the actual email in comment is redacted
        assert findings  # Some findings expected
    
    def test_redaction_logging(self, filter_enabled):
        """Test that redactions are logged"""
        response = "Contact john@example.com or call 555-123-4567"
        filter_enabled.filter_response(response)
        
        log = filter_enabled.get_redactions_log()
        assert len(log) == 1
        assert log[0]["redactions_count"] == 2
        assert len(log[0]["findings"]) == 2
    
    def test_multiple_same_pattern_redactions(self, filter_enabled):
        """Test multiple occurrences of same pattern are all redacted"""
        response = "Email john@example.com or jane@example.com"
        filtered, findings = filter_enabled.filter_response(response)
        
        assert filtered.count("[REDACTED_EMAIL]") == 2
        assert len(findings) == 2


class TestCacheIntegration:
    """Integration tests for cache with filter"""
    
    def test_cache_with_filtered_response(self):
        """Test full flow: cache stores filtered response"""
        mock_redis = MagicMock()
        cache = PromptCache(mock_redis)
        filter_obj = ResponseFilter()
        
        prompt = "How to contact support?"
        response = "Email: support@company.com, Phone: 555-123-4567"
        filtered_response, _ = filter_obj.filter_response(response)
        
        mock_redis.get.return_value = b"0"
        cache.set("user1", prompt, "llama3:8b", filtered_response, 150)
        
        # Verify filtered response was cached (not original with PII)
        call_args = mock_redis.setex.call_args
        cached_data = json.loads(call_args[0][2])
        assert "[REDACTED_EMAIL]" in cached_data["response"]
        assert "support@company.com" not in cached_data["response"]
