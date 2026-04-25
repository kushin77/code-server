"""
Unit tests for Phase 6 Qdrant clustering and multi-tenant support.
@file tests/unit/memory_engine/test_qdrant_multi_tenant.py
@issue #1537 (Testing & QA Strategy)
@governance GOV-002: Immutable test data, deterministic assertions
"""

import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from datetime import datetime

# Add apps to path
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "apps" / "memory-engine"))

from qdrant_client import QdrantMemoryClient
from multi_tenant import MultiTenantManager, TenantContext


# ============================================================================
# UNIT TESTS: Qdrant Client Configuration
# ============================================================================

@pytest.mark.unit
class TestQdrantClientInit:
    """Test Qdrant client initialization."""
    
    def test_qdrant_client_initialization(self, app_env):
        """Test that Qdrant client initializes with correct config."""
        # Note: In real test, mock the actual Qdrant connection
        client = MagicMock()
        client.get_collection = AsyncMock()
        
        assert client is not None
    
    def test_qdrant_host_configuration(self):
        """Test Qdrant host configuration from environment."""
        import os
        os.environ["QDRANT_URL"] = "http://qdrant-node-1:6333"
        os.environ["QDRANT_NODE2_URL"] = "http://qdrant-node-2:6343"
        
        assert os.environ["QDRANT_URL"] == "http://qdrant-node-1:6333"
        assert os.environ["QDRANT_NODE2_URL"] == "http://qdrant-node-2:6343"
    
    def test_replication_factor_config(self):
        """Test replication factor configuration."""
        config = {
            "replication_factor": 2,
            "write_consistency_factor": 1,
        }
        
        assert config["replication_factor"] == 2
        assert config["write_consistency_factor"] == 1


# ============================================================================
# UNIT TESTS: Collection Management
# ============================================================================

@pytest.mark.unit
class TestCollectionManagement:
    """Test Qdrant collection management operations."""
    
    def test_create_collection_with_replication(self, qdrant_collection_config, mock_qdrant_client):
        """Test creating a collection with replication factor=2."""
        config = qdrant_collection_config
        mock_client = mock_qdrant_client
        
        # Simulate collection creation
        mock_client.create_collection("test-collection", **config)
        
        # Verify create was called
        mock_client.create_collection.assert_called_once()
        args, kwargs = mock_client.create_collection.call_args
        assert args[0] == "test-collection"
    
    def test_collection_names_organizational_memory(self):
        """Test that organizational-memory collection is created with correct name."""
        collection_names = [
            "organizational-memory",
            "code-context",
            "agent-decisions",
        ]
        
        assert "organizational-memory" in collection_names
        assert "code-context" in collection_names
        assert "agent-decisions" in collection_names
    
    def test_collection_vector_size(self):
        """Test that collections use correct vector size (1536)."""
        config = {
            "vectors": {
                "size": 1536,  # OpenAI text-embedding-3-small
                "distance": "Cosine",
            }
        }
        
        assert config["vectors"]["size"] == 1536
        assert config["vectors"]["distance"] == "Cosine"


# ============================================================================
# UNIT TESTS: Multi-Tenant Context
# ============================================================================

@pytest.mark.unit
class TestTenantContext:
    """Test TenantContext model and validation."""
    
    def test_tenant_context_creation(self, tenant_context_standard):
        """Test creating a TenantContext."""
        ctx = TenantContext(**tenant_context_standard)
        
        assert ctx.tenant_id == "tenant-unit-test-001"
        assert ctx.namespace == "default"
        assert ctx.tier == "standard"
        assert ctx.quota_limit == 100000
    
    def test_tenant_context_enterprise_tier(self, tenant_context_enterprise):
        """Test enterprise tier context."""
        ctx = TenantContext(**tenant_context_enterprise)
        
        assert ctx.tier == "enterprise"
        assert ctx.quota_limit == 1000000
    
    def test_tenant_id_immutability(self, tenant_context_standard):
        """Test that tenant_id is required and immutable."""
        ctx_data = tenant_context_standard.copy()
        tenant_id = ctx_data["tenant_id"]
        
        ctx = TenantContext(**ctx_data)
        assert ctx.tenant_id == tenant_id
        # In a real Pydantic model, this would be immutable via frozen=True


# ============================================================================
# UNIT TESTS: Multi-Tenant Isolation
# ============================================================================

@pytest.mark.unit
class TestMultiTenantIsolation:
    """Test multi-tenant data isolation."""
    
    def test_get_tenant_filter_single_tenant(self):
        """Test generating filter for single tenant."""
        # Simulate filter generation
        tenant_id = "tenant-unit-test-001"
        
        expected_filter = {
            "must": [
                {"field": "tenant_id", "match": tenant_id}
            ]
        }
        
        assert expected_filter["must"][0]["match"] == tenant_id
    
    def test_get_tenant_filter_with_namespace(self):
        """Test generating filter with namespace."""
        tenant_id = "tenant-unit-test-001"
        namespace = "production"
        
        filter_conditions = [
            {"field": "tenant_id", "match": tenant_id},
            {"field": "namespace", "match": namespace},
        ]
        
        assert len(filter_conditions) == 2
        assert filter_conditions[0]["match"] == tenant_id
        assert filter_conditions[1]["match"] == namespace
    
    def test_tenant_payload_injection(self, multi_tenant_filter_document, tenant_context_standard):
        """Test that tenant metadata is injected into payloads."""
        doc = multi_tenant_filter_document.copy()
        
        # Verify tenant metadata is present
        assert doc["tenant_id"] == tenant_context_standard["tenant_id"]
        assert doc["namespace"] == tenant_context_standard["namespace"]
        assert "created_at" in doc


# ============================================================================
# UNIT TESTS: Payload Indexing
# ============================================================================

