"""
@file apps/prompt-gateway/memory-context-enricher.py
@description Prompt Gateway integration with Organizational Memory for context enrichment
@governance GOV-002
"""

import sys
import os
sys.path.insert(0, os.path.dirname(__file__))
from log import get_logger
from typing import List, Dict, Optional
import requests
import json

logger = get_logger(__name__)


class MemoryContextEnricher:
    """Enriches prompts with organizational memory context."""

    def __init__(
        self,
        memory_engine_url: str = "http://localhost:8001",
        max_context_tokens: int = 500,
        enabled: bool = True,
    ):
        self.memory_engine_url = memory_engine_url
        self.max_context_tokens = max_context_tokens
        self.enabled = enabled
        logger.info(f"Memory context enricher initialized (enabled={enabled})")

    def extract_memory_keywords(self, prompt: str) -> List[str]:
        """Extract keywords from prompt to search memory."""
        keywords = []

        # Look for error patterns
        error_patterns = ["error", "fail", "bug", "issue", "exception", "crash"]
        for pattern in error_patterns:
            if pattern.lower() in prompt.lower():
                keywords.append(pattern)

        # Look for feature keywords
        if len(prompt) > 20:
            # Extract first meaningful phrase
            words = prompt.split()
            keywords.extend([w for w in words[:10] if len(w) > 3])

        return keywords[:5]  # Limit to 5 keywords

    def search_memory(
        self,
        query: str,
        collection: str = "incidents",
        limit: int = 3,
    ) -> List[Dict]:
        """Search memory for relevant context."""
        try:
            response = requests.get(
                f"{self.memory_engine_url}/search",
                params={
                    "q": query,
                    "collection": collection,
                    "limit": limit,
                },
                timeout=5,
            )

            if response.status_code == 200:
                data = response.json()
                return data.get("results", [])
            else:
                logger.warning(f"Memory search failed: {response.status_code}")
                return []
        except Exception as e:
            logger.error(f"Memory search error: {e}")
            return []

    def format_context(self, results: List[Dict]) -> str:
        """Format search results as prompt context."""
        if not results:
            return ""

        context = "# Related Past Incidents and Solutions\n\n"

        for i, result in enumerate(results, 1):
            context += f"## {i}. {result.get('title', 'Untitled')}\n"
            context += f"   - Relevance: {result.get('relevance_score', 0) * 100:.0f}%\n"
            context += f"   - Summary: {result.get('summary', '')}\n"

            if result.get("url"):
                context += f"   - Reference: {result.get('url')}\n"

            context += "\n"

        return context

    def enrich_prompt(
        self,
        prompt: str,
        user_context: Optional[Dict] = None,
    ) -> Dict:
        """
        Enrich prompt with organizational memory context.
        
        Args:
            prompt: Original user prompt
            user_context: Optional user/request context
            
        Returns:
            Dictionary with original prompt and enriched context
        """
        if not self.enabled:
            return {
                "original_prompt": prompt,
                "enriched_prompt": prompt,
                "memory_context": "",
                "memory_used": False,
            }

        result = {
            "original_prompt": prompt,
            "enriched_prompt": prompt,
            "memory_context": "",
            "memory_used": False,
            "memory_sources": [],
        }

        try:
            # Determine collection based on user context
            collection = "incidents"  # Default
            if user_context:
                if user_context.get("type") == "pr_review":
                    collection = "pr_descriptions"
                elif user_context.get("type") == "learning":
                    collection = "agent_learnings"
                elif user_context.get("type") == "incident":
                    collection = "incidents"
                elif user_context.get("type") == "runbook":
                    collection = "runbooks"

            # Extract keywords and search
            keywords = self.extract_memory_keywords(prompt)
            query = " ".join(keywords) if keywords else prompt[:100]

            search_results = self.search_memory(query, collection=collection)

            if search_results:
                context = self.format_context(search_results)
                result["memory_context"] = context
                result["memory_used"] = True
                result["memory_sources"] = [
                    {
                        "title": r.get("title"),
                        "url": r.get("url"),
                        "score": r.get("relevance_score"),
                    }
                    for r in search_results
                ]

                # Enrich prompt with context
                result["enriched_prompt"] = (
                    f"{prompt}\n\n---\n\n{context}"
                )

                logger.info(
                    f"Enriched prompt with {len(search_results)} memory results"
                )

        except Exception as e:
            logger.error(f"Prompt enrichment failed: {e}")

        return result

    def validate_memory_health(self) -> bool:
        """Check if memory engine is healthy."""
        try:
            response = requests.get(
                f"{self.memory_engine_url}/health",
                timeout=5,
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Memory health check failed: {e}")
            return False


class MemoryContextMiddleware:
    """FastAPI middleware for prompt enrichment."""

    def __init__(self, memory_enricher: MemoryContextEnricher):
        self.enricher = memory_enricher

    async def __call__(self, request, call_next):
        """Middleware handler."""
        # This would be integrated into FastAPI middleware chain
        response = await call_next(request)
        return response


# Export for integration
__all__ = ["MemoryContextEnricher", "MemoryContextMiddleware"]
