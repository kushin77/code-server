"""Tests for trace querying system."""

import importlib.util
import sys
import types
from datetime import datetime, timedelta
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


TRACE_QUERY = _load_module("apps.shared.trace_query", "trace_query.py")

ComparisonOperator = TRACE_QUERY.ComparisonOperator
SortOrder = TRACE_QUERY.SortOrder
FilterCondition = TRACE_QUERY.FilterCondition
TraceQuery = TRACE_QUERY.TraceQuery
QueryResult = TRACE_QUERY.QueryResult
TraceQueryEngine = TRACE_QUERY.TraceQueryEngine
TraceAggregator = TRACE_QUERY.TraceAggregator


class TestFilterCondition:
    """Test filter conditions."""

    def test_eq_operator(self):
        """Test equality operator."""
        condition = FilterCondition("service_name", ComparisonOperator.EQ, "api")
        assert condition.matches({"service_name": "api"})
        assert not condition.matches({"service_name": "db"})

    def test_ne_operator(self):
        """Test not-equal operator."""
        condition = FilterCondition("status", ComparisonOperator.NE, "ERROR")
        assert condition.matches({"status": "OK"})
        assert not condition.matches({"status": "ERROR"})

    def test_lt_operator(self):
        """Test less-than operator."""
        condition = FilterCondition("duration_ms", ComparisonOperator.LT, 100)
        assert condition.matches({"duration_ms": 50})
        assert not condition.matches({"duration_ms": 150})

    def test_gte_operator(self):
        """Test greater-or-equal operator."""
        condition = FilterCondition("span_count", ComparisonOperator.GE, 5)
        assert condition.matches({"span_count": 5})
        assert condition.matches({"span_count": 10})
        assert not condition.matches({"span_count": 3})

    def test_in_operator(self):
        """Test in operator."""
        condition = FilterCondition("service_name", ComparisonOperator.IN, ["api", "db"])
        assert condition.matches({"service_name": "api"})
        assert condition.matches({"service_name": "db"})
        assert not condition.matches({"service_name": "cache"})

    def test_contains_operator(self):
        """Test contains operator."""
        condition = FilterCondition("operation", ComparisonOperator.CONTAINS, "query")
        assert condition.matches({"operation": "db_query"})
        assert condition.matches({"operation": "query_cache"})
        assert not condition.matches({"operation": "db_select"})


class TestTraceQuery:
    """Test trace query builder."""

    def test_filter_trace_id(self):
        """Test filtering by trace ID."""
        query = TraceQuery().filter_trace_id("trace_123")

        assert len(query.filters) == 1
        assert query.filters[0].field == "trace_id"

    def test_filter_service(self):
        """Test filtering by service."""
        query = TraceQuery().filter_service("api-service")

        assert len(query.filters) == 1
        assert query.filters[0].value == "api-service"

    def test_filter_duration(self):
        """Test filtering by duration."""
        query = (
            TraceQuery()
            .filter_min_duration(50)
            .filter_max_duration(500)
        )

        assert len(query.filters) == 2

    def test_filter_status(self):
        """Test filtering by status."""
        query = TraceQuery().filter_status("ERROR")

        assert query.filters[0].value == "ERROR"

    def test_filter_tag(self):
        """Test filtering by tag."""
        query = TraceQuery().filter_tag("http.status", 200)

        assert query.filters[0].field == "tags.http.status"

    def test_set_limit_and_offset(self):
        """Test setting limit and offset."""
        query = TraceQuery().set_limit(50).set_offset(100)

        assert query.limit == 50
        assert query.offset == 100

    def test_sort(self):
        """Test sorting."""
        query = TraceQuery().sort("duration_ms", SortOrder.ASC)

        assert query.sort_by == "duration_ms"
        assert query.sort_order == SortOrder.ASC

    def test_query_chaining(self):
        """Test method chaining."""
        query = (
            TraceQuery()
            .filter_service("api")
            .filter_min_duration(100)
            .sort("duration_ms", SortOrder.DESC)
            .set_limit(25)
        )

        assert len(query.filters) == 2
        assert query.sort_by == "duration_ms"
        assert query.limit == 25

    def test_time_range_filter(self):
        """Test time range filtering."""
        now = datetime.now()
        start = now - timedelta(hours=1)
        end = now

        query = TraceQuery().filter_time_range(start, end)

        assert query.time_start == start
        assert query.time_end == end


class TestQueryResult:
    """Test query results."""

    def test_result_creation(self):
        """Test creating query result."""
        result = QueryResult(
            total_count=100,
            returned_count=10,
            traces=[],
            query_time_ms=15.5,
        )

        assert result.total_count == 100
        assert result.returned_count == 10

    def test_result_to_dict(self):
        """Test converting result to dict."""
        result = QueryResult(
            total_count=50,
            returned_count=5,
            traces=[{"trace_id": "t1"}],
            query_time_ms=8.2,
        )

        result_dict = result.to_dict()

        assert result_dict["totalCount"] == 50
        assert "queryTimeMs" in result_dict


