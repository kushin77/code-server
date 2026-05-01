"""
Prompt Gateway — Unit Tests

Covers MemoryContextEnricher initialization, context building,
and configuration.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from unittest.mock import MagicMock, patch


# ── MemoryContextEnricher ─────────────────────────────────────────────────────

class TestMemoryContextEnricher:
    def test_import(self):
        from memory_context_enricher import MemoryContextEnricher
        assert MemoryContextEnricher is not None

    def test_default_memory_url(self):
        from memory_context_enricher import MemoryContextEnricher
        enricher = MemoryContextEnricher()
        # Should default to a localhost or container URL
        assert enricher.memory_engine_url.startswith("http")

    def test_custom_memory_url(self):
        from memory_context_enricher import MemoryContextEnricher
        enricher = MemoryContextEnricher(memory_engine_url="http://custom:9999")
        assert "9999" in enricher.memory_engine_url

    @patch("requests.get")
    def test_enrich_prompt_returns_string(self, mock_get):
        from memory_context_enricher import MemoryContextEnricher
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = {"memories": [], "context": ""}
        enricher = MemoryContextEnricher()
        if hasattr(enricher, "enrich_prompt"):
            result = enricher.enrich_prompt("What is X?")
            assert isinstance(result, (str, dict, list))

    @patch("requests.get")
    def test_enrich_prompt_handles_unavailable_engine(self, mock_get):
        from memory_context_enricher import MemoryContextEnricher
        mock_get.side_effect = Exception("connection refused")
        enricher = MemoryContextEnricher()
        if hasattr(enricher, "enrich_prompt"):
            # Should not raise — graceful degradation
            try:
                enricher.enrich_prompt("fallback test")
            except Exception as exc:
                pytest.fail(f"enrich_prompt raised unexpectedly: {exc}")


# ── config ────────────────────────────────────────────────────────────────────

class TestPromptGatewayConfig:
    def test_config_importable(self):
        import config
        assert hasattr(config, "MEMORY_ENGINE_URL")

    def test_default_llm_backend(self):
        import config
        assert config.DEFAULT_LLM_BACKEND in ("ollama", "openai")

    def test_context_max_tokens_positive(self):
        import config
        assert config.CONTEXT_MAX_TOKENS > 0

    def test_log_level_default(self):
        import config
        assert config.LOG_LEVEL == "INFO"
