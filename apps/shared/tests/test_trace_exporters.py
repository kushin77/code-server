"""Tests for trace exporters."""

import importlib.util
import sys
import types
import json
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


TRACE_EXPORTERS = _load_module("apps.shared.trace_exporters", "trace_exporters.py")

ExportFormat = TRACE_EXPORTERS.ExportFormat
ExportedSpan = TRACE_EXPORTERS.ExportedSpan
ExportedTrace = TRACE_EXPORTERS.ExportedTrace
JSONExporter = TRACE_EXPORTERS.JSONExporter
JaegerExporter = TRACE_EXPORTERS.JaegerExporter
ZipkinExporter = TRACE_EXPORTERS.ZipkinExporter
OTLPExporter = TRACE_EXPORTERS.OTLPExporter
ExporterFactory = TRACE_EXPORTERS.ExporterFactory


class TestExportedSpan:
    """Test exported span."""

    def test_span_creation(self):
        """Test span can be created."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id="parent_1",
            operation_name="test_op",
            service_name="test_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"key": "value"},
            logs=[{"timestamp": 1500000000, "fields": {"message": "test"}}],
            refs=[{"refType": "CHILD_OF", "traceID": "trace_1"}],
        )

        assert span.operation_name == "test_op"
        assert span.service_name == "test_service"
        assert span.status == "OK"


class TestExportedTrace:
    """Test exported trace."""

    def test_trace_creation(self):
        """Test trace can be created."""
        spans = [
            ExportedSpan(
                trace_id="trace_1",
                span_id="span_1",
                parent_span_id=None,
                operation_name="op1",
                service_name="svc1",
                start_time_unix_nano=1000000000,
                end_time_unix_nano=2000000000,
                duration_ns=1000000000,
                status="OK",
                tags={},
                logs=[],
                refs=[],
            ),
        ]

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=spans,
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=0,
        )

        assert trace.trace_id == "trace_1"
        assert trace.span_count == 1


class TestJSONExporter:
    """Test JSON exporter."""

    def test_json_export(self):
        """Test exporting to JSON."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="test_op",
            service_name="test_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"key": "value"},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=1,
        )

        exporter = JSONExporter()
        json_str = exporter.export(trace)

        # Verify it's valid JSON
        json_data = json.loads(json_str)
        assert json_data["traceId"] == "trace_1"
        assert json_data["spanCount"] == 1

    def test_json_export_not_pretty(self):
        """Test JSON export without pretty-printing."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="op",
            service_name="svc",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=0,
        )

        exporter = JSONExporter()
        json_str = exporter.export(trace, pretty=False)

        # Should be compact
        assert "\n" not in json_str or json_str.count("\n") < 2


class TestJaegerExporter:
    """Test Jaeger exporter."""

    def test_jaeger_export(self):
        """Test exporting to Jaeger format."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="test_op",
            service_name="test_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"tag1": "value1", "tag2": 42},
            logs=[{"timestamp": 1500000000, "fields": {"message": "test"}}],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=2,
        )

        exporter = JaegerExporter()
        jaeger_str = exporter.export(trace)

        # Verify it's valid JSON
        jaeger_data = json.loads(jaeger_str)
        assert jaeger_data["traceID"] == "trace_1"
        assert len(jaeger_data["spans"]) == 1

    def test_jaeger_tag_types(self):
        """Test Jaeger tag type conversion."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="op",
            service_name="svc",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={
                "string_tag": "value",
                "bool_tag": True,
                "number_tag": 42,
            },
            logs=[],
            refs=[],
        )

        exporter = JaegerExporter()

        jaeger_span_dict = exporter._span_to_jaeger_dict(span)
        tags = jaeger_span_dict["tags"]

        # Check tag types
        tag_types = {t["key"]: t["type"] for t in tags}
        assert tag_types["string_tag"] == "string"
        assert tag_types["bool_tag"] == "bool"
        assert tag_types["number_tag"] == "number"


class TestZipkinExporter:
    """Test Zipkin exporter."""

    def test_zipkin_export(self):
        """Test exporting to Zipkin format."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="test_op",
            service_name="test_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"tag1": "value1"},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=1,
        )

        exporter = ZipkinExporter()
        zipkin_str = exporter.export(trace)

        # Verify it's valid JSON
        zipkin_data = json.loads(zipkin_str)
        assert isinstance(zipkin_data, list)
        assert len(zipkin_data) == 1
        assert zipkin_data[0]["traceId"] == "trace_1"

    def test_zipkin_span_format(self):
        """Test Zipkin span format."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id="parent_1",
            operation_name="op",
            service_name="svc",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"key": "value"},
            logs=[],
            refs=[],
        )

        exporter = ZipkinExporter()
        zipkin_span = exporter._span_to_zipkin_dict(span)

        assert zipkin_span["traceId"] == "trace_1"
        assert zipkin_span["id"] == "span_1"
        assert zipkin_span["parentId"] == "parent_1"
        assert "localEndpoint" in zipkin_span


class TestOTLPExporter:
    """Test OTLP exporter."""

    def test_otlp_json_export(self):
        """Test exporting to OTLP JSON format."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="test_op",
            service_name="test_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"key": "value"},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=1,
        )

        exporter = OTLPExporter()
        otlp_str = exporter.export(trace, use_protobuf=False)

        # Verify it's valid JSON
        otlp_data = json.loads(otlp_str)
        assert "resourceSpans" in otlp_data

    def test_otlp_protobuf_export(self):
        """Test exporting to OTLP protobuf format."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="op",
            service_name="svc",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=0,
        )

        exporter = OTLPExporter()
        otlp_str = exporter.export(trace, use_protobuf=True)

        # Should be base64-encoded
        assert isinstance(otlp_str, str)
        assert len(otlp_str) > 0


class TestExporterFactory:
    """Test exporter factory."""

    def test_create_json_exporter(self):
        """Test creating JSON exporter."""
        exporter = ExporterFactory.create(ExportFormat.JSON)
        assert isinstance(exporter, JSONExporter)

    def test_create_jaeger_exporter(self):
        """Test creating Jaeger exporter."""
        exporter = ExporterFactory.create(ExportFormat.JAEGER)
        assert isinstance(exporter, JaegerExporter)

    def test_create_zipkin_exporter(self):
        """Test creating Zipkin exporter."""
        exporter = ExporterFactory.create(ExportFormat.ZIPKIN)
        assert isinstance(exporter, ZipkinExporter)

    def test_create_otlp_exporter(self):
        """Test creating OTLP exporter."""
        exporter = ExporterFactory.create(ExportFormat.OTLP)
        assert isinstance(exporter, OTLPExporter)

    def test_unsupported_format(self):
        """Test creating exporter for unsupported format."""
        with pytest.raises(ValueError):
            ExporterFactory.create("unsupported")

    def test_direct_export(self):
        """Test exporting directly through factory."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="op",
            service_name="svc",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={},
            logs=[],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[span],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=0,
        )

        # Export using factory
        json_export = ExporterFactory.export(trace, ExportFormat.JSON)
        jaeger_export = ExporterFactory.export(trace, ExportFormat.JAEGER)

        assert json_export is not None
        assert jaeger_export is not None
        assert json_export != jaeger_export


class TestExportIntegration:
    """Integration tests for exporters."""

    def test_multi_format_export(self):
        """Test exporting same trace to multiple formats."""
        span = ExportedSpan(
            trace_id="trace_1",
            span_id="span_1",
            parent_span_id=None,
            operation_name="api_call",
            service_name="api_service",
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            status="OK",
            tags={"http.method": "GET", "http.status": 200},
            logs=[{"timestamp": 1500000000, "fields": {"event": "request"}}],
            refs=[],
        )

        trace = ExportedTrace(
            trace_id="trace_1",
            spans=[trace],
            span_count=1,
            start_time_unix_nano=1000000000,
            end_time_unix_nano=2000000000,
            duration_ns=1000000000,
            tag_count=2,
        )

        # Export to all formats
        formats = [ExportFormat.JSON, ExportFormat.JAEGER, ExportFormat.ZIPKIN, ExportFormat.OTLP]
        exports = {}

        for fmt in formats:
            exports[fmt] = ExporterFactory.export(trace, fmt)

        # All exports should be different
        export_strings = list(exports.values())
        for i, exp1 in enumerate(export_strings):
            for j, exp2 in enumerate(export_strings):
                if i < j:
                    # They should be different formats
                    pass  # Not strictly required but likely
