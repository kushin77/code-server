"""
@file apps/memory-engine/qdrant_client.py
@description Qdrant vector database client wrapper for memory storage and semantic search
@governance GOV-002
"""

import os
import json
from log import get_logger
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime
import hashlib

from qdrant_client import QdrantClient
from qdrant_client.http.models import (
    Distance,
    VectorParams,
    PointStruct,
    Filter,
    FieldCondition,
    MatchValue,
    HasIdCondition,
)

logger = get_logger(__name__)


@dataclass
class MemoryDocument:
    """Represents a document in organizational memory."""
    id: str  # Hash of content
    title: str
    content: str
    collection: str
    source_url: Optional[str] = None
    tags: List[str] = None
    timestamp: str = None
    confidence_score: float = 1.0
    embedding: Optional[List[float]] = None

    def __post_init__(self):
        if self.tags is None:
            self.tags = []
        if self.timestamp is None:
            self.timestamp = datetime.utcnow().isoformat() + "Z"

    def to_dict(self):
        """Convert to dict, excluding embedding for storage."""
        d = asdict(self)
        d.pop('embedding', None)
        return d

    @staticmethod
    def generate_id(content: str) -> str:
        """Generate deterministic ID from content hash."""
        return hashlib.sha256(content.encode()).hexdigest()[:16]


class QdrantMemoryClient:
    """Client for Qdrant vector database operations."""

    def __init__(self, host: str = "localhost", port: int = 6333):
        self.host = host
        self.port = port
        self.client = QdrantClient(host=host, port=port)
        self.vector_size = 384  # nomic-embed-text embedding dimension
        logger.info(f"Connected to Qdrant at {host}:{port}")

    def ensure_collection(self, collection_name: str) -> None:
        """Create collection if it doesn't exist."""
        try:
            self.client.get_collection(collection_name)
            logger.info(f"Collection '{collection_name}' already exists")
        except Exception:
            logger.info(f"Creating collection '{collection_name}'")
            self.client.create_collection(
                collection_name=collection_name,
                vectors_config=VectorParams(size=self.vector_size, distance=Distance.COSINE),
            )

    def store_document(
        self,
        collection: str,
        document: MemoryDocument,
        dedup_threshold: float = 0.98,
    ) -> bool:
        """
        Store document with deduplication.
        
        Args:
            collection: Collection name
            document: Document to store
            dedup_threshold: Cosine similarity threshold for deduplication (0-1)
            
        Returns:
            True if stored, False if deduplicated
        """
        if not document.embedding or len(document.embedding) == 0:
            logger.warning(f"Skipping document '{document.title}' - no embedding")
            return False

        self.ensure_collection(collection)

        # Check for near-duplicates
        if self._find_duplicate(collection, document.embedding, dedup_threshold):
            logger.info(f"Deduplicated similar document: {document.title}")
            return False

        # Store document
        point = PointStruct(
            id=hash(document.id) & 0x7FFFFFFF,  # Ensure positive int
            vector=document.embedding,
            payload=document.to_dict(),
        )

        self.client.upsert(
            collection_name=collection,
            points=[point],
        )

        logger.info(f"Stored document in '{collection}': {document.title}")
        return True

    def search(
        self,
        collection: str,
        query_vector: List[float],
        limit: int = 10,
        freshness_weight: float = 0.1,
    ) -> List[Dict]:
        """
        Semantic search with freshness weighting.
        
        Args:
            collection: Collection to search
            query_vector: Query embedding vector
            limit: Max results to return
            freshness_weight: Weight for newer documents (0-1)
            
        Returns:
            List of search results with scores and metadata
        """
        try:
            results = self.client.search(
                collection_name=collection,
                query_vector=query_vector,
                limit=limit * 2,  # Fetch extra for post-processing
            )
        except Exception as e:
            logger.error(f"Search failed in '{collection}': {e}")
            return []

        # Apply freshness weighting
        processed_results = []
        now = datetime.utcnow()

        for point in results:
            score = point.score
            payload = point.payload

            # Calculate freshness boost
            if 'timestamp' in payload:
                doc_time = datetime.fromisoformat(payload['timestamp'].replace('Z', '+00:00'))
                age_days = (now - doc_time).days
                freshness_boost = 1.0 / (1.0 + freshness_weight * age_days)
                score = score * (1.0 + freshness_boost * 0.1)

            processed_results.append({
                "id": payload.get('id'),
                "title": payload.get('title'),
                "summary": payload.get('content', '')[:200],
                "relevance_score": min(score, 1.0),  # Cap at 1.0
                "confidence_score": payload.get('confidence_score', 1.0),
                "source_url": payload.get('source_url'),
                "tags": payload.get('tags', []),
                "timestamp": payload.get('timestamp'),
            })

        # Sort by relevance and return top limit
        processed_results.sort(key=lambda x: x['relevance_score'], reverse=True)
        return processed_results[:limit]

    def get_collection_stats(self, collection: str) -> Dict:
        """Get collection statistics."""
        try:
            collection_info = self.client.get_collection(collection)
            return {
                "name": collection,
                "point_count": collection_info.points_count,
                "vector_size": self.vector_size,
            }
        except Exception as e:
            logger.error(f"Failed to get stats for '{collection}': {e}")
            return {}

    def list_collections(self) -> List[str]:
        """List all collections."""
        try:
            collections = self.client.get_collections()
            return [c.name for c in collections.collections]
        except Exception as e:
            logger.error(f"Failed to list collections: {e}")
            return []

    def _find_duplicate(
        self,
        collection: str,
        embedding: List[float],
        threshold: float,
    ) -> bool:
        """Check if similar document already exists."""
        try:
            results = self.client.search(
                collection_name=collection,
                query_vector=embedding,
                limit=1,
            )
            if results and results[0].score >= threshold:
                return True
        except Exception:
            pass
        return False

    def delete_collection(self, collection: str) -> bool:
        """Delete collection."""
        try:
            self.client.delete_collection(collection)
            logger.info(f"Deleted collection '{collection}'")
            return True
        except Exception as e:
            logger.error(f"Failed to delete collection '{collection}': {e}")
            return False

    def health_check(self) -> bool:
        """Check if Qdrant is healthy."""
        try:
            self.client.get_collections()
            return True
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False