class TestTraceQueryEngine:
    """Test query engine."""

    def test_engine_creation(self):
        """Test creating engine."""
        engine = TraceQueryEngine()

        assert len(engine.traces) == 0

    def test_add_trace(self):
        """Test adding traces."""
        engine = TraceQueryEngine()

        engine.add_trace({"trace_id": "t1", "service_name": "api"})
        engine.add_trace({"trace_id": "t2", "service_name": "db"})

        assert len(engine.traces) == 2

    def test_simple_query(self):
        """Test simple query."""
        engine = TraceQueryEngine()

        engine.add_trace({"trace_id": "t1", "service_name": "api", "duration_ms": 100})
        engine.add_trace({"trace_id": "t2", "service_name": "db", "duration_ms": 50})
        engine.add_trace({"trace_id": "t3", "service_name": "api", "duration_ms": 200})

        query = TraceQuery().filter_service("api")
        result = engine.execute(query)

        assert result.total_count == 2
        assert result.returned_count == 2

    def test_duration_filter(self):
        """Test duration filtering."""
        engine = TraceQueryEngine()

        for i in range(5):
            engine.add_trace({
                "trace_id": f"t{i}",
                "duration_ms": (i + 1) * 100,
            })

        query = TraceQuery().filter_min_duration(300).filter_max_duration(500)
        result = engine.execute(query)

        assert result.total_count == 2  # 300 and 400ms

    def test_sorting(self):
        """Test query sorting."""
        engine = TraceQueryEngine()

        engine.add_trace({"trace_id": "t1", "duration_ms": 100})
        engine.add_trace({"trace_id": "t2", "duration_ms": 300})
        engine.add_trace({"trace_id": "t3", "duration_ms": 200})

        query = TraceQuery().sort("duration_ms", SortOrder.ASC)
        result = engine.execute(query)

        assert result.traces[0]["duration_ms"] == 100
        assert result.traces[1]["duration_ms"] == 200
        assert result.traces[2]["duration_ms"] == 300

    def test_pagination(self):
        """Test result pagination."""
        engine = TraceQueryEngine()

        for i in range(25):
            engine.add_trace({"trace_id": f"t{i}"})

        # First page
        query = TraceQuery().set_limit(10).set_offset(0)
        result1 = engine.execute(query)
        assert result1.returned_count == 10
        assert result1.total_count == 25

        # Second page
        query = TraceQuery().set_limit(10).set_offset(10)
        result2 = engine.execute(query)
        assert result2.returned_count == 10

        # Third page (partial)
        query = TraceQuery().set_limit(10).set_offset(20)
        result3 = engine.execute(query)
        assert result3.returned_count == 5

    def test_multiple_filters(self):
        """Test multiple filters."""
        engine = TraceQueryEngine()

        engine.add_trace({
            "trace_id": "t1",
            "service_name": "api",
            "status": "OK",
            "duration_ms": 100,
        })
        engine.add_trace({
            "trace_id": "t2",
            "service_name": "api",
            "status": "ERROR",
            "duration_ms": 200,
        })
        engine.add_trace({
            "trace_id": "t3",
            "service_name": "db",
            "status": "OK",
            "duration_ms": 50,
        })

        query = (
            TraceQuery()
            .filter_service("api")
            .filter_status("OK")
        )
        result = engine.execute(query)

        assert result.total_count == 1


class TestTraceAggregator:
    """Test trace aggregation."""

    def test_by_service(self):
        """Test grouping by service."""
        traces = [
            {"trace_id": "t1", "service_name": "api"},
            {"trace_id": "t2", "service_name": "db"},
            {"trace_id": "t3", "service_name": "api"},
        ]

        grouped = TraceAggregator.by_service(traces)

        assert len(grouped["api"]) == 2
        assert len(grouped["db"]) == 1

    def test_by_operation(self):
        """Test grouping by operation."""
        traces = [
            {"trace_id": "t1", "operation_name": "query"},
            {"trace_id": "t2", "operation_name": "insert"},
            {"trace_id": "t3", "operation_name": "query"},
        ]

        grouped = TraceAggregator.by_operation(traces)

        assert len(grouped["query"]) == 2
        assert len(grouped["insert"]) == 1

    def test_by_status(self):
        """Test grouping by status."""
        traces = [
            {"trace_id": "t1", "status": "OK"},
            {"trace_id": "t2", "status": "ERROR"},
            {"trace_id": "t3", "status": "OK"},
        ]

        grouped = TraceAggregator.by_status(traces)

        assert len(grouped["OK"]) == 2
        assert len(grouped["ERROR"]) == 1

    def test_summary_stats(self):
        """Test calculating summary stats."""
        traces = [
            {"duration_ms": 100},
            {"duration_ms": 200},
            {"duration_ms": 300},
            {"duration_ms": 400},
            {"duration_ms": 500},
        ]

        stats = TraceAggregator.summary_stats(traces)

        assert stats["count"] == 5
        assert stats["min_duration_ms"] == 100
        assert stats["max_duration_ms"] == 500
        assert stats["avg_duration_ms"] == 300

    def test_summary_stats_empty(self):
        """Test summary stats with empty traces."""
        stats = TraceAggregator.summary_stats([])

        assert stats == {}
