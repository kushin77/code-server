"""Tests for trace visualization."""

import importlib.util
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

apps_pkg = types.ModuleType("apps")
apps_pkg.__path__ = [str(ROOT.parent)]
sys.modules.setdefault("apps", apps_pkg)

shared_pkg = types.ModuleType("apps.shared")
shared_pkg.__path__ = [str(ROOT)]
sys.modules["apps.shared"] = shared_pkg


def _load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, ROOT / file_name)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


TRACE_VISUALIZATION = _load_module("apps.shared.trace_visualization", "trace_visualization.py")

TimelineSpan = TRACE_VISUALIZATION.TimelineSpan
Timeline = TRACE_VISUALIZATION.Timeline
FlameGraphNode = TRACE_VISUALIZATION.FlameGraphNode
FlameGraph = TRACE_VISUALIZATION.FlameGraph
ServiceNode = TRACE_VISUALIZATION.ServiceNode
ServiceEdge = TRACE_VISUALIZATION.ServiceEdge
ServiceMap = TRACE_VISUALIZATION.ServiceMap
SequenceDiagram = TRACE_VISUALIZATION.SequenceDiagram


class TestTimelineSpan:
    """Test timeline span."""

    def test_span_creation(self):
        """Test creating timeline span."""
        span = TimelineSpan(
            span_id="span_1",
            trace_id="trace_1",
            operation_name="db_query",
            service_name="db_service",
            start_time_ms=1000.0,
            duration_ms=100.0,
            status="OK",
        )

        assert span.operation_name == "db_query"
        assert span.duration_ms == 100.0

    def test_span_to_dict(self):
        """Test converting span to dict."""
        span = TimelineSpan(
            span_id="span_1",
            trace_id="trace_1",
            operation_name="op",
            service_name="svc",
            start_time_ms=1000.0,
            duration_ms=50.0,
            status="OK",
            tags={"key": "value"},
        )

        span_dict = span.to_dict()

        assert span_dict["spanId"] == "span_1"
        assert span_dict["duration"] == 50.0


class TestTimeline:
    """Test timeline visualization."""

    def test_timeline_creation(self):
        """Test creating timeline."""
        timeline = Timeline(trace_id="trace_1")

        assert timeline.trace_id == "trace_1"
        assert len(timeline.spans) == 0

    def test_add_span(self):
        """Test adding spans."""
        timeline = Timeline(trace_id="trace_1")

        span1 = TimelineSpan("s1", "t1", "op1", "svc1", 0, 100, "OK")
        span2 = TimelineSpan("s2", "t1", "op2", "svc2", 100, 50, "OK")

        timeline.add_span(span1).add_span(span2)

        assert len(timeline.spans) == 2

    def test_calculate_depth(self):
        """Test calculating span depth."""
        timeline = Timeline(trace_id="trace_1")

        # Sequential spans
        timeline.add_span(TimelineSpan("s1", "t1", "op1", "svc1", 0, 100, "OK"))
        timeline.add_span(TimelineSpan("s2", "t1", "op2", "svc2", 100, 100, "OK"))
        timeline.add_span(TimelineSpan("s3", "t1", "op3", "svc3", 200, 100, "OK"))

        timeline.calculate_depth()

        # All should be at depth 0 since they don't overlap
        assert all(s.depth == 0 for s in timeline.spans)

    def test_calculate_stats(self):
        """Test calculating timeline stats."""
        timeline = Timeline(trace_id="trace_1")

        timeline.add_span(TimelineSpan("s1", "t1", "op1", "svc1", 0, 100, "OK"))
        timeline.add_span(TimelineSpan("s2", "t1", "op2", "svc2", 50, 100, "OK"))

        timeline.calculate_stats()

        assert timeline.total_duration_ms > 0
        assert timeline.span_count == 2
        assert timeline.service_count == 2

    def test_timeline_to_dict(self):
        """Test converting timeline to dict."""
        timeline = Timeline(trace_id="trace_1")
        timeline.add_span(TimelineSpan("s1", "t1", "op1", "svc1", 0, 100, "OK"))

        timeline_dict = timeline.to_dict()

        assert timeline_dict["traceId"] == "trace_1"
        assert len(timeline_dict["spans"]) == 1


