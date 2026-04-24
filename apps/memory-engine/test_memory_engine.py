"""
@file apps/memory-engine/test_memory_engine.py
@description Comprehensive tests for organizational memory engine
@governance GOV-002
"""

import pytest
import json
from unittest.mock import Mock, patch, AsyncMock
from fastapi.testclient import TestClient

# Mock imports for testing
@pytest.fixture
def test_app():
    """Create test FastAPI app."""
    from main import app
    return app


@pytest.fixture
def client(test_app):
    """Create test client."""
    return TestClient(test_app)


class TestHealthCheck:
    """Test health check endpoint."""

    def test_health_check(self, client):
        """Health check should return healthy status."""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] in ["healthy", "degraded"]


class TestSearchEndpoint:
    """Test semantic search functionality."""

    def test_search_with_valid_query(self, client):
        """Search should return results for valid query."""
        response = client.get(
            "/search?q=502+error&collection=incidents&limit=10"
        )
        assert response.status_code == 200
        data = response.json()
        assert "results" in data
        assert "query" in data
        assert data["query"] == "502 error"

    def test_search_with_empty_query(self, client):
        """Search should reject empty query."""
        response = client.get("/search?q=&collection=incidents")
        assert response.status_code == 400

    def test_search_with_invalid_collection(self, client):
        """Search should reject invalid collection."""
        response = client.get(
            "/search?q=test&collection=invalid_collection"
        )
        assert response.status_code == 400

    def test_search_respects_limit(self, client):
        """Search should respect limit parameter."""
        response = client.get(
            "/search?q=test&collection=incidents&limit=5"
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["results"]) <= 5

    def test_search_with_post_request(self, client):
        """POST-based search should work."""
        response = client.post(
            "/search",
            json={
                "query": "database error",
                "collection": "incidents",
                "limit": 10,
            },
        )
        assert response.status_code == 200


class TestIngestionEndpoint:
    """Test document ingestion."""

    def test_ingest_valid_document(self, client):
        """Ingest should accept valid document."""
        response = client.post(
            "/ingest",
            json={
                "title": "Test Incident",
                "content": "This is a test incident",
                "collection": "incidents",
                "tags": ["test"],
                "confidence_score": 0.95,
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["success"] in [True, False]

    def test_ingest_with_empty_content(self, client):
        """Ingest should reject empty content."""
        response = client.post(
            "/ingest",
            json={
                "title": "Empty",
                "content": "",
                "collection": "incidents",
            },
        )
        assert response.status_code == 400

    def test_ingest_with_invalid_collection(self, client):
        """Ingest should reject invalid collection."""
        response = client.post(
            "/ingest",
            json={
                "title": "Test",
                "content": "Content",
                "collection": "invalid",
            },
        )
        assert response.status_code == 400

    def test_batch_ingest(self, client):
        """Batch ingest should process multiple documents."""
        response = client.post(
            "/batch/ingest",
            json=[
                {
                    "title": "Doc 1",
                    "content": "Content 1",
                    "collection": "incidents",
                },
                {
                    "title": "Doc 2",
                    "content": "Content 2",
                    "collection": "runbooks",
                },
            ],
        )
        assert response.status_code == 200
        data = response.json()
        assert "total" in data
        assert "successful" in data


class TestCollectionsEndpoint:
    """Test collections management."""

    def test_list_collections(self, client):
        """Should list all collections."""
        response = client.get("/collections")
        assert response.status_code == 200
        data = response.json()
        assert "collections" in data

    def test_get_stats(self, client):
        """Should return memory statistics."""
        response = client.get("/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total_documents" in data
        assert "collections" in data


class TestMemoryDocument:
    """Test MemoryDocument dataclass."""

    def test_memory_document_creation(self):
        """Should create memory document."""
        from qdrant_client_module import MemoryDocument

        doc = MemoryDocument(
            id="test123",
            title="Test Doc",
            content="Test content",
            collection="incidents",
        )

        assert doc.id == "test123"
        assert doc.title == "Test Doc"
        assert doc.timestamp is not None

    def test_memory_document_id_generation(self):
        """Should generate deterministic ID."""
        from qdrant_client_module import MemoryDocument

        content = "Test content for hashing"
        id1 = MemoryDocument.generate_id(content)
        id2 = MemoryDocument.generate_id(content)

        assert id1 == id2  # Deterministic
        assert len(id1) == 16  # SHA256[:16]


class TestQdrantClient:
    """Test Qdrant client functionality."""

    @patch('qdrant_client.QdrantClient')
    def test_collection_creation(self, mock_client):
        """Should create collection if not exists."""
        from qdrant_client_module import QdrantMemoryClient

        client = QdrantMemoryClient()
        client.ensure_collection("test_collection")

        # Verify create_collection was called if needed
        assert client.client is not None

    @patch('qdrant_client.QdrantClient')
    def test_search_with_dedup(self, mock_client):
        """Should deduplicate similar documents."""
        from qdrant_client_module import QdrantMemoryClient, MemoryDocument

        client = QdrantMemoryClient()
        doc = MemoryDocument(
            id="test123",
            title="Test",
            content="Test content",
            collection="incidents",
            embedding=[0.1] * 384,  # Mock embedding
        )

        # Mock duplicate detection
        with patch.object(
            client,
            '_find_duplicate',
            return_value=True
        ):
            result = client.store_document(
                "incidents",
                doc,
                dedup_threshold=0.98
            )
            assert result is False  # Should not store (duplicate)


class TestOllamaEmbedder:
    """Test Ollama embeddings."""

    @patch('requests.post')
    def test_embedding_generation(self, mock_post):
        """Should generate embedding."""
        from embedder import OllamaEmbedder

        mock_response = Mock()
        mock_response.json.return_value = {
            "embedding": [0.1, 0.2, 0.3] * 128  # Mock 384-dim embedding
        }
        mock_post.return_value = mock_response

        embedder = OllamaEmbedder()
        result = embedder.generate_embedding("test text")

        assert result is not None
        assert len(result) == 384

    @patch('requests.post')
    def test_embedding_with_retry(self, mock_post):
        """Should retry on connection error."""
        from embedder import OllamaEmbedder
        import requests

        mock_post.side_effect = [
            requests.exceptions.ConnectionError("Connection failed"),
            Mock(json=lambda: {"embedding": [0.1] * 384}),
        ]

        embedder = OllamaEmbedder(max_retries=3)
        result = embedder.generate_embedding("test text")

        # Should succeed after retry
        assert result is not None

    @patch('requests.get')
    def test_health_check(self, mock_get):
        """Should check Ollama health."""
        from embedder import OllamaEmbedder

        mock_response = Mock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        embedder = OllamaEmbedder()
        assert embedder.health_check() is True


class TestDocumentChunker:
    """Test document chunking."""

    def test_chunk_document(self):
        """Should chunk document properly."""
        from ingestion import DocumentChunker

        chunker = DocumentChunker()
        text = "Paragraph 1\n\nParagraph 2\n\nParagraph 3"
        chunks = chunker.chunk_document(text)

        assert len(chunks) > 0
        assert all('text' in c for c in chunks)

    def test_chunk_github_issue(self):
        """Should extract and chunk GitHub issue."""
        from ingestion import DocumentChunker

        chunker = DocumentChunker()
        issue = {
            "title": "Test Issue",
            "body": "Issue description",
            "number": 123,
            "html_url": "https://github.com/user/repo/issues/123",
            "labels": [{"name": "bug"}],
        }

        chunks = chunker.chunk_github_issue(issue)

        assert len(chunks) > 0
        assert chunks[0]["metadata"]["issue_number"] == 123


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