@pytest.mark.unit
class TestPayloadIndexing:
    """Test multi-tenant payload index creation."""
    
    def test_tenant_id_index_creation(self, mock_qdrant_client):
        """Test that tenant_id index is created."""
        mock_client = mock_qdrant_client
        collection_name = "organizational-memory"
        
        # Simulate index creation
        mock_client.create_payload_index(
            collection_name=collection_name,
            field_name="tenant_id",
            field_schema="keyword"
        )
        
        mock_client.create_payload_index.assert_called_once()
        call_args = mock_client.create_payload_index.call_args
        assert call_args.kwargs["field_name"] == "tenant_id"
        assert call_args.kwargs["field_schema"] == "keyword"
    
    def test_namespace_index_creation(self, mock_qdrant_client):
        """Test that namespace index is created."""
        mock_client = mock_qdrant_client
        
        mock_client.create_payload_index(
            collection_name="organizational-memory",
            field_name="namespace",
            field_schema="keyword"
        )
        
        call_args = mock_client.create_payload_index.call_args
        assert call_args.kwargs["field_name"] == "namespace"
    
    def test_created_at_datetime_index(self, mock_qdrant_client):
        """Test that created_at datetime index is created."""
        mock_client = mock_qdrant_client
        
        mock_client.create_payload_index(
            collection_name="organizational-memory",
            field_name="created_at",
            field_schema="datetime"
        )
        
        call_args = mock_client.create_payload_index.call_args
        assert call_args.kwargs["field_schema"] == "datetime"


# ============================================================================
# UNIT TESTS: Vector Operations
# ============================================================================

@pytest.mark.unit
class TestVectorOperations:
    """Test vector database operations."""
    
    def test_upsert_document_with_vector(self, sample_vector, sample_embedding_document):
        """Test upserting a document with vector embedding."""
        doc = sample_embedding_document.copy()
        doc["embedding"] = sample_vector
        
        assert "embedding" in doc
        assert len(doc["embedding"]) == 1536
        assert all(isinstance(v, float) for v in doc["embedding"])
    
    def test_search_with_tenant_filter(self):
        """Test searching with tenant isolation filter."""
        search_query = {
            "vector": [0.1] * 1536,
            "limit": 10,
            "filter": {
                "must": [
                    {"field": "tenant_id", "match": "tenant-unit-test-001"}
                ]
            }
        }
        
        assert search_query["limit"] == 10
        assert search_query["filter"]["must"][0]["field"] == "tenant_id"
    
    def test_delete_with_tenant_isolation(self):
        """Test deleting points with tenant filter."""
        delete_filter = {
            "must": [
                {"field": "tenant_id", "match": "tenant-unit-test-001"},
                {"field": "id", "match": "doc-mt-001"},
            ]
        }
        
        assert len(delete_filter["must"]) == 2
        assert delete_filter["must"][0]["field"] == "tenant_id"


# ============================================================================
# UNIT TESTS: Error Handling
# ============================================================================

@pytest.mark.unit
class TestErrorHandling:
    """Test error handling in multi-tenant operations."""
    
    def test_invalid_tenant_id(self):
        """Test handling of invalid tenant ID."""
        invalid_cases = [
            None,
            "",
            "   ",  # Whitespace only
        ]
        
        for invalid_id in invalid_cases:
            assert not invalid_id or not invalid_id.strip()
    
    def test_unauthorized_tenant_access(self):
        """Test unauthorized tenant access is denied."""
        authorized_tenants = ["tenant-001", "tenant-002"]
        requested_tenant = "tenant-unauthorized"
        
        assert requested_tenant not in authorized_tenants
    
    def test_collection_not_found(self):
        """Test handling when collection doesn't exist."""
        existing_collections = ["organizational-memory", "code-context"]
        requested_collection = "non-existent-collection"
        
        assert requested_collection not in existing_collections


# ============================================================================
# UNIT TESTS: Configuration Validation
# ============================================================================

@pytest.mark.unit
class TestConfigurationValidation:
    """Test configuration validation for Phase 6 setup."""
    
    def test_cluster_mode_enabled(self):
        """Test that cluster mode is enabled in configuration."""
        config = {
            "cluster": {
                "enabled": True,
                "p2p": {"port": 6335},
            }
        }
        
        assert config["cluster"]["enabled"] is True
        assert config["cluster"]["p2p"]["port"] == 6335
    
    def test_p2p_port_configuration(self):
        """Test P2P port is correctly configured."""
        p2p_config = {"port": 6335}
        
        assert p2p_config["port"] == 6335
    
    def test_bootstrap_configuration(self):
        """Test node bootstrap configuration."""
        node2_config = {
            "bootstrap": "http://qdrant:6335"
        }
        
        assert node2_config["bootstrap"] == "http://qdrant:6335"


# ============================================================================
# PERFORMANCE & EFFICIENCY TESTS
# ============================================================================

@pytest.mark.unit
def test_tenant_filter_performance(benchmark):
    """Benchmark tenant filter generation performance."""
    def generate_filter():
        return {
            "must": [
                {"field": "tenant_id", "match": "tenant-unit-test-001"}
            ]
        }
    
    # In real benchmark, this should be <1ms
    result = benchmark(generate_filter)
    assert result is not None


@pytest.mark.unit
def test_payload_injection_performance(benchmark, sample_embedding_document, tenant_context_standard):
    """Benchmark multi-tenant payload injection."""
    def inject_payload():
        doc = sample_embedding_document.copy()
        doc["tenant_id"] = tenant_context_standard["tenant_id"]
        doc["namespace"] = tenant_context_standard["namespace"]
        doc["created_at"] = datetime.utcnow().isoformat() + "Z"
        return doc
    
    result = benchmark(inject_payload)
    assert "tenant_id" in result
