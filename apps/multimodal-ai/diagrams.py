#!/usr/bin/env python3
# @file        apps/multimodal-ai/diagrams.py
# @module      multimodal-ai/diagrams
# @description Mermaid diagram generation from natural language via LLM (Ollama/OpenAI)
# @governance  GOV-002: Immutable, deterministic, no hardcoded secrets
"""Auto-generate Mermaid diagrams from natural language descriptions using an LLM."""

import json
import os
import re
from typing import Dict, List, Optional

import httpx
import config as _svc_config
from log import get_logger

logger = get_logger(__name__)




# Configuration via environment
_LLM_BACKEND = _svc_config.DIAGRAM_LLM_BACKEND        # ollama | openai
_OLLAMA_BASE_URL = _svc_config.OLLAMA_BASE_URL
_OLLAMA_MODEL = _svc_config.OLLAMA_MODEL
_OPENAI_API_KEY = _svc_config.OPENAI_API_KEY
_OPENAI_MODEL = _svc_config.OPENAI_MODEL
_LLM_TIMEOUT_SEC = _svc_config.LLM_TIMEOUT_SEC
_MERMAID_LIVE_BASE = "https://mermaid.live/view#base64:"

_GENERATE_PROMPT_TMPL = """You are an expert software architect. Convert the following description to a Mermaid diagram.

Description: {description}

Rules:
- Output ONLY the Mermaid code block (no explanation, no markdown fences)
- Start with 'graph TD' for flowcharts, 'sequenceDiagram' for sequences, 'classDiagram' for classes
- Use descriptive node labels in square brackets, e.g. API[REST API]
- Keep it simple: max 15 nodes
- Make sure the syntax is valid Mermaid

Mermaid code:"""

_ARCH_PROMPT_TMPL = """You are a software architect. Generate a Mermaid architecture diagram for these components: {components}

Show how they connect (which component calls/depends on which).
Output ONLY valid Mermaid code, starting with 'graph LR' or 'graph TD'.
Max 15 nodes. No explanation.

Mermaid code:"""


def _mermaid_live_url(code: str) -> str:
    """Generate a mermaid.live preview URL for the given Mermaid code."""
    import base64 as b64mod
    encoded = b64mod.urlsafe_b64encode(code.encode()).decode()
    return f"{_MERMAID_LIVE_BASE}{encoded}"


def _validate_mermaid(code: str) -> bool:
    """
    Basic syntactic validation: check for a known diagram type keyword at start.
    """
    first_line = code.strip().split("\n")[0].strip().lower()
    known_types = (
        "graph ", "flowchart ", "sequencediagram", "classdiagram",
        "statediagram", "erdiagram", "gantt", "pie", "gitgraph",
    )
    return any(first_line.startswith(kw) for kw in known_types)


class DiagramGenerator:
    """Generates Mermaid diagrams from text using a local or remote LLM."""

    async def generate_from_description(self, description: str) -> Dict:
        """
        Generate a Mermaid diagram from a natural language description.

        Example input: "I'm moving auth to a separate service with a Redis cache layer"
        Returns:
            {format, code, preview_url, valid}
        """
        prompt = _GENERATE_PROMPT_TMPL.format(description=description.strip())
        raw = await self._call_llm(prompt)
        code = self._extract_mermaid(raw)

        if not code:
            logger.warning(f"LLM did not produce Mermaid output for: '{description[:60]}'")
            code = "graph TD\n  A[Input] --> B[Output]"  # safe fallback

        valid = _validate_mermaid(code)
        preview_url = _mermaid_live_url(code)

        logger.info(f"Generated diagram ({len(code)} chars, valid={valid}) for: '{description[:60]}'")
        return {
            "format": "mermaid",
            "code": code,
            "preview_url": preview_url,
            "valid": valid,
        }

    async def architecture_diagram(self, components: List[str]) -> str:
        """
        Generate an architecture Mermaid diagram from a list of component names.

        Returns:
            Mermaid code string.
        """
        components_str = ", ".join(components)
        prompt = _ARCH_PROMPT_TMPL.format(components=components_str)
        raw = await self._call_llm(prompt)
        code = self._extract_mermaid(raw)

        if not code:
            # Fallback: generate a simple linear graph
            nodes = " --> ".join(f"{c.replace(' ', '')}[{c}]" for c in components[:10])
            code = f"graph LR\n  {nodes}"
            logger.warning("LLM fallback — generated simple architecture diagram")

        logger.info(f"Architecture diagram for {len(components)} components")
        return code

    async def _call_llm(self, prompt: str) -> str:
        """Route to configured LLM backend."""
        if _LLM_BACKEND == "openai" and _OPENAI_API_KEY:
            return await self._call_openai(prompt)
        return await self._call_ollama(prompt)

    async def _call_ollama(self, prompt: str) -> str:
        """Call Ollama /api/generate endpoint."""
        payload = {
            "model": _OLLAMA_MODEL,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.2},   # low temp for deterministic syntax
        }
        url = f"{_OLLAMA_BASE_URL}/api/generate"
        try:
            async with httpx.AsyncClient(timeout=_LLM_TIMEOUT_SEC) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                return resp.json().get("response", "")
        except httpx.HTTPStatusError as e:
            logger.error(f"Ollama LLM error {e.response.status_code}: {e.response.text[:200]}")
            return ""
        except Exception as e:
            logger.error(f"Ollama LLM call failed: {e}")
            return ""

    async def _call_openai(self, prompt: str) -> str:
        """Call OpenAI chat completions API."""
        payload = {
            "model": _OPENAI_MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
            "max_tokens": 800,
        }
        headers = {
            "Authorization": f"Bearer {_OPENAI_API_KEY}",
            "Content-Type": "application/json",
        }
        try:
            async with httpx.AsyncClient(timeout=_LLM_TIMEOUT_SEC) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    json=payload,
                    headers=headers,
                )
                resp.raise_for_status()
                return resp.json()["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error(f"OpenAI LLM call failed: {e}")
            return ""

    @staticmethod
    def _extract_mermaid(text: str) -> str:
        """
        Extract Mermaid code from LLM output.

        Handles:
        - Bare Mermaid (starts with graph/sequenceDiagram/etc.)
        - Wrapped in ```mermaid ... ``` fences
        """
        text = text.strip()

        # Remove markdown code fences if present
        fence_match = re.search(r"```(?:mermaid)?\s*\n(.*?)```", text, re.DOTALL | re.IGNORECASE)
        if fence_match:
            return fence_match.group(1).strip()

        # Check if it's bare Mermaid already
        first = text.split("\n")[0].strip().lower()
        known = ("graph ", "flowchart ", "sequencediagram", "classdiagram",
                 "statediagram", "erdiagram", "gantt", "pie", "gitgraph")
        if any(first.startswith(k) for k in known):
            return text

        return ""
