"""Tests for external service tracing instrumentation."""

import asyncio
import pytest
from apps.shared.external_tracing import (
    ExternalCallSpan,
    GitHubTracer,
    GCPTracer,
    trace_external_call,
)
from apps.shared.github_integration import GitHubIntegration, get_github_integration


class TestExternalCallSpan:
    """Test ExternalCallSpan dataclass."""

    def test_span_creation(self):
        """Test span can be created with required fields."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            method="GET",
        )

        assert span.service == "github"
        assert span.operation == "github.get_repo"
        assert span.endpoint == "/repos/owner/repo"
        assert span.method == "GET"
        assert span.start_time > 0

    def test_span_duration_calculation(self):
        """Test span duration is calculated correctly."""
        import time

        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
        )

        # Simulate some work
        time.sleep(0.1)
        span.end_time = span.start_time + 0.1

        # Duration should be approximately 100ms
        assert 90 < span.duration_ms < 110

    def test_span_status_ok(self):
        """Test span status is OK for successful calls."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            status_code=200,
        )

        assert span.status == "OK"

    def test_span_status_error_400(self):
        """Test span status is ERROR for 4xx responses."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            status_code=404,
        )

        assert span.status == "ERROR"

    def test_span_status_error_500(self):
        """Test span status is ERROR for 5xx responses."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            status_code=500,
        )

        assert span.status == "ERROR"

    def test_span_status_error_exception(self):
        """Test span status is ERROR when exception occurred."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            error="Connection timeout",
        )

        assert span.status == "ERROR"

    def test_span_to_dict(self):
        """Test span can be converted to dictionary."""
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            method="GET",
            status_code=200,
            response_size=1024,
        )
        span.end_time = span.start_time + 0.05

        span_dict = span.to_dict()

        assert span_dict["service"] == "github"
        assert span_dict["operation"] == "github.get_repo"
        assert span_dict["status"] == "OK"
        assert span_dict["status_code"] == 200
        assert span_dict["response_size"] == 1024
        assert span_dict["duration_ms"] > 0


class TestGitHubTracer:
    """Test GitHubTracer for GitHub API calls."""

    @pytest.mark.asyncio
    async def test_github_tracer_initialization(self):
        """Test GitHubTracer initialization."""
        tracer = GitHubTracer(token="test-token")

        assert tracer.service_name == "github"
        assert tracer.base_url == "https://api.github.com"
        assert tracer.token == "test-token"

    @pytest.mark.asyncio
    async def test_github_get_request(self):
        """Test GitHub GET request tracing."""
        tracer = GitHubTracer()

        result = await tracer.get("/repos/owner/repo")

        assert "status" in result
        assert len(tracer.get_spans()) == 1

        span = tracer.get_spans()[0]
        assert span.service == "github"
        assert span.method == "GET"
        assert span.status_code == 200
        assert span.endpoint == "/repos/owner/repo"

    @pytest.mark.asyncio
    async def test_github_post_request(self):
        """Test GitHub POST request tracing."""
        tracer = GitHubTracer()

        result = await tracer.post("/repos/owner/repo/issues", data={"title": "Bug"})

        assert "status" in result
        assert len(tracer.get_spans()) == 1

        span = tracer.get_spans()[0]
        assert span.service == "github"
        assert span.method == "POST"
        assert span.status_code == 201
        assert span.request_size > 0

    @pytest.mark.asyncio
    async def test_github_multiple_requests(self):
        """Test multiple GitHub requests are tracked."""
        tracer = GitHubTracer()

        await tracer.get("/repos/owner/repo1")
        await tracer.get("/repos/owner/repo2")
        await tracer.post("/repos/owner/repo1/issues", data={"title": "Issue"})

        spans = tracer.get_spans()
        assert len(spans) == 3

        # Check span types
        assert spans[0].method == "GET"
        assert spans[1].method == "GET"
        assert spans[2].method == "POST"

    @pytest.mark.asyncio
    async def test_github_tracer_export_spans(self):
        """Test span export for tracing backend."""
        tracer = GitHubTracer()

        await tracer.get("/repos/owner/repo")

        exported = tracer.export_spans()
        assert len(exported) == 1
        assert exported[0]["service"] == "github"
        assert "duration_ms" in exported[0]

    def test_github_tracer_clear_spans(self):
        """Test span clearing."""
        tracer = GitHubTracer()

        # Create mock span
        span = ExternalCallSpan(
            service="github",
            operation="github.test",
            endpoint="/test",
        )
        tracer.record_span(span)

        assert len(tracer.get_spans()) == 1

        tracer.clear_spans()
        assert len(tracer.get_spans()) == 0


class TestGCPTracer:
    """Test GCPTracer for Google Cloud Platform calls."""

    @pytest.mark.asyncio
    async def test_gcp_tracer_initialization(self):
        """Test GCPTracer initialization."""
        tracer = GCPTracer(project_id="my-project", service="storage")

        assert tracer.service_name == "gcp-storage"
        assert tracer.project_id == "my-project"

    @pytest.mark.asyncio
    async def test_gcp_get_request(self):
        """Test GCP GET request tracing."""
        tracer = GCPTracer(project_id="my-project", service="storage")

        result = await tracer.get("/storage/v1/b/bucket-name")

        assert "status" in result
        assert len(tracer.get_spans()) == 1

        span = tracer.get_spans()[0]
        assert "gcp" in span.service
        assert span.method == "GET"
        assert span.attributes["project_id"] == "my-project"

    @pytest.mark.asyncio
    async def test_gcp_post_request(self):
        """Test GCP POST request tracing."""
        tracer = GCPTracer(project_id="my-project", service="bigquery")

        result = await tracer.post(
            "/bigquery/v2/projects/my-project/datasets",
            data={"datasetId": "my_dataset"},
        )

        assert "status" in result
        assert len(tracer.get_spans()) == 1

        span = tracer.get_spans()[0]
        assert span.method == "POST"
        assert span.request_size > 0
        assert span.attributes["gcp_service"] == "bigquery"

    @pytest.mark.asyncio
    async def test_gcp_multiple_services(self):
        """Test tracing calls to multiple GCP services."""
        storage_tracer = GCPTracer(project_id="my-project", service="storage")
        bigquery_tracer = GCPTracer(project_id="my-project", service="bigquery")

        await storage_tracer.get("/storage/v1/b")
        await bigquery_tracer.get("/bigquery/v2/projects/my-project/datasets")

        assert len(storage_tracer.get_spans()) == 1
        assert len(bigquery_tracer.get_spans()) == 1
        assert storage_tracer.get_spans()[0].service == "gcp-storage"
        assert bigquery_tracer.get_spans()[0].service == "gcp-bigquery"


class TestTraceExternalCallDecorator:
    """Test trace_external_call decorator."""

    @pytest.mark.asyncio
    async def test_decorator_async_function(self):
        """Test decorator on async function."""
        tracer = GitHubTracer()

        @trace_external_call(tracer, "github.test_op")
        async def mock_call():
            return await tracer.get("/test")

        result = await mock_call()
        assert "status" in result

    @pytest.mark.asyncio
    async def test_decorator_with_capture_response(self):
        """Test decorator with response capture."""
        tracer = GitHubTracer()

        @trace_external_call(tracer, "github.test_op", capture_response=True)
        async def mock_call():
            return await tracer.get("/test")

        result = await mock_call()
        spans = tracer.get_spans()
        assert len(spans) == 1
        assert "response_type" in spans[0].attributes

    def test_decorator_sync_function(self):
        """Test decorator on sync function."""

        def mock_call():
            return {"status": "ok", "_span": ExternalCallSpan(
                service="test",
                operation="test.op",
                endpoint="/test",
            )}

        decorated = trace_external_call(
            GitHubTracer(), "test.op"
        )(mock_call)

        result = decorated()
        assert "status" in result
        # Span should be extracted and removed from result
        assert "_span" not in result


class TestIntegration:
    """Integration tests for external tracing."""

    @pytest.mark.asyncio
    async def test_multi_service_trace_correlation(self):
        """Test tracing calls across multiple services."""
        github_tracer = GitHubTracer()
        gcp_tracer = GCPTracer(project_id="my-project", service="storage")

        # Simulate a workflow that calls both services
        await github_tracer.get("/repos/owner/repo")
        await gcp_tracer.post(
            "/storage/v1/b/code-server-backup",
            data={"name": "backup"},
        )

        # Both tracers should have recorded spans
        assert len(github_tracer.get_spans()) == 1
        assert len(gcp_tracer.get_spans()) == 1

        # Spans can be exported for centralized tracing
        github_spans = github_tracer.export_spans()
        gcp_spans = gcp_tracer.export_spans()

        assert len(github_spans) == 1
        assert len(gcp_spans) == 1
        assert github_spans[0]["service"] == "github"
        assert "gcp" in gcp_spans[0]["service"]

    @pytest.mark.asyncio
    async def test_error_handling_in_spans(self):
        """Test error handling in external call spans."""
        tracer = GitHubTracer()

        # Create span with error
        span = ExternalCallSpan(
            service="github",
            operation="github.get_repo",
            endpoint="/repos/owner/repo",
            error="Request timeout",
        )

        assert span.status == "ERROR"
        assert span.error == "Request timeout"

        span_dict = span.to_dict()
        assert span_dict["status"] == "ERROR"
        assert span_dict["error"] == "Request timeout"


class TestGitHubIntegration:
    """Test GitHub integration wrapper that uses external tracing."""

    def test_singleton_accessor(self):
        integration_a = get_github_integration()
        integration_b = get_github_integration()

        assert integration_a is integration_b
        assert isinstance(integration_a, GitHubIntegration)

    @pytest.mark.asyncio
    async def test_get_user_records_trace(self):
        integration = GitHubIntegration(token="test-token")

        user = await integration.get_user("octocat")

        assert user is not None
        assert user.login == "octocat"
        traces = integration.get_traces()
        assert len(traces) == 1
        assert traces[0]["service"] == "github"
        assert traces[0]["status"] == "OK"

    @pytest.mark.asyncio
    async def test_create_pull_request_records_trace(self):
        integration = GitHubIntegration(token="test-token")

        pull_request = await integration.create_pull_request(
            owner="code-server",
            repo="code-server",
            title="Improve tracing",
            body="Add external tracing coverage",
            head="feature/tracing",
            base="main",
        )

        assert pull_request is not None
        assert pull_request.title == "Improve tracing"
        traces = integration.get_traces()
        assert len(traces) == 1
        assert traces[0]["method"] == "POST"