class TestFlameGraphNode:
    """Test flame graph node."""

    def test_node_creation(self):
        """Test creating node."""
        node = FlameGraphNode(
            span_id="s1",
            operation_name="op1",
            service_name="svc1",
            duration_ms=100.0,
            value=100.0,
        )

        assert node.operation_name == "op1"
        assert len(node.children) == 0

    def test_add_child(self):
        """Test adding child node."""
        parent = FlameGraphNode("s1", "op1", "svc1", 100, 100)
        child = FlameGraphNode("s2", "op2", "svc2", 50, 50)

        parent.add_child(child)

        assert len(parent.children) == 1
        assert child.parent == parent

    def test_node_to_dict(self):
        """Test converting node to dict."""
        node = FlameGraphNode("s1", "op1", "svc1", 100, 100)
        child = FlameGraphNode("s2", "op2", "svc2", 50, 50)
        node.add_child(child)

        node_dict = node.to_dict()

        assert node_dict["spanId"] == "s1"
        assert len(node_dict["children"]) == 1


class TestFlameGraph:
    """Test flame graph."""

    def test_graph_creation(self):
        """Test creating flame graph."""
        graph = FlameGraph(trace_id="trace_1")

        assert graph.trace_id == "trace_1"
        assert graph.root is None

    def test_build_from_spans(self):
        """Test building from spans."""
        graph = FlameGraph(trace_id="trace_1")

        spans = [
            {
                "span_id": "s1",
                "operation_name": "op1",
                "service_name": "svc1",
                "duration_ms": 200,
                "parent_span_id": None,
            },
            {
                "span_id": "s2",
                "operation_name": "op2",
                "service_name": "svc2",
                "duration_ms": 100,
                "parent_span_id": "s1",
            },
        ]

        graph.build_from_spans(spans)

        assert graph.root is not None
        assert len(graph.root.children) == 1
        assert graph.total_duration_ms == 200

    def test_graph_to_dict(self):
        """Test converting graph to dict."""
        graph = FlameGraph(trace_id="trace_1")

        spans = [
            {
                "span_id": "s1",
                "operation_name": "op1",
                "service_name": "svc1",
                "duration_ms": 100,
                "parent_span_id": None,
            },
        ]

        graph.build_from_spans(spans)
        graph_dict = graph.to_dict()

        assert graph_dict["traceId"] == "trace_1"
        assert graph_dict["root"] is not None


class TestServiceNode:
    """Test service node."""

    def test_node_creation(self):
        """Test creating service node."""
        node = ServiceNode(
            service_name="api-service",
            operation_count=10,
            error_count=1,
            latency_ms=45.5,
        )

        assert node.service_name == "api-service"
        assert node.operation_count == 10

    def test_node_to_dict(self):
        """Test converting node to dict."""
        node = ServiceNode("service", operation_count=5, latency_ms=123.45)

        node_dict = node.to_dict()

        assert node_dict["service"] == "service"
        assert node_dict["operationCount"] == 5


class TestServiceEdge:
    """Test service edge."""

    def test_edge_creation(self):
        """Test creating edge."""
        edge = ServiceEdge(
            source_service="api",
            target_service="db",
            call_count=100,
            error_count=2,
            avg_latency_ms=50.0,
            p99_latency_ms=150.0,
        )

        assert edge.source_service == "api"
        assert edge.call_count == 100

    def test_edge_to_dict(self):
        """Test converting edge to dict."""
        edge = ServiceEdge("svc1", "svc2", call_count=50, avg_latency_ms=75.0)

        edge_dict = edge.to_dict()

        assert edge_dict["source"] == "svc1"
        assert edge_dict["target"] == "svc2"


class TestServiceMap:
    """Test service map."""

    def test_map_creation(self):
        """Test creating service map."""
        map_viz = ServiceMap(trace_id="trace_1")

        assert len(map_viz.nodes) == 0
        assert len(map_viz.edges) == 0

    def test_add_service(self):
        """Test adding services."""
        map_viz = ServiceMap(trace_id="trace_1")

        map_viz.add_service("api").add_service("db").add_service("cache")

        assert len(map_viz.nodes) == 3

    def test_add_dependency(self):
        """Test adding dependencies."""
        map_viz = ServiceMap(trace_id="trace_1")

        map_viz.add_dependency("api", "db", latency_ms=50.0)
        map_viz.add_dependency("api", "cache", latency_ms=10.0)

        assert len(map_viz.edges) == 2

    def test_dependency_metrics(self):
        """Test dependency metrics."""
        map_viz = ServiceMap(trace_id="trace_1")

        # Add multiple calls with averaging
        map_viz.add_dependency("api", "db", latency_ms=40.0)
        map_viz.add_dependency("api", "db", latency_ms=60.0)

        edge = map_viz.edges[("api", "db")]

        assert edge.call_count == 2
        assert edge.avg_latency_ms == 50.0

    def test_error_tracking(self):
        """Test tracking errors in edges."""
        map_viz = ServiceMap(trace_id="trace_1")

        map_viz.add_dependency("api", "db", latency_ms=50.0, error=False)
        map_viz.add_dependency("api", "db", latency_ms=100.0, error=True)

        edge = map_viz.edges[("api", "db")]

        assert edge.call_count == 2
        assert edge.error_count == 1

    def test_build_from_trace(self):
        """Test building from trace spans."""
        map_viz = ServiceMap(trace_id="trace_1")

        spans = [
            {
                "span_id": "s1",
                "service_name": "api",
                "parent_span_id": None,
            },
            {
                "span_id": "s2",
                "service_name": "db",
                "parent_span_id": "s1",
                "duration_ms": 50.0,
                "status": "OK",
            },
        ]

        map_viz.build_from_trace(spans)

        assert len(map_viz.nodes) == 2
        assert len(map_viz.edges) == 1

    def test_map_to_dict(self):
        """Test converting map to dict."""
        map_viz = ServiceMap(trace_id="trace_1")

        map_viz.add_service("api")
        map_viz.add_dependency("api", "db")

        map_dict = map_viz.to_dict()

        assert map_dict["traceId"] == "trace_1"
        assert len(map_dict["nodes"]) == 2
        assert len(map_dict["edges"]) == 1


