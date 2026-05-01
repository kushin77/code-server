"""
@file apps/memory-engine/embedder.py
@description Ollama embedding generation for organizational memory documents
@governance GOV-002
"""

import os
from log import get_logger
import requests
from typing import List, Optional
import time

logger = get_logger(__name__)


class OllamaEmbedder:
    """Generate embeddings using local Ollama instance."""

    def __init__(
        self,
        ollama_host: str = "http://localhost:11434",
        model: str = "nomic-embed-text",
        timeout: int = 30,
        max_retries: int = 3,
    ):
        self.ollama_host = ollama_host
        self.model = model
        self.timeout = timeout
        self.max_retries = max_retries
        logger.info(f"Initialized embedder with model '{model}' at {ollama_host}")

    def generate_embedding(self, text: str) -> Optional[List[float]]:
        """
        Generate embedding for text using Ollama.
        
        Args:
            text: Text to embed
            
        Returns:
            Embedding vector or None if failed
        """
        if not text or not isinstance(text, str):
            logger.warning("Invalid text for embedding")
            return None

        # Truncate text if too long (nomic-embed-text has limits)
        text = text[:8192]

        for attempt in range(self.max_retries):
            try:
                response = requests.post(
                    f"{self.ollama_host}/api/embeddings",
                    json={"model": self.model, "prompt": text},
                    timeout=self.timeout,
                )
                response.raise_for_status()

                data = response.json()
                if "embedding" in data:
                    return data["embedding"]
                else:
                    logger.error(f"No embedding in response: {data}")
                    return None

            except requests.exceptions.ConnectionError:
                logger.warning(f"Attempt {attempt + 1}/{self.max_retries}: Cannot connect to Ollama")
                if attempt < self.max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
            except requests.exceptions.Timeout:
                logger.warning(f"Attempt {attempt + 1}/{self.max_retries}: Ollama request timeout")
                if attempt < self.max_retries - 1:
                    time.sleep(2 ** attempt)
            except Exception as e:
                logger.error(f"Failed to generate embedding: {e}")
                return None

        logger.error(f"Failed to generate embedding after {self.max_retries} attempts")
        return None

    def batch_generate(self, texts: List[str]) -> List[Optional[List[float]]]:
        """
        Generate embeddings for multiple texts.
        
        Args:
            texts: List of texts to embed
            
        Returns:
            List of embeddings (None for failed items)
        """
        embeddings = []
        for i, text in enumerate(texts):
            embedding = self.generate_embedding(text)
            embeddings.append(embedding)
            if (i + 1) % 10 == 0:
                logger.info(f"Generated {i + 1}/{len(texts)} embeddings")

        return embeddings

    def health_check(self) -> bool:
        """Check if Ollama is accessible."""
        try:
            response = requests.get(
                f"{self.ollama_host}/api/tags",
                timeout=5,
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Ollama health check failed: {e}")
            return False
