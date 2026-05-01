"""Tests for GCP integration service with distributed tracing."""

import pytest
from apps.shared.gcp_integration import (
    GCPIntegration,
    GCPStorageBucket,
    GCPBigQueryDataset,
    get_gcp_integration,
)


class TestGCPStorageBucket:
    """Test GCPStorageBucket dataclass."""

    def test_bucket_creation(self):
        """Test bucket can be created."""
        bucket = GCPStorageBucket(
            name="test-bucket",
            project="my-project",
            location="US",
            storage_class="STANDARD",
            created="2026-05-01T00:00:00Z",
            updated="2026-05-01T12:00:00Z",
        )

        assert bucket.name == "test-bucket"
        assert bucket.project == "my-project"
        assert bucket.location == "US"

    def test_bucket_to_dict(self):
        """Test bucket can be converted to dictionary."""
        bucket = GCPStorageBucket(
            name="test-bucket",
            project="my-project",
            location="US",
            storage_class="STANDARD",
            created="2026-05-01T00:00:00Z",
            updated="2026-05-01T12:00:00Z",
            size_bytes=1073741824,
            object_count=1000,
        )

        bucket_dict = bucket.to_dict()
        assert bucket_dict["name"] == "test-bucket"
        assert bucket_dict["size_bytes"] == 1073741824
        assert bucket_dict["object_count"] == 1000


class TestGCPBigQueryDataset:
    """Test GCPBigQueryDataset dataclass."""

    def test_dataset_creation(self):
        """Test dataset can be created."""
        dataset = GCPBigQueryDataset(
            dataset_id="my_dataset",
            project="my-project",
            description="Test dataset",
            location="US",
            created="2026-05-01T00:00:00Z",
        )

        assert dataset.dataset_id == "my_dataset"
        assert dataset.project == "my-project"
        assert dataset.location == "US"

    def test_dataset_to_dict(self):
        """Test dataset can be converted to dictionary."""
        dataset = GCPBigQueryDataset(
            dataset_id="my_dataset",
            project="my-project",
            description="Test dataset",
            location="US",
            created="2026-05-01T00:00:00Z",
            table_count=5,
        )

        dataset_dict = dataset.to_dict()
        assert dataset_dict["dataset_id"] == "my_dataset"
        assert dataset_dict["table_count"] == 5


class TestGCPIntegration:
    """Test GCPIntegration service."""

    def test_gcp_integration_initialization(self):
        """Test GCP integration initialization."""
        integration = GCPIntegration(project_id="my-project")

        assert integration.project_id == "my-project"
        assert integration.storage_tracer is not None
        assert integration.bigquery_tracer is not None
        assert integration.pubsub_tracer is not None
        assert integration.functions_tracer is not None

    @pytest.mark.asyncio
    async def test_get_storage_bucket(self):
        """Test getting storage bucket information."""
        integration = GCPIntegration(project_id="my-project")

        bucket = await integration.get_storage_bucket("test-bucket")

        assert bucket is not None
        assert bucket.name == "test-bucket"
        assert bucket.project == "my-project"
        assert bucket.object_count == 1000

    @pytest.mark.asyncio
    async def test_list_storage_buckets(self):
        """Test listing storage buckets."""
        integration = GCPIntegration(project_id="my-project")

        buckets = await integration.list_storage_buckets()

        assert len(buckets) == 3
        for i, bucket in enumerate(buckets):
            assert bucket.name == f"bucket-{i}"
            assert bucket.project == "my-project"

    @pytest.mark.asyncio
    async def test_create_bigquery_dataset(self):
        """Test creating BigQuery dataset."""
        integration = GCPIntegration(project_id="my-project")

        dataset = await integration.create_bigquery_dataset(
            dataset_id="test_dataset",
            description="Test dataset for Phase 11",
        )

        assert dataset is not None
        assert dataset.dataset_id == "test_dataset"
        assert dataset.project == "my-project"
        assert dataset.description == "Test dataset for Phase 11"

    @pytest.mark.asyncio
    async def test_get_bigquery_dataset(self):
        """Test getting BigQuery dataset information."""
        integration = GCPIntegration(project_id="my-project")

        dataset = await integration.get_bigquery_dataset("test_dataset")

        assert dataset is not None
        assert dataset.dataset_id == "test_dataset"
        assert dataset.table_count == 5

    @pytest.mark.asyncio
    async def test_publish_message(self):
        """Test publishing to Pub/Sub topic."""
        integration = GCPIntegration(project_id="my-project")

        success = await integration.publish_message(
            topic_name="test-topic",
            message="Hello, Pub/Sub!",
            attributes={"source": "phase-11"},
        )

        assert success is True

    @pytest.mark.asyncio
    async def test_invoke_function(self):
        """Test invoking Cloud Function."""
        integration = GCPIntegration(project_id="my-project")

        result = await integration.invoke_function(
            function_name="test-function",
            data={"name": "world"},
            region="us-central1",
        )

        assert result is not None
        assert result["result"] == "Function executed successfully"

    def test_gcp_get_all_traces(self):
        """Test getting all recorded traces."""
        integration = GCPIntegration(project_id="my-project")

        traces = integration.get_all_traces()

        assert "storage" in traces
        assert "bigquery" in traces
        assert "pubsub" in traces
        assert "functions" in traces
        assert isinstance(traces["storage"], list)

    def test_gcp_clear_all_traces(self):
        """Test clearing all traces."""
        integration = GCPIntegration(project_id="my-project")

        # Should not raise
        integration.clear_all_traces()

        traces = integration.get_all_traces()
        for service_traces in traces.values():
            assert len(service_traces) == 0


class TestGCPIntegrationSingleton:
    """Test GCP integration singleton."""

    def test_get_gcp_integration_singleton(self):
        """Test getting GCP integration singleton."""
        integration1 = get_gcp_integration()
        integration2 = get_gcp_integration()

        # Should be same instance
        assert integration1 is integration2

    @pytest.mark.asyncio
    async def test_gcp_integration_multi_service_tracing(self):
        """Test tracing calls across multiple GCP services."""
        integration = GCPIntegration(project_id="my-project")

        # Call multiple services
        bucket = await integration.get_storage_bucket("test-bucket")
        dataset = await integration.create_bigquery_dataset("test_dataset")
        success = await integration.publish_message("test-topic", "test")

        # All should succeed
        assert bucket is not None
        assert dataset is not None
        assert success is True

        # Get traces from all services
        traces = integration.get_all_traces()
        total_traces = sum(len(t) for t in traces.values())

        # Should have at least 3 traces (one from each service)
        assert total_traces >= 3


class TestGCPIntegrationErrorHandling:
    """Test GCP integration error handling."""

    @pytest.mark.asyncio
    async def test_get_nonexistent_bucket_returns_none(self):
        """Test getting nonexistent bucket."""
        integration = GCPIntegration(project_id="my-project")

        # Should return None instead of raising
        bucket = await integration.get_storage_bucket("nonexistent")
        assert bucket is None

    @pytest.mark.asyncio
    async def test_trace_correlation_across_services(self):
        """Test trace correlation across services."""
        integration = GCPIntegration(project_id="my-project")

        # Make calls to different services
        await integration.get_storage_bucket("bucket-1")
        await integration.get_bigquery_dataset("dataset-1")
        await integration.publish_message("topic-1", "message")

        # Each service tracer should have traces
        traces = integration.get_all_traces()
        assert len(traces["storage"]) >= 1
        assert len(traces["bigquery"]) >= 1
        assert len(traces["pubsub"]) >= 1
