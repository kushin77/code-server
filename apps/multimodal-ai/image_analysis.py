#!/usr/bin/env python3
# @file        apps/multimodal-ai/image_analysis.py
# @module      multimodal-ai/images
# @description Screenshot/error image analysis using Ollama LLaVA (or OpenAI GPT-4V)
# @governance  GOV-002: Immutable, deterministic, no hardcoded secrets
"""Analyze images (error screenshots, architecture diagrams) and suggest fixes."""

import base64
import json
import logging
import os
from typing import Dict, List, Optional

import httpx
import config as _svc_config



logger = logging.getLogger(__name__)

# Configuration via environment (never hardcoded)
_VISION_BACKEND = _svc_config.VISION_BACKEND           # ollama | openai
_OLLAMA_BASE_URL = _svc_config.OLLAMA_BASE_URL
_OLLAMA_VISION_MODEL = _svc_config.OLLAMA_VISION_MODEL
_OPENAI_API_KEY = _svc_config.OPENAI_API_KEY
_OPENAI_VISION_MODEL = _svc_config.OPENAI_VISION_MODEL
_VISION_TIMEOUT_SEC = _svc_config.VISION_TIMEOUT_SEC

_ERROR_ANALYSIS_PROMPT = """You are a DevOps/SRE assistant analyzing an error screenshot.
Identify:
1. The error type (e.g. TypeError, ConnectionRefused, OOM)
2. Root cause hypothesis (1-2 sentences)
3. Up to 3 concrete remediation steps

Respond ONLY as JSON:
{"error_type": "...", "diagnosis": "...", "fixes": ["...", "..."], "confidence": 0.0}"""

_ARCH_ANALYSIS_PROMPT = """You are a software architect. Analyze this architecture diagram and extract:
1. Components visible (service names, databases, caches, etc.)
2. Connections between components (A → B means A calls B)

Respond ONLY as JSON:
{"components": ["..."], "connections": [["A", "B"]]}"""


class ImageAnalyzer:
    """Analyzes images and suggests fixes using a vision-capable LLM."""

    async def analyze_error_screenshot(self, image_bytes: bytes) -> Dict:
        """
        Analyze error screenshot and return diagnosis and remediation.

        Uses LLaVA (via Ollama) by default, or GPT-4V when VISION_BACKEND=openai.

        Args:
            image_bytes: Raw PNG or JPEG image bytes

        Returns:
            {error_type, diagnosis, fixes: [...], confidence}
        """
        raw = await self._query_vision(image_bytes, _ERROR_ANALYSIS_PROMPT)
        try:
            result = json.loads(raw)
            # Validate expected keys; fill defaults if missing
            return {
                "error_type": result.get("error_type", "Unknown"),
                "diagnosis": result.get("diagnosis", "Could not determine root cause"),
                "fixes": result.get("fixes", []),
                "confidence": float(result.get("confidence", 0.0)),
            }
        except (json.JSONDecodeError, ValueError) as e:
            logger.warning(f"Vision model returned non-JSON; raw={raw[:200]} err={e}")
            return {
                "error_type": "Parse error",
                "diagnosis": raw[:500] if raw else "Vision model unavailable",
                "fixes": [],
                "confidence": 0.0,
            }

    async def analyze_architecture_diagram(self, image_bytes: bytes) -> Dict:
        """
        Parse architecture diagram image and extract components and connections.

        Args:
            image_bytes: Raw PNG or JPEG image bytes

        Returns:
            {components: [...], connections: [[A, B], ...]}
        """
        raw = await self._query_vision(image_bytes, _ARCH_ANALYSIS_PROMPT)
        try:
            result = json.loads(raw)
            return {
                "components": result.get("components", []),
                "connections": result.get("connections", []),
            }
        except (json.JSONDecodeError, ValueError) as e:
            logger.warning(f"Architecture parse failed; raw={raw[:200]} err={e}")
            return {"components": [], "connections": []}

    async def _query_vision(self, image_bytes: bytes, prompt: str) -> str:
        """
        Call the configured vision backend with an image and prompt.

        Returns:
            Raw string response from the model.
        """
        if _VISION_BACKEND == "openai" and _OPENAI_API_KEY:
            return await self._query_openai(image_bytes, prompt)
        return await self._query_ollama(image_bytes, prompt)

    async def _query_ollama(self, image_bytes: bytes, prompt: str) -> str:
        """Call Ollama's /api/generate endpoint with image + prompt."""
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        payload = {
            "model": _OLLAMA_VISION_MODEL,
            "prompt": prompt,
            "images": [b64],
            "stream": False,
        }
        url = f"{_OLLAMA_BASE_URL}/api/generate"
        try:
            async with httpx.AsyncClient(timeout=_VISION_TIMEOUT_SEC) as client:
                resp = await client.post(url, json=payload)
                resp.raise_for_status()
                data = resp.json()
                return data.get("response", "")
        except httpx.HTTPStatusError as e:
            logger.error(f"Ollama vision error {e.response.status_code}: {e.response.text[:200]}")
            return ""
        except Exception as e:
            logger.error(f"Ollama vision call failed: {e}")
            return ""

    async def _query_openai(self, image_bytes: bytes, prompt: str) -> str:
        """Call OpenAI GPT-4V via chat completions API."""
        b64 = base64.b64encode(image_bytes).decode("utf-8")
        payload = {
            "model": _OPENAI_VISION_MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:image/png;base64,{b64}"},
                        },
                    ],
                }
            ],
            "max_tokens": 800,
        }
        headers = {
            "Authorization": f"Bearer {_OPENAI_API_KEY}",
            "Content-Type": "application/json",
        }
        try:
            async with httpx.AsyncClient(timeout=_VISION_TIMEOUT_SEC) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    json=payload,
                    headers=headers,
                )
                resp.raise_for_status()
                data = resp.json()
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error(f"OpenAI vision call failed: {e}")
            return ""