class TestSequenceDiagram:
    """Test sequence diagram."""

    def test_diagram_creation(self):
        """Test creating sequence diagram."""
        diagram = SequenceDiagram(trace_id="trace_1")

        assert diagram.trace_id == "trace_1"
        assert len(diagram.actors) == 0

    def test_add_actor(self):
        """Test adding actors."""
        diagram = SequenceDiagram(trace_id="trace_1")

        diagram.add_actor("client").add_actor("api").add_actor("db")

        assert len(diagram.actors) == 3

    def test_add_interaction(self):
        """Test adding interactions."""
        diagram = SequenceDiagram(trace_id="trace_1")

        diagram.add_interaction("client", "api", "request", 100)
        diagram.add_interaction("api", "db", "query", 50)

        assert len(diagram.interactions) == 2

    def test_interaction_with_status(self):
        """Test interaction with status."""
        diagram = SequenceDiagram(trace_id="trace_1")

        diagram.add_interaction("api", "db", "query", 50, status="OK")
        diagram.add_interaction("api", "cache", "miss", 100, status="ERROR")

        assert diagram.interactions[0]["status"] == "OK"
        assert diagram.interactions[1]["status"] == "ERROR"

    def test_diagram_to_dict(self):
        """Test converting diagram to dict."""
        diagram = SequenceDiagram(trace_id="trace_1")

        diagram.add_actor("api")
        diagram.add_interaction("client", "api", "request", 100)

        diagram_dict = diagram.to_dict()

        assert diagram_dict["traceId"] == "trace_1"
        assert len(diagram_dict["actors"]) == 2
        assert len(diagram_dict["interactions"]) == 1


class TestVisualizationIntegration:
    """Integration tests for visualization."""

    def test_full_trace_visualization(self):
        """Test creating all visualizations from a trace."""
        spans = [
            {
                "span_id": "s1",
                "trace_id": "trace_1",
                "operation_name": "http_request",
                "service_name": "api",
                "parent_span_id": None,
                "duration_ms": 150,
                "status": "OK",
            },
            {
                "span_id": "s2",
                "trace_id": "trace_1",
                "operation_name": "db_query",
                "service_name": "db",
                "parent_span_id": "s1",
                "duration_ms": 100,
                "status": "OK",
            },
        ]

        # Create timeline
        timeline = Timeline(trace_id="trace_1")
        for span in spans:
            timeline_span = TimelineSpan(
                span_id=span["span_id"],
                trace_id=span["trace_id"],
                operation_name=span["operation_name"],
                service_name=span["service_name"],
                start_time_ms=0,
                duration_ms=span["duration_ms"],
                status=span["status"],
            )
            timeline.add_span(timeline_span)

        # Create flame graph
        flame_graph = FlameGraph(trace_id="trace_1")
        flame_graph.build_from_spans(spans)

        # Create service map
        service_map = ServiceMap(trace_id="trace_1")
        service_map.build_from_trace(spans)

        # Create sequence diagram
        sequence = SequenceDiagram(trace_id="trace_1")
        sequence.add_interaction("client", "api", "request", 150)
        sequence.add_interaction("api", "db", "query", 100)

        # Verify all created
        assert len(timeline.spans) == 2
        assert flame_graph.root is not None
        assert len(service_map.nodes) == 2
        assert len(sequence.actors) >= 2
