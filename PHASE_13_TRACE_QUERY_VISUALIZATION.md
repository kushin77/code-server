# Phase 13: Trace Query & Visualization

**Status**: ✅ Ready
**Focus**: trace search, aggregation, and renderable trace views

## Objective

This slice exposes the query and visualization helpers through the shared package
and documents how to use them for trace debugging and analysis.

## Deliverables

- `apps/shared/trace_query.py` - structured trace search and aggregation helpers
- `apps/shared/trace_visualization.py` - timeline, flame graph, service map, and sequence diagram models
- `docs/observability/trace-query-visualization-guide.md` - operator guide for query and visualization workflows

## Coverage

- Filtered trace search by service, operation, status, duration, and time range
- Grouping and summary statistics for trace sets
- Trace timeline, flame graph, dependency map, and sequence models
- Shared export surface through `apps.shared`