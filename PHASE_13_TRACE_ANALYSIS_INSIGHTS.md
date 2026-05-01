# Phase 13: Trace Analysis & Insights

**Status**: ✅ Ready
**Focus**: anomaly detection, latency profiling, critical path identification, and trace-based recommendations

## Objective

Phase 13 exposes the existing trace-analysis and trace-insights primitives through the
shared package and documents how to use them for incident response and performance review.

## Deliverables

- `apps/shared/trace_analysis.py` - low-level trace analysis primitives
- `apps/shared/trace_insights.py` - recommendation engine built on trace analysis
- `apps/shared/__init__.py` - shared export surface for the analysis helpers
- `docs/observability/trace-analysis-guide.md` - operator guide for using the new tools

## Coverage

- Latency baseline tracking and anomaly detection
- Critical path and bottleneck identification
- Trace correlation by user and tenant
- SLO metrics, service health scoring, and dependency analysis