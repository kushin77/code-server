"""Tests for external service tracing instrumentation.

Direct module loader (no pytest dependency).
Async test support via asyncio.run() wrappers.
"""

import asyncio
import importlib.util
import sys
import types
from pathlib import Path

# Create synthetic apps module structure
ROOT = Path(__file__).parent.parent.parent
apps_pkg = types.ModuleType("apps")
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
sys.modules["apps.shared"] = shared_pkg

# Load external_tracing module
spec = importlib.util.spec_from_file_location(
    "external_tracing",
    ROOT / "shared" / "external_tracing.py"
)
external_tracing_mod = importlib.util.module_from_spec(spec)
sys.modules["apps.shared.external_tracing"] = external_tracing_mod
spec.loader.exec_module(external_tracing_mod)

# Load github_integration module
spec = importlib.util.spec_from_file_location(
    "github_integration",
    ROOT / "shared" / "github_integration.py"
)
github_integration_mod = importlib.util.module_from_spec(spec)
sys.modules["apps.shared.github_integration"] = github_integration_mod
spec.loader.exec_module(github_integration_mod)

# Export symbols for tests
ExternalCallSpan = external_tracing_mod.ExternalCallSpan
GitHubTracer = external_tracing_mod.GitHubTracer
GCPTracer = external_tracing_mod.GCPTracer
trace_external_call = external_tracing_mod.trace_external_call
GitHubIntegration = github_integration_mod.GitHubIntegration
get_github_integration = github_integration_mod.get_github_integration


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

    def test_github_tracer_initialization_async(self):
        """Test GitHubTracer initialization."""
        async def _test():
            tracer = GitHubTracer(token="test-token")

            assert tracer.service_name == "github"
            assert tracer.base_url == "https://api.github.com"
            assert tracer.token == "test-token"

        asyncio.run(_test())

    def test_github_get_request_async(self):
        """Test GitHub GET request tracing."""
        async def _test():
            tracer = GitHubTracer()

            result = await tracer.get("/repos/owner/repo")

            assert "status" in result
            assert len(tracer.get_spans()) == 1

            span = tracer.get_spans()[0]
            assert span.service == "github"
            assert span.method == "GET"
            assert span.status_code == 200
            assert span.endpoint == "/repos/owner/repo"

        asyncio.run(_test())

    def test_github_post_request_async(self):
        """Test GitHub POST request tracing."""
        async def _test():
            tracer = GitHubTracer()

            result = await tracer.post("/repos/owner/repo/issues", data={"title": "Bug"})

            assert "status" in result
            assert len(tracer.get_spans()) == 1

            span = tracer.get_spans()[0]
            assert span.service == "github"
            assert span.method == "POST"
            assert span.status_code == 201
            assert span.request_size > 0

        asyncio.run(_test())

    def test_github_multiple_requests_async(self):
        """Test multiple GitHub requests are tracked."""
        async def _test():
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

        asyncio.run(_test())

    def test_github_tracer_export_spans_async(self):
        """Test span export for tracing backend."""
        async def _test():
            tracer = GitHubTracer()

            await tracer.get("/repos/owner/repo")

            exported = tracer.export_spans()
            assert len(exported) == 1
            assert exported[0]["service"] == "github"
            assert "duration_ms" in exported[0]

        asyncio.run(_test())

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

    def test_gcp_tracer_initialization_async(self):
        """Test GCPTracer initialization."""
        async def _test():
            tracer = GCPTracer(project_id="my-project", service="storage")

            assert tracer.service_name == "gcp-storage"
            assert tracer.project_id == "my-project"

        asyncio.run(_test())

    def test_gcp_get_request_async(self):
        """Test GCP GET request tracing."""
        async def _test():
            tracer = GCPTracer(project_id="my-project", service="storage")

            result = await tracer.get("/storage/v1/b/bucket-name")

            assert "status" in result
            assert len(tracer.get_spans()) == 1

            span = tracer.get_spans()[0]
            assert "gcp" in span.service
            assert span.method == "GET"
            assert span.attributes["project_id"] == "my-project"

        asyncio.run(_test())

    def test_gcp_post_request_async(self):
        """Test GCP POST request tracing."""
        async def _test():
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

        asyncio.run(_test())

    def test_gcp_multiple_services_async(self):
        """Test tracing calls to multiple GCP services."""
        async def _test():
            storage_tracer = GCPTracer(project_id="my-project", service="storage")
            bigquery_tracer = GCPTracer(project_id="my-project", service="bigquery")

            await storage_tracer.get("/storage/v1/b")
            await bigquery_tracer.get("/bigquery/v2/projects/my-project/datasets")

            assert len(storage_tracer.get_spans()) == 1
            assert len(bigquery_tracer.get_spans()) == 1
            assert storage_tracer.get_spans()[0].service == "gcp-storage"
            assert bigquery_tracer.get_spans()[0].service == "gcp-bigquery"

        asyncio.run(_test())


class TestTraceExternalCallDecorator:
    """Test trace_external_call decorator."""

    def test_decorator_async_function_wrapper(self):
        """Test decorator on async function."""
        async def _test():
            tracer = GitHubTracer()

            @trace_external_call(tracer, "github.test_op")
            async def mock_call():
                return await tracer.get("/test")

            result = await mock_call()
            assert "status" in result

        asyncio.run(_test())

    def test_decorator_with_capture_response_wrapper(self):
        """Test decorator with response capture."""
        async def _test():
            tracer = GitHubTracer()

            @trace_external_call(tracer, "github.test_op", capture_response=True)
            async def mock_call():
                return await tracer.get("/test")

            result = await mock_call()
            spans = tracer.get_spans()
            assert len(spans) == 1
            assert "response_type" in spans[0].attributes

        asyncio.run(_test())

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

    def test_multi_service_trace_correlation_async(self):
        """Test tracing calls across multiple services."""
        async def _test():
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

        asyncio.run(_test())

    def test_error_handling_in_spans_async(self):
        """Test error handling in external call spans."""
        async def _test():
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

        asyncio.run(_test())


class TestGitHubIntegration:
    """Test GitHub integration wrapper that uses external tracing."""

    def test_singleton_accessor(self):
        integration_a = get_github_integration()
        integration_b = get_github_integration()

        assert integration_a is integration_b
        assert isinstance(integration_a, GitHubIntegration)

    def test_get_user_records_trace_async(self):
        async def _test():
            integration = GitHubIntegration(token="test-token")

            user = await integration.get_user("octocat")

            assert user is not None
            assert user.login == "octocat"
            traces = integration.get_traces()
            assert len(traces) == 1
            assert traces[0]["service"] == "github"
            assert traces[0]["status"] == "OK"

        asyncio.run(_test())

    def test_create_pull_request_records_trace_async(self):
        async def _test():
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

        asyncio.run(_test())
